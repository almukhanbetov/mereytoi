package models

import "time"

// ListingView remembers that a viewer was recently counted for a listing, so
// reloading the page doesn't add to Listing.ViewCount again. ViewerHash is a
// keyed hash of the user id or guest IP: the raw value is never stored. Rows
// past the counting window are removed when that listing is next viewed.
type ListingView struct {
	ListingID    uint      `gorm:"primaryKey;autoIncrement:false"`
	ViewerHash   string    `gorm:"primaryKey;size:64"`
	LastViewedAt time.Time `gorm:"not null;index"`
}
