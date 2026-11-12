package handlers

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"github.com/almukhanbetov/mereytoi/backend/internal/config"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
	"github.com/almukhanbetov/mereytoi/backend/internal/promotion"
	"github.com/almukhanbetov/mereytoi/backend/internal/ratelimit"
)

// GoogleStore is the part of the Play Developer API the server uses.
type GoogleStore interface {
	GetPurchase(ctx context.Context, productID, token string) (promotion.GooglePurchase, error)
	Acknowledge(ctx context.Context, productID, token string) error
	Consume(ctx context.Context, productID, token string) error
}

// AppleStore verifies data signed by the App Store.
type AppleStore interface {
	VerifyTransaction(jws string) (promotion.AppleTransaction, error)
	VerifyNotification(signedPayload string) (promotion.AppleNotification, promotion.AppleTransaction, error)
}

// promotionEventWindow — one viewer counts once per event kind per
// promotion inside this window (repeat views, reloads, scrolling back).
const promotionEventWindow = 30 * time.Minute

// PromotionHandler serves paid promotion: the owner's package/status,
// orders, store purchase checks, store notifications, ad statistics and
// the catalog feed with ads.
type PromotionHandler struct {
	DB     *gorm.DB
	Cfg    config.Config
	Google GoogleStore // nil until the Play service account is configured
	Apple  AppleStore  // nil until the Apple root certificate is configured
	// Secret keys the feed cursor and the viewer hash.
	Secret string
	Now    func() time.Time
	events ratelimit.Limiter
}

func NewPromotionHandler(db *gorm.DB, cfg config.Config, google GoogleStore, apple AppleStore) *PromotionHandler {
	return &PromotionHandler{
		DB: db, Cfg: cfg, Google: google, Apple: apple, Secret: cfg.JWTSecret, Now: time.Now,
		// Per client IP, across all promotions: generous for real scrolling,
		// a hard ceiling for scripted inflation.
		events: ratelimit.NewMemory(300, 10*time.Minute),
	}
}

func (h *PromotionHandler) now() time.Time { return h.Now().UTC() }

// settings returns the single admin row (defaults if never saved).
func (h *PromotionHandler) settings() models.PromotionSettings {
	var s models.PromotionSettings
	if err := h.DB.First(&s, 1).Error; err != nil {
		return models.PromotionSettings{ID: 1}
	}
	return s
}

// adsOn — whether ads run at all right now.
func (h *PromotionHandler) adsOn(s models.PromotionSettings) bool {
	return h.Cfg.PromotionsEnabled && s.Enabled
}

func (h *PromotionHandler) layout() promotion.Layout {
	return promotion.Layout{First: h.Cfg.PromotionFirstPosition, Every: h.Cfg.PromotionEvery}
}

// channelState says whether purchases through channel can start, and why not.
func (h *PromotionHandler) channelState(channel string, s models.PromotionSettings) (productID string, available bool, reason string) {
	switch channel {
	case models.PromotionChannelGoogle:
		switch {
		case h.Google == nil:
			return "", false, "store_not_configured"
		case s.GoogleProductID == "":
			return "", false, "product_not_configured"
		}
		return s.GoogleProductID, true, ""
	case models.PromotionChannelApple:
		switch {
		case h.Apple == nil:
			return "", false, "store_not_configured"
		case s.AppleProductID == "":
			return "", false, "product_not_configured"
		}
		return s.AppleProductID, true, ""
	case models.PromotionChannelWeb:
		// No web payment provider exists in MEREYTOI yet.
		return "", false, "web_payment_not_available"
	}
	return "", false, "unknown_channel"
}

// listingOwner — the user with the owner role on the listing, if any.
func listingOwner(db *gorm.DB, listingID uint) (uint, bool) {
	var m models.ListingManager
	if err := db.Where("listing_id = ? AND role = ?", listingID, models.ListingManagerRoleOwner).First(&m).Error; err != nil {
		return 0, false
	}
	return m.UserID, true
}

