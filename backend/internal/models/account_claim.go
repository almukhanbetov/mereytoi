package models

import "time"

// AccountClaim is a one-time-onboarding bridge, not a general auth
// mechanism: when the booking→account pipeline (handlers/onboarding.go)
// auto-creates a brand-new "pending" User (no password, no session), this
// is the only way that person can actually open the workspace it just
// created for them.
//
// Single-use (UsedAt), unlike EventInvitation's own "reusable, not
// single-use" convention — deliberately different here because the actual
// delivery today is a same-page button click right after the booking
// response is received (see FloatingManagerWidget/CartDrawer/Contacts'
// success screens), never an externally-sent link someone might revisit
// days later; a fresh booking from the same still-pending phone mints its
// own new claim rather than reusing an old one (see onboarding.go's
// reconcileExistingUser). If SMS/WhatsApp delivery is added later and a
// claim link needs to survive being reopened, revisit this — a short reuse
// grace window would be the natural next step, not reverting to unlimited
// reuse.
//
// Deliberately never minted for an existing Status=active (password-
// protected) account — see onboarding.go's doc comment on why that would
// be an account-takeover risk, not a convenience.
type AccountClaim struct {
	ID        uint       `gorm:"primaryKey" json:"id"`
	UserID    uint       `gorm:"not null;index" json:"user_id"`
	Token     string     `gorm:"size:64;uniqueIndex;not null" json:"-"`
	ExpiresAt time.Time  `json:"expires_at"`
	UsedAt    *time.Time `json:"-"`
	CreatedAt time.Time  `json:"created_at"`

	// Delivery* — additive audit trail for the claim-link delivery pipeline
	// (internal/claimdelivery). Never touched by anything claim-semantic
	// (Claim/mintClaim above don't read these); purely observability plus
	// what BookingWorkspaceCTA.jsx needs to decide its own copy (brief
	// section 8 — "если внешняя доставка отсутствует: не писать, что
	// сообщение отправлено").
	//
	// DeliveryChannel: "" | "whatsapp" | "telegram" (SMS was this
	// pipeline's first iteration and has been fully removed — see
	// claimdelivery.Service's own doc comment).
	// DeliveryStatus: "" (never attempted — delivery not configured, or
	// this claim's account was never eligible, e.g. existing_account) |
	// "sent" | "failed" | "skipped" (rate-limited).
	// DeliveryError is a short classification (e.g. "provider_5xx",
	// "timeout") — never the raw provider error text, which could echo
	// back the request URL (and, for Telegram, the bot token embedded in
	// it) and, for either channel, the claim link/token in the message body.
	DeliveryChannel     string     `gorm:"size:16" json:"-"`
	DeliveryStatus      string     `gorm:"size:16;index" json:"-"`
	DeliveryAttemptedAt *time.Time `json:"-"`
	DeliverySentAt      *time.Time `json:"-"`
	DeliveryError       string     `gorm:"size:64" json:"-"`
}
