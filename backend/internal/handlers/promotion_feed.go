package handlers

import (
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"github.com/almukhanbetov/mereytoi/backend/internal/middleware"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
	"github.com/almukhanbetov/mereytoi/backend/internal/promotion"
)

const (
	feedDefaultLimit = 20
	feedMaxLimit     = 50
)

// feedItem is a catalog card: the same fields GET /api/listings returns,
// plus whether it's an ad. Ads never change rating, reviews or any badge.
type feedItem struct {
	listingOut
	Promoted    bool  `json:"promoted"`
	PromotionID *uint `json:"promotion_id,omitempty"`
}

// adCandidates — running promotions among the given (already filtered,
// active) listings whose owner's provider profile is active, with their
// impressions so far.
func (h *PromotionHandler) adCandidates(listingIDs []uint) ([]promotion.Candidate, map[uint]uint) {
	promoByListing := map[uint]uint{}
	if len(listingIDs) == 0 {
		return nil, promoByListing
	}
	now := h.now()
	var running []models.Promotion
	h.DB.Where("listing_id IN ? AND status = ? AND starts_at <= ? AND ends_at > ?",
		listingIDs, models.PromotionActive, now, now).Order("id").Find(&running)
	if len(running) == 0 {
		return nil, promoByListing
	}
	ids := make([]uint, 0, len(running))
	for _, p := range running {
		ids = append(ids, p.ListingID)
	}
	var owners []models.ListingManager
	h.DB.Where("listing_id IN ? AND role = ?", ids, models.ListingManagerRoleOwner).Find(&owners)
	ownerOf := map[uint]uint{}
	userIDs := make([]uint, 0, len(owners))
	for _, o := range owners {
		ownerOf[o.ListingID] = o.UserID
		userIDs = append(userIDs, o.UserID)
	}
	activeProvider := map[uint]bool{}
	if len(userIDs) > 0 {
		var providers []models.Provider
		h.DB.Where("user_id IN ? AND status = ?", userIDs, models.ProviderStatusActive).Find(&providers)
		for _, p := range providers {
			activeProvider[p.UserID] = true
		}
	}
	promoIDs := make([]uint, 0, len(running))
	for _, p := range running {
		promoIDs = append(promoIDs, p.ID)
	}
	stats := h.statsFor(promoIDs)

	var out []promotion.Candidate
	for _, p := range running {
		owner, ok := ownerOf[p.ListingID]
		if !ok || !activeProvider[owner] {
			continue
		}
		if _, dup := promoByListing[p.ListingID]; dup {
			continue
		}
		promoByListing[p.ListingID] = p.ID
		out = append(out, promotion.Candidate{
			ListingID: p.ListingID, AdvertiserID: owner, Impressions: stats[p.ID].Impressions,
		})
	}
	return out, promoByListing
}

// Feed — GET /api/listings/feed?category=&city_id=&search=&limit=&cursor=.
// The same filters and order as GET /api/listings, paged, with ads taken
// only from that same filtered result (so an ad always matches the city,
// category and search). The ad order is fixed on page one and carried in
// the signed cursor, so later pages neither repeat nor reshuffle ads and a
// listing never appears both as an ad and as a regular card.
func (h *PromotionHandler) Feed(c *gin.Context) {
	limit := feedDefaultLimit
	if raw := c.Query("limit"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 1 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_limit"})
			return
		}
		if n > feedMaxLimit {
			n = feedMaxLimit
		}
		limit = n
	}
	qkey := promotion.QueryKey(c.Query("category"), c.Query("city_id"), c.Query("search"))

	query, empty, status, errCode := catalogQuery(h.DB, c)
	if status != 0 {
		c.JSON(status, gin.H{"error": errCode})
		return
	}
	var organic []uint
	if !empty {
		if err := query.Order("created_at desc, id desc").Pluck("id", &organic).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch listings"})
			return
		}
	}

	settings := h.settings()
	cands, promoByListing := []promotion.Candidate(nil), map[uint]uint{}
	if h.adsOn(settings) {
		cands, promoByListing = h.adCandidates(organic)
	}

	offset := 0
	var ads []uint
	if raw := c.Query("cursor"); raw != "" {
		cur, err := promotion.ParseCursor(raw, h.Secret, qkey)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_cursor"})
			return
		}
		offset = cur.Offset
		// The page-one order, minus ads that stopped running meanwhile
		// (hidden, refunded, expired): those leave ads at once.
		for _, id := range cur.Ads {
			if _, ok := promoByListing[id]; ok {
				ads = append(ads, id)
			}
		}
	} else {
		seed := randomSeed()
		ads = promotion.Rotate(cands, func(id uint) uint64 {
			x := uint64(id) ^ seed
			x ^= x >> 33
			x *= 0xff51afd7ed558ccd
			x ^= x >> 33
			return x
		})
	}

	merged := promotion.Merge(organic, ads, h.layout())
	if offset > len(merged) {
		offset = len(merged)
	}
	end := offset + limit
	if end > len(merged) {
		end = len(merged)
	}
	page := merged[offset:end]

	items := make([]feedItem, 0, len(page))
	if len(page) > 0 {
		pageIDs := make([]uint, len(page))
		for i, it := range page {
			pageIDs[i] = it.ListingID
		}
		var listings []models.Listing
		if err := h.DB.Where("id IN ?", pageIDs).Find(&listings).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch listings"})
			return
		}
		byID := map[uint]listingOut{}
		for _, l := range attachListingCounts(h.DB, listings) {
			byID[l.ID] = l
		}
		for _, it := range page {
			l, ok := byID[it.ListingID]
			if !ok {
				continue
			}
			item := feedItem{listingOut: l, Promoted: it.Promoted}
			if it.Promoted {
				pid := promoByListing[it.ListingID]
				item.PromotionID = &pid
			}
			items = append(items, item)
		}
	}

	resp := gin.H{"items": items, "total": len(merged), "next_cursor": nil}
	if end < len(merged) {
		resp["next_cursor"] = promotion.Cursor{Query: qkey, Ads: ads, Offset: end}.Sign(h.Secret)
	}
	c.JSON(http.StatusOK, resp)
}

