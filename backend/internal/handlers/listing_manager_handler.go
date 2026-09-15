package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// ListingManagerHandler is the admin-only tool for assigning who owns/
// manages a listing (brief Этап 5 — "максимально минимально": this
// product has no self-serve "create your own restaurant listing" flow
// yet, so the only real assignment path today is a global admin handing
// a listing to a user, mirroring how EventMemberHandler.ChangeRole works
// for events).
type ListingManagerHandler struct {
	DB *gorm.DB
}

func NewListingManagerHandler(db *gorm.DB) *ListingManagerHandler {
	return &ListingManagerHandler{DB: db}
}

type listingManagerInput struct {
	UserID uint   `json:"user_id" binding:"required"`
	Role   string `json:"role" binding:"required,oneof=owner manager"`
}

// List — GET /api/listings/:id/managers (admin). Who currently manages
// this listing — mainly for the admin UI/QA, not consumed by the public
// or owner-facing screens.
func (h *ListingManagerHandler) List(c *gin.Context) {
	listingID, ok := atoiParam(c, "id")
	if !ok {
		return
	}

	var managers []models.ListingManager
	if err := h.DB.Preload("User").Where("listing_id = ?", listingID).Find(&managers).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch managers"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"managers": managers})
}

// Assign — POST /api/listings/:id/managers (admin). Upserts by
// (listing_id, user_id): assigning a role to a user who's already
// attached to this listing just changes their role rather than erroring
// on the unique index.
func (h *ListingManagerHandler) Assign(c *gin.Context) {
	listingID, ok := atoiParam(c, "id")
	if !ok {
		return
	}
	if err := h.DB.First(&models.Listing{}, listingID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "listing not found"})
		return
	}

	var in listingManagerInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if err := h.DB.First(&models.User{}, in.UserID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	var manager models.ListingManager
	err := h.DB.Where("listing_id = ? AND user_id = ?", listingID, in.UserID).First(&manager).Error
	if err == nil {
		manager.Role = in.Role
		if err := h.DB.Save(&manager).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update manager"})
			return
		}
	} else {
		manager = models.ListingManager{ListingID: uint(listingID), UserID: in.UserID, Role: in.Role}
		if err := h.DB.Create(&manager).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to assign manager"})
			return
		}
	}

	c.JSON(http.StatusOK, gin.H{"manager": manager})
}

// Remove — DELETE /api/listings/:id/managers/:userId (admin).
func (h *ListingManagerHandler) Remove(c *gin.Context) {
	listingID, ok := atoiParam(c, "id")
	if !ok {
		return
	}
	userID, err := strconv.Atoi(c.Param("userId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user id"})
		return
	}

	if err := h.DB.Where("listing_id = ? AND user_id = ?", listingID, userID).
		Delete(&models.ListingManager{}).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to remove manager"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "manager removed"})
}
