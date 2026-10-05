package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"log"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/almukhanbetov/mereytoi/backend/internal/media"
	"github.com/gin-gonic/gin"
)

type posterCall struct{ video, poster string }

// stubFFmpeg swaps both ffmpeg steps for fakes, runs in a fresh temp dir
// (uploadsDir is relative) and captures the log. The fake transcode just
// writes the output file; the fake generator answers with created/err.
func stubFFmpeg(t *testing.T, transcodeErr error, created bool, posterErr error) (*[]posterCall, *bytes.Buffer) {
	t.Helper()
	t.Chdir(t.TempDir())
	gin.SetMode(gin.TestMode)

	origTranscode, origPoster := transcodeVideo, generateVideoPoster
	t.Cleanup(func() { transcodeVideo, generateVideoPoster = origTranscode, origPoster })

	transcodeVideo = func(in, out string) error {
		if transcodeErr != nil {
			return transcodeErr
		}
		return os.WriteFile(out, []byte("h264 video"), 0644)
	}
	calls := &[]posterCall{}
	generateVideoPoster = func(ctx context.Context, video, poster string) (bool, error) {
		*calls = append(*calls, posterCall{video, poster})
		return created, posterErr
	}

	var logs bytes.Buffer
	log.SetOutput(&logs)
	t.Cleanup(func() { log.SetOutput(os.Stderr) })
	return calls, &logs
}

func upload(t *testing.T, path, field, filename string, handler gin.HandlerFunc) *httptest.ResponseRecorder {
	t.Helper()
	var body bytes.Buffer
	mw := multipart.NewWriter(&body)
	fw, _ := mw.CreateFormFile(field, filename)
	fw.Write([]byte("file bytes"))
	mw.Close()

	r := gin.New()
	r.POST(path, handler)
	req := httptest.NewRequest(http.MethodPost, path, &body)
	req.Header.Set("Content-Type", mw.FormDataContentType())
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)
	return rec
}

func uploadVideo(t *testing.T, filename string) *httptest.ResponseRecorder {
	return upload(t, "/api/uploads/video", "video", filename, NewUploadHandler().UploadVideo)
}

// videoResponse checks a 200 whose body is exactly {"url": "/uploads/<n>.mp4"}
// (no new fields) and that the video file is on disk; returns its path.
func videoResponse(t *testing.T, rec *httptest.ResponseRecorder) string {
	t.Helper()
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, body %s", rec.Code, rec.Body)
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	url, _ := body["url"].(string)
	if len(body) != 1 || !strings.HasPrefix(url, "/uploads/") || !strings.HasSuffix(url, ".mp4") {
		t.Fatalf("response = %v, want only {url: /uploads/<n>.mp4}", body)
	}
	video := filepath.Join(uploadsDir, filepath.Base(url))
	if _, err := os.Stat(video); err != nil {
		t.Fatalf("uploaded video missing: %v", err)
	}
	return video
}

func TestUploadVideoPosterCreated(t *testing.T) {
	calls, logs := stubFFmpeg(t, nil, true, nil)
	video := videoResponse(t, uploadVideo(t, "clip.mov"))

	if len(*calls) != 1 {
		t.Fatalf("poster generator called %d times, want 1", len(*calls))
	}
	if c := (*calls)[0]; c.video != video || c.poster != media.PosterPathFor(video) {
		t.Errorf("generator got %+v, want the transcoded video %s", c, video)
	}
	if !strings.Contains(logs.String(), "[video-poster] CREATED") {
		t.Errorf("log = %q", logs)
	}
}

func TestUploadVideoPosterAlreadyExists(t *testing.T) {
	calls, logs := stubFFmpeg(t, nil, false, nil)
	videoResponse(t, uploadVideo(t, "clip.mp4"))

	if len(*calls) != 1 {
		t.Fatalf("poster generator called %d times, want 1", len(*calls))
	}
	if !strings.Contains(logs.String(), "[video-poster] SKIP") {
		t.Errorf("log = %q", logs)
	}
}

func TestUploadVideoPosterFailureKeepsUpload(t *testing.T) {
	calls, logs := stubFFmpeg(t, nil, false, errors.New("poster: ffmpeg: exit status 1"))
	video := videoResponse(t, uploadVideo(t, "clip.mp4"))

	if len(*calls) != 1 {
		t.Fatalf("poster generator called %d times, want 1", len(*calls))
	}
	if b, err := os.ReadFile(video); err != nil || string(b) != "h264 video" {
		t.Errorf("video must stay as transcoded: %q, %v", b, err)
	}
	if !strings.Contains(logs.String(), "[video-poster] FAIL") {
		t.Errorf("log = %q", logs)
	}
}

func TestNonVideoUploadsDontMakePosters(t *testing.T) {
	calls, _ := stubFFmpeg(t, nil, true, nil)

	if rec := upload(t, "/api/uploads", "files", "photo.jpg", NewUploadHandler().Upload); rec.Code != http.StatusOK {
		t.Fatalf("image upload status = %d, body %s", rec.Code, rec.Body)
	}
	if rec := uploadVideo(t, "brochure.pdf"); rec.Code != http.StatusBadRequest {
		t.Fatalf("pdf on the video endpoint: status = %d", rec.Code)
	}
	if len(*calls) != 0 {
		t.Errorf("poster generator called %d times for non-video uploads", len(*calls))
	}
}

func TestFailedTranscodeMakesNoPoster(t *testing.T) {
	calls, _ := stubFFmpeg(t, errors.New("ffmpeg: exit status 1"), true, nil)

	if rec := uploadVideo(t, "clip.mp4"); rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", rec.Code)
	}
	if len(*calls) != 0 {
		t.Errorf("poster generator called %d times after a failed transcode", len(*calls))
	}
}
