package media

import (
	"context"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// BackfillVideo is one video_urls entry of one listing.
type BackfillVideo struct {
	ListingID uint
	URL       string
}

// BackfillOptions configures Backfill.
type BackfillOptions struct {
	UploadsDir string
	// DryRun only reports what would happen: nothing is written.
	DryRun bool
	// Generate is GeneratePoster in production; tests stand in for it.
	Generate func(ctx context.Context, videoPath, posterPath string) (bool, error)
	Log      *log.Logger
}

// BackfillSummary counts every video_urls entry exactly once.
type BackfillSummary struct {
	Total       int // every entry seen
	Created     int
	WouldCreate int // dry run: poster missing, video present
	Skipped     int // poster already there
	Failed      int // video file missing, or generation failed
	Invalid     int // external URL or not a plain /uploads/ video
	Duplicate   int // same video as an earlier entry (handled once)
	Duration    time.Duration
}

// Backfill makes the missing posters for videos, one at a time (never
// several ffmpeg processes at once), and never touches a poster that's
// already there — so it can be rerun safely. Only plain /uploads/ video
// files are handled (see PosterURLFor); anything else is counted as
// invalid and left alone. A failure is logged and the run moves on. It
// stops early, between videos, when ctx is cancelled.
func Backfill(ctx context.Context, videos []BackfillVideo, opts BackfillOptions) BackfillSummary {
	start := time.Now()
	logf := func(format string, args ...any) {
		if opts.Log != nil {
			opts.Log.Printf("[poster-backfill] "+format, args...)
		}
	}

	var s BackfillSummary
	seen := map[string]bool{}
	for _, v := range videos {
		if ctx.Err() != nil {
			logf("STOP: %v", ctx.Err())
			break
		}
		s.Total++

		_, posterPath, ok := PosterURLFor(v.URL, opts.UploadsDir)
		if !ok {
			s.Invalid++
			// The URL itself isn't logged: an external link may carry tokens.
			logf("IGNORE listing=%d: external or not a local /uploads/ video", v.ListingID)
			continue
		}
		name := strings.TrimPrefix(v.URL, uploadsURLPrefix)
		if seen[name] {
			s.Duplicate++
			continue
		}
		seen[name] = true
		videoPath := filepath.Join(opts.UploadsDir, name)

		if info, err := os.Stat(posterPath); err == nil && info.Mode().IsRegular() && info.Size() > 0 {
			s.Skipped++
			logf("SKIP %s", name)
			continue
		}
		if info, err := os.Stat(videoPath); err != nil || !info.Mode().IsRegular() {
			s.Failed++
			logf("FAIL %s (listing=%d): video file not found", name, v.ListingID)
			continue
		}
		if opts.DryRun {
			s.WouldCreate++
			logf("WOULD_CREATE %s", name)
			continue
		}

		created, err := opts.Generate(ctx, videoPath, posterPath)
		switch {
		case err != nil:
			s.Failed++
			logf("FAIL %s (listing=%d): %v", name, v.ListingID, err)
		case created:
			s.Created++
			logf("CREATED %s", filepath.Base(posterPath))
		default:
			s.Skipped++
			logf("SKIP %s", name)
		}
	}
	s.Duration = time.Since(start)

	mode := ""
	if opts.DryRun {
		mode = " (dry run, nothing written)"
	}
	logf("SUMMARY%s total=%d created=%d would_create=%d skipped=%d failed=%d invalid_or_external=%d duplicate=%d duration=%s",
		mode, s.Total, s.Created, s.WouldCreate, s.Skipped, s.Failed, s.Invalid, s.Duplicate, s.Duration.Round(time.Millisecond))
	return s
}
