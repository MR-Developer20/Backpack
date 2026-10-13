package flash

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

func TestWorkerISO(t *testing.T) {
	src := filepath.Join(t.TempDir(), "backpack-live-test-amd64.iso")
	want := bytes.Repeat([]byte("backpack"), 4096)
	if err := os.WriteFile(src, want, 0o644); err != nil {
		t.Fatal(err)
	}
	for _, dir := range []string{t.TempDir(), "/tmp"} { // same volume (clone) and, maybe, another (copy)
		d, err := os.MkdirTemp(dir, "worker-")
		if err != nil {
			t.Fatal(err)
		}
		defer os.RemoveAll(d)
		got, err := WorkerISO(src, d, func(string) {})
		if err != nil {
			t.Fatal(err)
		}
		if filepath.Dir(got) != d || filepath.Base(got) != filepath.Base(src) {
			t.Fatalf("workerISO put the image at %s, want it in %s", got, d)
		}
		if b, _ := os.ReadFile(got); !bytes.Equal(b, want) {
			t.Fatalf("%s: content differs", got)
		}
	}
}
