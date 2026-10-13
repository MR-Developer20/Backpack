package flash

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

// authopen needs a password dialog for a normal user; CI runs this test binary as root,
// where authopen grants the descriptor without asking.
func TestAuthOpen(t *testing.T) {
	if os.Geteuid() != 0 {
		t.Skip("needs root (authopen would show a password dialog)")
	}
	p := filepath.Join(t.TempDir(), "disk.img")
	if err := os.WriteFile(p, make([]byte, 4096), 0o600); err != nil {
		t.Fatal(err)
	}
	f, err := authOpen(p)
	if err != nil {
		t.Fatal(err)
	}
	want := []byte("backpack")
	if _, err := f.WriteAt(want, 512); err != nil {
		t.Fatal(err)
	}
	got := make([]byte, len(want))
	if _, err := f.ReadAt(got, 512); err != nil || !bytes.Equal(got, want) {
		t.Fatalf("read back %q, %v", got, err)
	}
	f.Close()
}
