package models

import "time"

// Client is a showcased customer entry on the homepage "Наши клиенты"
// section — just a photo and a name.
type Client struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	Name      string    `gorm:"size:150;not null" json:"name"`
	PhotoURL  string    `gorm:"size:255" json:"photo_url"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}
