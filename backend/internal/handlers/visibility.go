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

// Why visitors don't see a listing — reported to administrators only.
const (
	VisibilityOwnerUnpublished = "owner_unpublished"
	VisibilityAdminHidden      = "admin_hidden"
	VisibilityOwnerBlocked     = "owner_blocked"
)

// listingVisibility — whether visitors see a listing right now and, if not,
// every reason that applies. It reports the rule above; it never changes it:
// PubliclyVisible comes from publicListingScope itself, the reasons from the
// same three conditions.
type listingVisibility struct {
	PubliclyVisible   bool     `json:"publicly_visible"`
	VisibilityReasons []string `json:"visibility_reasons"`
	// OwnerBlockedUntil — when the owner's block ends; null with the
	// owner_blocked reason means a permanent block.
	OwnerBlockedUntil *time.Time `json:"owner_blocked_until"`
}

// listingVisibilities computes listingVisibility for each of listings at
// now, in three queries whatever their number.
func listingVisibilities(db *gorm.DB, listings []models.Listing, now time.Time) map[uint]*listingVisibility {
	out := make(map[uint]*listingVisibility, len(listings))
	if len(listings) == 0 {
		return out
	}
	ids := make([]uint, len(listings))
	for i, l := range listings {
		ids[i] = l.ID
	}
	var visible []uint
	db.Model(&models.Listing{}).Where("id IN ?", ids).Scopes(publicListingScope(now)).Pluck("id", &visible)
	isVisible := make(map[uint]bool, len(visible))
	for _, id := range visible {
		isVisible[id] = true
	}
	var owners []struct {
		ListingID    uint
		BlockedAt    *time.Time
		BlockedUntil *time.Time
	}
	db.Table("listing_managers lm").
		Select("lm.listing_id, u.blocked_at, u.blocked_until").
		Joins("JOIN users u ON u.id = lm.user_id").
		Where("lm.listing_id IN ? AND lm.role = ?", ids, models.ListingManagerRoleOwner).
		Scan(&owners)
	type block struct{ until *time.Time }
	blockedOwner := map[uint]block{}
	for _, o := range owners {
		if models.BlockActive(o.BlockedAt, o.BlockedUntil, now.UTC()) {
			blockedOwner[o.ListingID] = block{until: o.BlockedUntil}
		}
	}
	for _, l := range listings {
		v := &listingVisibility{PubliclyVisible: isVisible[l.ID], VisibilityReasons: []string{}}
		if !l.IsActive {
			v.VisibilityReasons = append(v.VisibilityReasons, VisibilityOwnerUnpublished)
		}
		if l.ModerationHiddenAt != nil {
			v.VisibilityReasons = append(v.VisibilityReasons, VisibilityAdminHidden)
		}
		if b, ok := blockedOwner[l.ID]; ok {
			v.VisibilityReasons = append(v.VisibilityReasons, VisibilityOwnerBlocked)
			v.OwnerBlockedUntil = b.until
		}
		out[l.ID] = v
	}
	return out
}
