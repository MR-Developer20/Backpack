package main

import (
	"errors"
	"os"
	"os/exec"
)

func elevated() bool { return os.Geteuid() == 0 }
func attachConsole() {}

func inProcess() bool { return elevated() }

// elevate runs exe args as root through pkexec (the desktop's password dialog).
func elevate(exe string, args []string, logPath string) (cancelled bool, err error) {
	if _, err := exec.LookPath("pkexec"); err != nil {
		return false, errors.New("pkexec is not installed: run this app with sudo, or use the command line (sudo backpack-usb-writer --help)")
	}
	cmd := exec.Command("pkexec", append([]string{exe}, args...)...)
	if f, ferr := os.OpenFile(logPath, os.O_WRONLY|os.O_APPEND|os.O_CREATE, 0o644); ferr == nil {
		defer f.Close()
		cmd.Stdout, cmd.Stderr = f, f
	}
	err = cmd.Run()
	var ee *exec.ExitError
	if errors.As(err, &ee) && (ee.ExitCode() == 126 || ee.ExitCode() == 127) {
		return true, nil
	}
	return false, err
}