// ineligibleReason — why a listing can't be advertised now ("" if it can):
// it must be published (is_active) and belong to an active provider. A
// hidden listing or a suspended/rejected provider drops out of ads at once.
func ineligibleReason(db *gorm.DB, listing models.Listing) string {
	if !listing.IsActive {
		return "listing_hidden"
	}
	owner, ok := listingOwner(db, listing.ID)
	if !ok {
		return "no_owner"
	}
	var p models.Provider
	if err := db.Where("user_id = ?", owner).First(&p).Error; err != nil || p.Status != models.ProviderStatusActive {
		return "provider_not_active"
	}
	return ""
}

// runningPromotion — the paid period in effect for the listing now, if any.
func (h *PromotionHandler) runningPromotion(db *gorm.DB, listingID uint) *models.Promotion {
	now := h.now()
	var p models.Promotion
	if err := db.Where("listing_id = ? AND status = ? AND starts_at <= ? AND ends_at > ?",
		listingID, models.PromotionActive, now, now).Order("ends_at desc").First(&p).Error; err != nil {
		return nil
	}
	return &p
}

type promotionStats struct {
	Impressions uint `json:"impressions"`
	Clicks      uint `json:"clicks"`
	Chats       uint `json:"chats"`
	Calls       uint `json:"calls"`
	WhatsApp    uint `json:"whatsapp"`
}

type promotionOut struct {
	ID        uint           `json:"id"`
	Status    string         `json:"status"`
	Running   bool           `json:"running"`
	Channel   string         `json:"channel"`
	StartsAt  time.Time      `json:"starts_at"`
	EndsAt    time.Time      `json:"ends_at"`
	RevokedAt *time.Time     `json:"revoked_at,omitempty"`
	Stats     promotionStats `json:"stats"`
}

func (h *PromotionHandler) statsFor(ids []uint) map[uint]promotionStats {
	out := map[uint]promotionStats{}
	if len(ids) == 0 {
		return out
	}
	var rows []models.PromotionStat
	h.DB.Where("promotion_id IN ?", ids).Find(&rows)
	for _, r := range rows {
		s := out[r.PromotionID]
		switch r.Kind {
		case models.PromotionEventImpression:
			s.Impressions = r.Count
		case models.PromotionEventClick:
			s.Clicks = r.Count
		case models.PromotionEventChat:
			s.Chats = r.Count
		case models.PromotionEventCall:
			s.Calls = r.Count
		case models.PromotionEventWhatsApp:
			s.WhatsApp = r.Count
		}
		out[r.PromotionID] = s
	}
	return out
}

func (h *PromotionHandler) outs(list []models.Promotion) []promotionOut {
	ids := make([]uint, len(list))
	for i, p := range list {
		ids[i] = p.ID
	}
	stats := h.statsFor(ids)
	now := h.now()
	out := make([]promotionOut, 0, len(list))
	for _, p := range list {
		out = append(out, promotionOut{
			ID: p.ID, Status: p.Status, Channel: p.Channel, StartsAt: p.StartsAt, EndsAt: p.EndsAt, RevokedAt: p.RevokedAt,
			Running: p.Status == models.PromotionActive && !now.Before(p.StartsAt) && now.Before(p.EndsAt),
			Stats:   stats[p.ID],
		})
	}
	return out
}

type channelOut struct {
	Available bool   `json:"available"`
	ProductID string `json:"product_id,omitempty"`
	Reason    string `json:"reason,omitempty"`
}

// ListingStatus — GET /api/promotions/listings/:id (owner, manager or
// admin of the listing, enforced by RequireListingAccess): the package
// terms and price before payment, whether and how it can be bought, the
// running promotion and every past one with its statistics.
func (h *PromotionHandler) ListingStatus(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	var listing models.Listing
	if err := h.DB.First(&listing, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "listing not found"})
		return
	}
	s := h.settings()

	var history []models.Promotion
	h.DB.Where("listing_id = ?", listing.ID).Order("starts_at desc, id desc").Limit(50).Find(&history)
	all := h.outs(history)
	var running *promotionOut
	for i := range all {
		if all[i].Running {
			running = &all[i]
			break
		}
	}

	channels := map[string]channelOut{}
	for _, ch := range []string{models.PromotionChannelGoogle, models.PromotionChannelApple, models.PromotionChannelWeb} {
		pid, ok, reason := h.channelState(ch, s)
		channels[ch] = channelOut{Available: ok, ProductID: pid, Reason: reason}
	}

	blocked := h.purchaseBlock(listing, s, running != nil, listingRole(c) == models.ListingManagerRoleOwner)

	c.JSON(http.StatusOK, gin.H{
		"listing_id": listing.ID,
		"package": gin.H{
			"duration_days": models.PromotionDurationDays,
			"auto_renew":    false,
			"price_kzt":     s.PriceKZT,
			"currency":      "KZT",
		},
		"channels":       channels,
		"can_purchase":   blocked == "",
		"blocked_reason": blocked,
		"running":        running,
		"history":        all,
	})
}

