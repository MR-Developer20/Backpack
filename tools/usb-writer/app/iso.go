package main

import (
	"os"
	"path/filepath"
	"strings"

	"backpack/usbwriter/flash"
)

// findDefaultISO picks the newest backpack*.iso from the usual places, or nil.
func findDefaultISO() *flash.ISOInfo {
	var dirs []string
	if wd, err := os.Getwd(); err == nil {
		dirs = append(dirs, wd, filepath.Join(wd, "build"))
	}
	if exe, err := os.Executable(); err == nil {
		dirs = append(dirs, filepath.Dir(exe))
	}
	if home, err := os.UserHomeDir(); err == nil {
		dirs = append(dirs, filepath.Join(home, "Downloads"), filepath.Join(home, "Desktop"), home)
	}
	if d := xdgDownloads(); d != "" {
		dirs = append(dirs, d)
	}
	var best string
	var bestTime int64
	for _, d := range dirs {
		entries, _ := os.ReadDir(d)
		for _, e := range entries {
			n := strings.ToLower(e.Name())
			if e.IsDir() || !strings.HasPrefix(n, "backpack") || !strings.HasSuffix(n, ".iso") {
				continue
			}
			if st, err := e.Info(); err == nil && st.ModTime().Unix() > bestTime {
				best, bestTime = filepath.Join(d, e.Name()), st.ModTime().Unix()
			}
		}
	}
	if best == "" {
		return nil
	}
	info := flash.InspectISO(best)
	return &info
}