type promotionEventInput struct {
	PromotionID uint   `json:"promotion_id" binding:"required"`
	Kind        string `json:"kind" binding:"required"`
}

var promotionCountedKinds = map[string]bool{
	models.PromotionEventImpression: true,
	models.PromotionEventClick:      true,
	models.PromotionEventChat:       true,
	models.PromotionEventCall:       true,
	models.PromotionEventWhatsApp:   true,
}

// RecordEvent — POST /api/promotions/events. The app sends an impression
// only once an ad card was actually on screen, and click/chat/call/WhatsApp
// for actions taken from an ad. Counted once per viewer per kind per
// promotion within promotionEventWindow; never for the listing's own
// owner/managers; only while the promotion is running and the listing is
// still advertisable; rate-limited per IP. These are taps, not orders.
func (h *PromotionHandler) RecordEvent(c *gin.Context) {
	var in promotionEventInput
	if err := c.ShouldBindJSON(&in); err != nil || !promotionCountedKinds[in.Kind] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_input"})
		return
	}
	if !h.events.Allow("ip:" + c.ClientIP()) {
		c.JSON(http.StatusTooManyRequests, gin.H{"error": "rate_limited"})
		return
	}
	var promo models.Promotion
	now := h.now()
	if err := h.DB.Where("id = ? AND status = ? AND starts_at <= ? AND ends_at > ?",
		in.PromotionID, models.PromotionActive, now, now).First(&promo).Error; err != nil {
		c.JSON(http.StatusOK, gin.H{"counted": false})
		return
	}
	var listing models.Listing
	if err := h.DB.First(&listing, promo.ListingID).Error; err != nil || ineligibleReason(h.DB, listing) != "" || !h.adsOn(h.settings()) {
		c.JSON(http.StatusOK, gin.H{"counted": false})
		return
	}
	if uid := currentUserID(c); uid != 0 {
		var n int64
		h.DB.Model(&models.ListingManager{}).Where("listing_id = ? AND user_id = ?", listing.ID, uid).Count(&n)
		if n > 0 {
			c.JSON(http.StatusOK, gin.H{"counted": false})
			return
		}
	}

	counted := false
	err := h.DB.Transaction(func(tx *gorm.DB) error {
		viewer := h.viewerHash(c)
		var seen models.PromotionEventSeen
		err := tx.Where("promotion_id = ? AND kind = ? AND viewer_hash = ?", promo.ID, in.Kind, viewer).First(&seen).Error
		switch {
		case err == nil && now.Sub(seen.LastAt) < promotionEventWindow:
			return nil
		case err == nil:
			res := tx.Model(&models.PromotionEventSeen{}).Where("id = ? AND last_at = ?", seen.ID, seen.LastAt).Update("last_at", now)
			if res.Error != nil || res.RowsAffected == 0 {
				return res.Error
			}
		default:
			res := tx.Clauses(clause.OnConflict{DoNothing: true}).Create(&models.PromotionEventSeen{
				PromotionID: promo.ID, Kind: in.Kind, ViewerHash: viewer, LastAt: now,
			})
			if res.Error != nil || res.RowsAffected == 0 {
				return res.Error
			}
		}
		counted = true
		return tx.Clauses(clause.OnConflict{
			Columns:   []clause.Column{{Name: "promotion_id"}, {Name: "kind"}},
			DoUpdates: clause.Assignments(map[string]any{"count": gorm.Expr("promotion_stats.count + 1"), "updated_at": now}),
		}).Create(&models.PromotionStat{PromotionID: promo.ID, Kind: in.Kind, Count: 1, UpdatedAt: now}).Error
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to record"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"counted": counted})
}

// GoogleNotification — POST /api/promotions/webhooks/google?token=…, the
// Pub/Sub push endpoint of Google Play Real-time developer notifications.
// The payload only says "look at this purchase": every state is re-read
// from the Play Developer API before anything changes.
func (h *PromotionHandler) GoogleNotification(c *gin.Context) {
	want := h.Cfg.GooglePlayRTDNToken
	if want == "" || h.Google == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "store_not_configured"})
		return
	}
	if subtle.ConstantTimeCompare([]byte(c.Query("token")), []byte(want)) != 1 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	var envelope struct {
		Message struct {
			Data      string `json:"data"`
			MessageID string `json:"messageId"`
		} `json:"message"`
	}
	if err := c.ShouldBindJSON(&envelope); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_input"})
		return
	}
	data, err := base64.StdEncoding.DecodeString(envelope.Message.Data)
	var n promotion.GoogleNotification
	if err != nil || json.Unmarshal(data, &n) != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_input"})
		return
	}
	if n.PackageName != "" && n.PackageName != h.Cfg.GooglePlayPackageName {
		c.Status(http.StatusNoContent)
		return
	}
	id := envelope.Message.MessageID
	if h.seenNotification(models.PromotionChannelGoogle, id, "rtdn") {
		c.Status(http.StatusNoContent)
		return
	}
	ok := true
	switch {
	case n.VoidedPurchaseNotification != nil:
		// Refunded or charged back: out of ads now.
		h.revoke(h.DB.Where("store_purchase_token = ?", n.VoidedPurchaseNotification.PurchaseToken),
			models.PromotionRefunded, "google_voided")
	case n.OneTimeProductNotification != nil:
		ok = h.googleOneTime(c, n.OneTimeProductNotification.PurchaseToken, n.OneTimeProductNotification.SKU)
	}
	if !ok {
		// Let Pub/Sub redeliver later.
		h.forgetNotification(models.PromotionChannelGoogle, id)
		c.JSON(http.StatusBadGateway, gin.H{"error": "store_unavailable"})
		return
	}
	c.Status(http.StatusNoContent)
}

