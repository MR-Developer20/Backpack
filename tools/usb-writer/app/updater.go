package main

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"

	wr "github.com/wailsapp/wails/v2/pkg/runtime"

	"backpack/usbwriter/flash"
	"backpack/usbwriter/update"
)

// UpdateInfo is what the window shows about the newest release.
type UpdateInfo struct {
	Current string `json:"current"`
	Latest  string `json:"latest"` // tag, "" when there is no release yet
	Page    string `json:"page"`
	Newer   bool   `json:"newer"`   // a newer writer for this system exists
	ISOName string `json:"isoName"` // the release's ISO (normal edition), if any
	ISOSize int64  `json:"isoSize"`
	// the + extras edition (Extra tab apps), if the release has one
	ExtrasName string `json:"extrasName"`
	ExtrasSize int64  `json:"extrasSize"`
}

// UpdateEvent reports a download ("app" or "iso") on the "update" event.
type UpdateEvent struct {
	Kind  string         `json:"kind"`
	Done  int64          `json:"done,omitempty"`
	Total int64          `json:"total,omitempty"`
	Ready bool           `json:"ready,omitempty"`
	Error string         `json:"error,omitempty"`
	ISO   *flash.ISOInfo `json:"iso,omitempty"`
}

var (
	relMu   sync.Mutex
	rel     *update.Release
	busy    = map[string]bool{}
	restart string
)

func latest(ctx context.Context) (*update.Release, error) {
	relMu.Lock()
	defer relMu.Unlock()
	if rel != nil {
		return rel, nil
	}
	r, err := update.Latest(ctx)
	if err == nil {
		rel = r
	}
	return r, err
}

// CheckUpdate asks GitHub for the newest release.
func (a *App) CheckUpdate() (UpdateInfo, error) {
	info := UpdateInfo{Current: version}
	r, err := latest(a.ctx)
	if err != nil || r == nil {
		return info, err
	}
	info.Latest, info.Page = r.Tag, r.Page
	info.Newer = update.Newer(version, r.Tag) && r.AppAsset() != nil
	if iso := r.ISOAsset(false); iso != nil {
		info.ISOName, info.ISOSize = iso.Name, iso.Size
	}
	if iso := r.ISOAsset(true); iso != nil {
		info.ExtrasName, info.ExtrasSize = iso.Name, iso.Size
	}
	return info, nil
}

func (a *App) start(kind string, job func(progress func(d, t int64)) (UpdateEvent, error)) error {
	relMu.Lock()
	if busy[kind] {
		relMu.Unlock()
		return errors.New("already downloading")
	}
	busy[kind] = true
	relMu.Unlock()
	go func() {
		defer func() { relMu.Lock(); busy[kind] = false; relMu.Unlock() }()
		ev, err := job(func(d, t int64) { wr.EventsEmit(a.ctx, "update", UpdateEvent{Kind: kind, Done: d, Total: t}) })
		ev.Kind = kind
		if err != nil {
			ev.Error = err.Error()
		} else {
			ev.Ready = true
		}
		wr.EventsEmit(a.ctx, "update", ev)
	}()
	return nil
}

// InstallUpdate downloads the newer writer and puts it in place; RestartApp then switches to it.
func (a *App) InstallUpdate() error {
	return a.start("app", func(p func(d, t int64)) (UpdateEvent, error) {
		r, err := latest(a.ctx)
		if err != nil || r == nil {
			return UpdateEvent{}, errors.New("no release found")
		}
		path, err := update.SelfUpdate(a.ctx, r, p)
		if err == nil {
			relMu.Lock()
			restart = path
			relMu.Unlock()
		}
		return UpdateEvent{}, err
	})
}

// RestartApp starts the updated program and closes this one.
func (a *App) RestartApp() error {
	relMu.Lock()
	path := restart
	relMu.Unlock()
	if path == "" {
		return errors.New("no update installed")
	}
	if err := update.Restart(path); err != nil {
		return err
	}
	wr.Quit(a.ctx)
	return nil
}

// DownloadISO saves the release's ISO (with extras: the + extras edition) into Downloads and
// makes it the chosen image.
func (a *App) DownloadISO(extras bool) error {
	return a.start("iso", func(p func(d, t int64)) (UpdateEvent, error) {
		path, err := downloadISO(a.ctx, extras, p)
		if err != nil {
			return UpdateEvent{}, err
		}
		info := flash.InspectISO(path)
		return UpdateEvent{ISO: &info}, nil
	})
}

func downloadISO(ctx context.Context, extras bool, p func(d, t int64)) (string, error) {
	r, err := latest(ctx)
	if err != nil {
		return "", err
	}
	if r == nil || r.ISOAsset(extras) == nil {
		if extras {
			return "", errors.New("the newest release has no + extras ISO")
		}
		return "", errors.New("no released ISO found")
	}
	dir := downloadsDir()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	a := r.ISOAsset(extras)
	dst := filepath.Join(dir, a.Name)
	return dst, r.Download(ctx, a, dst, p)
}

func downloadsDir() string {
	if d := xdgDownloads(); d != "" {
		return d
	}
	if home, err := os.UserHomeDir(); err == nil {
		return filepath.Join(home, "Downloads")
	}
	return "."
}

// xdgDownloads is the desktop's own Downloads folder on Linux (XDG_DOWNLOAD_DIR in
// user-dirs.dirs), which non-English desktops name in their language; "" when unset.
func xdgDownloads() string {
	if runtime.GOOS != "linux" {
		return ""
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	conf := os.Getenv("XDG_CONFIG_HOME")
	if conf == "" {
		conf = filepath.Join(home, ".config")
	}
	b, err := os.ReadFile(filepath.Join(conf, "user-dirs.dirs"))
	if err != nil {
		return ""
	}
	for _, l := range strings.Split(string(b), "\n") {
		v, ok := strings.CutPrefix(strings.TrimSpace(l), "XDG_DOWNLOAD_DIR=")
		if !ok {
			continue
		}
		v = strings.Trim(v, `"`)
		if rest, ok := strings.CutPrefix(v, "$HOME"); ok {
			v = home + rest
		}
		// set to $HOME itself means the desktop has no Downloads folder
		if !filepath.IsAbs(v) || filepath.Clean(v) == filepath.Clean(home) {
			return ""
		}
		return filepath.Clean(v)
	}
	return ""
}
