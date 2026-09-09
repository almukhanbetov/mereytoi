package models

import "time"

// BookingItem is a single line within a booking: one selected listing with
// the price snapshot at the time of the request (and guest count, for
// per-person priced venues). The whole []BookingItem slice is serialized
// as one JSON blob column (Booking.Items, `gorm:"serializer:json"`), so
// every field below is additive purely at the Go/JSON level — an old
// booking's stored JSON simply has no hall_id/menu_id keys, and decodes
// straight into these fields' zero values (nil/""/0), no migration
// needed.
//
// HallID/HallName/MenuID/MenuName/MenuPricePerGuest — restaurant/venue
// hall+menu snapshot (brief section 8). Frozen at booking time so a later
// admin edit to a ListingMenu's price never rewrites a historical
// booking's total — the same "trust and freeze the client-supplied
// snapshot" model this struct's own Name/UnitPrice/TotalPrice already use
// (nothing here is server-re-verified against the live Listing either;
// see booking_handler.go's own doc comment on why that's an intentional,
// pre-existing property of this endpoint, not something this stage
// introduces). Guests above already served as "nullable, 0 = unspecified"
// for ordinary per-guest pricing — reused as-is for a hall/menu-priced
// item's own guest count rather than adding a second, redundant field.
type BookingItem struct {
	ListingID  uint   `json:"listing_id"`
	Name       string `json:"name"`
	Category   string `json:"category"`
	Guests     uint   `json:"guests"`
	UnitPrice  uint   `json:"unit_price"`
	TotalPrice uint   `json:"total_price"`

	HallID            *uint  `json:"hall_id,omitempty"`
	HallName          string `json:"hall_name,omitempty"`
	MenuID            *uint  `json:"menu_id,omitempty"`
	MenuName          string `json:"menu_name,omitempty"`
	MenuPricePerGuest uint   `json:"menu_price_per_guest,omitempty"`

	// SelectedExtras/EstimatedTotal — the calculator's own extras
	// selection and computed total at the moment this item was added to
	// Cart (brief section 5 — added only because no equivalent field
	// existed yet). Frozen the same way as everything else above: a later
	// admin edit to a ListingMenuExtra's price never touches an already-
	// placed booking. EstimatedTotal is informational (what the customer
	// saw on the calculator, extras included) — TotalPrice above stays
	// the one figure the rest of this codebase (admin bookings list,
	// Booking.Total) already sums and displays, so nothing existing has
	// to learn about this new field to keep working.
	SelectedExtras []BookingItemExtra `json:"selected_extras,omitempty"`
	EstimatedTotal uint               `json:"estimated_total,omitempty"`
}

// BookingItemExtra is one frozen ListingMenuExtra selection — deliberately
// a tiny, flat snapshot (not a foreign key to ListingMenuExtra) for the
// same reason HallName/MenuName are plain strings and not just IDs: the
// admin row it came from can be edited or deleted later without touching
// history already written here.
type BookingItemExtra struct {
	Title string `json:"title"`
	Price uint   `json:"price"`
	Unit  string `json:"unit,omitempty"`
}

// Booking is a customer's booking request submitted from the cart — one or
// more BookingItems bundled together with contact info.
type Booking struct {
	ID        uint   `gorm:"primaryKey" json:"id"`
	PublicRef string `gorm:"size:24;uniqueIndex" json:"public_ref"`
	UserID    *uint  `gorm:"index" json:"user_id,omitempty"`
	// EventID links a Booking created from an event workspace's final
	// request (see models/event_request.go) back to that event — nil for
	// every ordinary cart checkout, which is unaffected by this column.
	EventID   *uint         `gorm:"index" json:"event_id,omitempty"`
	Name      string        `gorm:"size:150;not null" json:"name"`
	Phone     string        `gorm:"size:30;not null" json:"phone"`
	Message   string        `gorm:"type:text" json:"message"`
	Items     []BookingItem `gorm:"serializer:json" json:"items"`
	Total     uint          `json:"total"`
	Status    string        `gorm:"size:20;not null;default:new" json:"status"`
	Paid      bool          `gorm:"not null;default:false" json:"paid"`
	CreatedAt time.Time     `json:"created_at"`
	UpdatedAt time.Time     `json:"updated_at"`
}
