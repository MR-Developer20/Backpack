package flash

import (
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
	"time"
)

// Drive is a removable disk the writer may target.
type Drive struct {
	Path        string   `json:"path"`        // what the writer opens: /dev/sdb, /dev/disk4, \\.\PhysicalDrive2
	Display     string   `json:"display"`     // short name for the UI: /dev/sdb, disk4, Disk 2
	Name        string   `json:"name"`        // vendor + model
	Bus         string   `json:"bus"`         // USB, SD, ...
	Size        int64    `json:"size"`        // bytes
	Persistence bool     `json:"persistence"` // carries a Backpack persistence partition
	Mounted     []string `json:"mounted"`     // mounted volumes that will be unmounted first
}

// Options for one write. Persist is the new persistence size in bytes (ignored with Keep).
type Options struct {
	ISO     string
	Device  string
	Persist int64
	Keep    bool
	Force   bool // allow disks larger than MaxDisk
}

// Event is one progress report; the GUI and the --json worker mode both use it.
type Event struct {
	Phase string `json:"phase,omitempty"` // prepare, image, partition, format, sync, done
	Done  int64  `json:"done,omitempty"`
	Total int64  `json:"total,omitempty"`
	Log   string `json:"log,omitempty"`
	Error string `json:"error,omitempty"`
	End   bool   `json:"end,omitempty"` // last event of the job (success or Error)
}

const (
	MaxDisk     = 256 << 30
	DefaultSize = 5 << 30
	align       = 2048 // sectors: 1 MiB, as sfdisk does
	chunk       = 4 << 20
	syncEvery   = 64 << 20
)

// PersistenceConf is written to the root of a fresh persistence partition: targeted union
// directories, the same list scripts/mkusb.sh writes.
var PersistenceConf = []byte("/home\n/var/lib/backpack\n/etc/NetworkManager\n")

// ParseSize reads sfdisk-style sizes: 5G, 5GB, 512M, 5GiB (binary units), or plain bytes.
func ParseSize(s string) (int64, error) {
	t := strings.ToUpper(strings.TrimSpace(s))
	t = strings.TrimSuffix(strings.TrimSuffix(t, "B"), "I")
	mul := int64(1)
	if n := len(t); n > 0 {
		switch t[n-1] {
		case 'K':
			mul = 1 << 10
		case 'M':
			mul = 1 << 20
		case 'G':
			mul = 1 << 30
		case 'T':
			mul = 1 << 40
		}
		if mul > 1 {
			t = t[:n-1]
		}
	}
	f, err := strconv.ParseFloat(t, 64)
	if err != nil || f <= 0 {
		return 0, fmt.Errorf("bad size %q", s)
	}
	return int64(f * float64(mul)), nil
}

func Human(n int64) string {
	f := float64(n)
	for _, u := range []string{"B", "KB", "MB", "GB"} {
		if f < 1000 {
			if u == "B" {
				return fmt.Sprintf("%d B", n)
			}
			return fmt.Sprintf("%.1f %s", f, u)
		}
		f /= 1000
	}
	return fmt.Sprintf("%.1f TB", f)
}

// ISOInfo describes an image file for the UI.
type ISOInfo struct {
	Path   string `json:"path"`
	Name   string `json:"name"`
	Size   int64  `json:"size"`
	Volume string `json:"volume"` // ISO9660 volume id
	Error  string `json:"error,omitempty"`
}

func InspectISO(path string) ISOInfo {
	info := ISOInfo{Path: path, Name: baseName(path)}
	f, err := os.Open(path)
	if err != nil {
		info.Error = err.Error()
		return info
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		info.Error = err.Error()
		return info
	}
	info.Size = st.Size()
	pvd := make([]byte, 2048)
	if _, err := f.ReadAt(pvd, 16*2048); err != nil || string(pvd[1:6]) != "CD001" {
		info.Error = "not an ISO 9660 image"
		return info
	}
	info.Volume = strings.TrimSpace(string(pvd[40:72]))
	m, err := ReadMBR(f)
	if err != nil {
		info.Error = "image is not bootable from USB (no isohybrid MBR)"
	} else if m.GPT() {
		info.Error = "GPT images are not supported"
	}
	return info
}

