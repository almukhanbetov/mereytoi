// Package media holds server-side helpers for uploaded media files.
package media

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// PosterDirName is the folder, next to a video, that holds its poster.
const PosterDirName = "posters"

// DefaultPosterTimeout bounds one whole poster generation (all attempts).
// A single frame from a local, already transcoded file normally takes well
// under a second; this only stops a stuck ffmpeg from hanging the caller.
const DefaultPosterTimeout = 30 * time.Second

// posterWidth caps the poster width; narrower videos are never upscaled.
const posterWidth = 720

var posterVideoExt = map[string]bool{
	".mp4": true, ".webm": true, ".mov": true, ".m4v": true,
}

// PosterPathFor returns where the poster of videoPath lives: a .jpg with the
// same base name in a "posters" folder beside the video, e.g.
// uploads/123.mp4 → uploads/posters/123.jpg. Works the same for disk paths
// and for "/uploads/..." URL paths, so the URL can later be derived from the
// video URL alone, with nothing stored in the DB.
func PosterPathFor(videoPath string) string {
	dir, base := filepath.Split(videoPath)
	stem := strings.TrimSuffix(base, filepath.Ext(base))
	return filepath.Join(dir, PosterDirName, stem+".jpg")
}

// CommandRunner runs one external command and returns its stderr. It exists
// so tests can stand in for ffmpeg; production uses ExecRunner.
type CommandRunner func(ctx context.Context, name string, args []string) (stderr []byte, err error)

// ExecRunner runs the command directly (no shell), killed when ctx ends.
func ExecRunner(ctx context.Context, name string, args []string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	err := cmd.Run()
	return stderr.Bytes(), err
}

// PosterGenerator writes one JPEG still per video with ffmpeg.
type PosterGenerator struct {
	Run     CommandRunner
	Timeout time.Duration
}

// NewPosterGenerator returns a generator backed by the real ffmpeg binary.
func NewPosterGenerator() *PosterGenerator {
	return &PosterGenerator{Run: ExecRunner, Timeout: DefaultPosterTimeout}
}

// GeneratePoster writes the poster for videoPath to posterPath (usually
// PosterPathFor(videoPath)) with the real ffmpeg. See PosterGenerator.Generate.
func GeneratePoster(ctx context.Context, videoPath, posterPath string) (bool, error) {
	return NewPosterGenerator().Generate(ctx, videoPath, posterPath)
}

// Generate writes the poster for videoPath to posterPath. It returns
// created=false with no error when a non-empty poster is already there —
// it's never regenerated. The video is only read, never modified.
//
// The frame is taken ~1s in (many clips open on a black/fade-in frame) and,
// among the next few frames, ffmpeg's thumbnail filter picks the most
// representative one. A clip shorter than that gets its first frame instead.
//
// ffmpeg writes to a temp file in the posters folder, which is renamed onto
// posterPath only once it holds a complete, non-empty image, so a half-written
// poster is never visible; the temp file is removed on any failure.
//
// Callers that generate right after an upload should only log an error: the
// video itself is fine without a poster.
func (g *PosterGenerator) Generate(ctx context.Context, videoPath, posterPath string) (created bool, err error) {
	if !posterVideoExt[strings.ToLower(filepath.Ext(videoPath))] {
		return false, fmt.Errorf("poster: not a video file: %s", videoPath)
	}
	if info, err := os.Stat(videoPath); err != nil {
		return false, fmt.Errorf("poster: video: %w", err)
	} else if !info.Mode().IsRegular() {
		return false, fmt.Errorf("poster: video is not a regular file: %s", videoPath)
	}
	if info, err := os.Stat(posterPath); err == nil && info.Size() > 0 {
		return false, nil
	}

	// Absolute paths: a relative name starting with "-" can't be mistaken
	// for an ffmpeg option.
	videoAbs, err := filepath.Abs(videoPath)
	if err != nil {
		return false, fmt.Errorf("poster: %w", err)
	}
	posterAbs, err := filepath.Abs(posterPath)
	if err != nil {
		return false, fmt.Errorf("poster: %w", err)
	}
	posterDir := filepath.Dir(posterAbs)
	if err := os.MkdirAll(posterDir, 0755); err != nil {
		return false, fmt.Errorf("poster: %w", err)
	}

	tmp, err := os.CreateTemp(posterDir, ".poster-*.tmp")
	if err != nil {
		return false, fmt.Errorf("poster: %w", err)
	}
	tmpPath := tmp.Name()
	tmp.Close()
	defer func() {
		if !created {
			os.Remove(tmpPath)
		}
	}()

	timeout := g.Timeout
	if timeout <= 0 {
		timeout = DefaultPosterTimeout
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	var lastErr error
	for _, seek := range []string{"1", "0"} {
		stderr, runErr := g.Run(ctx, "ffmpeg", posterArgs(seek, videoAbs, tmpPath))
		if ctxErr := ctx.Err(); ctxErr != nil {
			return false, fmt.Errorf("poster: ffmpeg: %w", ctxErr)
		}
		if runErr != nil {
			lastErr = fmt.Errorf("poster: ffmpeg (at %ss): %w: %s", seek, runErr, tail(stderr, 500))
			continue
		}
		if info, err := os.Stat(tmpPath); err != nil || info.Size() == 0 {
			lastErr = fmt.Errorf("poster: ffmpeg (at %ss) produced no frame", seek)
			continue
		}
		if err := os.Chmod(tmpPath, 0644); err != nil {
			return false, fmt.Errorf("poster: %w", err)
		}
		if err := os.Rename(tmpPath, posterAbs); err != nil {
			return false, fmt.Errorf("poster: %w", err)
		}
		return true, nil
	}
	return false, lastErr
}

// posterArgs is the ffmpeg command line for one attempt:
//
//	ffmpeg -nostdin -hide_banner -loglevel error -y -ss <seek> -i <video>
//	  -map 0:v:0 -frames:v 1 -vf thumbnail=10,scale='min(720,iw)':-2
//	  -q:v 4 -f mjpeg <out>
//
// -ss before -i seeks fast on the input; scale keeps the aspect ratio with an
// even height; -q:v 4 is a good-quality, small JPEG; -f mjpeg because the
// temp file's name has no image extension.
func posterArgs(seek, videoPath, outPath string) []string {
	return []string{
		"-nostdin", "-hide_banner", "-loglevel", "error",
		"-y",
		"-ss", seek,
		"-i", videoPath,
		"-map", "0:v:0",
		"-frames:v", "1",
		"-vf", fmt.Sprintf("thumbnail=10,scale='min(%d,iw)':-2", posterWidth),
		"-q:v", "4",
		"-f", "mjpeg",
		outPath,
	}
}

func tail(b []byte, n int) string {
	s := strings.TrimSpace(string(b))
	if len(s) > n {
		s = "…" + s[len(s)-n:]
	}
	return s
}
