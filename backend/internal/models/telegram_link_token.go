package models

import "time"

// TelegramLinkToken is the short-lived "prove this Telegram chat belongs to
// this MEREYTOI account" bridge (brief section 5) — deliberately a
// separate token/table from AccountClaim, never the claim token itself:
// minted only for an already-authenticated user (see
// handlers/telegram_handler.go's MintLinkToken), carried through
// `https://t.me/<bot>?start=<token>`, and consumed by the bot's own
// webhook (Webhook) the moment Telegram delivers the resulting /start
// update — which is the only place a User's TelegramChatID is ever set,
// and always from this token's own UserID, never from anything the
// Telegram message itself claims to be. Single-use and short-lived
// (15 minutes — see telegramLinkTTL) since it only needs to survive one
// app-switch from browser to Telegram, not weeks like an onboarding claim.
type TelegramLinkToken struct {
	ID        uint       `gorm:"primaryKey" json:"id"`
	UserID    uint       `gorm:"not null;index" json:"user_id"`
	Token     string     `gorm:"size:64;uniqueIndex;not null" json:"-"`
	ExpiresAt time.Time  `json:"expires_at"`
	UsedAt    *time.Time `json:"-"`
	CreatedAt time.Time  `json:"created_at"`
}
