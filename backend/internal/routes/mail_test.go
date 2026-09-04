package routes_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/config"
	"github.com/almukhanbetov/mereytoi/backend/internal/mail"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
	"github.com/almukhanbetov/mereytoi/backend/internal/routes"
)

// Stage 11A — transactional email tests. These exercise the exact same
// route tree as every other routes_test.go file (routes.Register), just
// with a mock mail.Sender injected via routes.Register's new variadic
// mailSvc parameter (see routes.go) instead of a real SMTP/log transport —
// no test here opens a real network connection.

// mockSender is a mail.Sender that records every message it's asked to
// send instead of transporting it anywhere. Sends happen synchronously
// within the handler call (mail.Service.deliver has no goroutine of its
// own — see service.go's doc comment on the post-commit-with-timeout
// tradeoff), so by the time an apiClient.do(...) call returns, any email
// it triggered has already been recorded here; no sleep/poll is needed.
type mockSender struct {
	mu   sync.Mutex
	sent []mail.Message
	// failAll, when set, makes every Send return an error — used by
	// TestEmailFailureDoesNotFailBusinessAction to prove transport failure
	// never rolls back or fails the calling request.
	failAll bool
}

func (m *mockSender) Send(_ context.Context, msg mail.Message) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.failAll {
		return context.DeadlineExceeded
	}
	m.sent = append(m.sent, msg)
	return nil
}

func (m *mockSender) count() int {
	m.mu.Lock()
	defer m.mu.Unlock()
	return len(m.sent)
}

func (m *mockSender) last() mail.Message {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.sent[len(m.sent)-1]
}

func (m *mockSender) to(addr string) []mail.Message {
	m.mu.Lock()
	defer m.mu.Unlock()
	var out []mail.Message
	for _, msg := range m.sent {
		if msg.To == addr {
			out = append(out, msg)
		}
	}
	return out
}

// setupMailTestServer is setupTestServer (event_security_test.go) plus a
// mock mail sender wired in through MailEnabled: true — every other field
// on cfg matches setupTestServer's own {JWTSecret: "test-secret-only"} so
// behavior stays identical to every other test file except for mail
// actually being "on."
func setupMailTestServer(t *testing.T) (*httptest.Server, *gorm.DB, *mockSender) {
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
	); err != nil {
		t.Fatalf("failed to migrate: %v", err)
	}

	sender := &mockSender{}
	cfg := config.Config{JWTSecret: "test-secret-only", MailEnabled: true, FrontendURL: "https://mereytoi.kz"}
	mailer := mail.NewServiceWithSender(sender, cfg)

	r := gin.New()
	r.Use(cors.Default())
	routes.Register(r, db, cfg, mailer)

	srv := httptest.NewServer(r)
	t.Cleanup(srv.Close)
	return srv, db, sender
}

// --- (1) & (2): invitation email — sent when an address is given, safely
// skipped (invitation still created) when it isn't. ---

func TestInvitationEmailSentWhenAddressGiven(t *testing.T) {
	srv, _, sender := setupMailTestServer(t)
	owner := registerUser(t, srv.URL, "Диана", "mail-inv-owner@example.com")

	_, out := owner.do("POST", "/api/events", map[string]any{"title": "Юбилей", "type": "anniversary"})
	eventID := int(out["event"].(map[string]any)["id"].(float64))

	status, invOut := owner.do("POST", "/api/events/"+itoa(eventID)+"/invitations", map[string]any{
		"role": "editor", "email": "cousin@example.com",
	})
	if status != http.StatusCreated {
		t.Fatalf("create invitation: %d %v", status, invOut)
	}
	token := invOut["invitation"].(map[string]any)["token"].(string)

	if got := len(sender.to("cousin@example.com")); got != 1 {
		t.Fatalf("expected exactly 1 invitation email to cousin@example.com, got %d", got)
	}
	msg := sender.to("cousin@example.com")[0]
	if !strings.Contains(msg.HTMLBody, "/invite/"+token) {
		t.Fatalf("invitation email should link to the real invite token, body=%s", msg.HTMLBody)
	}
	if !strings.Contains(msg.HTMLBody, "Юбилей") {
		t.Fatalf("invitation email should mention the event title, body=%s", msg.HTMLBody)
	}
}

