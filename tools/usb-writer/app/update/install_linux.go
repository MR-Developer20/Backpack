package update

import (
	"os"
	"os/exec"
)

func installTarget(exe string) string { return exe }

func replace(dl, target, _ string) (string, error) {
	if err := os.Chmod(dl, 0o755); err != nil {
		return "", err
	}
	// rename over the running binary: the running process keeps the old inode
	return target, os.Rename(dl, target)
}

func Restart(path string) error { return exec.Command(path).Start() }
