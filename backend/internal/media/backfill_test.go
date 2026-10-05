package media

import (
	"bytes"
	"context"
	"errors"
	"log"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// fakeGen writes a poster like GeneratePoster would (or fails for the
// videos listed in fail) and records every call.
type fakeGen struct {
	fail  map[string]bool // video base name → error
	calls []string
}

func (f *fakeGen) generate(ctx context.Context, video, poster string) (bool, error) {
	f.calls = append(f.calls, filepath.Base(video))
	if f.fail[filepath.Base(video)] {
		return false, errors.New("poster: ffmpeg: exit status 1")
	}
	os.MkdirAll(filepath.Dir(poster), 0755)
	return true, os.WriteFile(poster, fakeJPEG, 0644)
}

// uploadsWith makes an uploads dir holding the given video files.
func uploadsWith(t *testing.T, videos ...string) string {
	t.Helper()
	dir := t.TempDir()
	for _, v := range videos {
		if err := os.WriteFile(filepath.Join(dir, v), []byte("video "+v), 0644); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

func runBackfill(t *testing.T, dir string, videos []BackfillVideo, dryRun bool, g *fakeGen) (BackfillSummary, string) {
	t.Helper()
	var logs bytes.Buffer
	s := Backfill(context.Background(), videos, BackfillOptions{
		UploadsDir: dir, DryRun: dryRun, Generate: g.generate, Log: log.New(&logs, "", 0),
	})
	return s, logs.String()
}

func vids(urls ...string) []BackfillVideo {
	var v []BackfillVideo
	for i, u := range urls {
		v = append(v, BackfillVideo{ListingID: uint(i + 1), URL: u})
	}
	return v
}

func TestBackfillCreatesMissingPoster(t *testing.T) { // A
	dir := uploadsWith(t, "1.mp4")
	g := &fakeGen{}
	s, logs := runBackfill(t, dir, vids("/uploads/1.mp4"), false, g)

	if s.Created != 1 || s.Total != 1 || len(g.calls) != 1 {
		t.Fatalf("summary %+v, calls %v", s, g.calls)
	}
	if _, err := os.Stat(filepath.Join(dir, "posters", "1.jpg")); err != nil {
		t.Errorf("poster not written: %v", err)
	}
	if !strings.Contains(logs, "[poster-backfill] CREATED 1.jpg") || !strings.Contains(logs, "SUMMARY") {
		t.Errorf("logs = %q", logs)
	}
}

func TestBackfillSkipsExistingPoster(t *testing.T) { // B
	dir := uploadsWith(t, "1.mp4")
	writePoster(t, dir, "1.jpg", []byte("old"))
	g := &fakeGen{}
	s, logs := runBackfill(t, dir, vids("/uploads/1.mp4"), false, g)

	if s.Skipped != 1 || s.Created != 0 || len(g.calls) != 0 {
		t.Fatalf("summary %+v, calls %v", s, g.calls)
	}
	if b, _ := os.ReadFile(filepath.Join(dir, "posters", "1.jpg")); string(b) != "old" {
		t.Errorf("existing poster changed: %q", b)
	}
	if !strings.Contains(logs, "[poster-backfill] SKIP 1.mp4") {
		t.Errorf("logs = %q", logs)
	}
}

func TestBackfillFailureContinues(t *testing.T) { // C
	dir := uploadsWith(t, "1.mp4", "2.mp4", "3.mp4")
	g := &fakeGen{fail: map[string]bool{"2.mp4": true}}
	s, logs := runBackfill(t, dir, vids("/uploads/1.mp4", "/uploads/2.mp4", "/uploads/3.mp4", "/uploads/gone.mp4"), false, g)

	if s.Created != 2 || s.Failed != 2 || strings.Join(g.calls, ",") != "1.mp4,2.mp4,3.mp4" {
		t.Fatalf("summary %+v, calls %v", s, g.calls)
	}
	if !strings.Contains(logs, "[poster-backfill] FAIL 2.mp4 (listing=2): poster: ffmpeg") ||
		!strings.Contains(logs, "FAIL gone.mp4 (listing=4): video file not found") {
		t.Errorf("logs = %q", logs)
	}
}

func TestBackfillIgnoresExternalAndMalformed(t *testing.T) { // D, E
	dir := uploadsWith(t, "1.mp4")
	g := &fakeGen{}
	s, logs := runBackfill(t, dir, vids(
		"https://cdn.example.com/x.mp4?token=SECRET", // external
		"//evil.example/uploads/1.mp4",
		"/uploads/../../etc/passwd.mp4", // traversal
		"/uploads/a/1.mp4",
		"/uploads/1.jpg",
		"",
	), false, g)

	if s.Invalid != 6 || s.Total != 6 || len(g.calls) != 0 {
		t.Fatalf("summary %+v, calls %v", s, g.calls)
	}
	if strings.Contains(logs, "SECRET") {
		t.Errorf("external URL leaked into logs: %q", logs)
	}
	if _, err := os.Stat(filepath.Join(dir, "posters")); !os.IsNotExist(err) {
		t.Errorf("nothing should be written for ignored URLs")
	}
}

func TestBackfillSharedVideoOnce(t *testing.T) { // F
	dir := uploadsWith(t, "1.mp4")
	g := &fakeGen{}
	s, _ := runBackfill(t, dir, []BackfillVideo{
		{ListingID: 10, URL: "/uploads/1.mp4"},
		{ListingID: 11, URL: "/uploads/1.mp4"},
		{ListingID: 12, URL: "/uploads/1.mp4"},
	}, false, g)

	if len(g.calls) != 1 || s.Created != 1 || s.Duplicate != 2 || s.Total != 3 {
		t.Fatalf("summary %+v, calls %v", s, g.calls)
	}
}

func TestBackfillDryRunWritesNothing(t *testing.T) { // G
	dir := uploadsWith(t, "1.mp4", "2.mp4")
	writePoster(t, dir, "2.jpg", fakeJPEG)
	g := &fakeGen{}
	s, logs := runBackfill(t, dir, vids("/uploads/1.mp4", "/uploads/2.mp4", "https://x/y.mp4", "/uploads/1.mp4"), true, g)

	if len(g.calls) != 0 || s.WouldCreate != 1 || s.Skipped != 1 || s.Invalid != 1 || s.Duplicate != 1 || s.Created != 0 {
		t.Fatalf("summary %+v, calls %v", s, g.calls)
	}
	if _, err := os.Stat(filepath.Join(dir, "posters", "1.jpg")); !os.IsNotExist(err) {
		t.Errorf("dry run wrote a poster")
	}
	if !strings.Contains(logs, "WOULD_CREATE 1.mp4") || !strings.Contains(logs, "dry run, nothing written") {
		t.Errorf("logs = %q", logs)
	}
}

func TestBackfillRerunSkipsAll(t *testing.T) { // H
	dir := uploadsWith(t, "1.mp4", "2.mp4")
	before1, _ := os.ReadFile(filepath.Join(dir, "1.mp4"))
	list := vids("/uploads/1.mp4", "/uploads/2.mp4")

	first, _ := runBackfill(t, dir, list, false, &fakeGen{})
	g := &fakeGen{}
	second, _ := runBackfill(t, dir, list, false, g)

	if first.Created != 2 || second.Skipped != 2 || second.Created != 0 || len(g.calls) != 0 {
		t.Fatalf("first %+v, second %+v, calls %v", first, second, g.calls)
	}
	if after1, _ := os.ReadFile(filepath.Join(dir, "1.mp4")); !bytes.Equal(before1, after1) {
		t.Errorf("video changed")
	}
}

func TestBackfillStopsWhenCancelled(t *testing.T) {
	dir := uploadsWith(t, "1.mp4", "2.mp4")
	ctx, cancel := context.WithCancel(context.Background())
	calls := 0
	s := Backfill(ctx, vids("/uploads/1.mp4", "/uploads/2.mp4"), BackfillOptions{
		UploadsDir: dir,
		Generate: func(ctx context.Context, v, p string) (bool, error) {
			calls++
			cancel() // e.g. Ctrl+C during the first video
			return true, nil
		},
	})
	if calls != 1 || s.Total != 1 {
		t.Fatalf("calls %d, summary %+v", calls, s)
	}
}