// purchaseBlock — why the caller can't start a purchase ("" if they can).
// Store availability is per channel and reported separately.
func (h *PromotionHandler) purchaseBlock(listing models.Listing, s models.PromotionSettings, running, isOwner bool) string {
	switch {
	case !h.Cfg.PromotionsEnabled || !s.Enabled:
		return "promotions_disabled"
	case s.PriceKZT == 0:
		return "price_not_set"
	case !isOwner:
		return "not_owner"
	case running:
		return "already_running"
	}
	return ineligibleReason(h.DB, listing)
}

type orderInput struct {
	ListingID uint   `json:"listing_id" binding:"required"`
	Channel   string `json:"channel" binding:"required"`
}

// CreateOrder — POST /api/promotions/orders. Only the listing's owner may
// buy; the order carries a random token the store purchase must quote back.
func (h *PromotionHandler) CreateOrder(c *gin.Context) {
	var in orderInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_input"})
		return
	}
	userID := currentUserID(c)
	var listing models.Listing
	if err := h.DB.First(&listing, in.ListingID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "listing not found"})
		return
	}
	if owner, ok := listingOwner(h.DB, listing.ID); !ok || owner != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "not_owner"})
		return
	}
	s := h.settings()
	if reason := h.purchaseBlock(listing, s, h.runningPromotion(h.DB, listing.ID) != nil, true); reason != "" {
		c.JSON(http.StatusConflict, gin.H{"error": reason})
		return
	}
	productID, ok, reason := h.channelState(in.Channel, s)
	if !ok {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": reason})
		return
	}
	token, err := newUUID()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create order"})
		return
	}
	order := models.PromotionOrder{
		ListingID: listing.ID, UserID: userID, Channel: in.Channel, ProductID: productID,
		Token: token, Status: models.PromotionOrderOpen, PriceKZT: s.PriceKZT,
	}
	if err := h.DB.Create(&order).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create order"})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"order": gin.H{
		"id": order.ID, "token": order.Token, "channel": order.Channel, "product_id": order.ProductID,
		"price_kzt": order.PriceKZT, "duration_days": models.PromotionDurationDays,
	}})
}

// ownOrder loads an order of the caller for channel.
func (h *PromotionHandler) ownOrder(c *gin.Context, orderID uint, channel string) (*models.PromotionOrder, bool) {
	var o models.PromotionOrder
	if err := h.DB.Where("id = ? AND user_id = ? AND channel = ?", orderID, currentUserID(c), channel).First(&o).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "order not found"})
		return nil, false
	}
	return &o, true
}

var errOrderUsed = errors.New("order already paid by another transaction")

