package flash

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"

	"golang.org/x/sys/unix"
)

type lsblkDev struct {
	Name, Path, Model, Vendor, Tran, Type, Label string
	Size                                         int64
	Rm, Hotplug                                  bool
	Mountpoints                                  []*string
	Children                                     []lsblkDev
}

func lsblk(args ...string) ([]lsblkDev, error) {
	out, err := exec.Command("lsblk", append([]string{"-J", "-b", "-o",
		"NAME,PATH,SIZE,MODEL,VENDOR,TRAN,RM,HOTPLUG,TYPE,LABEL,MOUNTPOINTS"}, args...)...).Output()
	if err != nil {
		return nil, fmt.Errorf("lsblk: %w", err)
	}
	var v struct{ Blockdevices []lsblkDev }
	if err := json.Unmarshal(out, &v); err != nil {
		return nil, err
	}
	return v.Blockdevices, nil
}

func mounted(d lsblkDev) bool {
	for _, m := range d.Mountpoints {
		if m != nil && *m != "" {
			return true
		}
	}
	return false
}

func rootDisk() string {
	src, err := exec.Command("findmnt", "-no", "SOURCE", "/").Output()
	if err != nil {
		return ""
	}
	pk, _ := exec.Command("lsblk", "-no", "PKNAME", strings.TrimSpace(string(src))).Output()
	if f := strings.Fields(string(pk)); len(f) > 0 {
		return "/dev/" + f[0]
	}
	return ""
}

// ListDrives returns USB / removable / hot-pluggable whole disks, never the one holding /.
func ListDrives() ([]Drive, error) {
	devs, err := lsblk()
	if err != nil {
		return nil, err
	}
	root := rootDisk()
	var out []Drive
	for _, d := range devs {
		if d.Type != "disk" || d.Path == root || d.Size == 0 {
			continue
		}
		if d.Tran != "usb" && !d.Rm && !d.Hotplug {
			continue
		}
		dr := Drive{Path: d.Path, Display: d.Path, Size: d.Size, Bus: strings.ToUpper(d.Tran), Mounted: []string{}}
		dr.Name = strings.TrimSpace(strings.TrimSpace(d.Vendor) + " " + strings.TrimSpace(d.Model))
		if dr.Name == "" {
			dr.Name = "USB drive"
		}
		if dr.Bus == "" {
			dr.Bus = "REMOVABLE"
		}
		if mounted(d) {
			dr.Mounted = append(dr.Mounted, d.Path)
		}
		for _, k := range d.Children {
			if mounted(k) {
				dr.Mounted = append(dr.Mounted, k.Path)
			}
			if k.Label == "persistence" {
				dr.Persistence = true
			}
		}
		out = append(out, dr)
	}
	return out, nil
}

func openDisk(path string, emit func(Event)) (*device, error) {
	devs, err := lsblk("-d", path)
	if err != nil || len(devs) != 1 {
		return nil, fmt.Errorf("%s is not a block device", path)
	}
	if devs[0].Type != "disk" {
		return nil, fmt.Errorf("%s is a %s, not a whole disk", path, devs[0].Type)
	}
	if path == rootDisk() {
		return nil, fmt.Errorf("%s holds the running system", path)
	}
	if os.Geteuid() != 0 {
		return nil, errors.New("writing a drive needs root (run with sudo, or start the app normally and it will ask for your password)")
	}
	// unmount everything on the disk (the desktop may have auto-mounted it)
	if all, err := lsblk(path); err == nil && len(all) == 1 {
		parts := append([]lsblkDev{all[0]}, all[0].Children...)
		for _, p := range parts {
			for _, m := range p.Mountpoints {
				if m != nil && *m != "" {
					emit(Event{Log: "Unmounting " + *m})
					if out, err := exec.Command("umount", *m).CombinedOutput(); err != nil {
						return nil, fmt.Errorf("could not unmount %s: %s", *m, strings.TrimSpace(string(out)))
					}
				}
			}
		}
	}
	f, err := os.OpenFile(path, os.O_RDWR|unix.O_EXCL, 0)
	if err != nil {
		return nil, fmt.Errorf("open %s: %w (is it still in use?)", path, err)
	}
	size, err := f.Seek(0, io.SeekEnd)
	if err != nil {
		f.Close()
		return nil, err
	}
	d := &device{File: f, Size: size}
	d.after = func(emit func(Event)) {
		emit(Event{Log: "Re-reading the partition table"})
		// BLKRRPART needs no other opener; partx is the fallback for a busy kernel view
		if err := unix.IoctlSetInt(int(f.Fd()), unix.BLKRRPART, 0); err != nil {
			exec.Command("partx", "-u", path).Run()
		}
		exec.Command("udevadm", "settle").Run()
	}
	return d, nil
}
