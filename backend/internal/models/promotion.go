package models

import "time"

// Paid promotion of a listing ("Продвигать"). Everything here is additive:
// new tables only, no column of an existing table changes.
//
// The money flow is: the owner opens an order for one listing, pays in the
// store (Google Play Billing / Apple In-App Purchase), and the server turns
// the order into a Promotion only after it has verified the purchase with
// the store itself. A store transaction can create at most one Promotion
// (Promotion.TransactionKey is unique), so a repeated notification or a
// repeated client call never creates a duplicate.

// PromotionDurationDays is the length of the only package. It defines the
// product itself, the price does not live in code (PromotionSettings).
const PromotionDurationDays = 7

// Store/payment channels.
const (
	PromotionChannelGoogle = "google"
	PromotionChannelApple  = "apple"
	PromotionChannelWeb    = "web"
)

// PromotionSettings is a single row (ID 1) edited by an admin.
type PromotionSettings struct {
	ID uint `gorm:"primaryKey" json:"-"`
	// Enabled lets an admin pause sales and ads without a deploy. Ads and
	// purchases also need config.PromotionsEnabled.
	Enabled bool `gorm:"not null;default:false" json:"enabled"`
	// PriceKZT is the advertised price in tenge. Store purchases are charged
	// at the price set for the product in App Store Connect / Play Console;
	// the app shows that store price to the buyer.
	PriceKZT uint `gorm:"not null;default:0" json:"price_kzt"`
	// Store product ids of the 7-day package (a consumable product).
	GoogleProductID string    `gorm:"size:150" json:"google_product_id"`
	AppleProductID  string    `gorm:"size:150" json:"apple_product_id"`
	UpdatedBy       *uint     `json:"updated_by,omitempty"`
	UpdatedAt       time.Time `json:"updated_at"`
}

// Order statuses.
const (
	PromotionOrderOpen      = "open"
	PromotionOrderCompleted = "completed"
	PromotionOrderCancelled = "cancelled"
)

// PromotionOrder binds a future store purchase to one listing and one
// buyer. Token (a random UUID) travels with the purchase: Google's
// obfuscatedExternalAccountId, Apple's appAccountToken. The server only
// accepts a purchase whose token matches an open order of the same user.
type PromotionOrder struct {
	ID        uint   `gorm:"primaryKey" json:"id"`
	ListingID uint   `gorm:"not null;index" json:"listing_id"`
	UserID    uint   `gorm:"not null;index" json:"user_id"`
	Channel   string `gorm:"size:20;not null" json:"channel"`
	ProductID string `gorm:"size:150;not null" json:"product_id"`
	Token     string `gorm:"size:64;not null;uniqueIndex" json:"token"`
	Status    string `gorm:"size:20;not null;index" json:"status"`
	// PriceKZT is the admin price shown to the buyer when the order opened.
	PriceKZT  uint      `gorm:"not null;default:0" json:"price_kzt"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// Promotion statuses. Expiry is not a status: a promotion is running while
// Status is active and StartsAt <= now < EndsAt.
const (
	PromotionActive   = "active"
	PromotionRefunded = "refunded"
	PromotionRevoked  = "revoked"
)

// Promotion is one paid 7-day period of one listing.
type Promotion struct {
	ID        uint   `gorm:"primaryKey" json:"id"`
	ListingID uint   `gorm:"not null;index" json:"listing_id"`
	OrderID   uint   `gorm:"not null;uniqueIndex" json:"order_id"`
	UserID    uint   `gorm:"not null;index" json:"user_id"`
	Channel   string `gorm:"size:20;not null" json:"channel"`
	ProductID string `gorm:"size:150;not null" json:"product_id"`
	// TransactionKey is "<channel>:<store transaction id>" — unique, the
	// guard against activating one payment twice. StorePurchaseToken is the
	// Google purchase token (refund notifications reference it).
	TransactionKey     string     `gorm:"size:300;not null;uniqueIndex" json:"-"`
	StorePurchaseToken string     `gorm:"size:500;index" json:"-"`
	Status             string     `gorm:"size:20;not null;index" json:"status"`
	StartsAt           time.Time  `gorm:"not null;index" json:"starts_at"`
	EndsAt             time.Time  `gorm:"not null;index" json:"ends_at"`
	RevokedAt          *time.Time `json:"revoked_at,omitempty"`
	RevokeReason       string     `gorm:"size:100" json:"revoke_reason,omitempty"`
	PriceKZT           uint       `gorm:"not null;default:0" json:"price_kzt"`
	CreatedAt          time.Time  `json:"created_at"`
	UpdatedAt          time.Time  `json:"updated_at"`
}

// Kinds of counted promotion events.
const (
	PromotionEventImpression = "impression"
	PromotionEventClick      = "click"
	PromotionEventChat       = "chat"
	PromotionEventCall       = "call"
	PromotionEventWhatsApp   = "whatsapp"
)

// PromotionStat is the running total of one event kind for one promotion.
type PromotionStat struct {
	ID          uint      `gorm:"primaryKey" json:"-"`
	PromotionID uint      `gorm:"not null;uniqueIndex:idx_promotion_stat" json:"promotion_id"`
	Kind        string    `gorm:"size:20;not null;uniqueIndex:idx_promotion_stat" json:"kind"`
	Count       uint      `gorm:"not null;default:0" json:"count"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// PromotionEventSeen remembers that a viewer was counted for one kind of
// one promotion recently, so a repeat inside the window isn't counted again
// (same scheme as ListingView). ViewerHash is a keyed hash, never an IP.
type PromotionEventSeen struct {
	ID          uint      `gorm:"primaryKey"`
	PromotionID uint      `gorm:"not null;uniqueIndex:idx_promotion_seen"`
	Kind        string    `gorm:"size:20;not null;uniqueIndex:idx_promotion_seen"`
	ViewerHash  string    `gorm:"size:64;not null;uniqueIndex:idx_promotion_seen"`
	LastAt      time.Time `gorm:"not null;index"`
}

// PromotionStoreNotification records each store notification once, so a
// redelivered notification is acknowledged without being applied again.
type PromotionStoreNotification struct {
	ID             uint      `gorm:"primaryKey"`
	Channel        string    `gorm:"size:20;not null;uniqueIndex:idx_promotion_notification"`
	NotificationID string    `gorm:"size:200;not null;uniqueIndex:idx_promotion_notification"`
	Type           string    `gorm:"size:80"`
	CreatedAt      time.Time `gorm:"not null"`
}
