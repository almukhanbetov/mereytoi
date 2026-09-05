package models

import "time"

// ManagerConversation is a real two-way thread between one customer and
// MEREYTOI's manager — distinct from every other message-shaped thing
// already in this codebase:
//   - Booking is a one-shot lead/order snapshot (no back-and-forth, no
//     message history) — still used unchanged for guest visitors, who
//     don't get a persistent chat identity to attach a conversation to.
//   - EventComment is the *team's own* internal discussion, never seen by
//     a manager (see event.go's own doc comment on that distinction).
//   - Notification is one-directional, system-generated, never a reply
//     channel.
//
// None of those fit a genuine two-way conversation, so this is a new,
// deliberately small pair of tables (see the stage report for the audit
// that led here) — not a CRM, just enough for "customer writes, manager
// replies, both see history."
//
// ListingID is this project's own name for what the brief calls
// "service_id" — a Listing already *is* the service being asked about
// (see models/listing.go), so this reuses that name/id rather than
// inventing a second one for the same concept.
type ManagerConversation struct {
	ID uint `gorm:"primaryKey" json:"id"`
	// UserID is required — the real-time, back-and-forth chat this stage
	// adds is an authenticated-only feature (see the stage report); guests
	// keep using the pre-existing FloatingManagerWidget "leave a message"
	// form, which becomes a Booking, unchanged.
	UserID uint  `gorm:"not null;index" json:"user_id"`
	User   *User `gorm:"foreignKey:UserID" json:"user,omitempty"`

	// EventID/ListingID are the "what page were they on" context (brief
	// section 17) — both optional and independent: a conversation can be
	// general (both nil), about one service (ListingID only), about one
	// event with no specific service (EventID only), or both.
	EventID   *uint    `gorm:"index" json:"event_id,omitempty"`
	Event     *Event   `gorm:"foreignKey:EventID" json:"event,omitempty"`
	ListingID *uint    `gorm:"index" json:"listing_id,omitempty"`
	Listing   *Listing `gorm:"foreignKey:ListingID" json:"listing,omitempty"`

	// Status: open (default) | closed. Closing is a manual admin action —
	// nothing in this stage closes one automatically.
	Status    string    `gorm:"size:20;not null;default:open" json:"status"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

const (
	ConversationOpen   = "open"
	ConversationClosed = "closed"
)

// ManagerMessage is one line in a ManagerConversation.
type ManagerMessage struct {
	ID             uint `gorm:"primaryKey" json:"id"`
	ConversationID uint `gorm:"not null;index" json:"conversation_id"`
	// SenderType: "user" | "manager" — which side of the conversation this
	// is, independent of exactly which admin account replied (any admin
	// can answer any conversation, matching how this project already has
	// no per-admin-account assignment anywhere else either).
	SenderType   string     `gorm:"size:10;not null" json:"sender_type"`
	SenderUserID *uint      `json:"sender_user_id,omitempty"`
	Body         string     `gorm:"type:text;not null" json:"body"`
	ReadAt       *time.Time `json:"read_at,omitempty"`
	CreatedAt    time.Time  `gorm:"index" json:"created_at"`
}

const (
	SenderUser    = "user"
	SenderManager = "manager"
)
