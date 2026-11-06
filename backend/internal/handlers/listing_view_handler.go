package handlers

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// listingViewWindow is how long one viewer counts once for one listing.
const listingViewWindow = time.Hour

// viewerHash identifies who is viewing: the signed-in user, otherwise the
// client IP (gin resolves it through the trusted proxies only). Nothing the
// client sends can make it a new viewer. Keyed, so the stored value can't be
// reversed into an IP by trying addresses.
func (h *ListingHandler) viewerHash(c *gin.Context) string {
	viewer := "ip:" + c.ClientIP()
	if id := currentUserID(c); id != 0 {
		viewer = fmt.Sprintf("user:%d", id)
	}
	mac := hmac.New(sha256.New, []byte(h.ViewSecret))
	mac.Write([]byte(viewer))
	return hex.EncodeToString(mac.Sum(nil))
}

// RecordView — POST /api/listings/:id/view, sent once when a listing's page
// opens. It's separate from GET so server rendering and link previews don't
// count. Hidden listings aren't counted. Returns the shared total.
func (h *ListingHandler) RecordView(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}

	var listing models.Listing
	if err := h.DB.Where("is_active = ?", true).First(&listing, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "listing not found"})
		return
	}

	now := time.Now()
	counted := false
	err = h.DB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("listing_id = ? AND last_viewed_at < ?", listing.ID, now.Add(-listingViewWindow)).
			Delete(&models.ListingView{}).Error; err != nil {
			return err
		}
		claim := tx.Clauses(clause.OnConflict{DoNothing: true}).Create(&models.ListingView{
			ListingID: listing.ID, ViewerHash: h.viewerHash(c), LastViewedAt: now,
		})
		if claim.Error != nil {
			return claim.Error
		}
		if claim.RowsAffected == 0 {
			return nil
		}
		counted = true
		// UpdateColumn: a view isn't an edit, so updated_at stays.
		return tx.Model(&models.Listing{}).Where("id = ?", listing.ID).
			UpdateColumn("view_count", gorm.Expr("view_count + 1")).Error
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to record view"})
		return
	}

	var total uint
	if err := h.DB.Model(&models.Listing{}).Where("id = ?", listing.ID).
		Select("view_count").Scan(&total).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to record view"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"view_count": total, "counted": counted})
}
