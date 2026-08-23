package models

import "time"

// SiteStatistics is a single-row table holding the homepage stats block
// numbers ("250+ Проведено тоев" etc.) so they can be edited from the admin
// panel instead of being hardcoded in the frontend.
type SiteStatistics struct {
	ID               uint      `gorm:"primaryKey" json:"id"`
	EventsCount      int       `gorm:"not null;default:0" json:"events_count"`
	HappyGuestsCount int       `gorm:"not null;default:0" json:"happy_guests_count"`
	YearsExperience  int       `gorm:"not null;default:0" json:"years_experience"`
	CitiesCount      int       `gorm:"not null;default:0" json:"cities_count"`
	UpdatedAt        time.Time `json:"updated_at"`
}
