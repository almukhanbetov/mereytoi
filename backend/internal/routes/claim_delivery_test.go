package routes_test

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/config"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
	"github.com/almukhanbetov/mereytoi/backend/internal/routes"
)

// Claim-link delivery over messengers (internal/claimdelivery +
// internal/whatsapp + internal/telegram), replacing this pipeline's
// earlier SMS-based iteration entirely. These tests point
// config.Config.WhatsAppBaseURL/TelegramBaseURL at local httptest.Servers
// standing in for graph.facebook.com/api.telegram.org, so the real
// MetaCloudSender/BotSender code path (JSON payload shape, status-code
// handling) is exercised end to end.

// fakeProvider is a local stand-in "messaging API": records every request
// body it receives and returns whatever status code the test configured.
type fakeProvider struct {
	mu        sync.Mutex
	bodies    []string
	statusSeq []int
}

func newFakeProvider(statusSeq ...int) (*httptest.Server, *fakeProvider) {
	fp := &fakeProvider{statusSeq: statusSeq}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		fp.mu.Lock()
		fp.bodies = append(fp.bodies, string(b))
		idx := len(fp.bodies) - 1
		fp.mu.Unlock()

		status := http.StatusOK
		if len(fp.statusSeq) > 0 {
			if idx < len(fp.statusSeq) {
				status = fp.statusSeq[idx]
			} else {
				status = fp.statusSeq[len(fp.statusSeq)-1]
			}
		}
		w.WriteHeader(status)
		w.Write([]byte(`{"messages":[{"id":"stub"}]}`))
	}))
	return srv, fp
}

func (f *fakeProvider) count() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.bodies)
}

func (f *fakeProvider) last() string {
	f.mu.Lock()
	defer f.mu.Unlock()
	if len(f.bodies) == 0 {
		return ""
	}
	return f.bodies[len(f.bodies)-1]
}

