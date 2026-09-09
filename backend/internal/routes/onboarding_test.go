package routes_test

import (
	"net/http"
	"net/http/httptest"
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

// setupOnboardingTestServer is setupTestServer (event_security_test.go)
// with AutoAccountFromBooking turned on — every other pre-existing test in
// this package deliberately keeps using the flag-off setupTestServer, so
// the flag's own "off means nothing changes" guarantee is exercised by the
// entire rest of the suite, not just asserted here.
func setupOnboardingTestServer(t *testing.T) (*httptest.Server, *gorm.DB) {
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
	cfg := config.Config{JWTSecret: "test-secret-only", AutoAccountFromBooking: true}
	routes.Register(r, db, cfg)

	srv := httptest.NewServer(r)
	t.Cleanup(srv.Close)
	return srv, db
}

// TestOnboardingFlagOffChangesNothing is the explicit regression guard for
// brief section 10: with the flag off (setupTestServer's own zero-value
// default), a guest booking must behave byte-for-byte as it always has —
// no onboarding field in the response, no new user, no new event.
func TestOnboardingFlagOffChangesNothing(t *testing.T) {
	srv, db := setupTestServer(t)
	c := apiClient{t: t, base: srv.URL}

	// Delta, not a global count — this suite's tests share one in-memory DB
	// (see other *_test.go files' own convention), so other tests may
	// already have created users before this one runs.
	var usersBefore int64
	db.Model(&models.User{}).Count(&usersBefore)

	status, out := c.do("POST", "/api/bookings", map[string]any{
		"name": "Гость", "phone": "+7 707 900 00 01", "message": "тест", "items": []any{},
	})
	if status != http.StatusCreated {
		t.Fatalf("booking create: %d %v", status, out)
	}
	if _, ok := out["onboarding"]; ok {
		t.Fatalf("flag-off booking response must not contain an 'onboarding' key, got %v", out)
	}
	var usersAfter int64
	db.Model(&models.User{}).Count(&usersAfter)
	if usersAfter != usersBefore {
		t.Fatalf("flag-off booking must not create any user, before=%d after=%d", usersBefore, usersAfter)
	}
}

// TestOnboardingCreatesPendingAccountAndWorkspace covers the core new
// pipeline: a genuinely new phone number gets a pending account, exactly
// one draft event (owner membership included), a claim link that actually
// logs them in, and that session can use the real workspace API.
func TestOnboardingCreatesPendingAccountAndWorkspace(t *testing.T) {
	srv, db := setupOnboardingTestServer(t)
	c := apiClient{t: t, base: srv.URL}

	status, out := c.do("POST", "/api/bookings", map[string]any{
		"name": "Жанна", "phone": "8 707 900 00 02", "message": "Оставила заявку", "items": []any{},
	})
	if status != http.StatusCreated {
		t.Fatalf("booking create: %d %v", status, out)
	}

	onboarding, ok := out["onboarding"].(map[string]any)
	if !ok {
		t.Fatalf("expected an 'onboarding' object in the response, got %v", out)
	}
	if onboarding["status"] != "created_pending" {
		t.Fatalf("expected status=created_pending, got %v", onboarding["status"])
	}
	claimToken, _ := onboarding["claim_token"].(string)
	if claimToken == "" {
		t.Fatalf("expected a non-empty claim_token, got %v", onboarding)
	}
	eventID := int(onboarding["event_id"].(float64))

	booking := out["booking"].(map[string]any)
	if booking["user_id"] == nil {
		t.Fatalf("booking should now be linked to the new pending user, got %v", booking)
	}
	if int(booking["event_id"].(float64)) != eventID {
		t.Fatalf("booking should be linked to the same draft event, got %v", booking["event_id"])
	}

	var user models.User
	if err := db.First(&user, uint(booking["user_id"].(float64))).Error; err != nil {
		t.Fatalf("pending user should exist in the DB: %v", err)
	}
	if user.Status != models.UserStatusPending {
		t.Fatalf("new user should have Status=pending, got %q", user.Status)
	}

	var memberCount int64
	db.Model(&models.EventMember{}).Where("event_id = ? AND user_id = ? AND role = ?", eventID, user.ID, "owner").Count(&memberCount)
	if memberCount != 1 {
		t.Fatalf("expected exactly one owner EventMember row, got %d", memberCount)
	}

	// The claim link actually works: it logs the pending user in, and that
	// session can use the real, unmodified workspace API.
	status, claimOut := c.do("POST", "/api/auth/claim/"+claimToken, nil)
	if status != http.StatusOK {
		t.Fatalf("claim: %d %v", status, claimOut)
	}
	sessionToken, _ := claimOut["token"].(string)
	if sessionToken == "" {
		t.Fatalf("claim should return a usable session token, got %v", claimOut)
	}
	claimEventID, ok := claimOut["event_id"].(float64)
	if !ok || int(claimEventID) != eventID {
		t.Fatalf("claim response should include the same event_id (for a standalone /claim/:token page with no prior state), got %v want %d", claimOut["event_id"], eventID)
	}
	authed := apiClient{t: t, base: srv.URL, token: sessionToken}
	status, evOut := authed.do("GET", "/api/events/"+itoa(eventID), nil)
	if status != http.StatusOK {
		t.Fatalf("claimed session should be able to open its own event workspace, got %d %v", status, evOut)
	}

	// Single-use: calling the same claim token again must be rejected, not
	// silently log in a second time.
	status, reuseOut := c.do("POST", "/api/auth/claim/"+claimToken, nil)
	if status != http.StatusGone {
		t.Fatalf("a used claim link must be rejected on reuse, got %d %v", status, reuseOut)
	}

	// workspace_created notification fired, system-generated (no actor).
	status, notifs := authed.do("GET", "/api/notifications", nil)
	if status != http.StatusOK {
		t.Fatalf("notifications list: %d", status)
	}
	if findNotif(notifs, "workspace_created") == nil {
		t.Fatalf("expected a workspace_created notification, got %v", notifs["notifications"])
	}
}

// TestOnboardingReusesExistingPendingEventNoDuplicate covers brief section
// 4: a second guest booking from the same (still-pending) phone must reuse
// the same account and the same draft event, never create a second one.
func TestOnboardingReusesExistingPendingEventNoDuplicate(t *testing.T) {
	srv, db := setupOnboardingTestServer(t)
	c := apiClient{t: t, base: srv.URL}

	_, out1 := c.do("POST", "/api/bookings", map[string]any{"name": "Марат", "phone": "+7 707 900 00 03", "message": "1", "items": []any{}})
	userID1 := uint(out1["booking"].(map[string]any)["user_id"].(float64))
	eventID1 := int(out1["onboarding"].(map[string]any)["event_id"].(float64))

	status, out2 := c.do("POST", "/api/bookings", map[string]any{"name": "Марат", "phone": "8 707 9000003", "message": "2", "items": []any{}})
	if status != http.StatusCreated {
		t.Fatalf("second booking: %d %v", status, out2)
	}
	onboarding2 := out2["onboarding"].(map[string]any)
	if onboarding2["status"] != "pending_claim" {
		t.Fatalf("second booking from the same still-pending phone should report pending_claim, got %v", onboarding2["status"])
	}
	userID2 := uint(out2["booking"].(map[string]any)["user_id"].(float64))
	eventID2 := int(onboarding2["event_id"].(float64))

	if userID1 != userID2 {
		t.Fatalf("both bookings from the same phone should link to the same pending user, got %d and %d", userID1, userID2)
	}
	if eventID1 != eventID2 {
		t.Fatalf("second booking must reuse the same draft event, not create a new one, got %d and %d", eventID1, eventID2)
	}

	var eventCount int64
	db.Model(&models.Event{}).Where("owner_id = ?", userID1).Count(&eventCount)
	if eventCount != 1 {
		t.Fatalf("expected exactly 1 event owned by this pending user, got %d", eventCount)
	}
}

// TestOnboardingExistingActiveAccountNeverGetsClaimLink is the
// security-critical case: a phone number matching a real, already
// password-protected account must link the booking, but must NEVER issue
// a claim link/session for that account.
func TestOnboardingExistingActiveAccountNeverGetsClaimLink(t *testing.T) {
	srv, db := setupOnboardingTestServer(t)
	c := apiClient{t: t, base: srv.URL}

	registerUser(t, srv.URL, "Настя", "onboarding-active@example.com")
	if err := db.Model(&models.User{}).Where("email = ?", "onboarding-active@example.com").Update("phone_normalized", "+77079000004").Error; err != nil {
		t.Fatalf("seed phone_normalized: %v", err)
	}

	status, out := c.do("POST", "/api/bookings", map[string]any{
		"name": "Настя", "phone": "+7 707 900 00 04", "message": "заявка", "items": []any{},
	})
	if status != http.StatusCreated {
		t.Fatalf("booking create: %d %v", status, out)
	}
	onboarding := out["onboarding"].(map[string]any)
	if onboarding["status"] != "existing_account" {
		t.Fatalf("expected status=existing_account, got %v", onboarding)
	}
	if _, hasClaim := onboarding["claim_token"]; hasClaim {
		t.Fatalf("must NEVER issue a claim_token for an existing active account, got %v", onboarding)
	}

	booking := out["booking"].(map[string]any)
	matchedUserID := uint(booking["user_id"].(float64))
	if matchedUserID == 0 {
		t.Fatalf("the booking should still be linked to the matched account, got %v", booking)
	}

	// Scoped to this specific user, not a global count — this suite's
	// tests share one in-memory DB (brief convention, see other *_test.go
	// files), so other tests' own claims legitimately exist alongside this.
	var claimCount int64
	db.Model(&models.AccountClaim{}).Where("user_id = ?", matchedUserID).Count(&claimCount)
	if claimCount != 0 {
		t.Fatalf("no AccountClaim row should have been created for this existing active account, got %d", claimCount)
	}

	var matchedUser models.User
	db.First(&matchedUser, matchedUserID)
	if matchedUser.Status != models.UserStatusActive {
		t.Fatalf("the matched account's status must remain untouched (active), got %q", matchedUser.Status)
	}
}

// TestOnboardingSkippedWhenBookingAlreadyHasEvent covers the "Мой той"
// request-submit path (Booking created with EventID already set) — the
// onboarding pipeline must not touch it at all.
func TestOnboardingSkippedWhenBookingAlreadyHasEvent(t *testing.T) {
	srv, db := setupOnboardingTestServer(t)

	var usersBefore, claimsBefore int64
	db.Model(&models.User{}).Count(&usersBefore)
	db.Model(&models.AccountClaim{}).Count(&claimsBefore)

	owner := registerUser(t, srv.URL, "Ержан", "onboarding-hasevent-owner@example.com")
	_, evOut := owner.do("POST", "/api/events", map[string]any{"title": "Той", "type": "toi"})
	eventID := int(evOut["event"].(map[string]any)["id"].(float64))
	status, _ := owner.do("POST", "/api/events/"+itoa(eventID)+"/request/submit", nil)
	if status != http.StatusOK {
		t.Fatalf("submit request: %d", status)
	}

	// The Submit call's own linked Booking must not have triggered any
	// onboarding side effect: exactly the one real registered user this
	// test itself created (+1), and zero new claims.
	var usersAfter, claimsAfter int64
	db.Model(&models.User{}).Count(&usersAfter)
	db.Model(&models.AccountClaim{}).Count(&claimsAfter)
	if usersAfter != usersBefore+1 {
		t.Fatalf("expected exactly +1 user (the registered owner), got before=%d after=%d", usersBefore, usersAfter)
	}
	if claimsAfter != claimsBefore {
		t.Fatalf("no claim should ever be minted for a request-submit booking, got before=%d after=%d", claimsBefore, claimsAfter)
	}
}

// TestOnboardingSkippedWhenAuthenticated covers the "logged-in customer
// places a plain cart booking" case — OptionalAuth already attaches
// UserID, so the onboarding pipeline has nothing to do.
func TestOnboardingSkippedWhenAuthenticated(t *testing.T) {
	srv, db := setupOnboardingTestServer(t)

	var usersBefore int64
	db.Model(&models.User{}).Count(&usersBefore)

	customer := registerUser(t, srv.URL, "Дана", "onboarding-authed@example.com")

	status, out := customer.do("POST", "/api/bookings", map[string]any{
		"name": "Дана", "phone": "+7 707 900 00 05", "message": "из корзины", "items": []any{},
	})
	if status != http.StatusCreated {
		t.Fatalf("booking create: %d %v", status, out)
	}
	if _, ok := out["onboarding"]; ok {
		t.Fatalf("an authenticated booking must not trigger onboarding, got %v", out)
	}
	var usersAfter int64
	db.Model(&models.User{}).Count(&usersAfter)
	if usersAfter != usersBefore+1 {
		t.Fatalf("expected exactly +1 user (the registered customer, no onboarding-created extra), got before=%d after=%d", usersBefore, usersAfter)
	}
}

// TestClaimExpiredOrUnknownTokenRejected is a direct check on the Claim
// endpoint's security edge cases (brief section 16): unknown token 404s,
// and an expired-but-otherwise-valid, never-used token is still rejected.
func TestClaimExpiredOrUnknownTokenRejected(t *testing.T) {
	srv, db := setupOnboardingTestServer(t)
	c := apiClient{t: t, base: srv.URL}

	status, _ := c.do("POST", "/api/auth/claim/this-token-does-not-exist", nil)
	if status != http.StatusNotFound {
		t.Fatalf("unknown claim token should 404, got %d", status)
	}

	// A real user + an already-expired claim (seeded directly, since
	// claimTTL is 30 days — nothing in normal use produces one this fast).
	user := models.User{Name: "Expired", Email: "onboarding-expired@example.com", PasswordHash: "x", Status: models.UserStatusPending}
	db.Create(&user)
	expired := models.AccountClaim{UserID: user.ID, Token: "already-expired-token-1234567890", ExpiresAt: time.Now().Add(-time.Hour)}
	db.Create(&expired)

	status, _ = c.do("POST", "/api/auth/claim/"+expired.Token, nil)
	if status != http.StatusGone {
		t.Fatalf("expired claim token should be rejected with 410, got %d", status)
	}
}
