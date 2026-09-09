package models

import "time"

// ListingHall is one physical hall/room belonging to a restaurant/venue
// Listing — "Listing = ресторан как поставщик/площадка, Hall = конкретный
// зал" (brief section 1). Purely additive: a Listing with zero halls
// behaves exactly as it always has — every place that reads a
// candidate/booking's HallID treats nil as "no specific hall chosen,"
// the pre-existing behavior, not an error state.
//
// Deliberately no back-reference slice field on Listing itself (no
// `Listing.Halls []ListingHall`) — every read of a listing's halls goes
// through an explicit, handler-level query (see listing_handler.go's
// Get/Menus) instead of a GORM association, so Listing's own JSON shape
// and migration behavior are completely unaffected by this table's
// existence, and no accidental N+1/auto-FK-constraint surprise can creep
// in through a Preload nobody asked for.
type ListingHall struct {
	ID            uint   `gorm:"primaryKey" json:"id"`
	ListingID     uint   `gorm:"not null;index" json:"listing_id"`
	NameRu        string `gorm:"size:200;not null" json:"name_ru"`
	NameKz        string `gorm:"size:200;not null" json:"name_kz"`
	DescriptionRu string `gorm:"type:text" json:"description_ru,omitempty"`
	DescriptionKz string `gorm:"type:text" json:"description_kz,omitempty"`

	// Capacity — this hall's own physical capacity. See Listing.Capacity's
	// own doc comment on why these are deliberately separate concepts, and
	// why neither reuses Listing.MinGuests/MaxGuests.
	Capacity uint `gorm:"default:0" json:"capacity"`

	// Price — 0 means "inherit Listing.Price" (brief section 2's own
	// wording). Never silently resolved at write time; a call site that
	// needs the effective price picks Price when non-zero, else the
	// parent Listing's Price, the same "own value overrides inherited
	// value" shape ListingMenu.PricePerGuest also follows.
	Price     uint     `gorm:"default:0" json:"price"`
	ImageURLs []string `gorm:"serializer:json" json:"image_urls"`
	// IsActive deliberately carries no `default:` tag, unlike most other
	// boolean columns in this codebase (e.g. Listing.IsActive) — GORM
	// treats a bool field with a `default:` tag whose value is false (its
	// own Go zero value) as "not set," and silently lets the DB's own
	// DEFAULT win instead, even when the caller explicitly asked for
	// false. Found live while building the admin UI's "Дублировать меню"
	// (a duplicate created inactive kept coming back active); the Go
	// literal (`IsActive: true` unless overridden — see Create/Update in
	// listing_hall_handler.go) already fully owns the default, so no
	// DB-level default is needed or safe to keep here. This is a pure Go
	// struct-tag fix — no migration/ALTER needed, since GORM's skip
	// behavior is driven by its own tag metadata, not by inspecting the
	// live column (verified directly against this exact Postgres/GORM
	// version before applying).
	IsActive  bool      `gorm:"not null" json:"is_active"`
	SortOrder int       `gorm:"not null;default:0" json:"sort_order"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}