// activate turns a verified payment into a Promotion, once. A repeated
// call or notification for the same store transaction returns the promotion
// it already created. A second payment racing an already-running promotion
// of the same listing starts when that one ends, so no payment is lost.
func (h *PromotionHandler) activate(order models.PromotionOrder, txKey, purchaseToken string) (models.Promotion, bool, error) {
	var out models.Promotion
	created := false
	err := h.DB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("transaction_key = ?", txKey).First(&out).Error; err == nil {
			if out.OrderID != order.ID {
				return errOrderUsed
			}
			return nil
		}
		if err := tx.Where("order_id = ?", order.ID).First(&out).Error; err == nil {
			return errOrderUsed
		}
		start := h.now()
		if run := h.runningPromotion(tx, order.ListingID); run != nil && run.EndsAt.After(start) {
			start = run.EndsAt
		}
		out = models.Promotion{
			ListingID: order.ListingID, OrderID: order.ID, UserID: order.UserID, Channel: order.Channel,
			ProductID: order.ProductID, TransactionKey: txKey, StorePurchaseToken: purchaseToken,
			Status: models.PromotionActive, StartsAt: start,
			EndsAt: start.Add(models.PromotionDurationDays * 24 * time.Hour), PriceKZT: order.PriceKZT,
		}
		if err := tx.Create(&out).Error; err != nil {
			return err
		}
		created = true
		return tx.Model(&models.PromotionOrder{}).Where("id = ?", order.ID).
			Update("status", models.PromotionOrderCompleted).Error
	})
	if err != nil && !errors.Is(err, errOrderUsed) {
		// A concurrent request may have created it between our read and
		// insert; the unique key makes that the only possible conflict.
		var again models.Promotion
		if h.DB.Where("transaction_key = ? AND order_id = ?", txKey, order.ID).First(&again).Error == nil {
			return again, false, nil
		}
	}
	return out, created, err
}

// revoke takes a promotion out of ads after a refund/void/revocation.
func (h *PromotionHandler) revoke(q *gorm.DB, status, reason string) int64 {
	now := h.now()
	res := q.Model(&models.Promotion{}).Where("status = ?", models.PromotionActive).
		Updates(map[string]any{"status": status, "revoked_at": now, "revoke_reason": reason})
	return res.RowsAffected
}

type googlePurchaseInput struct {
	OrderID       uint   `json:"order_id" binding:"required"`
	PurchaseToken string `json:"purchase_token" binding:"required"`
}

// ConfirmGoogle — POST /api/promotions/purchases/google. The client's word
// is never trusted: the purchase is fetched from Google Play and must be
// paid, for this order's product, and quote this order's token.
func (h *PromotionHandler) ConfirmGoogle(c *gin.Context) {
	var in googlePurchaseInput
	if err := c.ShouldBindJSON(&in); err != nil || len(in.PurchaseToken) > 500 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_input"})
		return
	}
	if h.Google == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "store_not_configured"})
		return
	}
	order, ok := h.ownOrder(c, in.OrderID, models.PromotionChannelGoogle)
	if !ok {
		return
	}
	status, body := h.applyGooglePurchase(c.Request.Context(), *order, in.PurchaseToken)
	c.JSON(status, body)
}

// applyGooglePurchase verifies a purchase token for order and activates it.
func (h *PromotionHandler) applyGooglePurchase(ctx context.Context, order models.PromotionOrder, token string) (int, gin.H) {
	p, err := h.Google.GetPurchase(ctx, order.ProductID, token)
	if err != nil {
		log.Printf("[promotion] google purchase check failed for order %d: %v", order.ID, err)
		return http.StatusBadGateway, gin.H{"error": "store_unavailable"}
	}
	if !strings.EqualFold(p.ObfuscatedExternalAccountID, order.Token) {
		return http.StatusConflict, gin.H{"error": "order_mismatch"}
	}
	switch p.PurchaseState {
	case promotion.GooglePending:
		return http.StatusAccepted, gin.H{"status": "pending"}
	case promotion.GooglePurchased:
	default:
		h.DB.Model(&models.PromotionOrder{}).Where("id = ? AND status = ?", order.ID, models.PromotionOrderOpen).
			Update("status", models.PromotionOrderCancelled)
		return http.StatusConflict, gin.H{"error": "payment_cancelled"}
	}
	key := "google:" + p.OrderID
	if p.OrderID == "" {
		key = "google-token:" + token
	}
	promo, created, err := h.activate(order, key, token)
	if errors.Is(err, errOrderUsed) {
		return http.StatusConflict, gin.H{"error": "order_used"}
	}
	if err != nil {
		return http.StatusInternalServerError, gin.H{"error": "activation_failed"}
	}
	// Delivery is confirmed only after the promotion exists. Failures are
	// retried by the next call/notification; Google refunds a purchase
	// that stays unacknowledged for 3 days.
	if p.AcknowledgementState == 0 {
		if err := h.Google.Acknowledge(ctx, order.ProductID, token); err != nil {
			log.Printf("[promotion] google acknowledge failed for order %d: %v", order.ID, err)
		}
	}
	if p.ConsumptionState == 0 {
		if err := h.Google.Consume(ctx, order.ProductID, token); err != nil {
			log.Printf("[promotion] google consume failed for order %d: %v", order.ID, err)
		}
	}
	status := http.StatusOK
	if created {
		status = http.StatusCreated
	}
	return status, gin.H{"promotion": h.outs([]models.Promotion{promo})[0]}
}

