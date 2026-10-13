package flash

import (
	"bytes"
	"encoding/binary"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

// fakeISO builds a small image shaped like the Backpack isohybrid: CD001 at 32 KiB, an MBR
// with p1 (type 0, covering the image) and p2 (EFI, nested inside p1).
func fakeISO(t *testing.T, sectors uint32, fill byte) string {
	b := bytes.Repeat([]byte{fill}, int(sectors)*512)
	copy(b[16*2048:], "\x01CD001")
	copy(b[16*2048+40:], "BACKPACK_LIVE                   ")
	for i := 446; i < 512; i++ {
		b[i] = 0
	}
	e := b[446:]
	e[0] = 0x80
	binary.LittleEndian.PutUint32(e[8:], 0)
	binary.LittleEndian.PutUint32(e[12:], sectors)
	e = b[462:]
	e[4] = 0xEF
	binary.LittleEndian.PutUint32(e[8:], 200)
	binary.LittleEndian.PutUint32(e[12:], 100)
	b[510], b[511] = 0x55, 0xAA
	p := filepath.Join(t.TempDir(), "backpack.iso")
	if err := os.WriteFile(p, b, 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func partitionUUID(t *testing.T, img string, start, sectors uint32) string {
	part := img + ".p3"
	defer os.Remove(part)
	cmd := exec.Command("dd", "if="+img, "of="+part, "bs=512", "skip="+itoa(start), "count="+itoa(sectors), "conv=sparse", "status=none")
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("dd: %v %s", err, out)
	}
	if out, err := exec.Command(e2fsckPath(t), "-fn", part).CombinedOutput(); err != nil {
		t.Fatalf("e2fsck: %v\n%s", err, out)
	}
	out, _ := exec.Command("blkid", "-o", "value", "-s", "UUID", part).Output()
	return string(bytes.TrimSpace(out))
}

func itoa(n uint32) string { return strconv.FormatUint(uint64(n), 10) }

func e2fsckPath(t *testing.T) string {
	for _, p := range []string{"e2fsck", "/usr/sbin/e2fsck", "/sbin/e2fsck"} {
		if q, err := exec.LookPath(p); err == nil {
			return q
		}
	}
	t.Skip("e2fsck not installed")
	return ""
}

func TestRunFreshThenKeep(t *testing.T) {
	e2fsckPath(t)
	iso := fakeISO(t, 40000, 0xAB) // ~20 MB
	img := filepath.Join(t.TempDir(), "usb.img")
	f, _ := os.Create(img)
	f.Truncate(1 << 30)
	f.Close()
	var events []Event
	emit := func(e Event) { events = append(events, e) }
	if err := Run(Options{ISO: iso, Device: img, Persist: 300 << 20}, emit); err != nil {
		t.Fatal(err)
	}
	if last := events[len(events)-1]; last.Phase != "done" || !last.End {
		t.Fatalf("last event %+v", last)
	}
	dev, _ := os.Open(img)
	m, err := ReadMBR(dev)
	dev.Close()
	if err != nil {
		t.Fatal(err)
	}
	p3 := m.Parts[2]
	if p3.Type != 0x83 || p3.Start != 40960 || p3.Sectors != 300<<20/512 {
		t.Fatalf("p3 = %+v", p3)
	}
	if m.Parts[0].Sectors != 40000 || m.Parts[1].Type != 0xEF {
		t.Fatalf("image partitions changed: %+v", m.Parts)
	}
	uuid := partitionUUID(t, img, p3.Start, p3.Sectors)
	if uuid == "" {
		t.Fatal("no filesystem UUID")
	}

	// update with a new image, keeping persistence
	iso2 := fakeISO(t, 38000, 0xCD)
	events = nil
	if err := Run(Options{ISO: iso2, Device: img, Keep: true}, emit); err != nil {
		t.Fatal(err)
	}
	dev, _ = os.Open(img)
	m2, _ := ReadMBR(dev)
	head := make([]byte, 4)
	dev.ReadAt(head, 1<<20)
	dev.Close()
	if m2.Parts[2] != p3 || m2.Parts[0].Sectors != 38000 {
		t.Fatalf("after keep: %+v", m2.Parts)
	}
	if head[0] != 0xCD {
		t.Fatal("new image not written")
	}
	if got := partitionUUID(t, img, p3.Start, p3.Sectors); got != uuid {
		t.Fatalf("persistence was reformatted: uuid %s -> %s", uuid, got)
	}

	// an image that would overlap persistence is refused before anything is written
	big := fakeISO(t, 50000, 0xEE)
	if err := Run(Options{ISO: big, Device: img, Keep: true}, func(Event) {}); err == nil {
		t.Fatal("overlapping keep accepted")
	}
}

func TestRunSmallDriveClamps(t *testing.T) {
	e2fsckPath(t)
	iso := fakeISO(t, 40000, 1)
	img := filepath.Join(t.TempDir(), "usb.img")
	f, _ := os.Create(img)
	f.Truncate(200 << 20)
	f.Close()
	if err := Run(Options{ISO: iso, Device: img, Persist: 5 << 30}, func(Event) {}); err != nil {
		t.Fatal(err)
	}
	dev, _ := os.Open(img)
	m, _ := ReadMBR(dev)
	dev.Close()
	if end := uint64(m.Parts[2].Start) + uint64(m.Parts[2].Sectors); end > 200<<20/512 {
		t.Fatalf("p3 past the end: %+v", m.Parts[2])
	}
	partitionUUID(t, img, m.Parts[2].Start, m.Parts[2].Sectors)
}

func TestParseSize(t *testing.T) {
	for in, want := range map[string]int64{"5G": 5 << 30, "5GB": 5 << 30, "5GiB": 5 << 30, "512M": 512 << 20, "1.5G": 3 << 29, "4096": 4096} {
		if got, err := ParseSize(in); err != nil || got != want {
			t.Errorf("%s = %d %v", in, got, err)
		}
	}
	if _, err := ParseSize("abc"); err == nil {
		t.Error("abc accepted")
	}
}

func TestInspectISO(t *testing.T) {
	if e := InspectISO(fakeISO(t, 4096, 0)).Error; e != "" {
		t.Fatalf("good image rejected: %s", e)
	}
	// a file without the .iso extension is judged by content
	iso := fakeISO(t, 4096, 0)
	bare := filepath.Join(t.TempDir(), "backpack-live-v1.0-amd64")
	if err := os.Rename(iso, bare); err != nil {
		t.Fatal(err)
	}
	if e := InspectISO(bare).Error; e != "" {
		t.Fatalf("image without extension rejected: %s", e)
	}
	// the writer binaries from the same release page, renamed to .iso
	for head, want := range map[string]string{
		"\x7fELF": "Linux program", "MZ\x90\x00": "Windows program",
		"\xcf\xfa\xed\xfe": "macOS program", "PK\x03\x04": "zip archive",
	} {
		p := filepath.Join(t.TempDir(), "Backpack_USB_Writer-v1.0.iso")
		os.WriteFile(p, append([]byte(head), make([]byte, 64<<10)...), 0o644)
		if e := InspectISO(p).Error; !strings.Contains(e, want) {
			t.Errorf("%q: got %q, want it to mention %q", head, e, want)
		}
	}
}
