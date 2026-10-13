// Backpack USB Writer: one program for Linux, Windows and macOS that writes the Backpack Live
// ISO to a USB drive and adds the ext persistence partition (see flash/). With no arguments it
// opens the window (Wails, frontend/dist); with arguments it is a command-line writer, which the
// window also uses as its elevated worker.
package main

import (
	"fmt"
	"os"
	"strings"

	"backpack/usbwriter/update"
)

var version = "dev"

func main() {
	update.CleanupOld()
	// macOS passes -psn_... to apps opened from Finder on old systems
	if len(os.Args) > 1 && !strings.HasPrefix(os.Args[1], "-psn_") {
		os.Exit(cli(os.Args[1:]))
	}
	if err := runGUI(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
