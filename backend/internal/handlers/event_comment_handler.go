package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

type EventCommentHandler struct {
	DB *gorm.DB
}

func NewEventCommentHandler(db *gorm.DB) *EventCommentHandler {
	return &EventCommentHandler{DB: db}
}

type addCommentInput struct {
	Body        string `json:"body" binding:"required"`
	CandidateID *uint  `json:"candidate_id"`
}

// AddComment — POST /api/events/:id/comments (editor+). CandidateID nil
// means it's a message on the event-wide "Обсуждение" tab; set, it's a
// reply in that one service's thread — same table, same handler either way.
func (h *EventCommentHandler) AddComment(c *gin.Context) {
	var in addCommentInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	eventID := currentEventID(c)
	var candidateName string
	if in.CandidateID != nil {
		var candidate models.EventCandidate
		if err := h.DB.Preload("Listing").Where("id = ? AND event_id = ?", *in.CandidateID, eventID).First(&candidate).Error; err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "candidate not found in this event"})
			return
		}
		if candidate.Listing != nil {
			candidateName = candidate.Listing.NameRu
		}
	}

	userID := currentUserID(c)
	comment := models.EventComment{EventID: eventID, CandidateID: in.CandidateID, UserID: userID, Body: in.Body}
	if err := h.DB.Create(&comment).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to add comment"})
		return
	}

	var user models.User
	h.DB.First(&user, userID)
	comment.User = &user

	payload := map[string]any{"name": user.Name}
	if candidateName != "" {
		payload["candidate_name"] = candidateName
	}
	logActivity(h.DB, eventID, userID, "comment.added", payload)

	c.JSON(http.StatusCreated, gin.H{"comment": comment})
}

// List — GET /api/events/:id/comments?candidate_id=123 (any member). No
// candidate_id → the general discussion tab; with it → that service's
// thread only.
func (h *EventCommentHandler) List(c *gin.Context) {
	eventID := currentEventID(c)
	query := h.DB.Preload("User").Where("event_id = ?", eventID)

	if raw := c.Query("candidate_id"); raw != "" {
		candidateID, err := strconv.Atoi(raw)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid candidate_id"})
			return
		}
		query = query.Where("candidate_id = ?", candidateID)
	} else {
		query = query.Where("candidate_id IS NULL")
	}

	var comments []models.EventComment
	if err := query.Order("created_at asc").Find(&comments).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch comments"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"comments": comments})
}

// Delete — DELETE /api/events/:id/comments/:commentId. Anyone can delete
// their own comment; the owner can delete any comment.
func (h *EventCommentHandler) Delete(c *gin.Context) {
	commentID, ok := atoiParam(c, "commentId")
	if !ok {
		return
	}

	var comment models.EventComment
	if err := h.DB.Where("id = ? AND event_id = ?", commentID, currentEventID(c)).First(&comment).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "comment not found"})
		return
	}

	if comment.UserID != currentUserID(c) && currentEventRole(c) != models.EventRoleOwner {
		c.JSON(http.StatusForbidden, gin.H{"error": "you can only delete your own comments"})
		return
	}

	if err := h.DB.Delete(&comment).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete comment"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "comment deleted"})
}
