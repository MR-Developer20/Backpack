package update

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

// SelfUpdate downloads the writer from r and puts it in place of the running program. It
// returns what to start to run the new version (see Restart).
func SelfUpdate(ctx context.Context, r *Release, progress func(done, total int64)) (string, error) {
	a := r.AppAsset()
	if a == nil {
		return "", errors.New("this release has no writer for this system")
	}
	exe, err := os.Executable()
	if err != nil {
		return "", err
	}
	if exe, err = filepath.EvalSymlinks(exe); err != nil {
		return "", err
	}
	target := installTarget(exe)
	dir := filepath.Dir(target)
	// download next to the target so the final rename stays on one filesystem
	tmp, err := os.MkdirTemp(dir, ".backpack-update-")
	if err != nil {
		return "", fmt.Errorf("cannot write to %s (download the new version from %s instead): %w", dir, r.Page, err)
	}
	defer os.RemoveAll(tmp)
	dl := filepath.Join(tmp, a.Name)
	if err := r.Download(ctx, a, dl, progress); err != nil {
		return "", err
	}
	return replace(dl, target, tmp)
}

// CleanupOld removes what a previous update left behind (Windows cannot delete a running .exe).
func CleanupOld() {
	if exe, err := os.Executable(); err == nil {
		os.Remove(exe + ".old")
	}
}