func TestInvitationWithoutEmailSkipsSendSafely(t *testing.T) {
	srv, _, sender := setupMailTestServer(t)
	owner := registerUser(t, srv.URL, "Ерсын", "mail-inv-noemail-owner@example.com")

	_, out := owner.do("POST", "/api/events", map[string]any{"title": "Той", "type": "toi"})
	eventID := int(out["event"].(map[string]any)["id"].(float64))

	status, invOut := owner.do("POST", "/api/events/"+itoa(eventID)+"/invitations", map[string]any{"role": "editor"})
	if status != http.StatusCreated {
		t.Fatalf("invitation without an email should still be created: %d %v", status, invOut)
	}
	if invOut["invitation"].(map[string]any)["token"] == nil {
		t.Fatalf("a usable invite link/token must still exist even with no email")
	}
	if got := sender.count(); got != 0 {
		t.Fatalf("no email address given -> zero emails, got %d", got)
	}
}

// --- (3)/(4)/(5): the three organizer decision emails. ---

func TestRequestChangesRequestedEmailsOrganizer(t *testing.T) {
	srv, db, sender := setupMailTestServer(t)
	owner := registerUser(t, srv.URL, "Асель", "mail-cr-owner@example.com")
	admin := registerAdmin(t, srv.URL, db, "Manager", "mail-cr-admin@example.com")

	_, out := owner.do("POST", "/api/events", map[string]any{"title": "Свадьба Асель", "type": "wedding"})
	eventID := int(out["event"].(map[string]any)["id"].(float64))
	owner.do("POST", "/api/events/"+itoa(eventID)+"/request/submit", nil)

	reqID := findEventRequestID(t, admin, eventID)
	status, _ := admin.do("POST", "/api/admin/event-requests/"+itoa(reqID)+"/status", map[string]any{
		"status": "changes_requested", "manager_comment": "Уточните дату",
	})
	if status != http.StatusOK {
		t.Fatalf("changes_requested transition failed: %d", status)
	}

	msgs := sender.to("mail-cr-owner@example.com")
	if len(msgs) != 1 {
		t.Fatalf("expected exactly 1 changes_requested email to the organizer, got %d", len(msgs))
	}
	if !strings.Contains(msgs[0].HTMLBody, "Уточните дату") {
		t.Fatalf("changes_requested email should include the manager's comment, body=%s", msgs[0].HTMLBody)
	}
}

func TestRequestApprovedEmailsOrganizer(t *testing.T) {
	srv, db, sender := setupMailTestServer(t)
	owner := registerUser(t, srv.URL, "Data", "mail-appr-owner@example.com")
	admin := registerAdmin(t, srv.URL, db, "Manager", "mail-appr-admin@example.com")

	_, out := owner.do("POST", "/api/events", map[string]any{"title": "Корпоратив", "type": "corporate"})
	eventID := int(out["event"].(map[string]any)["id"].(float64))
	owner.do("POST", "/api/events/"+itoa(eventID)+"/request/submit", nil)

	reqID := findEventRequestID(t, admin, eventID)
	status, _ := admin.do("POST", "/api/admin/event-requests/"+itoa(reqID)+"/status", map[string]any{"status": "approved"})
	if status != http.StatusOK {
		t.Fatalf("approve transition failed: %d", status)
	}

	msgs := sender.to("mail-appr-owner@example.com")
	if len(msgs) != 1 {
		t.Fatalf("expected exactly 1 approval email to the organizer, got %d", len(msgs))
	}
}

