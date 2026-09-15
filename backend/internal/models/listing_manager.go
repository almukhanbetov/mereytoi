package models

import "time"

// Listing ownership roles — see ListingManager.
const (
	ListingManagerRoleOwner   = "owner"
	ListingManagerRoleManager = "manager"
)

// ListingManager links a user to a listing (restaurant/venue) they are
// allowed to manage — the ownership model EventMember already established
// for "Мой той" (event_members), mirrored here for listings. A global
// admin needs no row here (RequireAdmin/RequireListingAccess both bypass
// on role=="admin"); a row only exists for a non-admin owner/manager.
//
// idx_listing_manager is a composite unique index on (listing_id,
// user_id) — the same user can't be added twice to the same listing — and
// each field also carries its own separate single-column index so both
// "who manages this listing" and "which listings does this user manage"
// stay index-scans, not sequential scans.
type ListingManager struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	ListingID uint      `gorm:"not null;uniqueIndex:idx_listing_manager;index" json:"listing_id"`
	UserID    uint      `gorm:"not null;uniqueIndex:idx_listing_manager;index" json:"user_id"`
	Role      string    `gorm:"size:20;not null" json:"role"`
	Listing   *Listing  `gorm:"foreignKey:ListingID" json:"listing,omitempty"`
	User      *User     `gorm:"foreignKey:UserID" json:"user,omitempty"`
	CreatedAt time.Time `json:"created_at"`
}
