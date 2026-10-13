package flash

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"howett.net/plist"
)

func diskutilPlist(v any, args ...string) error {
	out, err := exec.Command("diskutil", append(args[:1:1], append([]string{"-plist"}, args[1:]...)...)...).Output()
	if err != nil {
		return fmt.Errorf("diskutil %s: %w", args[0], err)
	}
	_, err = plist.Unmarshal(out, v)
	return err
}

type duInfo struct {
	DeviceIdentifier string
	DeviceNode       string
	MediaName        string
	IORegistryEntryName string
	BusProtocol      string
	TotalSize        int64
	Size             int64
	WholeDisk        bool
	Internal         bool
	VirtualOrPhysical string
}

// ListDrives returns external physical disks (USB sticks, SD cards).
func ListDrives() ([]Drive, error) {
	var list struct {
		AllDisksAndPartitions []struct {
			DeviceIdentifier string
			Size             int64
			MountPoint       string
			Partitions       []struct {
				DeviceIdentifier string
				Content          string
				MountPoint       string
			}
		}
	}
	if err := diskutilPlist(&list, "list", "external", "physical"); err != nil {
		return nil, err
	}
	var out []Drive
	for _, d := range list.AllDisksAndPartitions {
		var info duInfo
		if err := diskutilPlist(&info, "info", d.DeviceIdentifier); err != nil || info.Internal {
			continue
		}
		size := info.TotalSize
		if size == 0 {
			size = d.Size
		}
		dr := Drive{Path: "/dev/" + d.DeviceIdentifier, Display: d.DeviceIdentifier, Size: size,
			Bus: strings.ToUpper(info.BusProtocol), Mounted: []string{}}
		dr.Name = strings.TrimSpace(info.MediaName)
		if dr.Name == "" {
			dr.Name = strings.TrimSpace(info.IORegistryEntryName)
		}
		if dr.Name == "" {
			dr.Name = "External drive"
		}
		if d.MountPoint != "" {
			dr.Mounted = append(dr.Mounted, d.MountPoint)
		}
		for i, p := range d.Partitions {
			if p.MountPoint != "" {
				dr.Mounted = append(dr.Mounted, p.MountPoint)
			}
			// macOS cannot read ext labels without root: a Linux partition after the image's
			// two is taken as persistence here; the writer checks the label before keeping it.
			if i >= 2 && strings.EqualFold(p.Content, "Linux") {
				dr.Persistence = true
			}
		}
		out = append(out, dr)
	}
	return out, nil
}

func openDisk(path string, emit func(Event)) (*device, error) {
	id := strings.TrimPrefix(strings.TrimPrefix(path, "/dev/"), "r")
	var info duInfo
	if err := diskutilPlist(&info, "info", id); err != nil {
		return nil, fmt.Errorf("%s is not a disk", path)
	}
	if !info.WholeDisk {
		return nil, fmt.Errorf("%s is a partition, not a whole disk", path)
	}
	if info.Internal {
		return nil, fmt.Errorf("%s is an internal disk", path)
	}
	if os.Geteuid() != 0 {
		return nil, errors.New("writing a drive needs administrator rights (run with sudo)")
	}
	emit(Event{Log: "Unmounting " + id})
	if out, err := exec.Command("diskutil", "unmountDisk", "force", "/dev/"+id).CombinedOutput(); err != nil {
		return nil, fmt.Errorf("could not unmount %s: %s", id, strings.TrimSpace(string(out)))
	}
	// the raw node (rdisk) skips the buffer cache and is many times faster
	f, err := os.OpenFile("/dev/r"+id, os.O_RDWR, 0)
	if err != nil {
		return nil, fmt.Errorf("open /dev/r%s: %w", id, err)
	}
	size := info.TotalSize
	if size == 0 {
		size = info.Size
	}
	d := &device{File: f, Size: size}
	d.after = func(emit func(Event)) {
		f.Close() // the open rdisk would keep the disk busy
		emit(Event{Log: "Ejecting " + id})
		exec.Command("diskutil", "eject", "/dev/"+id).Run()
	}
	return d, nil
}
