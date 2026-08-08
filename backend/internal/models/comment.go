package models

import "time"

// Comment is a customer's rating + text review left on a specific listing.
// New comments start unapproved and only appear publicly once an admin
// approves them.
type Comment struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	ListingID uint      `gorm:"not null;index" json:"listing_id"`
	UserID    uint      `gorm:"not null;index" json:"user_id"`
	UserName  string    `gorm:"size:150;not null" json:"user_name"`
	Rating    uint      `gorm:"not null" json:"rating"`
	Text      string    `gorm:"type:text;not null" json:"text"`
	Approved  bool      `gorm:"not null;default:false" json:"approved"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}