// googleOneTime handles a purchased/cancelled one-time product: a purchase
// the app never reported (closed mid-way, pending payment completed later)
// is activated here; a cancelled one closes its order.
func (h *PromotionHandler) googleOneTime(c *gin.Context, token, sku string) bool {
	if token == "" || sku == "" {
		return true
	}
	p, err := h.Google.GetPurchase(c.Request.Context(), sku, token)
	if err != nil {
		return false
	}
	var order models.PromotionOrder
	if err := h.DB.Where("token = ? AND channel = ? AND product_id = ?",
		strings.ToLower(p.ObfuscatedExternalAccountID), models.PromotionChannelGoogle, sku).First(&order).Error; err != nil {
		return true // not one of our promotion orders
	}
	if p.PurchaseState == promotion.GooglePurchased {
		status, _ := h.applyGooglePurchase(c.Request.Context(), order, token)
		return status != http.StatusBadGateway
	}
	if p.PurchaseState == promotion.GoogleCanceled {
		h.DB.Model(&models.PromotionOrder{}).Where("id = ? AND status = ?", order.ID, models.PromotionOrderOpen).
			Update("status", models.PromotionOrderCancelled)
		h.revoke(h.DB.Where("store_purchase_token = ?", token), models.PromotionRevoked, "google_cancelled")
	}
	return true
}

