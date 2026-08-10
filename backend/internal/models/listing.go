package models

import "time"

// Listing is an entry inside a category: a restaurant/venue name, a host's
// name, a show program, an artist, etc. — whatever the category holds.
type Listing struct {
	ID            uint      `gorm:"primaryKey" json:"id"`
	CategoryID    uint      `gorm:"not null;index" json:"category_id"`
	Category      *Category `gorm:"foreignKey:CategoryID" json:"category,omitempty"`
	NameRu        string    `gorm:"size:200;not null" json:"name_ru"`
	NameKz        string    `gorm:"size:200;not null" json:"name_kz"`
	DescriptionRu string    `gorm:"type:text" json:"description_ru"`
	DescriptionKz string    `gorm:"type:text" json:"description_kz"`
	City          string    `gorm:"size:100" json:"city"`
	Phone         string    `gorm:"size:30" json:"phone"`
	Price         uint      `gorm:"default:0" json:"price"`
	MinGuests     uint      `gorm:"default:0" json:"min_guests"`
	MaxGuests     uint      `gorm:"default:0" json:"max_guests"`
	Rating        float32   `gorm:"default:0" json:"rating"`
	Emoji         string    `gorm:"size:10" json:"emoji"`
	ColorFrom     string    `gorm:"size:10" json:"color_from"`
	ColorTo       string    `gorm:"size:10" json:"color_to"`
	ImageURLs     []string  `gorm:"serializer:json" json:"image_urls"`
	VideoURL      string    `gorm:"size:255" json:"video_url"`
	IsActive      bool      `gorm:"not null;default:true" json:"is_active"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}
