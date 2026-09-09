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
	VideoURLs     []string  `gorm:"serializer:json" json:"video_urls"`
	IsActive      bool      `gorm:"not null;default:true" json:"is_active"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`

	// Address/Latitude/Longitude/PlaceID/Capacity — additive location
	// fields from the restaurant/venue audit. City above is unchanged and
	// still what search/filter use; Address is the fuller street address
	// City never captured. Latitude/Longitude/PlaceID are nil until a map
	// is actually wired up somewhere (none exists yet in this codebase) —
	// every existing Listing simply has them empty, same as every other
	// category (hosts/shows/artists/stars), which never populates these
	// either and is completely unaffected by their existence.
	//
	// Capacity is the venue's own overall/nominal capacity — deliberately
	// a *different* concept from MinGuests/MaxGuests above (a commercial
	// per-person pricing-tier range used to compute a booking's price,
	// untouched by this stage) and from ListingHall.Capacity (one
	// specific hall's physical capacity, see listing_hall.go). A Listing
	// with no halls yet can still report its own Capacity; once halls
	// exist, each hall's own Capacity is the more precise figure for that
	// specific hall.
	Address   string   `gorm:"size:300" json:"address,omitempty"`
	Latitude  *float64 `json:"latitude,omitempty"`
	Longitude *float64 `json:"longitude,omitempty"`
	PlaceID   *string  `gorm:"size:200" json:"place_id,omitempty"`
	Capacity  uint     `gorm:"default:0" json:"capacity,omitempty"`
}
