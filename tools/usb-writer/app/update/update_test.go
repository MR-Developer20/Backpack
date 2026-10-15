package update

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
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

// TestDownloadParallel: ranged parts reassemble, a part whose connection drops resumes, and a
// server without Range support falls back to one stream.
func TestDownloadParallel(t *testing.T) {
	defer func(m int64) { parallelMin = m }(parallelMin)
	parallelMin = 1
	body := make([]byte, 3<<20+12345)
	for i := range body {
		body[i] = byte(i * 7 / 3)
	}
	sum := sha256.Sum256(body)
	var mu sync.Mutex
	ranged, dropped := 0, false
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/SHA256SUMS":
			fmt.Fprintf(w, "%x  a.iso\n%x  b.iso\n", sum, sum)
		case "/a":
			mu.Lock()
			if r.Header.Get("Range") != "" {
				ranged++
			}
			drop := !dropped && strings.HasPrefix(r.Header.Get("Range"), "bytes=0-")
			dropped = dropped || drop
			mu.Unlock()
			if drop { // send half of the first part, then cut the connection
				w.Header().Set("Content-Range", fmt.Sprintf("bytes 0-%d/%d", len(body)/8, len(body)))
				w.Header().Set("Content-Length", fmt.Sprint(len(body)/8+1))
				w.WriteHeader(http.StatusPartialContent)
				w.Write(body[:len(body)/16])
				panic(http.ErrAbortHandler)
			}
			http.ServeContent(w, r, "a.iso", time.Time{}, bytes.NewReader(body))
		case "/b":
			w.Write(body) // ignores Range
		}
	}))
	defer srv.Close()
	r := &Release{Assets: []Asset{
		{Name: "SHA256SUMS", URL: srv.URL + "/SHA256SUMS"},
		{Name: "a.iso", URL: srv.URL + "/a", Size: int64(len(body))},
		{Name: "b.iso", URL: srv.URL + "/b", Size: int64(len(body))},
	}}
	dir := t.TempDir()
	for _, a := range r.Assets[1:] {
		var last int64
		dst := filepath.Join(dir, a.Name)
		if err := r.Download(context.Background(), &a, dst, func(d, _ int64) { last = d }); err != nil {
			t.Fatalf("%s: %v", a.Name, err)
		}
		if got, _ := os.ReadFile(dst); !bytes.Equal(got, body) || last != int64(len(body)) {
			t.Fatalf("%s: wrong content or progress %d", a.Name, last)
		}
	}
	if ranged < Parts+1 || !dropped {
		t.Fatalf("ranged requests %d, dropped %v", ranged, dropped)
	}
}

// GitHub's CDN speaks HTTP/2, where Go would multiplex every part onto one connection.
func TestDownloadPartsUseOwnConnections(t *testing.T) {
	defer func(m int64, c *http.Client) { parallelMin, client = m, c }(parallelMin, client)
	parallelMin = 1
	body := bytes.Repeat([]byte("backpack"), 1<<17)
	sum := sha256.Sum256(body)
	var mu sync.Mutex
	conns, waiting, protos, allIn := 0, 0, map[string]bool{}, make(chan struct{})
	srv := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		protos[r.Proto] = true
		mu.Unlock()
		if r.URL.Path == "/SHA256SUMS" {
			fmt.Fprintf(w, "%x  a.iso\n", sum)
			return
		}
		// hold every part until all are in flight, so none can reuse a finished part's connection
		mu.Lock()
		if waiting++; waiting == Parts {
			close(allIn)
		}
		mu.Unlock()
		select {
		case <-allIn:
		case <-time.After(5 * time.Second):
		}
		http.ServeContent(w, r, "a.iso", time.Time{}, bytes.NewReader(body))
	}))
	srv.EnableHTTP2 = true
	srv.Config.ConnState = func(_ net.Conn, s http.ConnState) {
		if s == http.StateNew {
			mu.Lock()
			conns++
			mu.Unlock()
		}
	}
	srv.StartTLS()
	defer srv.Close()
	tr := client.Transport.(*http.Transport).Clone()
	tr.TLSClientConfig = srv.Client().Transport.(*http.Transport).TLSClientConfig
	client = &http.Client{Transport: tr}

	r := &Release{Assets: []Asset{
		{Name: "SHA256SUMS", URL: srv.URL + "/SHA256SUMS"},
		{Name: "a.iso", URL: srv.URL + "/a", Size: int64(len(body))},
	}}
	if err := r.Download(context.Background(), &r.Assets[1], filepath.Join(t.TempDir(), "a.iso"), func(int64, int64) {}); err != nil {
		t.Fatal(err)
	}
	if protos["HTTP/2.0"] || conns < Parts {
		t.Fatalf("protocols %v over %d connections, want HTTP/1.1 over >= %d", protos, conns, Parts)
	}
}
