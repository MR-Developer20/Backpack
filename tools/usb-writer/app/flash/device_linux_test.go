package flash

import (
	"os"
	"strings"
	"testing"
)

// TestLoopDevice writes a real block device the way a USB stick is written: unmount, exclusive
// open, partition re-read. It needs root and an attached loop device:
//
//	BACKPACK_TEST_LOOP=$(sudo losetup -f --show disk.img) sudo -E go test -run LoopDevice ./flash
func TestLoopDevice(t *testing.T) {
	dev := os.Getenv("BACKPACK_TEST_LOOP")
	if dev == "" {
		t.Skip("BACKPACK_TEST_LOOP is not set")
	}
	e2fsckPath(t)
	allowLoop = true
	defer func() { allowLoop = false }()
	iso := fakeISO(t, 40000, 0xAB)
	var log []string
	emit := func(e Event) {
		if e.Log != "" {
			log = append(log, e.Log)
		}
	}
	if err := Run(Options{ISO: iso, Device: dev, Persist: 300 << 20}, emit); err != nil {
		t.Fatalf("fresh: %v\n%s", err, strings.Join(log, "\n"))
	}
	uuid := partitionUUID(t, dev, 40960, 300<<20/512)
	if uuid == "" {
		t.Fatal("no filesystem UUID after the fresh write")
	}
	if err := Run(Options{ISO: fakeISO(t, 38000, 0xCD), Device: dev, Keep: true}, emit); err != nil {
		t.Fatalf("keep: %v\n%s", err, strings.Join(log, "\n"))
	}
	if got := partitionUUID(t, dev, 40960, 300<<20/512); got != uuid {
		t.Fatalf("persistence UUID %q after keep, was %q", got, uuid)
	}
	t.Log(strings.Join(log, "\n"))
}
