package models

import "time"

type Category struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	Slug      string    `gorm:"size:60;uniqueIndex;not null" json:"slug"`
	NameRu    string    `gorm:"size:150;not null" json:"name_ru"`
	NameKz    string    `gorm:"size:150;not null" json:"name_kz"`
	Position  int       `gorm:"not null;default:0" json:"position"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}
