package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/middleware"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

type CommentHandler struct {
	DB *gorm.DB
}

func NewCommentHandler(db *gorm.DB) *CommentHandler {
	return &CommentHandler{DB: db}
}

// ListApproved returns approved comments for a listing, newest first —
// GET /api/listings/:id/comments.
func (h *CommentHandler) ListApproved(c *gin.Context) {
	listingID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid listing id"})
		return
	}

	var comments []models.Comment
	if err := h.DB.
		Where("listing_id = ? AND approved = ?", listingID, true).
		Order("created_at desc").
		Find(&comments).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch comments"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"comments": comments})
}

type commentInput struct {
	Rating uint   `json:"rating" binding:"required,min=1,max=5"`
	Text   string `json:"text" binding:"required,min=1"`
}

// Create submits a new comment for a listing — POST /api/listings/:id/comments
// (authenticated). It starts unapproved until an admin reviews it.
func (h *CommentHandler) Create(c *gin.Context) {
	listingID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid listing id"})
		return
	}

	var in commentInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	userIDVal, _ := c.Get(middleware.ContextUserIDKey)
	userID, _ := userIDVal.(uint)

	var user models.User
	if err := h.DB.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not found"})
		return
	}

	var listing models.Listing
	if err := h.DB.First(&listing, listingID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "listing not found"})
		return
	}

	comment := models.Comment{
		ListingID: uint(listingID),
		UserID:    userID,
		UserName:  user.Name,
		Rating:    in.Rating,
		Text:      in.Text,
		Approved:  false,
	}
	if err := h.DB.Create(&comment).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create comment"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"comment": comment})
}

// ListAll returns every comment for the admin moderation queue —
// GET /api/comments (optionally ?approved=false).
func (h *CommentHandler) ListAll(c *gin.Context) {
	query := h.DB.Model(&models.Comment{})
	if v := c.Query("approved"); v != "" {
		query = query.Where("approved = ?", v == "true")
	}

	var comments []models.Comment
	if err := query.Order("created_at desc").Find(&comments).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch comments"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"comments": comments})
}

type commentApprovalInput struct {
	Approved bool `json:"approved"`
}

// UpdateApproval approves or rejects a comment — PUT /api/comments/:id (admin).
func (h *CommentHandler) UpdateApproval(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}

	var comment models.Comment
	if err := h.DB.First(&comment, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "comment not found"})
		return
	}

	var in commentApprovalInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	comment.Approved = in.Approved
	if err := h.DB.Save(&comment).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update comment"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"comment": comment})
}

// Delete removes a comment — DELETE /api/comments/:id (admin).
func (h *CommentHandler) Delete(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}

	if err := h.DB.Delete(&models.Comment{}, id).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete comment"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "comment deleted"})
}
