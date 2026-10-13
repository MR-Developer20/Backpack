package update

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"sync"
	"sync/atomic"
	"time"
)

// Parts is how many connections a large download uses. GitHub's release CDN limits each
// connection, so one stream is slow on many home lines; ranged parts add up.
var Parts = 8

var parallelMin int64 = 64 << 20 // smaller files use one connection

const partRetries = 4

var errNoRange = errors.New("server ignores Range requests")

// fetch downloads url (size bytes) into a new file at dst, in parallel ranges when it can.
func fetch(ctx context.Context, url, dst string, size int64, progress func(done, total int64)) error {
	f, err := os.Create(dst)
	if err != nil {
		return err
	}
	var done atomic.Int64
	stop := make(chan struct{})
	ticked := make(chan struct{})
	go func() { // progress at most 5 times a second, from one goroutine
		defer close(ticked)
		t := time.NewTicker(200 * time.Millisecond)
		defer t.Stop()
		for {
			select {
			case <-t.C:
				progress(done.Load(), size)
			case <-stop:
				return
			}
		}
	}()
	err = fetchInto(ctx, f, url, size, &done)
	close(stop)
	<-ticked
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err == nil {
		progress(size, size)
	}
	return err
}

func fetchInto(ctx context.Context, f *os.File, url string, size int64, done *atomic.Int64) error {
	n := Parts
	if size < parallelMin || n < 2 {
		n = 1
	}
	if n > 1 {
		if err := f.Truncate(size); err != nil {
			return err
		}
		err := fetchParts(ctx, f, url, size, n, done)
		if !errors.Is(err, errNoRange) {
			return err
		}
		done.Store(0) // fall back to one plain stream
	}
	resp, err := get(ctx, url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	_, err = io.CopyBuffer(&countWriter{w: io.NewOffsetWriter(f, 0), n: done}, resp.Body, make([]byte, 1<<20))
	return err
}

func fetchParts(ctx context.Context, f *os.File, url string, size int64, n int, done *atomic.Int64) error {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	var wg sync.WaitGroup
	var once sync.Once
	var first error
	step := (size + int64(n) - 1) / int64(n)
	for start := int64(0); start < size; start += step {
		end := min(start+step, size) // exclusive
		wg.Add(1)
		go func(start, end int64) {
			defer wg.Done()
			if err := fetchRange(ctx, f, url, start, end, done); err != nil {
				once.Do(func() { first = err; cancel() })
			}
		}(start, end)
	}
	wg.Wait()
	return first
}

// fetchRange copies bytes [start, end) and resumes where it stopped after a dropped connection.
func fetchRange(ctx context.Context, f *os.File, url string, start, end int64, done *atomic.Int64) error {
	buf := make([]byte, 1<<20)
	var err error
	for try := 0; try < partRetries; try++ {
		if try > 0 {
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(time.Duration(try) * time.Second):
			}
		}
		var got int64
		got, err = fetchRangeOnce(ctx, f, url, start, end, done, buf)
		start += got
		if err == nil || errors.Is(err, errNoRange) || ctx.Err() != nil {
			return err
		}
	}
	return err
}

func fetchRangeOnce(ctx context.Context, f *os.File, url string, start, end int64, done *atomic.Int64, buf []byte) (int64, error) {
	if start >= end {
		return 0, nil
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return 0, err
	}
	req.Header.Set("User-Agent", "backpack-usb-writer")
	req.Header.Set("Range", fmt.Sprintf("bytes=%d-%d", start, end-1))
	resp, err := client.Do(req)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	switch resp.StatusCode {
	case http.StatusPartialContent:
	case http.StatusOK:
		return 0, errNoRange
	default:
		return 0, fmt.Errorf("%s: %s", url, resp.Status)
	}
	w := &countWriter{w: io.NewOffsetWriter(f, start), n: done}
	got, err := io.CopyBuffer(w, io.LimitReader(resp.Body, end-start), buf)
	if err == nil && got < end-start {
		err = io.ErrUnexpectedEOF
	}
	return got, err
}

type countWriter struct {
	w io.Writer
	n *atomic.Int64
}

func (c *countWriter) Write(b []byte) (int, error) {
	n, err := c.w.Write(b)
	c.n.Add(int64(n))
	return n, err
}
