package flash

import (
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
)

const (
	ioctlVolumeGetDiskExtents = 0x00560000
	fsctlLockVolume           = 0x00090018
	fsctlDismountVolume       = 0x00090020
	ioctlDiskGetLengthInfo    = 0x0007405C
	ioctlDiskUpdateProperties = 0x00070140
)

// PowerShell, without flashing a console window.
func powershell(script string) ([]byte, error) {
	cmd := exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-Command", script)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x08000000} // CREATE_NO_WINDOW
	return cmd.Output()
}

type psDisk struct {
	Number   int
	Name     string
	Size     int64
	Bus      string
	IsBoot   bool
	IsSystem bool
	Letters  []string
}

const psDisks = `$ErrorActionPreference='Stop'; ConvertTo-Json -Compress -Depth 3 -InputObject @(Get-Disk | ForEach-Object {
 [pscustomobject]@{ Number=$_.Number; Name="$($_.FriendlyName)"; Size=$_.Size; Bus="$($_.BusType)"; IsBoot=$_.IsBoot; IsSystem=$_.IsSystem;
  Letters=@(Get-Partition -DiskNumber $_.Number -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } | ForEach-Object { "$($_.DriveLetter):" }) } })`

func disks() ([]psDisk, error) {
	out, err := powershell(psDisks)
	if err != nil {
		return nil, fmt.Errorf("Get-Disk: %w", err)
	}
	var v []psDisk
	if err := json.Unmarshal(out, &v); err != nil {
		return nil, fmt.Errorf("Get-Disk output: %w", err)
	}
	return v, nil
}

func removableBus(b string) bool {
	switch strings.ToUpper(b) {
	case "USB", "SD", "MMC":
		return true
	}
	return false
}

func physPath(n int) string { return `\\.\PhysicalDrive` + strconv.Itoa(n) }

// ListDrives returns USB / SD disks that are neither the boot nor the system disk.
func ListDrives() ([]Drive, error) {
	all, err := disks()
	if err != nil {
		return nil, err
	}
	var out []Drive
	for _, d := range all {
		if !removableBus(d.Bus) || d.IsBoot || d.IsSystem || d.Size == 0 {
			continue
		}
		dr := Drive{Path: physPath(d.Number), Display: fmt.Sprintf("Disk %d", d.Number), Name: strings.TrimSpace(d.Name),
			Bus: strings.ToUpper(d.Bus), Size: d.Size, Mounted: d.Letters}
		if dr.Mounted == nil {
			dr.Mounted = []string{}
		}
		if f, err := os.Open(dr.Path); err == nil { // the app runs elevated, so it can read the disk
			_, dr.Persistence = FindPersistence(f)
			f.Close()
		}
		out = append(out, dr)
	}
	return out, nil
}

func diskNumber(path string) (int, error) {
	s := strings.TrimPrefix(strings.ToLower(path), strings.ToLower(`\\.\PhysicalDrive`))
	s = strings.TrimPrefix(s, "disk")
	return strconv.Atoi(strings.TrimSpace(s))
}

// lockVolumes locks and dismounts every volume on disk n; the handles must stay open while writing.
func lockVolumes(n int, emit func(Event)) ([]windows.Handle, error) {
	var locked []windows.Handle
	name := make([]uint16, windows.MAX_PATH)
	find, err := windows.FindFirstVolume(&name[0], uint32(len(name)))
	if err != nil {
		return nil, err
	}
	defer windows.FindVolumeClose(find)
	for {
		vol := strings.TrimSuffix(windows.UTF16ToString(name), `\`)
		if h, err := windows.CreateFile(windows.StringToUTF16Ptr(vol), windows.GENERIC_READ|windows.GENERIC_WRITE,
			windows.FILE_SHARE_READ|windows.FILE_SHARE_WRITE, nil, windows.OPEN_EXISTING, 0, 0); err == nil {
			var ext [1024]byte
			var ret uint32
			onDisk := false
			if windows.DeviceIoControl(h, ioctlVolumeGetDiskExtents, nil, 0, &ext[0], uint32(len(ext)), &ret, nil) == nil {
				cnt := binary.LittleEndian.Uint32(ext[0:])
				for i := uint32(0); i < cnt && 8+24*(i+1) <= ret; i++ {
					if int(binary.LittleEndian.Uint32(ext[8+24*i:])) == n {
						onDisk = true
					}
				}
			}
			if onDisk {
				emit(Event{Log: "Locking volume " + vol})
				if err := windows.DeviceIoControl(h, fsctlLockVolume, nil, 0, nil, 0, &ret, nil); err != nil {
					windows.CloseHandle(h)
					for _, l := range locked {
						windows.CloseHandle(l)
					}
					return nil, fmt.Errorf("a volume on this drive is in use (close any open files or Explorer windows on it): %w", err)
				}
				windows.DeviceIoControl(h, fsctlDismountVolume, nil, 0, nil, 0, &ret, nil)
				locked = append(locked, h)
			} else {
				windows.CloseHandle(h)
			}
		}
		if err := windows.FindNextVolume(find, &name[0], uint32(len(name))); err != nil {
			break
		}
	}
	return locked, nil
}

func openDisk(path string, emit func(Event)) (*device, error) {
	n, err := diskNumber(path)
	if err != nil {
		return nil, fmt.Errorf("%s is not a disk (expected \\\\.\\PhysicalDriveN)", path)
	}
	all, err := disks()
	if err != nil {
		return nil, err
	}
	found := false
	for _, d := range all {
		if d.Number == n {
			found = true
			if d.IsBoot || d.IsSystem {
				return nil, fmt.Errorf("disk %d holds the running system", n)
			}
		}
	}
	if !found {
		return nil, fmt.Errorf("disk %d not found", n)
	}
	if !windows.GetCurrentProcessToken().IsElevated() {
		return nil, errors.New("writing a drive needs administrator rights")
	}
	locked, err := lockVolumes(n, emit)
	if err != nil {
		return nil, err
	}
	release := func() {
		for _, h := range locked {
			windows.CloseHandle(h)
		}
	}
	p := physPath(n)
	h, err := windows.CreateFile(windows.StringToUTF16Ptr(p), windows.GENERIC_READ|windows.GENERIC_WRITE,
		windows.FILE_SHARE_READ|windows.FILE_SHARE_WRITE, nil, windows.OPEN_EXISTING, windows.FILE_FLAG_WRITE_THROUGH, 0)
	if err != nil {
		release()
		return nil, fmt.Errorf("open %s: %w", p, err)
	}
	var size int64
	var ret uint32
	if err := windows.DeviceIoControl(h, ioctlDiskGetLengthInfo, nil, 0, (*byte)(unsafe.Pointer(&size)), 8, &ret, nil); err != nil {
		windows.CloseHandle(h)
		release()
		return nil, fmt.Errorf("disk size: %w", err)
	}
	d := &device{File: os.NewFile(uintptr(h), p), Size: size, release: release}
	d.after = func(emit func(Event)) {
		emit(Event{Log: "Asking Windows to re-read the drive"})
		windows.DeviceIoControl(h, ioctlDiskUpdateProperties, nil, 0, nil, 0, &ret, nil)
	}
	return d, nil
}
