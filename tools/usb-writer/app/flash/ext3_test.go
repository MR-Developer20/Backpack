package flash

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// The formatter's output must pass e2fsck untouched and carry the label and files.
func TestFormatExt3Fsck(t *testing.T) {
	e2fsck, err := exec.LookPath("e2fsck")
	if err != nil {
		if _, err = os.Stat("/usr/sbin/e2fsck"); err != nil {
			t.Skip("e2fsck not installed")
		}
		e2fsck = "/usr/sbin/e2fsck"
	}
	sizes := []int64{64 << 20, 1 << 30, 5 << 30, 5<<30 + 123<<20, 40 << 30}
	if testing.Short() {
		sizes = sizes[:2]
	}
	for _, size := range sizes {
		img := filepath.Join(t.TempDir(), "fs.img")
		f, err := os.Create(img)
		if err != nil {
			t.Fatal(err)
		}
		const off = 3 << 20 // exercise the partition offset
		if err := f.Truncate(off + size); err != nil {
			t.Fatal(err)
		}
		conf := []byte("/home\n/var/lib/backpack\n/etc/NetworkManager\n")
		if err := FormatExt3(f, off, size, "persistence", map[string][]byte{"persistence.conf": conf}, nil); err != nil {
			t.Fatal(err)
		}
		f.Close()
		part := img + ".part"
		// e2fsck has no offset option: copy the partition out (sparse-aware via dd skip)
		if out, err := exec.Command("dd", "if="+img, "of="+part, "bs=1M", "skip=3", "conv=sparse", "status=none").CombinedOutput(); err != nil {
			t.Fatalf("dd: %v %s", err, out)
		}
		out, err := exec.Command(e2fsck, "-fn", part).CombinedOutput()
		if err != nil {
			t.Fatalf("size %d: e2fsck: %v\n%s", size, err, out)
		}
		if l, ok := ExtLabel(mustOpen(t, part), 0); !ok || l != "persistence" {
			t.Fatalf("label %q %v", l, ok)
		}
		if debugfs, err := exec.LookPath("debugfs"); err == nil || fileExists("/usr/sbin/debugfs") {
			if debugfs == "" {
				debugfs = "/usr/sbin/debugfs"
			}
			got, err := exec.Command(debugfs, "-R", "cat /persistence.conf", part).Output()
			if err != nil || string(got) != string(conf) {
				t.Fatalf("persistence.conf = %q (%v)", got, err)
			}
			feat, _ := exec.Command(debugfs, "-R", "features", part).Output()
			if !strings.Contains(string(feat), "has_journal") {
				t.Fatalf("no journal: %s", feat)
			}
		}
		os.Remove(part)
	}
}

func mustOpen(t *testing.T, p string) *os.File {
	f, err := os.Open(p)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { f.Close() })
	return f
}

func fileExists(p string) bool { _, err := os.Stat(p); return err == nil }
