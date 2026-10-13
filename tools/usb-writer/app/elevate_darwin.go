package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

func elevated() bool { return os.Geteuid() == 0 }
func attachConsole() {}

func shq(s string) string { return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'" }

// elevate runs exe args as root through the macOS administrator password prompt. The
// worker's own output goes to logPath, so a worker that dies early can still be explained.
func elevate(exe string, args []string, logPath string) (cancelled bool, err error) {
	cmd := shq(exe)
	for _, a := range args {
		cmd += " " + shq(a)
	}
	// markers around the worker say whether it started and how it ended
	cmd = "{ echo \"started as uid $(id -u)\"; " + cmd + "; rc=$?; echo \"exited with status $rc\"; exit $rc; } >>" +
		shq(logPath) + " 2>&1"
	as := strings.NewReplacer(`\`, `\\`, `"`, `\"`).Replace(cmd)
	script := `do shell script "` + as + `" with prompt "Backpack USB Writer needs an administrator password to write the USB drive." with administrator privileges`
	out, err := exec.Command("osascript", "-e", script).CombinedOutput()
	if err != nil && strings.Contains(string(out), "-128") {
		return true, nil
	}
	var ee *exec.ExitError
	if errors.As(err, &ee) {
		// the worker's own error is in the status file; osascript's message says how it ended
		return false, fmt.Errorf("%s", strings.TrimSpace(string(out)))
	}
	return false, err
}
