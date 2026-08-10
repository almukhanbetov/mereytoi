package models

import "time"

// Client is a showcased customer entry on the homepage "Наши клиенты"
// section — a photo, name, event type, and a short quote/review.
type Client struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	Name      string    `gorm:"size:150;not null" json:"name"`
	EventType string    `gorm:"size:30;not null" json:"event_type"`
	Quote     string    `gorm:"type:text" json:"quote"`
	PhotoURL  string    `gorm:"size:255" json:"photo_url"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}
