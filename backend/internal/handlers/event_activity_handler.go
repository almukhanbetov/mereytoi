package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

type EventActivityHandler struct {
	DB *gorm.DB
}

func NewEventActivityHandler(db *gorm.DB) *EventActivityHandler {
	return &EventActivityHandler{DB: db}
}

// List — GET /api/events/:id/activity (any member). Newest first, capped
// at 100 — this is a feed people scroll, not a full audit export.
func (h *EventActivityHandler) List(c *gin.Context) {
	var entries []models.EventActivity
	if err := h.DB.Preload("Actor").Where("event_id = ?", currentEventID(c)).Order("created_at desc").Limit(100).Find(&entries).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch activity"})
		return
	}

	for i := range entries {
		if entries[i].Payload != "" {
			var parsed map[string]any
			if json.Unmarshal([]byte(entries[i].Payload), &parsed) == nil {
				entries[i].PayloadJSON = parsed
			}
		}
	}

	c.JSON(http.StatusOK, gin.H{"activity": entries})
}
