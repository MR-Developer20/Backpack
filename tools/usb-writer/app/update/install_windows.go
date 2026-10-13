package update

import (
	"os"
	"os/exec"
)

func installTarget(exe string) string { return exe }

// A running .exe cannot be overwritten but can be renamed: move it aside, put the new one in
// its place; CleanupOld deletes the old one on the next start.
func replace(dl, target, _ string) (string, error) {
	os.Remove(target + ".old")
	if err := os.Rename(target, target+".old"); err != nil {
		return "", err
	}
	if err := os.Rename(dl, target); err != nil {
		os.Rename(target+".old", target)
		return "", err
	}
	return target, nil
}

func Restart(path string) error { return exec.Command(path).Start() }
