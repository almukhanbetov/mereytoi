package handlers

import (
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/middleware"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// Listing visibility for visitors. A visitor sees a listing only if:
//   - the owner has it published (is_active) — the owner's own switch, which
//     nothing here ever changes;
//   - an administrator hasn't hidden it (moderation_hidden_at);
//   - its owner account isn't blocked right now — derived at read time from
//     the block, so when the block ends (unblock or the term running out)
//     exactly the listings that were visible before come back: unpublished
//     and admin-hidden ones stay out.
//
// The same rule holds for the catalog, the feed (and so its ads), the
// listing page by direct link and its public sub-resources (halls, menus,
// reviews, view counting). The owner/managers and admins still see it
// (canSeeRestrictedListing).

// restrictedSQL matches the listings visitors must not see (bound with
// false, ownerRole, now).
const restrictedSQL = `(listings.is_active = ? OR listings.moderation_hidden_at IS NOT NULL OR EXISTS (
	SELECT 1 FROM listing_managers lm JOIN users u ON u.id = lm.user_id
	WHERE lm.listing_id = listings.id AND lm.role = ?
	AND u.blocked_at IS NOT NULL AND (u.blocked_until IS NULL OR u.blocked_until > ?)))`

// publicListingScope narrows a query on listings to what visitors may see.
func publicListingScope(now time.Time) func(*gorm.DB) *gorm.DB {
	return func(q *gorm.DB) *gorm.DB {
		return q.Where("NOT "+restrictedSQL, false, models.ListingManagerRoleOwner, now.UTC())
	}
}

// listingRestricted reports whether visitors must not see the listing, by a
// direct link too: unpublished by the owner, hidden by an administrator, or
// its owner is blocked now.
// A database error counts as restricted (fails closed).
func listingRestricted(db *gorm.DB, listingID uint, now time.Time) bool {
	var n int64
	err := db.Model(&models.Listing{}).Where("listings.id = ?", listingID).
		Where(restrictedSQL, false, models.ListingManagerRoleOwner, now.UTC()).Count(&n).Error
	return err != nil || n > 0
}

// canSeeRestrictedListing — a global admin, or a user assigned to manage
// this listing (owner or manager), still sees it while restricted, so the
// owner's own management screens keep working. Identity comes from the
// session (OptionalAuth/RequireAuth), never from the request body.
func canSeeRestrictedListing(c *gin.Context, db *gorm.DB, listingID uint) bool {
	if role, _ := c.Get(middleware.ContextUserRoleKey); role == "admin" {
		return true
	}
	uid := currentUserID(c)
	if uid == 0 {
		return false
	}
	var n int64
	db.Model(&models.ListingManager{}).Where("listing_id = ? AND user_id = ?", listingID, uid).Count(&n)
	return n > 0
}

// listingHiddenFromRequester — the single check a public listing endpoint
// makes before answering: true means answer 404 as if it didn't exist.
func listingHiddenFromRequester(c *gin.Context, db *gorm.DB, listingID uint) bool {
	return listingRestricted(db, listingID, time.Now()) && !canSeeRestrictedListing(c, db, listingID)
}

// userBlockedNow — whether the account is blocked at this moment.
func userBlockedNow(db *gorm.DB, userID uint) bool {
	var row struct {
		BlockedAt    *time.Time
		BlockedUntil *time.Time
	}
	if err := db.Model(&models.User{}).Select("blocked_at", "blocked_until").
		Where("id = ?", userID).Take(&row).Error; err != nil {
		return false
	}
	return models.BlockActive(row.BlockedAt, row.BlockedUntil, time.Now().UTC())
}
