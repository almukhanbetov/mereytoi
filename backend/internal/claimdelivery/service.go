// Package claimdelivery is the secondary, best-effort half of claim-link
// delivery — the primary half (booking → pending account → draft event →
// AccountClaim) already exists and is untouched (handlers/onboarding.go).
//
// This stage replaces an earlier, SMS-based iteration entirely — no SMS
// code, config, or env var remains anywhere in this codebase. The channel
// priority is now:
//
//	WhatsApp (if a real Meta Cloud API credential is configured)
//	  -> Telegram (if a bot token is configured AND this specific user has
//	     linked their own chat — see models.TelegramLinkToken)
//	    -> no external delivery at all (the in-page "Открыть мой той"
//	       button, which never depends on any of this, is always there)
//
// Shape, top to bottom, mirroring internal/mail:
//
//	handlers/onboarding.go (mintClaim call sites) / auth_handler.go's
//	ClaimResend
//	  -> claimdelivery.Service (channel selection, rate limiting, retry,
//	     status bookkeeping on the AccountClaim row)
//	    -> whatsapp.Sender / telegram.Sender (provider-agnostic transport)
package claimdelivery

import (
	"context"
	"errors"
	"log"
	"net"
	"time"

	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/config"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
	"github.com/almukhanbetov/mereytoi/backend/internal/telegram"
	"github.com/almukhanbetov/mereytoi/backend/internal/whatsapp"
)

const (
	// sendTimeout bounds one HTTP attempt, same tradeoff internal/mail's
	// own deliverTimeout already documents.
	sendTimeout = 8 * time.Second

	// cooldown / maxPerHour — brief section 11's abuse guard, unchanged
	// from the SMS-era pipeline: the same account must not get flooded by
	// repeated booking clicks or resend requests. Keyed by UserID.
	cooldown   = 90 * time.Second
	maxPerHour = 3

	// retryAttempts/retryBaseDelay — runs synchronously inside the
	// booking/resend request (like internal/mail's own send already
	// does), so the backoff is deliberately short. Only transient
	// failures (timeout, network error, 5xx) retry; permanent ones (4xx)
	// don't.
	retryAttempts  = 2
	retryBaseDelay = 300 * time.Millisecond
)

// Channel names — also what's persisted in AccountClaim.DeliveryChannel.
const (
	ChannelWhatsApp = "whatsapp"
	ChannelTelegram = "telegram"
)

// Service is the one thing onboarding.go and ClaimResend depend on — never
// whatsapp.Sender/telegram.Sender directly. Constructed once in
// routes.Register from config.Config, mirroring mail.Service.
type Service struct {
	whatsapp whatsapp.Sender // nil means "WhatsApp not configured" — never a LogSender standing in as "available"
	telegram telegram.Sender // nil means "Telegram not configured" at all (independent of any given user's own linked state)
	enabled  bool
	primary  string // config.Config.ClaimDeliveryPrimary — the default order when a user has no personal preference

	frontendURL string
}

// NewService builds the real, config-driven Service. WhatsApp is only
// ever non-nil when both WHATSAPP_ACCESS_TOKEN and
// WHATSAPP_PHONE_NUMBER_ID are set — an empty credential means "channel
// unavailable" (pickChannel falls through), not "attempt anyway". Same for
// Telegram and TELEGRAM_BOT_TOKEN.
func NewService(cfg config.Config) *Service {
	var wa whatsapp.Sender
	if cfg.WhatsAppAccessToken != "" && cfg.WhatsAppPhoneNumberID != "" {
		wa = &whatsapp.MetaCloudSender{
			BaseURL:  cfg.WhatsAppBaseURL,
			Token:    cfg.WhatsAppAccessToken,
			PhoneID:  cfg.WhatsAppPhoneNumberID,
			Template: cfg.WhatsAppTemplateName,
			Language: cfg.WhatsAppTemplateLanguage,
		}
	}

	var tg telegram.Sender
	if cfg.TelegramBotToken != "" {
		tg = &telegram.BotSender{BaseURL: cfg.TelegramBaseURL, Token: cfg.TelegramBotToken}
	}

	return NewServiceWithSenders(wa, tg, cfg)
}