func TestRequestRejectedEmailsOrganizer(t *testing.T) {
	srv, db, sender := setupMailTestServer(t)
	owner := registerUser(t, srv.URL, "Rustem", "mail-rej-owner@example.com")
	admin := registerAdmin(t, srv.URL, db, "Manager", "mail-rej-admin@example.com")

	_, out := owner.do("POST", "/api/events", map[string]any{"title": "Той", "type": "toi"})
	eventID := int(out["event"].(map[string]any)["id"].(float64))
	owner.do("POST", "/api/events/"+itoa(eventID)+"/request/submit", nil)

	reqID := findEventRequestID(t, admin, eventID)
	status, _ := admin.do("POST", "/api/admin/event-requests/"+itoa(reqID)+"/status", map[string]any{
		"status": "rejected", "manager_comment": "Недостаточно данных",
	})
	if status != http.StatusOK {
		t.Fatalf("reject transition failed: %d", status)
	}

	msgs := sender.to("mail-rej-owner@example.com")
	if len(msgs) != 1 {
		t.Fatalf("expected exactly 1 rejection email to the organizer, got %d", len(msgs))
	}
	if !strings.Contains(msgs[0].HTMLBody, "Недостаточно данных") {
		t.Fatalf("rejection email should include the manager's reason, body=%s", msgs[0].HTMLBody)
	}
}

// --- (6): submitted request emails admin(s). ---

func TestRequestSubmittedEmailsAdmin(t *testing.T) {
	srv, db, sender := setupMailTestServer(t)
	owner := registerUser(t, srv.URL, "Madina", "mail-sub-owner@example.com")
	registerAdmin(t, srv.URL, db, "Manager", "mail-sub-admin@example.com")

	_, out := owner.do("POST", "/api/events", map[string]any{"title": "Той", "type": "toi"})
	eventID := int(out["event"].(map[string]any)["id"].(float64))
	if status, _ := owner.do("POST", "/api/events/"+itoa(eventID)+"/request/submit", nil); status != http.StatusOK {
		t.Fatalf("submit failed: %d", status)
	}

	if got := len(sender.to("mail-sub-admin@example.com")); got != 1 {
		t.Fatalf("expected exactly 1 request_submitted email to the admin, got %d", got)
	}
	// The organizer who submitted must never be emailed about their own
	// submission — mirrors the in-app notification rule.
	if got := len(sender.to("mail-sub-owner@example.com")); got != 0 {
		t.Fatalf("the submitting organizer must not be emailed about their own submission, got %d", got)
	}
}

// --- (7): transport failure never fails the business action. ---

func TestEmailFailureDoesNotFailBusinessAction(t *testing.T) {
	srv, db, sender := setupMailTestServer(t)
	sender.failAll = true

	owner := registerUser(t, srv.URL, "Askar", "mail-fail-owner@example.com")
	registerAdmin(t, srv.URL, db, "Manager", "mail-fail-admin@example.com")

	_, out := owner.do("POST", "/api/events", map[string]any{"title": "Той", "type": "toi"})
	eventID := int(out["event"].(map[string]any)["id"].(float64))

	status, subOut := owner.do("POST", "/api/events/"+itoa(eventID)+"/request/submit", nil)
	if status != http.StatusOK {
		t.Fatalf("submit must still succeed even though every email send fails: %d %v", status, subOut)
	}
	if got := subOut["request"].(map[string]any)["status"]; got != "submitted" {
		t.Fatalf("request must still transition to submitted despite email transport failure, got %v", got)
	}
	// Confirms the failure really was exercised (not just "no admin
	// configured") — mockSender.Send still runs and returns an error every
	// time, it just never records a message on failure.
	if got := sender.count(); got != 0 {
		t.Fatalf("a failing sender should record 0 successful sends, got %d", got)
	}
}

// --- (8): duplicate domain action does not duplicate email. ---

func TestDuplicateApprovalDoesNotDuplicateEmail(t *testing.T) {
	srv, db, sender := setupMailTestServer(t)
	owner := registerUser(t, srv.URL, "Zarina", "mail-dup-owner@example.com")
	admin := registerAdmin(t, srv.URL, db, "Manager", "mail-dup-admin@example.com")

	_, out := owner.do("POST", "/api/events", map[string]any{"title": "Той", "type": "toi"})
	eventID := int(out["event"].(map[string]any)["id"].(float64))
	owner.do("POST", "/api/events/"+itoa(eventID)+"/request/submit", nil)
	reqID := findEventRequestID(t, admin, eventID)
	statusPath := "/api/admin/event-requests/" + itoa(reqID) + "/status"

	if status, _ := admin.do("POST", statusPath, map[string]any{"status": "approved"}); status != http.StatusOK {
		t.Fatalf("first approve failed: %d", status)
	}
	// A retried/duplicate approve call: CanTransition rejects it (approved
	// isn't a valid *source* state) before any notify/email side effect
	// runs — this is what actually prevents the duplicate, the same
	// mechanism 10B's own duplicate-status test already relies on.
	status, _ := admin.do("POST", statusPath, map[string]any{"status": "approved"})
	if status != http.StatusConflict {
		t.Fatalf("repeating an already-terminal status should be rejected, got %d", status)
	}

	if got := len(sender.to("mail-dup-owner@example.com")); got != 1 {
		t.Fatalf("duplicate approve call must not duplicate the approval email, got %d", got)
	}
}

