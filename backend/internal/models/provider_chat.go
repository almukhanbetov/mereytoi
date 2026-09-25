package models

import "time"

// ProviderConversation — Этап 11G. Direct chat between a customer and a
// marketplace provider, deliberately separate from ManagerConversation
// (which is semantically tied to MEREYTOI's own staff, not to individual
// providers — see manager_chat.go's own doc comment: "guests keep using the
// pre-existing FloatingManagerWidget"). ProviderID references Provider.ID
// (the provider's own marketplace profile row), not the provider's
// underlying User.ID — ownership for "is the caller this conversation's
// provider" is resolved via Provider.UserID at request time (see
// provider_chat_handler.go), never stored redundantly here.
type ProviderConversation struct {
	ID uint `gorm:"primaryKey" json:"id"`

	ProviderID uint      `gorm:"not null;index" json:"provider_id"`
	Provider   *Provider `gorm:"foreignKey:ProviderID" json:"provider,omitempty"`

	CustomerUserID uint  `gorm:"not null;index" json:"customer_user_id"`
	Customer       *User `gorm:"foreignKey:CustomerUserID" json:"customer,omitempty"`

	ListingID *uint    `gorm:"index" json:"listing_id,omitempty"`
	Listing   *Listing `gorm:"foreignKey:ListingID" json:"listing,omitempty"`

	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// ProviderMessage — one message inside a ProviderConversation. No
// SenderType column (unlike ManagerMessage, which needs one because "the
// manager side" can be any admin): a ProviderConversation only ever has
// exactly two possible senders — the customer (CustomerUserID) or the
// provider's own account (Provider.UserID) — so SenderUserID alone lets the
// handler resolve "who sent this" and lets a client decide "is this my own
// message" by comparing against its own logged-in user id, no extra field
// needed.
type ProviderMessage struct {
	ID             uint `gorm:"primaryKey" json:"id"`
	ConversationID uint `gorm:"not null;index" json:"conversation_id"`

	SenderUserID uint `gorm:"not null" json:"sender_user_id"`

	Body      string     `gorm:"type:text;not null" json:"body"`
	ReadAt    *time.Time `json:"read_at,omitempty"`
	CreatedAt time.Time  `gorm:"index" json:"created_at"`
}