// AppleNotification — POST /api/promotions/webhooks/apple (App Store
// Server Notifications V2). Only payloads signed by Apple are accepted.
func (h *PromotionHandler) AppleNotification(c *gin.Context) {
	if h.Apple == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "store_not_configured"})
		return
	}
	var in struct {
		SignedPayload string `json:"signedPayload" binding:"required"`
	}
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_input"})
		return
	}
	n, tx, err := h.Apple.VerifyNotification(in.SignedPayload)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_notification"})
		return
	}
	if h.seenNotification(models.PromotionChannelApple, n.NotificationUUID, n.NotificationType) {
		c.Status(http.StatusOK)
		return
	}
	key := "apple:" + tx.TransactionID
	switch n.NotificationType {
	case "REFUND", "REVOKE":
		h.revoke(h.DB.Where("transaction_key = ?", key), models.PromotionRefunded, "apple_"+strings.ToLower(n.NotificationType))
	case "REFUND_REVERSED":
		h.DB.Model(&models.Promotion{}).Where("transaction_key = ? AND status = ? AND ends_at > ?", key, models.PromotionRefunded, h.now()).
			Updates(map[string]any{"status": models.PromotionActive, "revoked_at": nil, "revoke_reason": ""})
	case "ONE_TIME_CHARGE":
		var order models.PromotionOrder
		if tx.AppAccountToken != "" && h.DB.Where("token = ? AND channel = ?",
			strings.ToLower(tx.AppAccountToken), models.PromotionChannelApple).First(&order).Error == nil {
			h.applyAppleTransaction(order, tx)
		}
	}
	c.Status(http.StatusOK)
}

type settingsInput struct {
	Enabled         bool   `json:"enabled"`
	PriceKZT        uint   `json:"price_kzt"`
	GoogleProductID string `json:"google_product_id"`
	AppleProductID  string `json:"apple_product_id"`
}

func validProductID(s string) bool {
	if len(s) > 150 {
		return false
	}
	for _, r := range s {
		if !(r >= 'a' && r <= 'z' || r >= '0' && r <= '9' || r == '_' || r == '.') {
			return false
		}
	}
	return true
}

func (h *PromotionHandler) settingsResponse(s models.PromotionSettings) gin.H {
	return gin.H{
		"settings":      s,
		"duration_days": models.PromotionDurationDays,
		"layout":        gin.H{"first_position": h.Cfg.PromotionFirstPosition, "every": h.Cfg.PromotionEvery},
		"readiness": gin.H{
			"feature_flag":      h.Cfg.PromotionsEnabled,
			"google_configured": h.Google != nil,
			"google_rtdn_token": h.Cfg.GooglePlayRTDNToken != "",
			"apple_configured":  h.Apple != nil,
			"apple_environment": h.Cfg.AppleEnvironment,
			"web_payment":       false,
		},
	}
}

// AdminSettings — GET /api/admin/promotions/settings.
func (h *PromotionHandler) AdminSettings(c *gin.Context) {
	c.JSON(http.StatusOK, h.settingsResponse(h.settings()))
}

// AdminUpdateSettings — PUT /api/admin/promotions/settings.
func (h *PromotionHandler) AdminUpdateSettings(c *gin.Context) {
	var in settingsInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_input"})
		return
	}
	in.GoogleProductID = strings.TrimSpace(in.GoogleProductID)
	in.AppleProductID = strings.TrimSpace(in.AppleProductID)
	if !validProductID(in.GoogleProductID) || !validProductID(in.AppleProductID) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_product_id"})
		return
	}
	if in.Enabled && in.PriceKZT == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "price_required"})
		return
	}
	uid := currentUserID(c)
	s := models.PromotionSettings{
		ID: 1, Enabled: in.Enabled, PriceKZT: in.PriceKZT,
		GoogleProductID: in.GoogleProductID, AppleProductID: in.AppleProductID, UpdatedBy: &uid,
	}
	if err := h.DB.Save(&s).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save"})
		return
	}
	c.JSON(http.StatusOK, h.settingsResponse(h.settings()))
}

// AdminList — GET /api/admin/promotions: recent promotions for support.
func (h *PromotionHandler) AdminList(c *gin.Context) {
	var list []models.Promotion
	h.DB.Order("id desc").Limit(200).Find(&list)
	names := map[uint]string{}
	if len(list) > 0 {
		ids := make([]uint, len(list))
		for i, p := range list {
			ids[i] = p.ListingID
		}
		var listings []models.Listing
		h.DB.Select("id", "name_ru").Where("id IN ?", ids).Find(&listings)
		for _, l := range listings {
			names[l.ID] = l.NameRu
		}
	}
	outs := h.outs(list)
	rows := make([]gin.H, len(list))
	for i, p := range list {
		rows[i] = gin.H{
			"promotion": outs[i], "listing_id": p.ListingID, "listing_name": names[p.ListingID],
			"user_id": p.UserID, "revoke_reason": p.RevokeReason, "price_kzt": p.PriceKZT,
		}
	}
	c.JSON(http.StatusOK, gin.H{"promotions": rows})
}

// listingRole — the caller's role on the listing set by RequireListingAccess.
func listingRole(c *gin.Context) string {
	v, _ := c.Get(middleware.ContextListingRoleKey)
	s, _ := v.(string)
	return s
}
