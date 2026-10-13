package flash

import (
	"encoding/binary"
	"errors"
	"fmt"
	"io"
)

// MBR partition table handling. The Backpack ISO is an MBR isohybrid: p1 covers the ISO9660
// image (type 0x00 but a non-zero size), p2 is the EFI image nested inside p1. The persistence
// partition is appended as p3 after the end of the image, like `sfdisk --append` does.

const sector = 512

type Part struct {
	Index   int // 0-3
	Boot    byte
	Type    byte
	Start   uint32 // LBA, 512-byte sectors
	Sectors uint32
}

func (p Part) End() uint64 { return uint64(p.Start) + uint64(p.Sectors) }
func (p Part) Used() bool  { return p.Sectors != 0 || p.Start != 0 || p.Type != 0 }

type MBR struct {
	raw   [sector]byte
	Parts [4]Part
}

func ReadMBR(r io.ReaderAt) (*MBR, error) {
	m := &MBR{}
	if _, err := r.ReadAt(m.raw[:], 0); err != nil {
		return nil, fmt.Errorf("read partition table: %w", err)
	}
	if m.raw[510] != 0x55 || m.raw[511] != 0xAA {
		return nil, errors.New("no MBR partition table found (is this a Backpack ISO?)")
	}
	for i := range m.Parts {
		e := m.raw[446+16*i:]
		m.Parts[i] = Part{Index: i, Boot: e[0], Type: e[4],
			Start: binary.LittleEndian.Uint32(e[8:]), Sectors: binary.LittleEndian.Uint32(e[12:])}
	}
	return m, nil
}

// GPT reports whether the table is a GPT protective MBR, which this writer does not edit.
func (m *MBR) GPT() bool {
	for _, p := range m.Parts {
		if p.Type == 0xEE {
			return true
		}
	}
	return false
}

// End is the first sector after every used partition.
func (m *MBR) End() uint64 {
	var end uint64
	for _, p := range m.Parts {
		if p.Sectors > 0 && p.End() > end {
			end = p.End()
		}
	}
	return end
}

func (m *MBR) FreeSlot() int {
	for i, p := range m.Parts {
		if !p.Used() {
			return i
		}
	}
	return -1
}

// Set writes a Linux (0x83) entry into slot i. CHS fields carry the "use LBA" marker.
func (m *MBR) Set(i int, start, sectors uint32) {
	e := m.raw[446+16*i : 446+16*i+16]
	e[0] = 0
	copy(e[1:4], []byte{0xFE, 0xFF, 0xFF})
	e[4] = 0x83
	copy(e[5:8], []byte{0xFE, 0xFF, 0xFF})
	binary.LittleEndian.PutUint32(e[8:], start)
	binary.LittleEndian.PutUint32(e[12:], sectors)
	m.Parts[i] = Part{Index: i, Type: 0x83, Start: start, Sectors: sectors}
}

func (m *MBR) Write(w io.WriterAt) error {
	_, err := w.WriteAt(m.raw[:], 0)
	return err
}

// ExtLabel returns the ext2/3/4 volume label of the filesystem starting at byte off, or ok=false.
// Reads one aligned 4 KiB block so it also works on raw devices (Windows, macOS rdisk).
func ExtLabel(r io.ReaderAt, off int64) (label string, ok bool) {
	var b [4096]byte
	if _, err := r.ReadAt(b[:], off); err != nil && !errors.Is(err, io.EOF) {
		return "", false
	}
	sb := b[1024:]
	if binary.LittleEndian.Uint16(sb[56:]) != 0xEF53 {
		return "", false
	}
	n := 0
	for n < 16 && sb[120+n] != 0 {
		n++
	}
	return string(sb[120 : 120+n]), true
}

// FindPersistence returns the partition whose ext filesystem is labelled "persistence".
func FindPersistence(r io.ReaderAt) (Part, bool) {
	m, err := ReadMBR(r)
	if err != nil {
		return Part{}, false
	}
	for _, p := range m.Parts {
		if p.Sectors == 0 {
			continue
		}
		if l, ok := ExtLabel(r, int64(p.Start)*sector); ok && l == "persistence" {
			return p, true
		}
	}
	return Part{}, false
}