// NewServiceWithSenders builds a Service around caller-supplied senders.
// Production never calls this directly; tests use it to point a real
// MetaCloudSender/BotSender at a local httptest.Server (via their BaseURL
// field) instead of the real graph.facebook.com/api.telegram.org, or to
// pass nil for "this channel isn't configured".
func NewServiceWithSenders(wa whatsapp.Sender, tg telegram.Sender, cfg config.Config) *Service {
	return &Service{
		whatsapp:    wa,
		telegram:    tg,
		enabled:     cfg.ClaimDeliveryEnabled,
		primary:     cfg.ClaimDeliveryPrimary,
		frontendURL: cfg.FrontendURL,
	}
}

// Deliver attempts to send user's claim link over whichever messenger
// channel is actually usable for them right now (see pickChannel). Returns
// the status to put straight into onboardingResult.DeliveryStatus: "" (not
// attempted at all — CLAIM_DELIVERY_ENABLED=false, or no channel is usable
// for this user at all), "sent", "failed", or "skipped" (rate-limited).
//
// Never fails the caller's booking — every outcome here is recorded on the
// claim row and returned as a plain string, never an error.
func (s *Service) Deliver(db *gorm.DB, claim *models.AccountClaim, user *models.User) string {
	if !s.enabled {
		return ""
	}
	channel := s.pickChannel(user)
	if channel == "" {
		// Brief section 6's "else: no external delivery" — genuinely
		// nothing usable (no WhatsApp credential, and either no Telegram
		// bot token or this user hasn't linked one). Not a failure; the
		// in-page button remains the access path.
		return ""
	}
	if allowed, reason := s.checkRate(db, claim.UserID); !allowed {
		log.Printf("[claim-delivery] skipped user #%d: %s", claim.UserID, reason)
		s.markSkipped(db, claim, channel)
		return "skipped"
	}

	delay := retryBaseDelay
	status := "failed"
	for attempt := 0; attempt <= retryAttempts; attempt++ {
		var transient bool
		status, transient = s.attempt(db, claim, user, channel)
		if status == "sent" || !transient {
			break
		}
		if attempt < retryAttempts {
			time.Sleep(delay)
			delay *= 3
		}
	}
	return status
}

// pickChannel implements brief sections 6 and 7: a user's own
// PreferredDeliveryChannel (if set to a recognized value) is tried first,
// otherwise cfg.ClaimDeliveryPrimary's order is used; either way, the
// other channel is tried as fallback before giving up. Telegram is only
// ever "available" for a specific user who has actually linked their chat
// — a freshly-created pending user (who has never logged in, let alone
// visited a Telegram-linking flow that itself requires an authenticated
// session) can never have this set, so their first delivery attempt can
// only ever go out over WhatsApp or not at all.
func (s *Service) pickChannel(user *models.User) string {
	waAvailable := s.whatsapp != nil
	tgAvailable := s.telegram != nil && user.TelegramChatID != ""

	order := []string{s.primary, other(s.primary)}
	if user.PreferredDeliveryChannel == ChannelWhatsApp || user.PreferredDeliveryChannel == ChannelTelegram {
		order = []string{user.PreferredDeliveryChannel, other(user.PreferredDeliveryChannel)}
	}

	for _, ch := range order {
		if ch == ChannelWhatsApp && waAvailable {
			return ChannelWhatsApp
		}
		if ch == ChannelTelegram && tgAvailable {
			return ChannelTelegram
		}
	}
	return ""
}

func other(channel string) string {
	if channel == ChannelTelegram {
		return ChannelWhatsApp
	}
	return ChannelTelegram
}

