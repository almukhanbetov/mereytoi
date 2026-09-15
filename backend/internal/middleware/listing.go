package middleware

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

const ContextListingRoleKey = "listingRole"

// RequireListingAccess must run after RequireAuth, on a route with an :id
// param naming the listing (restaurant/venue). A global admin always
// passes. Otherwise it looks up the caller's ListingManager row for this
// listing and rejects with 403 if none exists — unlike RequireEventRole's
// deliberate 404-for-non-member obscurity, a listing's existence is
// already public (GET /api/listings/:id), so there's nothing to hide
// here: a non-manager gets a plain "you don't manage this listing" 403.
//
// Never trust listing_id from the client body for this check — only the
// URL :id, which is what the caller is actually about to mutate.
func RequireListingAccess(db *gorm.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		listingID, err := strconv.Atoi(c.Param("id"))
		if err != nil {
			c.AbortWithStatusJSON(http.StatusBadRequest, gin.H{"error": "invalid listing id"})
			return
		}

		role, _ := c.Get(ContextUserRoleKey)
		if role == "admin" {
			c.Set(ContextListingRoleKey, "admin")
			c.Next()
			return
		}

		userIDVal, _ := c.Get(ContextUserIDKey)
		userID, _ := userIDVal.(uint)

		var manager models.ListingManager
		if err := db.Where("listing_id = ? AND user_id = ?", listingID, userID).First(&manager).Error; err != nil {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "you do not manage this listing"})
			return
		}

		c.Set(ContextListingRoleKey, manager.Role)
		c.Next()
	}
}
