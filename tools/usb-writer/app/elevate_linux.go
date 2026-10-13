package main

import (
	"errors"
	"os"
	"os/exec"
)

func elevated() bool { return os.Geteuid() == 0 }
func attachConsole() {}

func inProcess() bool { return elevated() }

// A GUI started with sudo cannot reach a Wayland desktop, so the fallback is the command line.
const sudoHint = "run the command shown under Write in a terminal, with sudo in front"

// elevate runs exe args as root through pkexec (the desktop's password dialog).
func elevate(exe string, args []string, logPath string) (cancelled bool, err error) {
	if _, err := exec.LookPath("pkexec"); err != nil {
		return false, errors.New("pkexec is not installed: " + sudoHint)
	}
	cmd := exec.Command("pkexec", append([]string{exe}, args...)...)
	if f, ferr := os.OpenFile(logPath, os.O_WRONLY|os.O_APPEND|os.O_CREATE, 0o644); ferr == nil {
		defer f.Close()
		cmd.Stdout, cmd.Stderr = f, f
	}
	err = cmd.Run()
	var ee *exec.ExitError
	if errors.As(err, &ee) {
		switch ee.ExitCode() {
		case 126: // the password dialog was dismissed
			return true, nil
		case 127: // not authorized, or no password agent runs (sway, i3 and other bare sessions)
			return false, errors.New("no password prompt could be shown (no polkit agent running?): " + sudoHint)
		}
	}
	return false, err
}