func setupMessengerTestServer(t *testing.T, override func(*config.Config)) (*httptest.Server, *gorm.DB) {
	t.Helper()
	gin.SetMode(gin.TestMode)

	db, err := gorm.Open(sqlite.Open("file::memory:?cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatalf("failed to open in-memory db: %v", err)
	}
	if err := db.AutoMigrate(
		&models.User{}, &models.Category{}, &models.Listing{}, &models.Booking{}, &models.Comment{}, &models.Client{}, &models.SiteStatistics{},
		&models.Event{}, &models.EventMember{}, &models.EventInvitation{},
		&models.EventCandidate{}, &models.EventVote{}, &models.EventComment{},
		&models.EventActivity{}, &models.EventTask{},
		&models.EventRequest{}, &models.EventRequestRevision{},
		&models.Notification{},
		&models.ManagerConversation{}, &models.ManagerMessage{},
		&models.AccountClaim{}, &models.TelegramLinkToken{},
		&models.ListingHall{}, &models.ListingMenu{}, &models.ListingMenuSection{}, &models.ListingMenuItem{}, &models.ListingMenuExtra{},
	); err != nil {
		t.Fatalf("failed to migrate: %v", err)
	}

	r := gin.New()
	r.Use(cors.Default())
	cfg := config.Config{
		JWTSecret:              "test-secret-only",
		FrontendURL:            "https://mereytoi.kz",
		AutoAccountFromBooking: true,
		ClaimDeliveryEnabled:   true,
		ClaimDeliveryPrimary:   "whatsapp",
	}
	if override != nil {
		override(&cfg)
	}
	routes.Register(r, db, cfg)

	srv := httptest.NewServer(r)
	t.Cleanup(srv.Close)
	return srv, db
}

// TestClaimDeliverySentViaWhatsApp — brief section 14 Test A.
func TestClaimDeliverySentViaWhatsApp(t *testing.T) {
	waSrv, wa := newFakeProvider(http.StatusOK)
	defer waSrv.Close()
	srv, db := setupMessengerTestServer(t, func(cfg *config.Config) {
		cfg.WhatsAppAccessToken = "test-token"
		cfg.WhatsAppPhoneNumberID = "1234567890"
		cfg.WhatsAppBaseURL = waSrv.URL
	})
	c := apiClient{t: t, base: srv.URL}

	status, out := c.do("POST", "/api/bookings", map[string]any{
		"name": "Айгерим", "phone": "+7 707 111 22 33", "items": []any{},
	})
	if status != http.StatusCreated {
		t.Fatalf("booking create: %d %v", status, out)
	}
	onboarding := out["onboarding"].(map[string]any)
	if onboarding["delivery_status"] != "sent" || onboarding["delivery_channel"] != "whatsapp" {
		t.Fatalf("expected sent via whatsapp, got %v", onboarding)
	}

	if wa.count() != 1 {
		t.Fatalf("expected exactly one WhatsApp API call, got %d", wa.count())
	}
	body := wa.last()
	if !strings.Contains(body, `"messaging_product":"whatsapp"`) {
		t.Fatalf("expected a real Cloud API payload shape, got %s", body)
	}
	if !strings.Contains(body, "77071112233") {
		t.Fatalf("expected the normalized recipient phone in the payload, got %s", body)
	}
	claimToken, _ := onboarding["claim_token"].(string)
	if claimToken == "" || !strings.Contains(body, claimToken) {
		t.Fatalf("expected the real claim link (with token %q) in the message body, got %s", claimToken, body)
	}

	var claim models.AccountClaim
	if err := db.Where("token = ?", claimToken).First(&claim).Error; err != nil {
		t.Fatalf("claim row should exist: %v", err)
	}
	if claim.DeliveryChannel != "whatsapp" || claim.DeliveryStatus != "sent" || claim.DeliverySentAt == nil {
		t.Fatalf("expected the claim row to record a sent WhatsApp delivery, got channel=%q status=%q sentAt=%v",
			claim.DeliveryChannel, claim.DeliveryStatus, claim.DeliverySentAt)
	}
}

// TestClaimDeliveryFallsBackToTelegramWhenLinked — brief section 14 Test B.
// A brand-new pending user can never have Telegram linked on their very
// first send (linking itself requires an authenticated session, which
// doesn't exist until after a first claim) — so this test walks the full
// realistic path: book -> claim -> link Telegram from the resulting
// session -> book again from the same still-pending phone, which should
// now deliver over Telegram since WhatsApp is deliberately left
// unconfigured throughout.
func TestClaimDeliveryFallsBackToTelegramWhenLinked(t *testing.T) {
	tgSrv, tg := newFakeProvider(http.StatusOK)
	defer tgSrv.Close()
	srv, _ := setupMessengerTestServer(t, func(cfg *config.Config) {
		// WhatsApp intentionally left unconfigured.
		cfg.TelegramBotToken = "test-bot-token"
		cfg.TelegramBotUsername = "MereytoiBot"
		cfg.TelegramBaseURL = tgSrv.URL
	})
	c := apiClient{t: t, base: srv.URL}

	_, out1 := c.do("POST", "/api/bookings", map[string]any{"name": "Ерлан", "phone": "+7 707 444 55 66", "items": []any{}})
	onboarding1 := out1["onboarding"].(map[string]any)
	if _, has := onboarding1["delivery_status"]; has {
		t.Fatalf("first send with neither channel usable yet should have no delivery_status, got %v", onboarding1)
	}
	claimToken1, _ := onboarding1["claim_token"].(string)

	_, claimOut := c.do("POST", "/api/auth/claim/"+claimToken1, nil)
	sessionToken, _ := claimOut["token"].(string)
	if sessionToken == "" {
		t.Fatalf("claim should return a usable session token, got %v", claimOut)
	}
	authed := apiClient{t: t, base: srv.URL, token: sessionToken}

	linkStatus, linkOut := authed.do("POST", "/api/users/me/telegram/link-token", nil)
	if linkStatus != http.StatusOK || linkOut["configured"] != true {
		t.Fatalf("mint-link-token: %d %v", linkStatus, linkOut)
	}
	linkURL, _ := linkOut["link_url"].(string)
	if !strings.HasPrefix(linkURL, "https://t.me/MereytoiBot?start=") {
		t.Fatalf("unexpected link_url shape: %q", linkURL)
	}
	linkToken := linkURL[strings.LastIndex(linkURL, "=")+1:]

	webhookStatus, _ := c.do("POST", "/api/telegram/webhook", map[string]any{
		"message": map[string]any{"chat": map[string]any{"id": 555111}, "text": "/start " + linkToken},
	})
	if webhookStatus != http.StatusOK {
		t.Fatalf("telegram webhook: %d", webhookStatus)
	}

	meStatus, meOut := authed.do("GET", "/api/auth/me", nil)
	if meStatus != http.StatusOK || meOut["telegram_linked"] != true {
		t.Fatalf("expected telegram_linked=true after the webhook links it, got %d %v", meStatus, meOut)
	}

	_, out2 := c.do("POST", "/api/bookings", map[string]any{"name": "Ерлан", "phone": "8 707 4445566", "items": []any{}})
	onboarding2 := out2["onboarding"].(map[string]any)
	if onboarding2["delivery_status"] != "sent" || onboarding2["delivery_channel"] != "telegram" {
		t.Fatalf("expected this second send to go out over telegram, got %v", onboarding2)
	}
	if tg.count() < 1 {
		t.Fatalf("expected at least one Telegram API call, got %d", tg.count())
	}
	if !strings.Contains(tg.last(), "555111") {
		t.Fatalf("expected the linked chat_id in the telegram payload, got %s", tg.last())
	}
}

// TestClaimDeliveryNoExternalChannelStillSucceeds — brief section 14 Test C
// and section 13's core principle: booking/account/workspace/claim access
// never depends on either messenger.
func TestClaimDeliveryNoExternalChannelStillSucceeds(t *testing.T) {
	srv, _ := setupMessengerTestServer(t, nil) // neither WhatsApp nor Telegram configured at all
	c := apiClient{t: t, base: srv.URL}

	status, out := c.do("POST", "/api/bookings", map[string]any{
		"name": "Данияр", "phone": "+7 707 777 88 99", "items": []any{},
	})
	if status != http.StatusCreated {
		t.Fatalf("booking must still succeed with no messenger configured, got %d %v", status, out)
	}
	onboarding := out["onboarding"].(map[string]any)
	if _, has := onboarding["delivery_status"]; has {
		t.Fatalf("no channel configured at all must produce no delivery_status field, got %v", onboarding)
	}
	claimToken, _ := onboarding["claim_token"].(string)
	if claimToken == "" {
		t.Fatalf("the in-page claim CTA must still work as the fallback, got %v", onboarding)
	}
	status, claimOut := c.do("POST", "/api/auth/claim/"+claimToken, nil)
	if status != http.StatusOK {
		t.Fatalf("fallback claim button must still work end to end: %d %v", status, claimOut)
	}
}

// TestClaimDeliveryNeverAttemptedForActiveAccount — brief section 14 Test D.
func TestClaimDeliveryNeverAttemptedForActiveAccount(t *testing.T) {
	waSrv, wa := newFakeProvider(http.StatusOK)
	defer waSrv.Close()
	srv, db := setupMessengerTestServer(t, func(cfg *config.Config) {
		cfg.WhatsAppAccessToken = "t"
		cfg.WhatsAppPhoneNumberID = "1"
		cfg.WhatsAppBaseURL = waSrv.URL
	})
	c := apiClient{t: t, base: srv.URL}

	registerUser(t, srv.URL, "Асем", "claim-delivery-msg-active@example.com")
	if err := db.Model(&models.User{}).Where("email = ?", "claim-delivery-msg-active@example.com").Update("phone_normalized", "+77079990000").Error; err != nil {
		t.Fatalf("seed phone_normalized: %v", err)
	}

	status, out := c.do("POST", "/api/bookings", map[string]any{
		"name": "Асем", "phone": "+7 707 999 00 00", "items": []any{},
	})
	if status != http.StatusCreated {
		t.Fatalf("booking create: %d %v", status, out)
	}
	onboarding := out["onboarding"].(map[string]any)
	if _, has := onboarding["delivery_status"]; has {
		t.Fatalf("an existing active account must never get a delivery_status field at all, got %v", onboarding)
	}
	if wa.count() != 0 {
		t.Fatalf("must never call the WhatsApp API for an existing active account, got %d calls", wa.count())
	}
}

// TestClaimDeliveryResendBlockedWithinCooldown — brief section 14 Test E.
func TestClaimDeliveryResendBlockedWithinCooldown(t *testing.T) {
	waSrv, wa := newFakeProvider(http.StatusOK)
	defer waSrv.Close()
	srv, _ := setupMessengerTestServer(t, func(cfg *config.Config) {
		cfg.WhatsAppAccessToken = "t"
		cfg.WhatsAppPhoneNumberID = "1"
		cfg.WhatsAppBaseURL = waSrv.URL
	})
	c := apiClient{t: t, base: srv.URL}

	c.do("POST", "/api/bookings", map[string]any{"name": "Гуля", "phone": "+7 707 222 33 11", "items": []any{}})
	before := wa.count()

	status, _ := c.do("POST", "/api/auth/claim/resend", map[string]any{"phone": "+7 707 222 33 11"})
	if status != http.StatusOK {
		t.Fatalf("resend should still 200 even when rate-limited, got %d", status)
	}
	if wa.count() != before {
		t.Fatalf("a resend inside the cooldown window must not trigger an additional real send, before=%d after=%d", before, wa.count())
	}
}

// TestClaimDeliveryResendAllowedAfterCooldown — brief section 14 Test F.
// Rather than sleeping the real 90s cooldown in an automated test, this
// back-dates the one signal claimdelivery.Service.checkRate actually
// reads (AccountClaim.DeliveryAttemptedAt) — a deterministic way to
// simulate "the cooldown has elapsed" without a slow test.
func TestClaimDeliveryResendAllowedAfterCooldown(t *testing.T) {
	waSrv, wa := newFakeProvider(http.StatusOK)
	defer waSrv.Close()
	srv, db := setupMessengerTestServer(t, func(cfg *config.Config) {
		cfg.WhatsAppAccessToken = "t"
		cfg.WhatsAppPhoneNumberID = "1"
		cfg.WhatsAppBaseURL = waSrv.URL
	})
	c := apiClient{t: t, base: srv.URL}

	_, out := c.do("POST", "/api/bookings", map[string]any{"name": "Марат2", "phone": "+7 707 333 22 11", "items": []any{}})
	userID := uint(out["booking"].(map[string]any)["user_id"].(float64))
	before := wa.count()

	past := time.Now().Add(-2 * time.Minute)
	if err := db.Model(&models.AccountClaim{}).Where("user_id = ?", userID).Update("delivery_attempted_at", past).Error; err != nil {
		t.Fatalf("seed: %v", err)
	}

	status, _ := c.do("POST", "/api/auth/claim/resend", map[string]any{"phone": "+7 707 333 22 11"})
	if status != http.StatusOK {
		t.Fatalf("resend: %d", status)
	}
	if wa.count() != before+1 {
		t.Fatalf("a resend after the cooldown window should trigger exactly one more send, before=%d after=%d", before, wa.count())
	}
}

// TestTelegramLinkTokenCannotBeReused — brief section 14 Test G / section
// 11's "Telegram linking token отдельный" + single-use requirement.
func TestTelegramLinkTokenCannotBeReused(t *testing.T) {
	tgSrv, _ := newFakeProvider(http.StatusOK)
	defer tgSrv.Close()
	srv, db := setupMessengerTestServer(t, func(cfg *config.Config) {
		cfg.TelegramBotToken = "test-bot-token"
		cfg.TelegramBotUsername = "MereytoiBot"
		cfg.TelegramBaseURL = tgSrv.URL
	})
	c := apiClient{t: t, base: srv.URL}

	_, out := c.do("POST", "/api/bookings", map[string]any{"name": "Ботагоз", "phone": "+7 707 555 44 33", "items": []any{}})
	claimToken, _ := out["onboarding"].(map[string]any)["claim_token"].(string)
	_, claimOut := c.do("POST", "/api/auth/claim/"+claimToken, nil)
	sessionToken, _ := claimOut["token"].(string)
	userID := uint(claimOut["user"].(map[string]any)["id"].(float64))
	authed := apiClient{t: t, base: srv.URL, token: sessionToken}

	_, linkOut := authed.do("POST", "/api/users/me/telegram/link-token", nil)
	linkURL, _ := linkOut["link_url"].(string)
	linkToken := linkURL[strings.LastIndex(linkURL, "=")+1:]

	c.do("POST", "/api/telegram/webhook", map[string]any{
		"message": map[string]any{"chat": map[string]any{"id": 111}, "text": "/start " + linkToken},
	})
	var user models.User
	db.First(&user, userID)
	if user.TelegramChatID != "111" {
		t.Fatalf("expected chat 111 to be linked, got %q", user.TelegramChatID)
	}

	// Reuse with a *different* chat_id must be rejected — the already-used
	// token must not re-link (and definitely must not silently move the
	// link to a different, unrelated chat).
	c.do("POST", "/api/telegram/webhook", map[string]any{
		"message": map[string]any{"chat": map[string]any{"id": 222}, "text": "/start " + linkToken},
	})
	db.First(&user, userID)
	if user.TelegramChatID != "111" {
		t.Fatalf("a reused telegram link token must not re-link to a different chat, got %q", user.TelegramChatID)
	}
}

// Test H (brief section 14 — "claim still one-time") is already covered by
// TestOnboardingCreatesPendingAccountAndWorkspace's own single-use
// assertion (onboarding_test.go) — unaffected by this stage, since
// Claim()'s single-use logic was never touched here.
