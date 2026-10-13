package flash

import (
	"os"
)

// device is an open write target: a whole disk, or a regular file (disk image, used by tests
// and by `--image`-style runs).
type device struct {
	*os.File
	Size    int64
	release func()                 // undo platform locks (Windows volume locks)
	after   func(emit func(Event)) // platform step after writing (re-read partitions, eject)
	sync    func() error           // platform flush, when File.Sync does not fit the device
}

func (d *device) Sync() error {
	if d.sync != nil {
		return d.sync()
	}
	return d.File.Sync()
}

func (d *device) Close() error {
	err := d.File.Close()
	if d.release != nil {
		d.release()
	}
	return err
}

func (d *device) finish(emit func(Event)) {
	if d.after != nil {
		d.after(emit)
	}
}

func openDevice(path string, emit func(Event)) (*device, error) {
	if st, err := os.Stat(path); err == nil && st.Mode().IsRegular() {
		f, err := os.OpenFile(path, os.O_RDWR, 0)
		if err != nil {
			return nil, err
		}
		return &device{File: f, Size: st.Size()}, nil
	}
	return openDisk(path, emit)
}
