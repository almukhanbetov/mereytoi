package routes_test

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"regexp"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/driver/postgres"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/config"
	"github.com/almukhanbetov/mereytoi/backend/internal/mail"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
	"github.com/almukhanbetov/mereytoi/backend/internal/passwordreset"
	"github.com/almukhanbetov/mereytoi/backend/internal/routes"
)

const (
	otpRequestPath = "/api/auth/recovery/email/request"
	otpResetPath   = "/api/auth/recovery/email/reset"
)

var otpBody = regexp.MustCompile(`\b\d{6}\b`)

type otpMailbox struct {
	mu   sync.Mutex
	sent []mail.Message
	fail error
}

func (m *otpMailbox) Send(_ context.Context, msg mail.Message) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.fail != nil {
		return m.fail
	}
	m.sent = append(m.sent, msg)
	return nil
}

func (m *otpMailbox) count() int {
	m.mu.Lock()
	defer m.mu.Unlock()
	return len(m.sent)
}

// last returns the code in the newest message.
func (m *otpMailbox) last(t *testing.T) string {
	t.Helper()
	m.mu.Lock()
	defer m.mu.Unlock()
	if len(m.sent) == 0 {
		t.Fatal("nothing sent")
	}
	code := otpBody.FindString(m.sent[len(m.sent)-1].TextBody)
	if code == "" {
		t.Fatal("no code in the email")
	}
	return code
}

type otpEnv struct {
	*recEnv
	box   *otpMailbox
	svc   *passwordreset.Service
	mu    sync.Mutex
	shift time.Duration
}

func (e *otpEnv) advance(d time.Duration) {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.shift += d
}

// newOTPEnvOn turns on only the code flag: the notifications stay off, as in
// the planned first production setup.
func newOTPEnvOn(t *testing.T, db *gorm.DB, enabled bool) *otpEnv {
	t.Helper()
	return newOTPEnvFlags(t, db, false, enabled)
}

func newOTPEnvFlags(t *testing.T, db *gorm.DB, mailEnabled, otpEnabled bool) *otpEnv {
	t.Helper()
	gin.SetMode(gin.TestMode)
	if err := db.AutoMigrate(&models.User{}, &models.PasswordResetCode{}, &models.RecoveryAttempt{}, &models.RecoveryAuditEvent{}); err != nil {
		t.Fatal(err)
	}
	e := &otpEnv{box: &otpMailbox{}}
	e.svc = passwordreset.New(db, passwordreset.NotConfiguredSender{}, "", recSecret).WithClock(func() time.Time {
		e.mu.Lock()
		defer e.mu.Unlock()
		return time.Now().Add(e.shift)
	})
	cfg := config.Config{JWTSecret: recSecret, MailEnabled: mailEnabled, PasswordEmailOTPEnabled: otpEnabled}
	r := gin.New()
	routes.RegisterWithOptions(r, db, cfg, routes.Options{Mail: mail.NewServiceWithSender(e.box, cfg), PasswordReset: e.svc})
	e.recEnv = &recEnv{t: t, r: r, db: db}
	return e
}

