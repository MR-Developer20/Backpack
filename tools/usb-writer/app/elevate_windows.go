package main

import (
	"errors"
	"os"

	"golang.org/x/sys/windows"
)

// The Windows build asks for Administrator at launch (build/windows/wails.exe.manifest), so the
// write runs in-process.
func elevated() bool { return windows.GetCurrentProcessToken().IsElevated() }

func elevate(exe string, args []string, logPath string) (bool, error) {
	return false, errors.New("Backpack USB Writer must run as Administrator: right-click it and choose Run as administrator")
}

// attachConsole lets the command-line mode print into the terminal it was started from
// (the .exe is a GUI-subsystem program).
func inProcess() bool { return elevated() }

func attachConsole() {
	const attachParentProcess = ^uint32(0)
	k := windows.NewLazySystemDLL("kernel32.dll")
	if r, _, _ := k.NewProc("AttachConsole").Call(uintptr(attachParentProcess)); r == 0 {
		return
	}
	reopen := func(name string, mode int, dst **os.File) {
		h, err := windows.CreateFile(windows.StringToUTF16Ptr(name), windows.GENERIC_READ|windows.GENERIC_WRITE,
			windows.FILE_SHARE_READ|windows.FILE_SHARE_WRITE, nil, windows.OPEN_EXISTING, 0, 0)
		if err == nil {
			*dst = os.NewFile(uintptr(h), name)
		}
	}
	reopen("CONOUT$", 0, &os.Stdout)
	reopen("CONOUT$", 0, &os.Stderr)
	reopen("CONIN$", 0, &os.Stdin)
}
