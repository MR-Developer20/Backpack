package flash

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"syscall"

	"golang.org/x/sys/unix"
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
	DeviceIdentifier    string
	DeviceNode          string
	MediaName           string
	IORegistryEntryName string
	BusProtocol         string
	TotalSize           int64
	Size                int64
	WholeDisk           bool
	Internal            bool
	VirtualOrPhysical   string
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
	emit(Event{Log: "Unmounting " + id})
	if out, err := exec.Command("diskutil", "unmountDisk", "force", "/dev/"+id).CombinedOutput(); err != nil {
		return nil, fmt.Errorf("could not unmount %s: %s", id, strings.TrimSpace(string(out)))
	}
	// the raw node (rdisk) skips the buffer cache and is many times faster
	f, err := os.OpenFile("/dev/r"+id, os.O_RDWR, 0)
	if errors.Is(err, os.ErrPermission) {
		// not root, or root that macOS privacy protection keeps off removable drives
		// (a root process started through osascript's password prompt): authopen asks
		emit(Event{Phase: "auth", Log: "Asking for your password"})
		f, err = authOpen("/dev/r" + id)
	}
	if err != nil {
		return nil, fmt.Errorf("open /dev/r%s: %w", id, err)
	}
	size := info.TotalSize
	if size == 0 {
		size = info.Size
	}
	d := &device{File: f, Size: size}
	// File.Sync is fcntl(F_FULLFSYNC), which a raw disk node refuses with ENOTTY. Writes to
	// rdisk bypass the buffer cache; fsync is the most the node takes, and may refuse too.
	d.sync = func() error {
		err := syscall.Fsync(int(f.Fd()))
		if errors.Is(err, syscall.ENOTTY) || errors.Is(err, syscall.ENOTSUP) {
			return nil
		}
		return err
	}
	d.after = func(emit func(Event)) {
		f.Close() // the open rdisk would keep the disk busy
		emit(Event{Log: "Ejecting " + id})
		exec.Command("diskutil", "eject", "/dev/"+id).Run()
	}
	return d, nil
}

// authOpen opens path read-write through /usr/libexec/authopen, which asks for an
// administrator password in macOS's own dialog and passes the open descriptor back over a
// socket. The descriptor is not subject to the removable-drive privacy check, and the caller
// keeps its own access to the user's files (Downloads): no root process is needed.
func authOpen(path string) (*os.File, error) {
	fds, err := unix.Socketpair(unix.AF_UNIX, unix.SOCK_STREAM, 0)
	if err != nil {
		return nil, err
	}
	defer unix.Close(fds[0])
	child := os.NewFile(uintptr(fds[1]), "authopen")
	cmd := exec.Command("/usr/libexec/authopen", "-stdoutpipe", "-o", strconv.Itoa(unix.O_RDWR), path)
	var stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = child, &stderr
	err = cmd.Start()
	child.Close()
	if err != nil {
		return nil, err
	}
	fd := -1
	buf, oob := make([]byte, 64), make([]byte, unix.CmsgSpace(4))
	for fd < 0 {
		n, oobn, _, _, rerr := unix.Recvmsg(fds[0], buf, oob, 0)
		if rerr != nil || n == 0 && oobn == 0 {
			break
		}
		msgs, _ := unix.ParseSocketControlMessage(oob[:oobn])
		for _, m := range msgs {
			if rights, err := unix.ParseUnixRights(&m); err == nil && len(rights) > 0 {
				fd = rights[0]
			}
		}
	}
	werr := cmd.Wait()
	if fd < 0 {
		msg := strings.TrimSpace(stderr.String())
		if msg == "" && werr != nil {
			msg = werr.Error()
		}
		return nil, fmt.Errorf("no access to the drive (password cancelled or refused): %s", msg)
	}
	return os.NewFile(uintptr(fd), path), nil
}
