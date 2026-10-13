//go:build !darwin

package flash

// WorkerISO: pkexec'd root on Linux reads the ISO where it is; Windows writes in-process.
func WorkerISO(iso, dir string, emit func(string)) (string, error) { return iso, nil }
