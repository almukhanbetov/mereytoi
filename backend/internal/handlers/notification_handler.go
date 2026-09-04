package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

type NotificationHandler struct {
	DB *gorm.DB
}

func NewNotificationHandler(db *gorm.DB) *NotificationHandler {
	return &NotificationHandler{DB: db}
}

func unmarshalPayload(n *models.Notification) {
	if n.Payload == "" {
		return
	}
	var parsed map[string]any
	if json.Unmarshal([]byte(n.Payload), &parsed) == nil {
		n.PayloadJSON = parsed
	}
}

// List — GET /api/notifications?unread=true&page=1&limit=20 (auth only —
// always scoped to the caller; there is no "list someone else's
// notifications" mode at any permission level).
func (h *NotificationHandler) List(c *gin.Context) {
	userID := currentUserID(c)
	unreadOnly := c.Query("unread") == "true"

	limit := 20
	if l, err := strconv.Atoi(c.Query("limit")); err == nil && l > 0 {
		limit = l
	}
	if limit > 100 {
		limit = 100
	}
	page := 1
	if p, err := strconv.Atoi(c.Query("page")); err == nil && p > 0 {
		page = p
	}

	countQuery := h.DB.Model(&models.Notification{}).Where("user_id = ?", userID)
	if unreadOnly {
		countQuery = countQuery.Where("is_read = ?", false)
	}
	var total int64
	countQuery.Count(&total)

	listQuery := h.DB.Preload("Actor").Preload("Event").Where("user_id = ?", userID)
	if unreadOnly {
		listQuery = listQuery.Where("is_read = ?", false)
	}

	var notifications []models.Notification
	if err := listQuery.Order("created_at desc").Limit(limit).Offset((page - 1) * limit).Find(&notifications).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch notifications"})
		return
	}
	for i := range notifications {
		unmarshalPayload(&notifications[i])
	}

	c.JSON(http.StatusOK, gin.H{"notifications": notifications, "total": total, "page": page, "limit": limit})
}

// UnreadCount — GET /api/notifications/unread-count. Always a fresh COUNT
// from the DB — never derived from whatever page the client happens to have
// loaded (brief section 9).
func (h *NotificationHandler) UnreadCount(c *gin.Context) {
	var count int64
	h.DB.Model(&models.Notification{}).Where("user_id = ? AND is_read = ?", currentUserID(c), false).Count(&count)
	c.JSON(http.StatusOK, gin.H{"count": count})
}

// MarkRead — POST /api/notifications/:id/read. Idempotent: marking an
// already-read notification read again just succeeds without changing
// read_at again. 404 (not 403) for a notification that doesn't belong to
// the caller — same "don't confirm it exists" posture as the event routes.
func (h *NotificationHandler) MarkRead(c *gin.Context) {
	id, ok := atoiParam(c, "id")
	if !ok {
		return
	}

	var n models.Notification
	if err := h.DB.Where("id = ? AND user_id = ?", id, currentUserID(c)).First(&n).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "notification not found"})
		return
	}

	if !n.IsRead {
		now := time.Now()
		n.IsRead = true
		n.ReadAt = &now
		if err := h.DB.Save(&n).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to mark notification read"})
			return
		}
	}

	unmarshalPayload(&n)
	c.JSON(http.StatusOK, gin.H{"notification": n})
}

// MarkAllRead — POST /api/notifications/read-all. The WHERE clause scopes
// to the caller's own rows — this can never touch another user's
// notifications no matter what.
func (h *NotificationHandler) MarkAllRead(c *gin.Context) {
	now := time.Now()
	if err := h.DB.Model(&models.Notification{}).
		Where("user_id = ? AND is_read = ?", currentUserID(c), false).
		Updates(map[string]any{"is_read": true, "read_at": now}).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to mark notifications read"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "all notifications marked read"})
}
