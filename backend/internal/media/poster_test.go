package media

import (
	"bytes"
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

var fakeJPEG = []byte{0xFF, 0xD8, 0xFF, 0xE0, 'p', 'o', 's', 't', 'e', 'r', 0xFF, 0xD9}

// fakeFFmpeg stands in for ffmpeg: for each attempt (keyed by its -ss value)
// it writes the given bytes to the output path, or fails, or blocks.
type fakeFFmpeg struct {
	output map[string][]byte // seek → bytes written (nil: write nothing)
	fail   map[string]bool   // seek → exit with an error
	block  bool              // wait for ctx to end
	calls  [][]string
}

func (f *fakeFFmpeg) run(ctx context.Context, name string, args []string) ([]byte, error) {
	f.calls = append(f.calls, append([]string{name}, args...))
	if f.block {
		<-ctx.Done()
		return nil, ctx.Err()
	}
	seek := argAfter(args, "-ss")
	out := args[len(args)-1]
	if f.fail[seek] {
		os.WriteFile(out, []byte("partial"), 0644) // a half-written file
		return []byte("Invalid data found when processing input"), errors.New("exit status 1")
	}
	if b := f.output[seek]; b != nil {
		if err := os.WriteFile(out, b, 0644); err != nil {
			return nil, err
		}
	}
	return nil, nil
}

func (f *fakeFFmpeg) seeks() []string {
	var s []string
	for _, c := range f.calls {
		s = append(s, argAfter(c, "-ss"))
	}
	return s
}

func argAfter(args []string, flag string) string {
	for i, a := range args {
		if a == flag && i+1 < len(args) {
			return args[i+1]
		}
	}
	return ""
}

// setup creates uploads/123.mp4 in a temp dir and returns its path.
func setup(t *testing.T) string {
	t.Helper()
	dir := filepath.Join(t.TempDir(), "uploads")
	if err := os.MkdirAll(dir, 0755); err != nil {
		t.Fatal(err)
	}
	video := filepath.Join(dir, "123.mp4")
	if err := os.WriteFile(video, []byte("not really an mp4"), 0644); err != nil {
		t.Fatal(err)
	}
	return video
}

func newGen(f *fakeFFmpeg) *PosterGenerator {
	return &PosterGenerator{Run: f.run, Timeout: time.Second}
}

// leftovers lists anything in the posters folder besides the final poster.
func leftovers(t *testing.T, posterPath string) []string {
	t.Helper()
	entries, _ := os.ReadDir(filepath.Dir(posterPath))
	var extra []string
	for _, e := range entries {
		if e.Name() != filepath.Base(posterPath) {
			extra = append(extra, e.Name())
		}
	}
	return extra
}

func TestPosterPathFor(t *testing.T) {
	cases := map[string]string{
		"uploads/123.mp4":           "uploads/posters/123.jpg",
		"./uploads/123.mp4":         "uploads/posters/123.jpg",
		"/app/uploads/123.mp4":      "/app/uploads/posters/123.jpg",
		"/uploads/123.mp4":          "/uploads/posters/123.jpg", // URL path
		"uploads/a/b/123.mp4":       "uploads/a/b/posters/123.jpg",
		"uploads/clip.v2.MOV":       "uploads/posters/clip.v2.jpg",
		"uploads/1788712840932.mp4": "uploads/posters/1788712840932.jpg",
	}
	for in, want := range cases {
		if got := PosterPathFor(in); got != want {
			t.Errorf("PosterPathFor(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestGenerateSuccess(t *testing.T) {
	video := setup(t)
	poster := PosterPathFor(video)
	f := &fakeFFmpeg{output: map[string][]byte{"1": fakeJPEG}}

	created, err := newGen(f).Generate(context.Background(), video, poster)
	if err != nil || !created {
		t.Fatalf("Generate = %v, %v; want true, nil", created, err)
	}
	got, err := os.ReadFile(poster)
	if err != nil || !bytes.Equal(got, fakeJPEG) {
		t.Fatalf("poster content = %q, %v", got, err)
	}
	if extra := leftovers(t, poster); len(extra) > 0 {
		t.Errorf("leftover files: %v", extra)
	}
	if s := f.seeks(); len(s) != 1 || s[0] != "1" {
		t.Errorf("attempts = %v, want [1]", s)
	}

	args := f.calls[0]
	if args[0] != "ffmpeg" {
		t.Errorf("command = %q", args[0])
	}
	if in := argAfter(args, "-i"); !filepath.IsAbs(in) || in != mustAbs(t, video) {
		t.Errorf("-i = %q, want absolute video path", in)
	}
	if vf := argAfter(args, "-vf"); vf != "thumbnail=10,scale='min(720,iw)':-2" {
		t.Errorf("-vf = %q", vf)
	}
	if out := args[len(args)-1]; out == mustAbs(t, poster) || !strings.HasSuffix(out, ".tmp") {
		t.Errorf("ffmpeg must write to a temp file, wrote to %q", out)
	}
}

func TestGenerateSkipsExistingPoster(t *testing.T) {
	video := setup(t)
	poster := PosterPathFor(video)
	os.MkdirAll(filepath.Dir(poster), 0755)
	os.WriteFile(poster, []byte("old poster"), 0644)
	f := &fakeFFmpeg{output: map[string][]byte{"1": fakeJPEG}}

	created, err := newGen(f).Generate(context.Background(), video, poster)
	if err != nil || created {
		t.Fatalf("Generate = %v, %v; want false, nil", created, err)
	}
	if len(f.calls) != 0 {
		t.Errorf("ffmpeg ran %d times for an existing poster", len(f.calls))
	}
	if got, _ := os.ReadFile(poster); string(got) != "old poster" {
		t.Errorf("existing poster overwritten: %q", got)
	}
}

func TestGenerateReplacesEmptyPoster(t *testing.T) {
	video := setup(t)
	poster := PosterPathFor(video)
	os.MkdirAll(filepath.Dir(poster), 0755)
	os.WriteFile(poster, nil, 0644)
	f := &fakeFFmpeg{output: map[string][]byte{"1": fakeJPEG}}

	created, err := newGen(f).Generate(context.Background(), video, poster)
	if err != nil || !created {
		t.Fatalf("Generate = %v, %v; want true, nil", created, err)
	}
}

func TestGenerateFallsBackToFirstFrame(t *testing.T) {
	video := setup(t)
	poster := PosterPathFor(video)
	// Shorter than 1s: the first attempt yields no frame.
	f := &fakeFFmpeg{output: map[string][]byte{"0": fakeJPEG}}

	created, err := newGen(f).Generate(context.Background(), video, poster)
	if err != nil || !created {
		t.Fatalf("Generate = %v, %v; want true, nil", created, err)
	}
	if s := f.seeks(); strings.Join(s, ",") != "1,0" {
		t.Errorf("attempts = %v, want [1 0]", s)
	}
}

func TestGenerateFFmpegErrorCleansUp(t *testing.T) {
	video := setup(t)
	poster := PosterPathFor(video)
	f := &fakeFFmpeg{fail: map[string]bool{"1": true, "0": true}}

	created, err := newGen(f).Generate(context.Background(), video, poster)
	if err == nil || created {
		t.Fatalf("Generate = %v, %v; want an error", created, err)
	}
	if !strings.Contains(err.Error(), "Invalid data found") {
		t.Errorf("error should carry ffmpeg's stderr: %v", err)
	}
	if _, err := os.Stat(poster); !os.IsNotExist(err) {
		t.Errorf("no poster expected after failure, stat err = %v", err)
	}
	if extra := leftovers(t, poster); len(extra) > 0 {
		t.Errorf("temp files left behind: %v", extra)
	}
}

func TestGenerateTimeout(t *testing.T) {
	video := setup(t)
	poster := PosterPathFor(video)
	f := &fakeFFmpeg{block: true}
	g := &PosterGenerator{Run: f.run, Timeout: 20 * time.Millisecond}

	created, err := g.Generate(context.Background(), video, poster)
	if !errors.Is(err, context.DeadlineExceeded) || created {
		t.Fatalf("Generate = %v, %v; want DeadlineExceeded", created, err)
	}
	if len(f.calls) != 1 {
		t.Errorf("no further attempt after a timeout, got %d calls", len(f.calls))
	}
	if _, err := os.Stat(poster); !os.IsNotExist(err) {
		t.Errorf("no poster expected after timeout")
	}
	if extra := leftovers(t, poster); len(extra) > 0 {
		t.Errorf("temp files left behind: %v", extra)
	}
}

func TestGenerateLeavesVideoUntouched(t *testing.T) {
	video := setup(t)
	before, _ := os.ReadFile(video)
	infoBefore, _ := os.Stat(video)

	for _, f := range []*fakeFFmpeg{
		{output: map[string][]byte{"1": fakeJPEG}},
		{fail: map[string]bool{"1": true, "0": true}},
	} {
		os.RemoveAll(filepath.Dir(PosterPathFor(video)))
		newGen(f).Generate(context.Background(), video, PosterPathFor(video))
	}

	after, _ := os.ReadFile(video)
	infoAfter, _ := os.Stat(video)
	if !bytes.Equal(before, after) || !infoBefore.ModTime().Equal(infoAfter.ModTime()) {
		t.Error("the video file changed")
	}
}

func TestGenerateRejectsBadInput(t *testing.T) {
	video := setup(t)
	dir := filepath.Dir(video)
	os.WriteFile(filepath.Join(dir, "notes.txt"), []byte("x"), 0644)
	os.Mkdir(filepath.Join(dir, "folder.mp4"), 0755)

	for _, in := range []string{
		filepath.Join(dir, "notes.txt"),   // not a video
		filepath.Join(dir, "missing.mp4"), // doesn't exist
		filepath.Join(dir, "folder.mp4"),  // not a regular file
	} {
		f := &fakeFFmpeg{output: map[string][]byte{"1": fakeJPEG}}
		if _, err := newGen(f).Generate(context.Background(), in, PosterPathFor(in)); err == nil {
			t.Errorf("Generate(%q) should fail", in)
		}
		if len(f.calls) != 0 {
			t.Errorf("Generate(%q) ran ffmpeg", in)
		}
	}
}

// TestGenerateRealFFmpeg is a smoke test against the real binary; it's
// skipped wherever ffmpeg isn't installed (CI included).
func TestGenerateRealFFmpeg(t *testing.T) {
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("ffmpeg not installed")
	}
	video := filepath.Join(t.TempDir(), "uploads", "clip.mp4")
	os.MkdirAll(filepath.Dir(video), 0755)
	src := exec.Command("ffmpeg", "-loglevel", "error", "-f", "lavfi",
		"-i", "testsrc=duration=3:size=1280x720:rate=25",
		"-c:v", "libx264", "-pix_fmt", "yuv420p", video)
	if out, err := src.CombinedOutput(); err != nil {
		t.Skipf("can't make a test video: %v: %s", err, out)
	}

	poster := PosterPathFor(video)
	created, err := GeneratePoster(context.Background(), video, poster)
	if err != nil || !created {
		t.Fatalf("GeneratePoster = %v, %v", created, err)
	}
	b, _ := os.ReadFile(poster)
	if len(b) < 4 || b[0] != 0xFF || b[1] != 0xD8 {
		t.Errorf("poster is not a JPEG (%d bytes)", len(b))
	}
}

func mustAbs(t *testing.T, p string) string {
	t.Helper()
	a, err := filepath.Abs(p)
	if err != nil {
		t.Fatal(err)
	}
	return a
}