type applePurchaseInput struct {
	OrderID           uint   `json:"order_id" binding:"required"`
	SignedTransaction string `json:"signed_transaction" binding:"required"`
}

// ConfirmApple — POST /api/promotions/purchases/apple with the StoreKit 2
// signed transaction; its signature, app, environment, product and order
// token are all checked here.
func (h *PromotionHandler) ConfirmApple(c *gin.Context) {
	var in applePurchaseInput
	if err := c.ShouldBindJSON(&in); err != nil || len(in.SignedTransaction) > 20000 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_input"})
		return
	}
	if h.Apple == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "store_not_configured"})
		return
	}
	order, ok := h.ownOrder(c, in.OrderID, models.PromotionChannelApple)
	if !ok {
		return
	}
	tx, err := h.Apple.VerifyTransaction(in.SignedTransaction)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_transaction"})
		return
	}
	status, body := h.applyAppleTransaction(*order, tx)
	c.JSON(status, body)
}

func (h *PromotionHandler) applyAppleTransaction(order models.PromotionOrder, tx promotion.AppleTransaction) (int, gin.H) {
	if tx.ProductID != order.ProductID || !strings.EqualFold(tx.AppAccountToken, order.Token) {
		return http.StatusConflict, gin.H{"error": "order_mismatch"}
	}
	if tx.RevocationDate != 0 {
		return http.StatusConflict, gin.H{"error": "payment_refunded"}
	}
	promo, created, err := h.activate(order, "apple:"+tx.TransactionID, "")
	if errors.Is(err, errOrderUsed) {
		return http.StatusConflict, gin.H{"error": "order_used"}
	}
	if err != nil {
		return http.StatusInternalServerError, gin.H{"error": "activation_failed"}
	}
	status := http.StatusOK
	if created {
		status = http.StatusCreated
	}
	return status, gin.H{"promotion": h.outs([]models.Promotion{promo})[0]}
}

// seenNotification records a store notification id; false if it was
// already applied (a redelivery).
func (h *PromotionHandler) seenNotification(channel, id, kind string) bool {
	if id == "" {
		return false
	}
	res := h.DB.Clauses(clause.OnConflict{DoNothing: true}).Create(&models.PromotionStoreNotification{
		Channel: channel, NotificationID: id, Type: kind, CreatedAt: h.now(),
	})
	return res.Error == nil && res.RowsAffected == 0
}

func (h *PromotionHandler) forgetNotification(channel, id string) {
	h.DB.Where("channel = ? AND notification_id = ?", channel, id).Delete(&models.PromotionStoreNotification{})
}

// newUUID returns a random RFC 4122 version 4 UUID.
func newUUID() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	b[6] = b[6]&0x0f | 0x40
	b[8] = b[8]&0x3f | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16]), nil
}

func randomSeed() uint64 {
	var b [8]byte
	_, _ = rand.Read(b[:])
	return binary.LittleEndian.Uint64(b[:])
}

// viewerHash identifies a viewer without storing who: the signed-in user,
// else the client IP (resolved through trusted proxies only).
func (h *PromotionHandler) viewerHash(c *gin.Context) string {
	viewer := "ip:" + c.ClientIP()
	if id := currentUserID(c); id != 0 {
		viewer = fmt.Sprintf("user:%d", id)
	}
	m := hmac.New(sha256.New, []byte("promotion-viewer:"+h.Secret))
	m.Write([]byte(viewer))
	return hex.EncodeToString(m.Sum(nil))
}