func baseName(p string) string {
	if i := strings.LastIndexAny(p, `/\`); i >= 0 {
		return p[i+1:]
	}
	return p
}

// Run writes the image, then adds (or restores) the persistence partition.
func Run(o Options, emit func(Event)) (err error) {
	defer func() {
		if err != nil {
			emit(Event{Error: err.Error(), End: true})
		}
	}()
	iso, err := os.Open(o.ISO)
	if err != nil {
		return err
	}
	defer iso.Close()
	st, err := iso.Stat()
	if err != nil {
		return err
	}
	isoBytes := st.Size()
	if isoBytes%sector != 0 {
		return errors.New("image size is not a multiple of 512 bytes")
	}
	table, err := ReadMBR(iso)
	if err != nil {
		return err
	}
	if table.GPT() {
		return errors.New("GPT images are not supported")
	}
	slot := table.FreeSlot()
	if slot < 0 {
		return errors.New("the image's partition table has no free slot for persistence")
	}

	emit(Event{Phase: "prepare", Log: "Opening " + o.Device})
	dev, err := openDevice(o.Device, emit)
	if err != nil {
		return err
	}
	defer dev.Close()
	diskBytes := dev.Size
	if diskBytes <= 0 {
		return errors.New("could not read the drive size")
	}
	if diskBytes > MaxDisk && !o.Force {
		return fmt.Errorf("%s is %s, larger than 256 GiB: refusing without --force (is this really a USB stick?)", o.Device, Human(diskBytes))
	}
	if isoBytes > diskBytes {
		return fmt.Errorf("the image (%s) does not fit on the drive (%s)", Human(isoBytes), Human(diskBytes))
	}
	isoSectors := uint64(isoBytes / sector)
	diskSectors := uint64(diskBytes / sector)

	// plan the persistence partition before touching the drive
	var pStart, pSectors uint64
	if o.Keep {
		p, ok := FindPersistence(dev)
		if !ok {
			return errors.New("no partition labelled 'persistence' on this drive: use a fresh install instead")
		}
		if isoSectors > uint64(p.Start) {
			return errors.New("the new image would overlap the persistence partition: use a fresh install (this erases persistence)")
		}
		pStart, pSectors = uint64(p.Start), uint64(p.Sectors)
		emit(Event{Log: fmt.Sprintf("Keeping persistence partition (%s at sector %d)", Human(int64(pSectors*sector)), pStart)})
	} else {
		end := max(table.End(), isoSectors)
		pStart = (end + align - 1) / align * align
		want := uint64(o.Persist) / sector
		if want == 0 {
			want = DefaultSize / sector
		}
		if pStart >= diskSectors {
			return errors.New("no room for a persistence partition after the image")
		}
		pSectors = min(want, diskSectors-pStart)
		pSectors = pSectors / 8 * 8
		if pSectors*sector < 64<<20 {
			return errors.New("less than 64 MB left for persistence after the image: use a bigger drive")
		}
		if pSectors < want {
			emit(Event{Log: fmt.Sprintf("Drive is smaller than requested: persistence will be %s", Human(int64(pSectors*sector)))})
		}
	}
	if pStart > 1<<32-1 || pSectors > 1<<32-1 {
		return errors.New("partition beyond the 2 TiB MBR limit")
	}

	// 1. image
	emit(Event{Phase: "image", Done: 0, Total: isoBytes, Log: fmt.Sprintf("Writing %s (%s)", baseName(o.ISO), Human(isoBytes))})
	buf := make([]byte, chunk)
	var done, sinceSync int64
	last := time.Time{}
	for done < isoBytes {
		n, rerr := io.ReadFull(iso, buf)
		if n > 0 {
			if _, err := dev.WriteAt(buf[:n], done); err != nil {
				return fmt.Errorf("write at %s: %w", Human(done), err)
			}
			done += int64(n)
			sinceSync += int64(n)
			if sinceSync >= syncEvery {
				if err := dev.Sync(); err != nil {
					return err
				}
				sinceSync = 0
			}
			if time.Since(last) > 200*time.Millisecond || done == isoBytes {
				emit(Event{Phase: "image", Done: done, Total: isoBytes})
				last = time.Now()
			}
		}
		if rerr == io.EOF || rerr == io.ErrUnexpectedEOF {
			break
		}
		if rerr != nil {
			return rerr
		}
	}
	if done != isoBytes {
		return fmt.Errorf("short read from the image: %d of %d bytes", done, isoBytes)
	}
	emit(Event{Phase: "sync", Log: "Flushing the image to the drive"})
	if err := dev.Sync(); err != nil {
		return err
	}

	// 2. partition table: the image's MBR plus a Linux entry
	emit(Event{Phase: "partition", Log: fmt.Sprintf("Adding partition %d: start sector %d, %s", slot+1, pStart, Human(int64(pSectors*sector)))})
	table.Set(slot, uint32(pStart), uint32(pSectors))
	if err := table.Write(dev); err != nil {
		return fmt.Errorf("write partition table: %w", err)
	}

	// 3. filesystem
	off := int64(pStart * sector)
	if o.Keep {
		if l, ok := ExtLabel(dev, off); !ok || l != "persistence" {
			return fmt.Errorf("after the update the persistence partition reads label %q: stop and check the drive", l)
		}
		emit(Event{Log: "Persistence kept"})
	} else {
		emit(Event{Phase: "format", Log: "Creating the persistence filesystem (ext3, label persistence)"})
		last = time.Time{}
		err := FormatExt3(dev, off, int64(pSectors*sector), "persistence",
			map[string][]byte{"persistence.conf": PersistenceConf}, func(d, t int64) {
				if time.Since(last) > 200*time.Millisecond || d == t {
					emit(Event{Phase: "format", Done: d, Total: t})
					last = time.Now()
				}
			})
		if err != nil {
			return fmt.Errorf("format persistence: %w", err)
		}
	}
	emit(Event{Phase: "sync", Log: "Flushing to the drive"})
	if err := dev.Sync(); err != nil {
		return err
	}
	dev.finish(emit)
	emit(Event{Phase: "done", Log: "Done. You can remove the drive.", End: true})
	return nil
}
