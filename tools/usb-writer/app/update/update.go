// Package update finds the newest GitHub release of Backpack and downloads its files: the writer
// for this system (to replace the running program) and the ISO. Every download is checked against
// the release's SHA256SUMS.
package update

import (
	"bufio"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"runtime"
	"strconv"
	"strings"
	"time"
)

// Repo is the GitHub repository releases come from (owner/name).
var Repo = "MR-Developer20/backpack"

type Asset struct {
	Name string `json:"name"`
	URL  string `json:"browser_download_url"`
	Size int64  `json:"size"`
}

type Release struct {
	Tag    string  `json:"tag_name"`
	Name   string  `json:"name"`
	Page   string  `json:"html_url"`
	Assets []Asset `json:"assets"`
}

var client = &http.Client{Timeout: 0}

func get(ctx context.Context, url string) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "backpack-usb-writer")
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode != http.StatusOK {
		resp.Body.Close()
		return nil, fmt.Errorf("%s: %s", url, resp.Status)
	}
	return resp, nil
}

// Latest returns the newest published release, or nil when there is none yet.
func Latest(ctx context.Context) (*Release, error) {
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, "https://api.github.com/repos/"+Repo+"/releases/latest", nil)
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "backpack-usb-writer")
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotFound {
		return nil, nil
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("GitHub: %s", resp.Status)
	}
	var r Release
	if err := json.NewDecoder(resp.Body).Decode(&r); err != nil {
		return nil, err
	}
	return &r, nil
}

func (r *Release) find(match func(string) bool) *Asset {
	for i := range r.Assets {
		if match(r.Assets[i].Name) {
			return &r.Assets[i]
		}
	}
	return nil
}

// AppAsset is the writer built for this system.
func (r *Release) AppAsset() *Asset {
	suffix := map[string]string{"linux": "-linux-x86_64", "windows": "-windows-x86_64.exe", "darwin": "-macos-universal.zip"}[runtime.GOOS]
	if suffix == "" || runtime.GOOS != "darwin" && runtime.GOARCH != "amd64" {
		return nil
	}
	return r.find(func(n string) bool {
		return strings.HasPrefix(n, "Backpack_USB_Writer-") && strings.HasSuffix(n, suffix)
	})
}

// ISOAsset is the live image.
func (r *Release) ISOAsset() *Asset {
	return r.find(func(n string) bool {
		n = strings.ToLower(n)
		return strings.HasPrefix(n, "backpack-live-") && strings.HasSuffix(n, ".iso")
	})
}

// checksums reads the release's SHA256SUMS (sha256sum format).
func (r *Release) checksums(ctx context.Context) (map[string]string, error) {
	a := r.find(func(n string) bool { return n == "SHA256SUMS" })
	if a == nil {
		return nil, errors.New("the release has no SHA256SUMS")
	}
	resp, err := get(ctx, a.URL)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	sums := map[string]string{}
	sc := bufio.NewScanner(resp.Body)
	for sc.Scan() {
		f := strings.Fields(sc.Text())
		if len(f) == 2 {
			sums[strings.TrimPrefix(f[1], "*")] = strings.ToLower(f[0])
		}
	}
	return sums, sc.Err()
}

// Download fetches a to dst (written as dst.part, renamed when complete) and checks its SHA-256
// against the release's SHA256SUMS. A dst that already matches is kept without downloading.
func (r *Release) Download(ctx context.Context, a *Asset, dst string, progress func(done, total int64)) error {
	sums, err := r.checksums(ctx)
	if err != nil {
		return err
	}
	want := sums[a.Name]
	if want == "" {
		return fmt.Errorf("%s is not listed in SHA256SUMS", a.Name)
	}
	if st, err := os.Stat(dst); err == nil && st.Size() == a.Size {
		if got, err := fileSHA(dst); err == nil && got == want {
			progress(a.Size, a.Size)
			return nil
		}
	}
	part := dst + ".part"
	if err := fetch(ctx, a.URL, part, a.Size, progress); err != nil {
		os.Remove(part)
		return err
	}
	if got, err := fileSHA(part); err != nil || got != want {
		os.Remove(part)
		if err != nil {
			return err
		}
		return fmt.Errorf("%s: checksum mismatch, download discarded", a.Name)
	}
	return os.Rename(part, dst)
}

func fileSHA(p string) (string, error) {
	f, err := os.Open(p)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// Newer reports whether release tag is a newer version than current. Development builds
// ("dev", "0.0.0-<sha>") are older than every release.
func Newer(current, tag string) bool {
	c, okC := parse(current)
	t, okT := parse(tag)
	if !okT {
		return false
	}
	if !okC {
		return true
	}
	for i := range t {
		if t[i] != c[i] {
			return t[i] > c[i]
		}
	}
	return false
}

func parse(v string) ([3]int, bool) {
	var out [3]int
	v = strings.TrimPrefix(strings.TrimSpace(v), "v")
	if i := strings.IndexAny(v, "-+"); i >= 0 {
		v = v[:i]
	}
	parts := strings.Split(v, ".")
	if len(parts) == 0 || len(parts) > 3 {
		return out, false
	}
	for i, p := range parts {
		n, err := strconv.Atoi(p)
		if err != nil {
			return out, false
		}
		out[i] = n
	}
	return out, out != [3]int{}
}