// --- (9): language fallback. There is nowhere to read a per-user language
// preference from (see copy.go's pick doc comment) — every call site
// currently always passes lang="ru", so the Russian subject line is the
// one this test pins down as the documented, deliberate fallback. ---

func TestEmailLanguageFallsBackToRussian(t *testing.T) {
	srv, db, sender := setupMailTestServer(t)
	owner := registerUser(t, srv.URL, "Timur", "mail-lang-owner@example.com")
	registerAdmin(t, srv.URL, db, "Manager", "mail-lang-admin@example.com")

	_, out := owner.do("POST", "/api/events", map[string]any{"title": "Той", "type": "toi"})
	eventID := int(out["event"].(map[string]any)["id"].(float64))
	owner.do("POST", "/api/events/"+itoa(eventID)+"/request/submit", nil)

	msgs := sender.to("mail-lang-admin@example.com")
	if len(msgs) != 1 {
		t.Fatalf("expected 1 admin email, got %d", len(msgs))
	}
	if msgs[0].Subject != "Новая заявка" {
		t.Fatalf("with no stored language preference, subject should fall back to the Russian copy, got %q", msgs[0].Subject)
	}
}

// --- (10): unauthorized actors cannot trigger a foreign-user email. ---

func TestNonAdminCannotTriggerRequestDecisionEmail(t *testing.T) {
	srv, db, sender := setupMailTestServer(t)
	owner := registerUser(t, srv.URL, "Bota", "mail-unauth-owner@example.com")
	outsider := registerUser(t, srv.URL, "Outsider", "mail-unauth-outsider@example.com")
	admin := registerAdmin(t, srv.URL, db, "Manager", "mail-unauth-admin@example.com")

	_, out := owner.do("POST", "/api/events", map[string]any{"title": "Той", "type": "toi"})
	eventID := int(out["event"].(map[string]any)["id"].(float64))
	owner.do("POST", "/api/events/"+itoa(eventID)+"/request/submit", nil)
	reqID := findEventRequestID(t, admin, eventID)

	before := sender.count()

	// A plain (non-admin) user hitting the admin-only decision endpoint —
	// RequireAdmin rejects it before AdminUpdateStatus, let alone its email
	// dispatch, ever runs.
	status, _ := outsider.do("POST", "/api/admin/event-requests/"+itoa(reqID)+"/status", map[string]any{"status": "approved"})
	if status != http.StatusForbidden {
		t.Fatalf("a non-admin must be rejected by RequireAdmin before reaching the handler, got %d", status)
	}
	if got := sender.count(); got != before {
		t.Fatalf("a rejected non-admin call must not trigger any additional email, before=%d after=%d", before, got)
	}
	if got := len(sender.to("mail-unauth-owner@example.com")); got != 0 {
		t.Fatalf("the outsider's forbidden call must never reach an email to the organizer, got %d", got)
	}
}

// findEventRequestID looks up an EventRequest's own id (as opposed to its
// event id) from the admin's request list — every admin-status test needs
// this, matching the pattern already used inline in request_notification_
// test.go.
func findEventRequestID(t *testing.T, admin apiClient, eventID int) int {
	t.Helper()
	_, adminList := admin.do("GET", "/api/admin/event-requests", nil)
	for _, r := range adminList["requests"].([]any) {
		rm := r.(map[string]any)
		if int(rm["event_id"].(float64)) == eventID {
			return int(rm["id"].(float64))
		}
	}
	t.Fatalf("admin should see the submitted request for event %d", eventID)
	return 0
}
