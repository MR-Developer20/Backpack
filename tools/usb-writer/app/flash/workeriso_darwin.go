package flash

import (
	"io"
	"os"
	"path/filepath"

	"golang.org/x/sys/unix"
)

// WorkerISO gives the root worker a copy of the ISO it can open. macOS privacy protection
// (TCC) keeps a root process started through the password prompt out of ~/Downloads, ~/Desktop
// and ~/Documents even though this window may read them, so the image goes into the worker's
// folder: an APFS clone (instant, no extra space) when it is on the same volume, else a copy.
func WorkerISO(iso, dir string, emit func(string)) (string, error) {
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
