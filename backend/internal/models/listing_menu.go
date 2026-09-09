package models

import "time"

// ListingMenu is one banquet-menu variant belonging to a Listing —
// optionally scoped to one specific ListingHall (HallID nil means "this
// menu applies venue-wide, regardless of which hall ends up booked").
// Like ListingHall, deliberately no back-reference slice association on
// Listing/ListingHall — see listing_hall.go's own doc comment on why; the
// full menu tree is only ever assembled by an explicit handler-level
// query (listing_handler.go's Get/Menus), never a Preload.
type ListingMenu struct {
	ID            uint   `gorm:"primaryKey" json:"id"`
	ListingID     uint   `gorm:"not null;index" json:"listing_id"`
	HallID        *uint  `gorm:"index" json:"hall_id,omitempty"`
	NameRu        string `gorm:"size:200;not null" json:"name_ru"`
	NameKz        string `gorm:"size:200;not null" json:"name_kz"`
	DescriptionRu string `gorm:"type:text" json:"description_ru,omitempty"`
	DescriptionKz string `gorm:"type:text" json:"description_kz,omitempty"`
	PricePerGuest uint   `gorm:"not null;default:0" json:"price_per_guest"`
	// MinGuests/MaxGuests here are this specific menu's own order-size
	// constraints (e.g. "only bookable for 50+ guests") — a third,
	// independent concept from Listing.MinGuests/MaxGuests (pricing-tier
	// range) and ListingHall.Capacity (physical capacity). Pointers, not
	// plain uint, because 0 is not a sensible "no constraint" default the
	// way it is for a capacity/price field — nil unambiguously means "not
	// set" for consistency with Event.EventDate/EventRequest.SubmittedAt's
	// own existing *time.Time convention for optional scalars in this
	// codebase.
	MinGuests *uint `json:"min_guests,omitempty"`
	MaxGuests *uint `json:"max_guests,omitempty"`
	// IsActive — see ListingHall.IsActive's own doc comment on why this
	// carries no `default:` tag: GORM silently drops an explicit false
	// for a bool field tagged with a default (treating it as "unset"),
	// which is exactly what "Дублировать меню" (draft/inactive copies)
	// needs to actually work. Pure Go struct-tag fix, no migration
	// needed — verified directly against this Postgres/GORM version.
	IsActive   bool       `gorm:"not null" json:"is_active"`
	SortOrder  int        `gorm:"not null;default:0" json:"sort_order"`
	ValidFrom  *time.Time `json:"valid_from,omitempty"`
	ValidUntil *time.Time `json:"valid_until,omitempty"`
	CreatedAt  time.Time  `json:"created_at"`
	UpdatedAt  time.Time  `json:"updated_at"`
}

// ListingMenuSection groups ListingMenuItems under a heading (e.g.
// "Салаты", "Горячее") within one ListingMenu.
type ListingMenuSection struct {
	ID        uint   `gorm:"primaryKey" json:"id"`
	MenuID    uint   `gorm:"not null;index" json:"menu_id"`
	TitleRu   string `gorm:"size:150;not null" json:"title_ru"`
	TitleKz   string `gorm:"size:150;not null" json:"title_kz"`
	SortOrder int    `gorm:"not null;default:0" json:"sort_order"`
}

// ListingMenuItem is one dish within a ListingMenuSection.
type ListingMenuItem struct {
	ID            uint   `gorm:"primaryKey" json:"id"`
	SectionID     uint   `gorm:"not null;index" json:"section_id"`
	NameRu        string `gorm:"size:200;not null" json:"name_ru"`
	NameKz        string `gorm:"size:200;not null" json:"name_kz"`
	DescriptionRu string `gorm:"type:text" json:"description_ru,omitempty"`
	DescriptionKz string `gorm:"type:text" json:"description_kz,omitempty"`
	// QuantityText is free-form ("200 г", "1 порция на гостя") rather than
	// a structured amount+unit pair — matches how little structure this
	// codebase already imposes on similar display-only text elsewhere
	// (e.g. Listing.DescriptionRu/Kz).
	QuantityText string `gorm:"size:100" json:"quantity_text,omitempty"`
	SortOrder    int    `gorm:"not null;default:0" json:"sort_order"`
}

// ListingMenuExtra is an optional add-on priced independently of the
// per-guest menu price (e.g. an extra drink package, a service fee, decor)
// — Type/Unit are free-form strings rather than DB enums, matching how
// Event.Type/Booking.Status are already modeled in this codebase.
type ListingMenuExtra struct {
	ID            uint   `gorm:"primaryKey" json:"id"`
	MenuID        uint   `gorm:"not null;index" json:"menu_id"`
	Type          string `gorm:"size:30;not null" json:"type"`
	TitleRu       string `gorm:"size:200;not null" json:"title_ru"`
	TitleKz       string `gorm:"size:200;not null" json:"title_kz"`
	Price         uint   `gorm:"not null;default:0" json:"price"`
	Unit          string `gorm:"size:30" json:"unit,omitempty"`
	DescriptionRu string `gorm:"type:text" json:"description_ru,omitempty"`
	DescriptionKz string `gorm:"type:text" json:"description_kz,omitempty"`
	SortOrder     int    `gorm:"not null;default:0" json:"sort_order"`
}
