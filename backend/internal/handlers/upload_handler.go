package handlers

import (
	"fmt"
	"net/http"
	"os"
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
