package models

import "time"

// Password-reset code purposes: "reset" is the signed-out "forgot
// password" flow, "change" the signed-in "I don't remember my current
// password" one. A code only ever works for the purpose it was issued for.
const (
	PasswordCodePurposeReset  = "reset"
	PasswordCodePurposeChange = "change"
)

// PasswordResetCode is one one-time code sent to a user's phone to prove
// they own it before their password is replaced (internal/passwordreset).
// The code itself is never stored — only an HMAC of it, keyed by a secret
// that isn't in the database (see passwordreset.Service).
//
// At most one code per user and purpose is live at a time — "live" meaning
// neither used nor invalidated — enforced by a partial unique index, so
// even two concurrent requests can't leave two usable codes behind.
// Expiry and the attempt cap are checked when a code is verified.
type PasswordResetCode struct {
	ID     uint `gorm:"primaryKey"`
	UserID uint `gorm:"not null;index:idx_prc_user_purpose_created,priority:1;uniqueIndex:idx_prc_live,where:used_at IS NULL AND invalidated_at IS NULL,priority:1"`
	// PhoneNormalized is the number the code was sent to — what the
	// per-phone cooldown/hourly cap count by.
	PhoneNormalized string    `gorm:"size:20;not null;index:idx_prc_phone_created,priority:1"`
	Purpose         string    `gorm:"size:16;not null;index:idx_prc_user_purpose_created,priority:2;uniqueIndex:idx_prc_live,priority:2"`
	CodeHash        string    `gorm:"size:64;not null"`
	ExpiresAt       time.Time `gorm:"not null"`
	Attempts        int       `gorm:"not null;default:0"`
	UsedAt          *time.Time
	// InvalidatedAt — superseded by a newer code, out of attempts, or never
	// delivered.
	InvalidatedAt *time.Time
	CreatedAt     time.Time `gorm:"index:idx_prc_user_purpose_created,priority:3;index:idx_prc_phone_created,priority:2"`
}
