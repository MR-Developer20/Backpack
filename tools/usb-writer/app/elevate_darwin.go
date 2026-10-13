package main

import (
	"errors"
	"os"
	"os/exec"
	"strings"
)

func elevated() bool { return os.Geteuid() == 0 }
func attachConsole() {}

func shq(s string) string { return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'" }

// elevate runs exe args as root through the macOS administrator password prompt.
func elevate(exe string, args []string) (cancelled bool, err error) {
	cmd := shq(exe)
	for _, a := range args {
		cmd += " " + shq(a)
	}
	cmd += " >/dev/null 2>&1"
	as := strings.NewReplacer(`\`, `\\`, `"`, `\"`).Replace(cmd)
	script := `do shell script "` + as + `" with prompt "Backpack USB Writer needs an administrator password to write the USB drive." with administrator privileges`
	out, err := exec.Command("osascript", "-e", script).CombinedOutput()
	if err != nil && strings.Contains(string(out), "-128") {
		return true, nil
	}
	var ee *exec.ExitError
	if errors.As(err, &ee) {
		return false, nil // the worker's own error is in the status file
	}
	return false, err
}
