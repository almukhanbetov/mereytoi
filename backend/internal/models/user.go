package models

import "time"

type User struct {
	ID           uint      `gorm:"primaryKey" json:"id"`
	Name         string    `gorm:"size:150;not null" json:"name"`
	Email        string    `gorm:"size:150;uniqueIndex;not null" json:"email"`
	Phone        string    `gorm:"size:30" json:"phone"`
	PasswordHash string    `gorm:"not null" json:"-"`
	Role         string    `gorm:"size:20;not null;default:user" json:"role"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`

	// Status/PhoneNormalized/PhoneVerifiedAt — additive columns for the
	// booking→account onboarding flow (see handlers/onboarding.go). Every
	// row created by the existing Register handler keeps defaulting to
	// Status="active" (a real, password-protected account); "pending" is
	// only ever set by the new onboarding pipeline for an account it just
	// auto-created from a guest booking, and is the one signal that gates
	// whether an AccountClaim link may safely be issued for it (never for
	// an "active" account — see onboarding.go's own doc comment on why).
	Status string `gorm:"size:20;not null;default:active" json:"status"`
	// PhoneNormalized is a *stronger* normalization than the existing
	// normalizePhone() (which only strips whitespace, used for phone-login
	// lookup and display, left completely untouched) — this collapses the
	// "8.../+7..." prefix ambiguity so the onboarding pipeline can actually
	// match "the same person" across booking/registration. Populated
	// additively at Register/UpdateMe time going forward; pre-existing rows
	// simply have "" until next updated — no forced backfill.
	PhoneNormalized string `gorm:"size:20;index" json:"-"`
	// PhoneVerifiedAt is forward-compatible schema only, per the brief's
	// own suggested field list — no OTP/SMS verification flow is built in
	// this stage, so this is always nil for now.
	PhoneVerifiedAt *time.Time `json:"phone_verified_at,omitempty"`

	// TelegramChatID/PreferredDeliveryChannel — claim-link delivery over
	// messengers (internal/claimdelivery), replacing the earlier SMS-based
	// pipeline. TelegramChatID is only ever set by
	// handlers/telegram_handler.go's Webhook, in response to a
	// TelegramLinkToken this exact user minted while authenticated — never
	// derived from anything a Telegram message claims about itself, so
	// there's no way to link Telegram to someone else's account. Not
	// exposed in JSON directly (see Me()'s own additive "telegram_linked"
	// boolean instead) since a raw chat_id is an internal identifier, not
	// something a client needs. PreferredDeliveryChannel is optional
	// (brief section 7 — "не делать обязательной"); "" means "use the
	// default priority order" (claimdelivery.Service's own
	// ClaimDeliveryPrimary-driven default, WhatsApp first).
	TelegramChatID           string `gorm:"size:32" json:"-"`
	PreferredDeliveryChannel string `gorm:"size:16" json:"-"`
}

const (
	UserStatusActive  = "active"
	UserStatusPending = "pending"
)
