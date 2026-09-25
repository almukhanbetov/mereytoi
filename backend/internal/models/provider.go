package models

import "time"

// Provider is a user's optional "услугодатель" profile — Этап 11. A plain
// User stays a plain User (brief section 2: "не вводить отдельный тип
// login"); Provider is a separate, optional 1:1 extension of one, the same
// way ManagerConversation extends User with a customer-support thread
// without turning them into a different kind of account. A User can be a
// customer, an "Мой той" member, and a services provider all at once —
// nothing here changes User.Role or auth.
//
// Ownership of the provider's actual listings is deliberately NOT modeled
// here (no Provider.Listings, no Listing.ProviderID) — it reuses the
// existing ListingManager table restaurants/venues already use (brief
// section 6: "не дублируй существующую ownership-логику"). A listing's
// provider, when one exists, is derived by joining
// ListingManager(role=owner) -> UserID -> Provider(user_id) — see
// listing_handler.go's attachProviderBriefs/loadProviderBrief.
type Provider struct {
	ID uint `gorm:"primaryKey" json:"id"`
	// UserID unique — "Один User должен иметь максимум один Provider
	// profile" (brief section 2).
	UserID      uint   `gorm:"not null;uniqueIndex" json:"user_id"`
	User        *User  `gorm:"foreignKey:UserID" json:"user,omitempty"`
	DisplayName string `gorm:"size:150;not null" json:"display_name"`
	City        string `gorm:"size:100" json:"city"`
	Description string `gorm:"type:text" json:"description,omitempty"`
	Phone       string `gorm:"size:30" json:"phone,omitempty"`
	WhatsApp    string `gorm:"size:30" json:"whatsapp,omitempty"`
	Telegram    string `gorm:"size:60" json:"telegram,omitempty"`
	AvatarURL   string `gorm:"size:500" json:"avatar_url,omitempty"`

	// Status — see the ProviderStatus* consts below. New profiles are
	// created directly as ProviderStatusActive: this stage explicitly
	// excludes building any moderation admin screen (brief section 14 —
	// "не делать отдельную админку"), so a self-serve profile that landed
	// on "pending" would have no operator-facing way to ever leave it.
	// The enum still exists so a later moderation stage can start writing
	// "pending"/"rejected"/"suspended" without a schema change — nothing
	// in this stage ever sets those values itself.
	Status    string    `gorm:"size:20;not null" json:"status"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

const (
	ProviderStatusDraft     = "draft"
	ProviderStatusPending   = "pending"
	ProviderStatusActive    = "active"
	ProviderStatusRejected  = "rejected"
	ProviderStatusSuspended = "suspended"
)