func newOTPEnv(t *testing.T, enabled ...bool) *otpEnv {
	t.Helper()
	recDBSeq++
	db, err := gorm.Open(sqlite.Open(fmt.Sprintf("file:emailotp%d?mode=memory&cache=shared", recDBSeq)), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	sqlDB, err := db.DB()
	if err != nil {
		t.Fatal(err)
	}
	sqlDB.SetMaxOpenConns(1)
	return newOTPEnvOn(t, db, len(enabled) == 0 || enabled[0])
}

func (e *otpEnv) request(email string, remote ...string) (int, string) {
	e.t.Helper()
	q := recReq{method: "POST", path: otpRequestPath, body: map[string]string{"email": email}}
	if len(remote) > 0 {
		q.remote = remote[0]
	}
	st, out, hdr := e.do(q)
	if hdr.Get("Cache-Control") != "no-store" {
		e.t.Fatal("cacheable")
	}
	e.svc.Flush()
	return st, fmt.Sprint(out)
}

func (e *otpEnv) reset(email, otp, password string, remote ...string) (int, map[string]any) {
	e.t.Helper()
	q := recReq{method: "POST", path: otpResetPath, body: map[string]string{"email": email, "otp": otp, "new_password": password}}
	if len(remote) > 0 {
		q.remote = remote[0]
	}
	st, out, _ := e.do(q)
	return st, out
}

func wrongCode(right string) string {
	if right == "000000" {
		return "000001"
	}
	return "000000"
}

func TestEmailOTPAnswerIsTheSameForAnyAccount(t *testing.T) {
	e := newOTPEnv(t)
	e.register("known@test.local", "", "oldpass12")

	stKnown, known := e.request("known@test.local")
	stUnknown, unknown := e.request("nobody@test.local")
	stBad, bad := e.request("not-an-email")
	if stKnown != 200 || stUnknown != 200 || stBad != 200 || known != unknown || unknown != bad || known != "map[status:ok]" {
		t.Fatalf("%d %s / %d %s / %d %s", stKnown, known, stUnknown, unknown, stBad, bad)
	}
	if e.box.count() != 1 {
		t.Fatalf("emails %d", e.box.count())
	}
	if e.box.sent[0].To != "known@test.local" {
		t.Fatalf("to %q", e.box.sent[0].To)
	}
}

func TestEmailOTPStoredOnlyAsHashAndNeverLogged(t *testing.T) {
	var logs bytes.Buffer
	log.SetOutput(&logs)
	defer log.SetOutput(os.Stderr)

	e := newOTPEnv(t)
	u := e.register("hash@test.local", "", "oldpass12")
	_, answer := e.request("hash@test.local")
	code := e.box.last(t)
	if len(code) != 6 {
		t.Fatalf("code %q", code)
	}
	if strings.Contains(answer, code) {
		t.Fatal("code in the response")
	}
	row := map[string]any{}
	e.db.Model(&models.PasswordResetCode{}).Where("user_id = ?", u.id).Take(&row)
	if strings.Contains(fmt.Sprint(row), code) {
		t.Fatal("plaintext code stored")
	}
	if row["purpose"] != models.PasswordCodePurposeEmail {
		t.Fatalf("purpose %v", row["purpose"])
	}
	expires := row["expires_at"].(time.Time)
	if ttl := time.Until(expires); ttl < 9*time.Minute || ttl > 11*time.Minute {
		t.Fatalf("ttl %v", ttl)
	}
	if strings.Contains(e.box.sent[0].Subject, code) {
		t.Fatal("code in the subject")
	}
	if st, _ := e.reset("hash@test.local", code, "NewPass123"); st != 200 {
		t.Fatalf("reset %d", st)
	}
	for _, secret := range []string{code, "hash@test.local", "NewPass123"} {
		if strings.Contains(logs.String(), secret) {
			t.Fatalf("%q in the log", secret)
		}
	}
}

func TestEmailOTPResetChangesPasswordRevokesSessionsAndAudits(t *testing.T) {
	e := newOTPEnv(t)
	u := e.register("flow@test.local", "+7 700 500 00 01", "oldpass12")
	backup := u.code
	// Sessions are compared by whole seconds; make the old one strictly older.
	time.Sleep(1100 * time.Millisecond)
	e.request("FLOW@test.local ")
	code := e.box.last(t)

	stWrong, wrong := e.reset("flow@test.local", wrongCode(code), "NewPass123")
	stNobody, nobody := e.reset("nobody@test.local", code, "NewPass123")
	if stWrong != 400 || stNobody != 400 || fmt.Sprint(wrong) != fmt.Sprint(nobody) || wrong["error"] != "invalid_recovery_code" {
		t.Fatalf("%d %v / %d %v", stWrong, wrong, stNobody, nobody)
	}
	if st, out := e.reset("flow@test.local", code, "short"); st != 400 || out["error"] != "weak_password" {
		t.Fatalf("weak: %d %v", st, out)
	}
	if st, out := e.reset("Flow@Test.local", " "+code+" ", "NewPass123"); st != 200 || fmt.Sprint(out) != "map[status:ok]" {
		t.Fatalf("reset: %d %v", st, out)
	}
	if e.login("flow@test.local", "NewPass123") != 200 || e.login("flow@test.local", "oldpass12") != 401 {
		t.Fatal("password not replaced")
	}
	if st, _ := e.me(u.token); st != http.StatusUnauthorized {
		t.Fatalf("old session: %d", st)
	}
	// One use only.
	if st, _ := e.reset("flow@test.local", code, "Another123"); st != 400 {
		t.Fatalf("second use: %d", st)
	}
	var user models.User
	e.db.First(&user, u.id)
	if user.PhoneVerifiedAt != nil {
		t.Fatal("email code marked the phone verified")
	}
	var live int64
	e.db.Model(&models.PasswordResetCode{}).Where("user_id = ? AND used_at IS NULL AND invalidated_at IS NULL", u.id).Count(&live)
	if live != 0 {
		t.Fatalf("live codes %d", live)
	}
	var actions []string
	e.db.Model(&models.RecoveryAuditEvent{}).Where("user_id = ?", u.id).Order("id").Pluck("action", &actions)
	if strings.Join(actions, ",") != "email_requested,email_used" {
		t.Fatalf("audit %v", actions)
	}
	var withCode int64
	e.db.Model(&models.RecoveryAuditEvent{}).Where("action LIKE ?", "%"+code+"%").Count(&withCode)
	if withCode != 0 {
		t.Fatal("code in the audit")
	}
	// The backup code still belongs to its owner and still works.
	if st, _ := e.recover("flow@test.local", backup, "Backup12345"); st != 200 {
		t.Fatalf("backup flow: %d", st)
	}
}

func TestEmailOTPResendCooldownAndNewCodeInvalidatesOld(t *testing.T) {
	e := newOTPEnv(t)
	e.register("re@test.local", "", "oldpass12")
	e.request("re@test.local")
	first := e.box.last(t)

	if st, body := e.request("re@test.local"); st != 200 || body != "map[status:ok]" {
		t.Fatalf("within cooldown: %d %s", st, body)
	}
	if e.box.count() != 1 {
		t.Fatalf("emails within cooldown: %d", e.box.count())
	}
	e.advance(61 * time.Second)
	e.request("re@test.local")
	if e.box.count() != 2 {
		t.Fatalf("emails after cooldown: %d", e.box.count())
	}
	second := e.box.last(t)
	if first != second {
		if st, _ := e.reset("re@test.local", first, "NewPass123"); st != 400 {
			t.Fatalf("old code: %d", st)
		}
	}
	if st, _ := e.reset("re@test.local", second, "NewPass123"); st != 200 {
		t.Fatalf("new code: %d", st)
	}
}

func TestEmailOTPHourlyCapPerAccount(t *testing.T) {
	e := newOTPEnv(t)
	e.register("cap@test.local", "", "oldpass12")
	for i := 0; i < 5; i++ {
		e.request("cap@test.local", fmt.Sprintf("198.51.100.%d:1", i+1))
		e.advance(61 * time.Second)
		e.db.Where("1 = 1").Delete(&models.RecoveryAttempt{})
	}
	if e.box.count() != 5 {
		t.Fatalf("emails %d", e.box.count())
	}
	if st, _ := e.request("cap@test.local"); st != 200 {
		t.Fatalf("over the cap: %d", st)
	}
	if e.box.count() != 5 {
		t.Fatalf("sixth email went out: %d", e.box.count())
	}
}

func TestEmailOTPExpires(t *testing.T) {
	e := newOTPEnv(t)
	e.register("late@test.local", "", "oldpass12")
	e.request("late@test.local")
	code := e.box.last(t)
	e.advance(10*time.Minute + time.Second)
	if st, out := e.reset("late@test.local", code, "NewPass123"); st != 400 || out["error"] != "invalid_recovery_code" {
		t.Fatalf("%d %v", st, out)
	}
	if e.login("late@test.local", "oldpass12") != 200 {
		t.Fatal("password changed")
	}
}

func TestEmailOTPDiesAfterFiveWrongAttempts(t *testing.T) {
	e := newOTPEnv(t)
	e.register("five@test.local", "", "oldpass12")
	e.request("five@test.local")
	code := e.box.last(t)
	for i := 0; i < 5; i++ {
		if st, _ := e.reset("five@test.local", wrongCode(code), "NewPass123"); st != 400 {
			t.Fatalf("attempt %d: %d", i, st)
		}
	}
	if st, _ := e.reset("five@test.local", code, "NewPass123"); st != 400 {
		t.Fatalf("right code after five wrong: %d", st)
	}
	if e.login("five@test.local", "oldpass12") != 200 {
		t.Fatal("password changed")
	}
}

func TestEmailOTPRateLimits(t *testing.T) {
	e := newOTPEnv(t)
	// Per address: 429 whatever the email, known or not.
	for i := 0; i < 10; i++ {
		if st, _ := e.request(fmt.Sprintf("n%d@test.local", i), "198.51.100.20:1"); st != 200 {
			t.Fatalf("attempt %d: %d", i, st)
		}
	}
	if st, _ := e.request("n99@test.local", "198.51.100.20:1"); st != http.StatusTooManyRequests {
		t.Fatalf("address limit: %d", st)
	}

	// Per email: silent, from fresh addresses, known or not.
	e.register("bomb@test.local", "", "oldpass12")
	for i := 0; i < 8; i++ {
		e.advance(61 * time.Second)
		for _, email := range []string{"bomb@test.local", "ghost@test.local"} {
			if st, body := e.request(email, fmt.Sprintf("198.51.100.%d:1", 30+i)); st != 200 || body != "map[status:ok]" {
				t.Fatalf("%s: %d %s", email, st, body)
			}
		}
	}
	if e.box.count() != 5 {
		t.Fatalf("emails to the target: %d", e.box.count())
	}

	// Resets: per email, then per address; the same for known and unknown.
	for _, email := range []string{"bomb@test.local", "ghost2@test.local"} {
		for i := 0; i < 10; i++ {
			e.reset(email, "000000", "NewPass123", fmt.Sprintf("198.51.100.%d:1", 60+i))
		}
		if st, out := e.reset(email, "000000", "NewPass123", "198.51.100.90:1"); st != http.StatusTooManyRequests || out["error"] != "too_many_attempts" {
			t.Fatalf("%s: %d %v", email, st, out)
		}
	}
	for i := 0; i < 20; i++ {
		e.reset(fmt.Sprintf("x%d@test.local", i), "000000", "NewPass123", "198.51.100.91:1")
	}
	if st, _ := e.reset("x99@test.local", "000000", "NewPass123", "198.51.100.91:1"); st != http.StatusTooManyRequests {
		t.Fatalf("address limit on reset: %d", st)
	}
}

func TestSMTPFailureLooksTheSameAndLeavesNoUsableCode(t *testing.T) {
	var logs bytes.Buffer
	log.SetOutput(&logs)
	defer log.SetOutput(os.Stderr)

	e := newOTPEnv(t)
	u := e.register("down@test.local", "", "oldpass12")
	e.box.fail = errors.New("rcpt to: 550 no such user down@test.local")
	st, body := e.request("down@test.local")
	stOther, other := e.request("nobody@test.local")
	if st != 200 || stOther != 200 || body != other {
		t.Fatalf("%d %s / %d %s", st, body, stOther, other)
	}
	var live int64
	e.db.Model(&models.PasswordResetCode{}).Where("user_id = ? AND used_at IS NULL AND invalidated_at IS NULL", u.id).Count(&live)
	if live != 0 {
		t.Fatal("an undelivered code stays usable")
	}
	if !strings.Contains(logs.String(), "not delivered: rcpt to") || strings.Contains(logs.String(), "down@test.local") {
		t.Fatalf("log: %s", logs.String())
	}
}

// Each flag governs its own kind of email, in all four combinations, through
// the real routes and one shared sender.
func TestEmailFlagsAreIndependent(t *testing.T) {
	for _, tc := range []struct{ mail, otp bool }{{false, false}, {false, true}, {true, false}, {true, true}} {
		t.Run(fmt.Sprintf("mail=%v otp=%v", tc.mail, tc.otp), func(t *testing.T) {
			recDBSeq++
			db, err := gorm.Open(sqlite.Open(fmt.Sprintf("file:emailflags%d?mode=memory&cache=shared", recDBSeq)), &gorm.Config{})
			if err != nil {
				t.Fatal(err)
			}
			sqlDB, err := db.DB()
			if err != nil {
				t.Fatal(err)
			}
			sqlDB.SetMaxOpenConns(1)
			if err := db.AutoMigrate(&models.Event{}, &models.EventMember{}, &models.EventInvitation{}, &models.EventActivity{}, &models.Notification{}); err != nil {
				t.Fatal(err)
			}
			e := newOTPEnvFlags(t, db, tc.mail, tc.otp)
			u := e.register("flags@test.local", "", "oldpass12")

			st, out, _ := e.do(recReq{method: "GET", path: "/api/auth/password/config"})
			if st != 200 || out["email_otp_available"] != tc.otp {
				t.Fatalf("config: %d %v", st, out)
			}

			// A notification, through its real route.
			st, out, _ = e.do(recReq{method: "POST", path: "/api/events", token: u.token, body: map[string]any{"title": "Той", "type": "wedding"}})
			if st != http.StatusCreated {
				t.Fatalf("create event: %d %v", st, out)
			}
			eventID := int(out["event"].(map[string]any)["id"].(float64))
			st, out, _ = e.do(recReq{method: "POST", path: fmt.Sprintf("/api/events/%d/invitations", eventID), token: u.token,
				body: map[string]any{"role": "editor", "email": "guest@test.local"}})
			if st != http.StatusCreated {
				t.Fatalf("invitation: %d %v", st, out)
			}
			wantInvites := 0
			if tc.mail {
				wantInvites = 1
			}

			// A code. The answer is the same whatever the flags.
			if st, body := e.request("flags@test.local"); st != 200 || body != "map[status:ok]" {
				t.Fatalf("request: %d %s", st, body)
			}
			wantCodes := int64(0)
			if tc.otp {
				wantCodes = 1
			}
			var codes int64
			db.Model(&models.PasswordResetCode{}).Count(&codes)
			if codes != wantCodes {
				t.Fatalf("codes in the DB: %d", codes)
			}

			invites, otps := 0, 0
			e.box.mu.Lock()
			for _, msg := range e.box.sent {
				switch msg.To {
				case "guest@test.local":
					invites++
				case "flags@test.local":
					otps++
				}
			}
			e.box.mu.Unlock()
			if invites != wantInvites || int64(otps) != wantCodes {
				t.Fatalf("invitation emails %d, code emails %d", invites, otps)
			}

			if tc.otp {
				if st, _ := e.reset("flags@test.local", e.box.last(t), "NewPass123"); st != 200 {
					t.Fatalf("reset: %d", st)
				}
			} else {
				// Nothing usable exists, and the refusal is the usual one.
				if st, out := e.reset("flags@test.local", "123456", "NewPass123"); st != 400 || out["error"] != "invalid_recovery_code" {
					t.Fatalf("reset: %d %v", st, out)
				}
				if e.login("flags@test.local", "oldpass12") != 200 {
					t.Fatal("password changed")
				}
			}
		})
	}
}

func TestEmailOTPOffWhenItsFlagIsOffAndConfigSaysSo(t *testing.T) {
	e := newOTPEnv(t, false)
	e.register("off@test.local", "", "oldpass12")
	st, out, _ := e.do(recReq{method: "GET", path: "/api/auth/password/config"})
	if st != 200 || out["email_otp_available"] != false {
		t.Fatalf("%d %v", st, out)
	}
	if st, body := e.request("off@test.local"); st != 200 || body != "map[status:ok]" {
		t.Fatalf("%d %s", st, body)
	}
	var n int64
	e.db.Model(&models.PasswordResetCode{}).Count(&n)
	if n != 0 || e.box.count() != 0 {
		t.Fatalf("codes %d, emails %d", n, e.box.count())
	}
	on := newOTPEnv(t)
	if st, out, _ := on.do(recReq{method: "GET", path: "/api/auth/password/config"}); st != 200 || out["email_otp_available"] != true {
		t.Fatalf("%d %v", st, out)
	}
}

func TestEmailOTPSkipsPendingAccounts(t *testing.T) {
	e := newOTPEnv(t)
	u := e.register("pend@test.local", "", "oldpass12")
	e.db.Model(&models.User{}).Where("id = ?", u.id).Update("status", models.UserStatusPending)
	e.request("pend@test.local")
	if e.box.count() != 0 {
		t.Fatal("email sent to a pending account")
	}
}

func TestEmailOTPDoesNotWorkInOtherFlows(t *testing.T) {
	e := newOTPEnv(t)
	u := e.register("iso@test.local", "+7 700 500 00 02", "oldpass12")
	e.request("iso@test.local")
	code := e.box.last(t)
	if st, _ := e.recover("iso@test.local", code, "NewPass123"); st != 400 {
		t.Fatalf("backup flow: %d", st)
	}
	st, _, _ := e.do(recReq{method: "POST", path: "/api/auth/password/reset",
		body: map[string]string{"phone": "+7 700 500 00 02", "code": code, "new_password": "NewPass123"}})
	if st == 200 {
		t.Fatal("phone flow took an email code")
	}
	if st, _ := e.reset("iso@test.local", u.code, "NewPass123"); st != 400 {
		t.Fatalf("backup code on email reset: %d", st)
	}
	if e.login("iso@test.local", "oldpass12") != 200 {
		t.Fatal("password changed")
	}
}

// A support code and an email code are separate: neither redeems through the
// other's endpoint.
func TestEmailOTPAndSupportCodesDoNotCross(t *testing.T) {
	e := newOTPEnv(t)
	if err := e.db.AutoMigrate(&models.PasswordRecoveryRequest{}); err != nil {
		t.Fatal(err)
	}
	e.register("adm-otp@test.local", "", "adminpass1")
	e.db.Model(&models.User{}).Where("email = ?", "adm-otp@test.local").Update("role", "admin")
	st, out, _ := e.do(recReq{method: "POST", path: "/api/auth/login", body: map[string]string{"email": "adm-otp@test.local", "password": "adminpass1"}})
	if st != 200 {
		t.Fatalf("admin login %d", st)
	}
	adminToken := out["token"].(string)

	u := e.register("cross2@test.local", "", "oldpass12")
	e.do(recReq{method: "POST", path: supRequestPath, body: map[string]string{"login": "cross2@test.local"}})
	var req models.PasswordRecoveryRequest
	if err := e.db.Where("user_id = ?", u.id).First(&req).Error; err != nil {
		t.Fatal(err)
	}
	st, out, _ = e.do(recReq{method: "POST", path: fmt.Sprintf("%s/%d/approve", supAdminPath, req.ID), token: adminToken})
	if st != 200 {
		t.Fatalf("approve %d %v", st, out)
	}
	support := out["temp_code"].(string)

	e.request("cross2@test.local")
	otp := e.box.last(t)

	if st, _ := e.reset("cross2@test.local", support, "NewPass123"); st != 400 {
		t.Fatalf("support code on email reset: %d", st)
	}
	st, _, _ = e.do(recReq{method: "POST", path: supResetPath, body: map[string]string{"login": "cross2@test.local", "temp_code": otp, "new_password": "NewPass123"}})
	if st != 400 {
		t.Fatalf("email code on support reset: %d", st)
	}
	if e.login("cross2@test.local", "oldpass12") != 200 {
		t.Fatal("password changed")
	}
	if st, _ := e.reset("cross2@test.local", otp, "NewPass123"); st != 200 {
		t.Fatalf("email code: %d", st)
	}
}

func TestConcurrentEmailOTPResetSucceedsOnce(t *testing.T) {
	e := newOTPEnv(t)
	e.register("race@test.local", "", "oldpass12")
	e.request("race@test.local")
	if wins := parallelOTPResets(e, "race@test.local", e.box.last(t), 4); wins != 1 {
		t.Fatalf("%d resets succeeded", wins)
	}
}

func parallelOTPResets(e *otpEnv, email, code string, n int) int {
	var wg sync.WaitGroup
	var mu sync.Mutex
	wins := 0
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			st, _, _ := e.do(recReq{method: "POST", path: otpResetPath, remote: fmt.Sprintf("198.51.100.%d:1", 150+i),
				body: map[string]string{"email": email, "otp": code, "new_password": fmt.Sprintf("Parallel%d23", i)}})
			if st == 200 {
				mu.Lock()
				wins++
				mu.Unlock()
			}
		}(i)
	}
	wg.Wait()
	return wins
}