// attempt performs exactly one send over channel and persists its outcome.
// transient tells the caller whether retrying again has any chance of a
// different result.
func (s *Service) attempt(db *gorm.DB, claim *models.AccountClaim, user *models.User, channel string) (status string, transient bool) {
	now := time.Now()
	claimURL := s.frontendURL + "/claim/" + claim.Token
	text := buildMessage(claimURL)

	ctx, cancel := context.WithTimeout(context.Background(), sendTimeout)
	defer cancel()

	var err error
	switch channel {
	case ChannelWhatsApp:
		err = s.whatsapp.Send(ctx, whatsapp.Message{To: user.PhoneNormalized, Body: text, TemplateParam: claimURL})
	case ChannelTelegram:
		err = s.telegram.Send(ctx, user.TelegramChatID, text)
	}

	// Set on the in-memory struct too (not just the DB row) so
	// onboarding.go's attemptDelivery can read claim.DeliveryChannel
	// straight off the same pointer it already has, no reload needed.
	claim.DeliveryChannel = channel
	claim.DeliveryAttemptedAt = &now

	updates := map[string]any{
		"delivery_channel":      channel,
		"delivery_attempted_at": now,
	}
	if err == nil {
		claim.DeliveryStatus = "sent"
		claim.DeliverySentAt = &now
		updates["delivery_status"] = "sent"
		updates["delivery_sent_at"] = now
		db.Model(claim).Updates(updates)
		log.Printf("[claim-delivery] sent user #%d via %s", claim.UserID, channel)
		return "sent", false
	}

	class, transient := classifyError(err)
	claim.DeliveryStatus = "failed"
	claim.DeliveryError = class
	updates["delivery_status"] = "failed"
	updates["delivery_error"] = class
	db.Model(claim).Updates(updates)
	log.Printf("[claim-delivery] failed user #%d via %s: %s", claim.UserID, channel, class)
	return "failed", transient
}

func (s *Service) markSkipped(db *gorm.DB, claim *models.AccountClaim, channel string) {
	db.Model(claim).Updates(map[string]any{
		"delivery_channel":      channel,
		"delivery_status":       "skipped",
		"delivery_attempted_at": time.Now(),
	})
}

// checkRate enforces brief section 11 — cooldown between consecutive sends
// to the same account, and a hard cap per rolling hour. Scoped to UserID,
// across all of that user's AccountClaim rows (a fresh booking or a resend
// both mint a new row, so the limit has to look across rows).
func (s *Service) checkRate(db *gorm.DB, userID uint) (bool, string) {
	var last models.AccountClaim
	err := db.Where("user_id = ? AND delivery_attempted_at IS NOT NULL", userID).
		Order("delivery_attempted_at DESC").First(&last).Error
	if err == nil && last.DeliveryAttemptedAt != nil && time.Since(*last.DeliveryAttemptedAt) < cooldown {
		return false, "cooldown"
	}

	var count int64
	db.Model(&models.AccountClaim{}).
		Where("user_id = ? AND delivery_attempted_at > ?", userID, time.Now().Add(-time.Hour)).
		Count(&count)
	if count >= maxPerHour {
		return false, "hourly limit"
	}
	return true, ""
}

// classifyError never calls err.Error() — for a transport-level failure
// that's a *url.Error, whose Error() string embeds the full request URL
// (for WhatsApp, the claim link baked into a GET-style query would be one
// risk; for Telegram, the bot token is literally part of the URL path).
// Only a short, fixed classification is ever persisted or logged (brief
// section 11 — "provider logs не содержат полный token").
func classifyError(err error) (class string, transient bool) {
	var waErr *whatsapp.StatusError
	if errors.As(err, &waErr) {
		if waErr.Code >= 500 {
			return "provider_5xx", true
		}
		return "provider_4xx", false
	}
	var tgErr *telegram.StatusError
	if errors.As(err, &tgErr) {
		if tgErr.Code >= 500 {
			return "provider_5xx", true
		}
		return "provider_4xx", false
	}
	var netErr net.Error
	if errors.As(err, &netErr) {
		if netErr.Timeout() {
			return "timeout", true
		}
		return "network_error", true
	}
	return "unknown_error", true
}

// buildMessage is brief section 3's copy — used verbatim for both
// channels. WhatsApp sends it either as the plain-text body (dev/session
// messages) or as the {{1}} template parameter's value on its own,
// depending on whether MetaCloudSender.Template is set — see that
// package's own doc comment on why a production deployment needs an
// approved template with this same copy on Meta's side.
func buildMessage(claimURL string) string {
	return "MEREYTOI: для вас подготовлено пространство «Мой той».\n\n" +
		"Здесь можно вместе с близкими:\n" +
		"• выбирать услуги\n" +
		"• обсуждать варианты\n" +
		"• сравнивать цены\n" +
		"• контролировать бюджет\n\n" +
		"Открыть:\n" + claimURL
}
