package models

import "time"

// BookingItem is a single line within a booking: one selected listing with
// the price snapshot at the time of the request (and guest count, for
// per-person priced venues).
type BookingItem struct {
	ListingID  uint   `json:"listing_id"`
	Name       string `json:"name"`
	Category   string `json:"category"`
	Guests     uint   `json:"guests"`
	UnitPrice  uint   `json:"unit_price"`
	TotalPrice uint   `json:"total_price"`
}

// Booking is a customer's booking request submitted from the cart — one or
// more BookingItems bundled together with contact info.
type Booking struct {
	ID        uint          `gorm:"primaryKey" json:"id"`
	PublicRef string        `gorm:"size:24;uniqueIndex" json:"public_ref"`
	UserID    *uint         `gorm:"index" json:"user_id,omitempty"`
	Name      string        `gorm:"size:150;not null" json:"name"`
	Phone     string        `gorm:"size:30;not null" json:"phone"`
	Message   string        `gorm:"type:text" json:"message"`
	Items     []BookingItem `gorm:"serializer:json" json:"items"`
	Total     uint          `json:"total"`
	Status    string        `gorm:"size:20;not null;default:new" json:"status"`
	Paid      bool          `gorm:"not null;default:false" json:"paid"`
	CreatedAt time.Time     `json:"created_at"`
	UpdatedAt time.Time     `json:"updated_at"`
}
