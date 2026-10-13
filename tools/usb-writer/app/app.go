package main

import (
	"bufio"
	"bytes"
	"context"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/assetserver"
	"github.com/wailsapp/wails/v2/pkg/options/linux"
	"github.com/wailsapp/wails/v2/pkg/options/mac"
	"github.com/wailsapp/wails/v2/pkg/options/windows"
	wr "github.com/wailsapp/wails/v2/pkg/runtime"

	"backpack/usbwriter/flash"
)

//go:embed all:frontend/dist
var assets embed.FS

// App is bound to the window; its exported methods are callable from frontend/dist/app.js.
type App struct {
	ctx     context.Context
	mu      sync.Mutex
	running bool
}

type Info struct {
	OS       string         `json:"os"`
	Version  string         `json:"version"`
	ISO      *flash.ISOInfo `json:"iso"`
	Elevated bool           `json:"elevated"`
}

type WriteRequest struct {
	ISO    string `json:"iso"`
	Device string `json:"device"`
	SizeGB int    `json:"sizeGB"`
	Keep   bool   `json:"keep"`
}

func (a *App) startup(ctx context.Context) { a.ctx = ctx }

func (a *App) Info() Info {
	return Info{OS: osName(), Version: version, ISO: findDefaultISO(), Elevated: elevated()}
}

func (a *App) Drives() ([]flash.Drive, error) {
	d, err := flash.ListDrives()
	if d == nil {
		d = []flash.Drive{}
	}
	return d, err
}

func (a *App) PickISO() (*flash.ISOInfo, error) {
	p, err := wr.OpenFileDialog(a.ctx, wr.OpenDialogOptions{
		Title: "Choose the Backpack ISO image",
		Filters: []wr.FileFilter{
			{DisplayName: "ISO images (*.iso)", Pattern: "*.iso"},
			{DisplayName: "All files", Pattern: "*"},
		},
	})
	if err != nil || p == "" {
		return nil, err
	}
	info := flash.InspectISO(p)
	return &info, nil
}

func (a *App) Inspect(path string) flash.ISOInfo { return flash.InspectISO(path) }

func (a *App) args(r WriteRequest) []string {
	args := []string{"--iso", r.ISO}
	if r.Keep {
		args = append(args, "--keep-persistence")
	} else {
		args = append(args, "--size", fmt.Sprintf("%dG", r.SizeGB))
	}
	return append(args, r.Device)
}

// Command is the equivalent command line, shown in the Run row.
func (a *App) Command(r WriteRequest) string {
	parts := []string{"backpack-usb-writer"}
	for _, s := range a.args(r) {
		parts = append(parts, shellQuote(s))
	}
	return strings.Join(parts, " ")
}

func shellQuote(s string) string {
	if s != "" && !strings.ContainsAny(s, " '\"$`\\!*?&;|<>()[]{}#~") || runtime.GOOS == "windows" && !strings.ContainsAny(s, " ") {
		return s
	}
	if runtime.GOOS == "windows" {
		return `"` + s + `"`
	}
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

func (a *App) emit(e flash.Event) { wr.EventsEmit(a.ctx, "job", e) }

// Write starts the job; progress arrives as "job" events. Without root/Administrator the
// work runs in a second, elevated copy of this program (pkexec on Linux, the macOS password
// prompt), which reports through a JSON-lines file this process follows.
func (a *App) Write(r WriteRequest) error {
	a.mu.Lock()
	if a.running {
		a.mu.Unlock()
		return errors.New("a write is already running")
	}
	a.running = true
	a.mu.Unlock()
	if r.SizeGB < 1 {
		r.SizeGB = 5
	}
	go func() {
		defer func() { a.mu.Lock(); a.running = false; a.mu.Unlock() }()
		if elevated() {
			flash.Run(flash.Options{ISO: r.ISO, Device: r.Device, Persist: int64(r.SizeGB) << 30, Keep: r.Keep}, a.emit)
			return
		}
		a.runElevated(r)
	}()
	return nil
}

func (a *App) runElevated(r WriteRequest) {
	dir, err := os.MkdirTemp("", "backpack-usb-writer-")
	if err != nil {
		a.emit(flash.Event{Error: err.Error(), End: true})
		return
	}
	defer os.RemoveAll(dir)
	status := filepath.Join(dir, "events.jsonl")
	if err := os.WriteFile(status, nil, 0o666); err != nil {
		a.emit(flash.Event{Error: err.Error(), End: true})
		return
	}
	os.Chmod(status, 0o666)
	exe, err := os.Executable()
	if err != nil {
		a.emit(flash.Event{Error: err.Error(), End: true})
		return
	}
	args := append([]string{"--yes", "--json", status}, a.args(r)...)
	a.emit(flash.Event{Phase: "auth", Log: "Asking for your password"})

	done := make(chan struct{})
	ended := false
	var wg sync.WaitGroup
	wg.Add(1)
	go func() { // follow the status file
		defer wg.Done()
		f, err := os.Open(status)
		if err != nil {
			return
		}
		defer f.Close()
		rd := bufio.NewReader(f)
		var part string
		for {
			line, err := rd.ReadString('\n')
			part += line
			if err == nil {
				var e flash.Event
				if json.Unmarshal([]byte(part), &e) == nil {
					ended = ended || e.End
					a.emit(e)
				}
				part = ""
				continue
			}
			select {
			case <-done:
				if line == "" {
					return
				}
			case <-time.After(150 * time.Millisecond):
			}
		}
	}()
	output := filepath.Join(dir, "output.log")
	cancelled, err := elevate(exe, args, output)
	close(done)
	wg.Wait()
	switch {
	case ended:
	case cancelled:
		a.emit(flash.Event{Error: "Authentication was cancelled. Nothing was written.", End: true})
	default:
		// the worker ended without a result: show what it printed and how it exited
		msg := "the writer stopped without reporting a result"
		if b, _ := os.ReadFile(output); len(bytes.TrimSpace(b)) > 0 {
			for _, l := range strings.Split(strings.TrimSpace(string(b)), "\n") {
				a.emit(flash.Event{Log: "worker: " + l})
			}
		}
		if err != nil && err.Error() != "" {
			msg += " (" + err.Error() + ")"
		}
		a.emit(flash.Event{Error: msg, End: true})
	}
}

func osName() string {
	switch runtime.GOOS {
	case "darwin":
		return "macOS"
	case "windows":
		return "Windows"
	}
	return "Linux"
}

func runGUI() error {
	app := &App{}
	return wails.Run(&options.App{
		Title:            "Backpack USB Writer",
		Width:            560,
		Height:           780,
		MinWidth:         480,
		MinHeight:        660,
		BackgroundColour: &options.RGBA{R: 7, G: 9, B: 10, A: 255},
		AssetServer:      &assetserver.Options{Assets: assets},
		OnStartup:        app.startup,
		Bind:             []interface{}{app},
		DragAndDrop:      &options.DragAndDrop{EnableFileDrop: true},
		Windows:          &windows.Options{Theme: windows.Dark},
		Mac: &mac.Options{
			Appearance: mac.NSAppearanceNameDarkAqua,
			About:      &mac.AboutInfo{Title: "Backpack USB Writer", Message: "Writes Backpack Live to a USB drive. " + version},
		},
		Linux: &linux.Options{ProgramName: "backpack-usb-writer"},
	})
}
