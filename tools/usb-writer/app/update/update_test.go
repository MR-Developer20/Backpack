package update

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestNewer(t *testing.T) {
	for _, c := range []struct {
		cur, tag string
		want     bool
	}{
		{"v1.0.0", "v1.0.1", true}, {"v1.2.0", "v1.10.0", true}, {"v1.2.0", "v1.2.0", false},
		{"v2.0.0", "v1.9.9", false}, {"dev", "v1.0.0", true}, {"0.0.0-abc1234", "v0.1.0", true},
		{"v1.0.0", "nightly", false}, {"1.0", "v1.0.1", true},
	} {
		if got := Newer(c.cur, c.tag); got != c.want {
			t.Errorf("Newer(%q, %q) = %v", c.cur, c.tag, got)
		}
	}
}

func TestDownloadVerifies(t *testing.T) {
	body := []byte("backpack iso bytes")
	sum := sha256.Sum256(body)
	good := hex.EncodeToString(sum[:])
	sums := good + "  backpack.iso\n" + strings.Repeat("0", 64) + "  bad.iso\n"
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/SHA256SUMS":
			w.Write([]byte(sums))
		default:
			w.Write(body)
		}
	}))
	defer srv.Close()
	r := &Release{Assets: []Asset{
		{Name: "SHA256SUMS", URL: srv.URL + "/SHA256SUMS"},
		{Name: "backpack.iso", URL: srv.URL + "/a", Size: int64(len(body))},
		{Name: "bad.iso", URL: srv.URL + "/b", Size: int64(len(body))},
	}}
	dir := t.TempDir()
	var last int64
	if err := r.Download(context.Background(), &r.Assets[1], filepath.Join(dir, "ok.iso"), func(d, _ int64) { last = d }); err != nil {
		t.Fatal(err)
	}
	if got, _ := os.ReadFile(filepath.Join(dir, "ok.iso")); string(got) != string(body) || last != int64(len(body)) {
		t.Fatalf("got %q, progress %d", got, last)
	}
	if err := r.Download(context.Background(), &r.Assets[2], filepath.Join(dir, "bad.iso"), func(int64, int64) {}); err == nil {
		t.Fatal("checksum mismatch accepted")
	}
	if _, err := os.Stat(filepath.Join(dir, "bad.iso")); err == nil {
		t.Fatal("bad download kept")
	}
}

func TestISOAsset(t *testing.T) {
	r := Release{Assets: []Asset{
		{Name: "Backpack_USB_Writer-v1.0-linux-x86_64"},
		{Name: "Backpack_USB_Writer-v1.0-linux-x86_64.iso"},
		{Name: "backpack-live-v1.0-amd64.iso"},
	}}
	if a := r.ISOAsset(); a == nil || a.Name != "backpack-live-v1.0-amd64.iso" {
		t.Fatalf("ISOAsset = %+v", a)
	}
}
