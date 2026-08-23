package models

import "time"

type Category struct {
	ID       uint   `gorm:"primaryKey" json:"id"`
	Slug     string `gorm:"size:60;uniqueIndex;not null" json:"slug"`
	NameRu   string `gorm:"size:150;not null" json:"name_ru"`
	NameKz   string `gorm:"size:150;not null" json:"name_kz"`
	Position int    `gorm:"not null;default:0" json:"position"`
	// ImageURL is the category's own cover photo — independent of any
	// listing's image_urls, nullable so existing categories keep working
	// unchanged. Populated via the same upload endpoint listings use.
	ImageURL  *string   `gorm:"size:500" json:"image_url,omitempty"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}
