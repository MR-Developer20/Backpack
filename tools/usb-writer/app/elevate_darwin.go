package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"golang.org/x/sys/unix"
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
	cmd = "cd / && { echo \"started as uid $(id -u)\"; " + cmd + "; rc=$?; echo \"exited with status $rc\"; exit $rc; } >>" +
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

// workerISO gives the root worker a copy of the ISO it can open. macOS privacy protection
// (TCC) keeps a root process started through the password prompt out of ~/Downloads, ~/Desktop
// and ~/Documents even though this window may read them, so the image goes into the worker's
// folder: an APFS clone (instant, no extra space) when it is on the same volume, else a copy.
func workerISO(iso, dir string, emit func(string)) (string, error) {
	dst := filepath.Join(dir, filepath.Base(iso))
	if unix.Clonefile(iso, dst, unix.CLONE_NOFOLLOW) == nil {
		return dst, nil
	}
	emit("Copying the image where the writer can read it")
	src, err := os.Open(iso)
	if err != nil {
		return "", err
	}
	defer src.Close()
	out, err := os.Create(dst)
	if err != nil {
		return "", err
	}
	if _, err = io.Copy(out, src); err != nil {
		out.Close()
		return "", err
	}
	return dst, out.Close()
}
