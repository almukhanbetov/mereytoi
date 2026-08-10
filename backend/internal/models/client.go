package models

import "time"

// Client is a logo shown in the homepage "Наши клиенты" carousel — just an
// image, no caption.
type Client struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	PhotoURL  string    `gorm:"size:255;not null" json:"photo_url"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}
