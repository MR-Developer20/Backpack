package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"strings"
	"sync"

	"backpack/usbwriter/flash"
	"backpack/usbwriter/update"
)

const usage = `Backpack USB Writer %s: write the Backpack Live ISO to a USB drive and add a persistence partition.

Usage:
  backpack-usb-writer                          open the window
  backpack-usb-writer --list                   list USB drives
  backpack-usb-writer --update                 update this program from the newest release
  backpack-usb-writer --download-iso           download the newest release's ISO into Downloads
  backpack-usb-writer [options] DEVICE         write from the command line (needs root / Administrator)

DEVICE is /dev/sdX (Linux), /dev/diskN (macOS) or \\.\PhysicalDriveN (Windows), or a disk image file.

Options:
`

// cli runs the command-line mode and returns the exit code.
func cli(args []string) int {
	attachConsole()
	fs := flag.NewFlagSet("backpack-usb-writer", flag.ContinueOnError)
	iso := fs.String("iso", "", "ISO image to write (default: newest backpack*.iso in Downloads or the current directory)")
	size := fs.String("size", "5G", "persistence partition size (fresh install)")
	keep := fs.Bool("keep-persistence", false, "update the system only: keep the existing persistence partition")
	force := fs.Bool("force", false, "allow drives larger than 256 GB")
	yes := fs.Bool("yes", false, "do not ask for confirmation")
	jsonOut := fs.String("json", "", "append progress events as JSON lines to this file (used by the window)")
	list := fs.Bool("list", false, "list USB drives and exit")
	ver := fs.Bool("version", false, "print the version and exit")
	upd := fs.Bool("update", false, "replace this program with the newest release and exit")
	getISO := fs.Bool("download-iso", false, "download the newest release's ISO into Downloads and exit")
	fs.Usage = func() {
		fmt.Fprintf(fs.Output(), usage, version)
		fs.PrintDefaults()
	}
	if err := fs.Parse(args); err != nil {
		return 2
	}
	switch {
	case *ver:
		fmt.Println(version)
		return 0
	case *upd:
		return cliUpdate()
	case *getISO:
		return cliDownloadISO()
	case *list:
		drives, err := flash.ListDrives()
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		if len(drives) == 0 {
			fmt.Println("No USB drive found.")
		}
		for _, d := range drives {
			extra := ""
			if d.Persistence {
				extra = "  [persistence]"
			}
			fmt.Printf("%-22s %-9s %-5s %s%s\n", d.Path, flash.Human(d.Size), d.Bus, d.Name, extra)
		}
		return 0
	}
	// The window's worker reports through --json: open it first, so every failure below,
	// a panic included, reaches the window instead of a terminal nobody sees.
	emit := printEvent
	fail := func(code int, err error) int {
		fmt.Fprintln(os.Stderr, err)
		return code
	}
	if *jsonOut != "" {
		f, err := os.OpenFile(*jsonOut, os.O_WRONLY|os.O_APPEND|os.O_CREATE, 0o644)
		if err != nil {
			return fail(1, err)
		}
		defer f.Close()
		var mu sync.Mutex
		enc := json.NewEncoder(f)
		emit = func(e flash.Event) {
			mu.Lock()
			enc.Encode(e)
			f.Sync()
			mu.Unlock()
		}
		fail = func(code int, err error) int {
			emit(flash.Event{Error: err.Error(), End: true})
			return code
		}
		defer func() {
			if r := recover(); r != nil {
				emit(flash.Event{Error: fmt.Sprintf("internal error: %v", r), End: true})
				panic(r)
			}
		}()
	}
	if fs.NArg() != 1 {
		if *jsonOut != "" {
			return fail(2, fmt.Errorf("expected one drive, got %q", fs.Args()))
		}
		fs.Usage()
		return 2
	}
	o := flash.Options{ISO: *iso, Device: fs.Arg(0), Keep: *keep, Force: *force}
	if o.ISO == "" {
		if info := findDefaultISO(); info != nil {
			o.ISO = info.Path
		} else {
			return fail(2, errors.New("no ISO given and no backpack*.iso found: use --iso FILE"))
		}
	}
	if !o.Keep {
		n, err := flash.ParseSize(*size)
		if err != nil {
			return fail(2, err)
		}
		o.Persist = n
	}

	if !*yes && *jsonOut == "" {
		if o.Keep {
			fmt.Printf("The system on %s will be replaced with %s. The persistence partition is kept.\n", o.Device, o.ISO)
		} else {
			fmt.Printf("EVERYTHING on %s will be erased and replaced with %s + %s persistence.\n", o.Device, o.ISO, *size)
		}
		fmt.Printf("Type the device name (%s) to continue: ", o.Device)
		line, _ := bufio.NewReader(os.Stdin).ReadString('\n')
		if strings.TrimSpace(line) != o.Device {
			fmt.Println("aborted")
			return 1
		}
	}
	if err := flash.Run(o, emit); err != nil {
		if *jsonOut == "" {
			fmt.Fprintln(os.Stderr, "\nerror:", err)
		}
		return 1
	}
	return 0
}

var lastPhase string

func printEvent(e flash.Event) {
	if e.Log != "" {
		if lastPhase == "progress" {
			fmt.Println()
		}
		fmt.Println(e.Log)
		lastPhase = ""
	}
	if e.Total > 0 && e.Error == "" {
		fmt.Printf("\r%-9s %3d%%  %s of %s   ", e.Phase, e.Done*100/e.Total, flash.Human(e.Done), flash.Human(e.Total))
		lastPhase = "progress"
	}
}

func cliProgress(d, t int64) {
	if t > 0 {
		fmt.Printf("\r%3d%%  %s of %s   ", d*100/t, flash.Human(d), flash.Human(t))
	}
}

func cliUpdate() int {
	r, err := update.Latest(context.Background())
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	if r == nil || !update.Newer(version, r.Tag) {
		fmt.Printf("Backpack USB Writer %s is up to date.\n", version)
		return 0
	}
	fmt.Printf("Updating %s -> %s\n", version, r.Tag)
	path, err := update.SelfUpdate(context.Background(), r, cliProgress)
	fmt.Println()
	if err != nil {
		fmt.Fprintln(os.Stderr, "update failed:", err)
		return 1
	}
	fmt.Println("Installed", path)
	return 0
}

func cliDownloadISO() int {
	path, err := downloadISO(context.Background(), cliProgress)
	fmt.Println()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	fmt.Println("Saved", path)
	return 0
}
