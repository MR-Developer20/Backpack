package update

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// installTarget is the .app bundle around the executable (X.app/Contents/MacOS/exe).
func installTarget(exe string) string {
	b := filepath.Dir(filepath.Dir(filepath.Dir(exe)))
	if strings.HasSuffix(b, ".app") {
		return b
	}
	return exe
}

func replace(dl, target, tmp string) (string, error) {
	if !strings.HasSuffix(target, ".app") {
		return "", errors.New("not running from an .app bundle: unzip the new version by hand")
	}
	out := filepath.Join(tmp, "x")
	if b, err := exec.Command("ditto", "-x", "-k", dl, out).CombinedOutput(); err != nil {
		return "", errors.New("unzip: " + strings.TrimSpace(string(b)))
	}
	apps, _ := filepath.Glob(filepath.Join(out, "*.app"))
	if len(apps) != 1 {
		return "", errors.New("the download holds no .app")
	}
	old := filepath.Join(tmp, "old.app")
	if err := os.Rename(target, old); err != nil {
		return "", err
	}
	if err := os.Rename(apps[0], target); err != nil {
		os.Rename(old, target)
		return "", err
	}
	return target, nil
}

func Restart(path string) error { return exec.Command("open", "-n", path).Start() }
