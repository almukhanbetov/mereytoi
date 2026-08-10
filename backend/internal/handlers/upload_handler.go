package handlers

import (
	"bytes"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

const uploadsDir = "./uploads"

var allowedImageExt = map[string]bool{
	".jpg": true, ".jpeg": true, ".png": true, ".webp": true, ".gif": true,
}

const maxImageSize = 8 << 20 // 8MB per file

var allowedVideoExt = map[string]bool{
	".mp4": true, ".webm": true, ".mov": true, ".m4v": true,
}

const maxVideoSize = 200 << 20 // 200MB per file

type UploadHandler struct{}

func NewUploadHandler() *UploadHandler {
	return &UploadHandler{}
}

// Upload handles POST /api/uploads (multipart form, field name "files",
// one or many). Saves images to disk and returns their public URLs.
func (h *UploadHandler) Upload(c *gin.Context) {
	form, err := c.MultipartForm()
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid multipart form"})
		return
	}

	files := form.File["files"]
	if len(files) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "no files provided"})
		return
	}

	if err := os.MkdirAll(uploadsDir, 0755); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to prepare upload directory"})
		return
	}

	urls := make([]string, 0, len(files))
	for _, file := range files {
		ext := strings.ToLower(filepath.Ext(file.Filename))
		if !allowedImageExt[ext] {
			c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("unsupported file type: %s", ext)})
			return
		}
		if file.Size > maxImageSize {
			c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("%s is larger than 8MB", file.Filename)})
			return
		}

		name := fmt.Sprintf("%d_%d%s", time.Now().UnixNano(), len(urls), ext)
		dest := filepath.Join(uploadsDir, name)
		if err := c.SaveUploadedFile(file, dest); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save file"})
			return
		}

		urls = append(urls, "/uploads/"+name)
	}

	c.JSON(http.StatusOK, gin.H{"urls": urls})
}

// transcodeToH264 normalizes any input video to an H.264/AAC .mp4 so every
// browser can play it — iPhone recordings default to HEVC (H.265), which
// most browsers (Chrome on Linux/Windows/Android in particular) can't
// decode: the file plays audio but shows a black frame.
func transcodeToH264(inputPath, outputPath string) error {
	cmd := exec.Command("ffmpeg",
		"-y",
		"-i", inputPath,
		"-c:v", "libx264",
		"-profile:v", "high",
		"-pix_fmt", "yuv420p",
		"-c:a", "aac",
		"-movflags", "+faststart",
		outputPath,
	)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("ffmpeg: %w: %s", err, stderr.String())
	}
	return nil
}

// UploadVideo handles POST /api/uploads/video (multipart form, single field
// "video"). Saves the upload, transcodes it to H.264/AAC, and returns the
// public URL of the transcoded file.
func (h *UploadHandler) UploadVideo(c *gin.Context) {
	file, err := c.FormFile("video")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "no video file provided"})
		return
	}

	ext := strings.ToLower(filepath.Ext(file.Filename))
	if !allowedVideoExt[ext] {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("unsupported file type: %s", ext)})
		return
	}
	if file.Size > maxVideoSize {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("%s is larger than 200MB", file.Filename)})
		return
	}

	if err := os.MkdirAll(uploadsDir, 0755); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to prepare upload directory"})
		return
	}

	srcName := fmt.Sprintf("%d_src%s", time.Now().UnixNano(), ext)
	srcPath := filepath.Join(uploadsDir, srcName)
	if err := c.SaveUploadedFile(file, srcPath); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save file"})
		return
	}
	defer os.Remove(srcPath)

	name := fmt.Sprintf("%d.mp4", time.Now().UnixNano())
	dest := filepath.Join(uploadsDir, name)
	if err := transcodeToH264(srcPath, dest); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to process video"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"url": "/uploads/" + name})
}