// Real parallel resets on Postgres; needs a disposable database:
//
//	MEREYTOI_TEST_POSTGRES_DSN="host=... dbname=... sslmode=disable" go test ./internal/routes -run EmailOTPPostgres
func TestParallelEmailOTPPostgres(t *testing.T) {
	dsn := os.Getenv("MEREYTOI_TEST_POSTGRES_DSN")
	if dsn == "" {
		t.Skip("MEREYTOI_TEST_POSTGRES_DSN not set")
	}
	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.Migrator().DropTable(&models.PasswordRecoveryRequest{}, &models.RecoveryAuditEvent{},
		&models.RecoveryAttempt{}, &models.PasswordResetCode{}, &models.User{}); err != nil {
		t.Fatal(err)
	}
	e := newOTPEnvOn(t, db, true)
	e.register("pg-otp@test.local", "", "oldpass12")
	e.request("pg-otp@test.local")
	if wins := parallelOTPResets(e, "pg-otp@test.local", e.box.last(t), 5); wins != 1 {
		t.Fatalf("%d resets succeeded", wins)
	}
	var used int64
	db.Model(&models.RecoveryAuditEvent{}).Where("action = ?", models.RecoveryAuditEmailUsed).Count(&used)
	if used != 1 {
		t.Fatalf("audit used %d", used)
	}
}
