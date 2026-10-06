package routes_test

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/config"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
	"github.com/almukhanbetov/mereytoi/backend/internal/passwordreset"
	"github.com/almukhanbetov/mereytoi/backend/internal/routes"
)

const pwSecret = "test-secret-only"

// fakeCodeSender records every code it is asked to deliver.
type fakeCodeSender struct {
	mu   sync.Mutex
	sent []passwordreset.CodeMessage
}

func (f *fakeCodeSender) SendPasswordResetCode(_ context.Context, m passwordreset.CodeMessage) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.sent = append(f.sent, m)
	return nil
}

func (f *fakeCodeSender) count() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.sent)
}

func (f *fakeCodeSender) last(t *testing.T) passwordreset.CodeMessage {
	t.Helper()
	f.mu.Lock()
	defer f.mu.Unlock()
	if len(f.sent) == 0 {
		t.Fatal("no code was sent")
	}
	return f.sent[len(f.sent)-1]
}

type pwEnv struct {
	t      *testing.T
	r      *gin.Engine
	db     *gorm.DB
	sender *fakeCodeSender
	svc    *passwordreset.Service
}

var pwDBSeq int

// newPwEnv builds the real route tree on a private in-memory database.
// sender nil means production's default (NotConfiguredSender).
func newPwEnv(t *testing.T, sender *fakeCodeSender, trustedProxies []string) *pwEnv {
	t.Helper()
	gin.SetMode(gin.TestMode)
	pwDBSeq++
	db, err := gorm.Open(sqlite.Open(fmt.Sprintf("file:pwreset%d?mode=memory&cache=shared", pwDBSeq)), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(&models.User{}, &models.PasswordResetCode{}); err != nil {
		t.Fatal(err)
	}
	r := gin.New()
	var codeSender passwordreset.Sender // nil → production default (not configured)
	if sender != nil {
		codeSender = sender
	}
	svc := passwordreset.New(db, codeSender, "", pwSecret)
	routes.RegisterWithOptions(r, db, config.Config{JWTSecret: pwSecret, TrustedProxies: trustedProxies},
		routes.Options{PasswordReset: svc})
	return &pwEnv{t: t, r: r, db: db, sender: sender, svc: svc}
}

type req struct {
	method, path string
	body         any
	token        string
	remote       string // socket address; default 192.0.2.10:5000
	xff          string
}

func (e *pwEnv) do(q req) (int, string) {
	e.t.Helper()
	var buf bytes.Buffer
	if q.body != nil {
		_ = json.NewEncoder(&buf).Encode(q.body)
	}
	hr := httptest.NewRequest(q.method, q.path, &buf)
	hr.Header.Set("Content-Type", "application/json")
	if q.token != "" {
		hr.Header.Set("Authorization", "Bearer "+q.token)
	}
	hr.RemoteAddr = q.remote
	if hr.RemoteAddr == "" {
		hr.RemoteAddr = "192.0.2.10:5000"
	}
	if q.xff != "" {
		hr.Header.Set("X-Forwarded-For", q.xff)
	}
	rec := httptest.NewRecorder()
	e.r.ServeHTTP(rec, hr)
	return rec.Code, rec.Body.String()
}

func (e *pwEnv) user(phone, password, status string) models.User {
	e.t.Helper()
	hash, _ := bcrypt.GenerateFromPassword([]byte(password), bcrypt.MinCost)
	u := models.User{
		Name: "U", Email: fmt.Sprintf("u%d-%s@test.local", time.Now().UnixNano(), phone),
		Phone: phone, PhoneNormalized: phone, PasswordHash: string(hash), Role: "user", Status: status,
	}
	if err := e.db.Create(&u).Error; err != nil {
		e.t.Fatal(err)
	}
	return u
}

// forgot requests a code and waits for the background delivery to finish.
func (e *pwEnv) forgot(phone string) (int, string) {
	defer e.svc.Flush()
	return e.do(req{method: "POST", path: "/api/auth/password/forgot", body: map[string]string{"phone": phone}})
}

func (e *pwEnv) reset(phone, code, pw string) (int, string) {
	return e.do(req{method: "POST", path: "/api/auth/password/reset",
		body: map[string]string{"phone": phone, "code": code, "new_password": pw}})
}

func (e *pwEnv) login(phone, pw string) int {
	code, _ := e.do(req{method: "POST", path: "/api/auth/login", body: map[string]string{"phone": phone, "password": pw}})
	return code
}

// backdateCodes moves every code of phone d into the past (time travel for
// cooldown/expiry checks without sleeping).
func (e *pwEnv) backdateCodes(phone string, d time.Duration) {
	var rows []models.PasswordResetCode
	e.db.Where("phone_normalized = ?", phone).Find(&rows)
	for _, row := range rows {
		e.db.Model(&row).Update("created_at", row.CreatedAt.Add(-d))
	}
}

func tokenFor(t *testing.T, userID uint, iat time.Time) string {
	t.Helper()
	s, err := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub": userID, "role": "user", "iat": iat.Unix(), "exp": time.Now().Add(time.Hour).Unix(),
	}).SignedString([]byte(pwSecret))
	if err != nil {
		t.Fatal(err)
	}
	return s
}

const neutralForgot = `{"message":"Если номер зарегистрирован, мы отправили код.","resend_after":60}`

// 1–5: every kind of number gets byte-for-byte the same answer; only the
// one real, unambiguous, active account is sent a code.
func TestForgotPasswordNeverRevealsAccounts(t *testing.T) {
	e := newPwEnv(t, &fakeCodeSender{}, nil)
	e.user("+77001000001", "oldpassword1", models.UserStatusActive) // known
	e.user("+77001000002", "aaaaaaaa", models.UserStatusActive)     // duplicate #1
	e.user("+77001000002", "bbbbbbbb", models.UserStatusActive)     // duplicate #2
	e.user("+77001000003", "cccccccc", models.UserStatusPending)    // pending
	passwordless := e.user("+77001000004", "x", models.UserStatusActive)
	e.db.Model(&passwordless).Update("password_hash", "not-a-bcrypt-hash")

	cases := map[string]string{
		"known":        "8 700 100 00 01", // other spelling, same number
		"unknown":      "+77009999999",
		"duplicate":    "+77001000002",
		"pending":      "+77001000003",
		"passwordless": "+77001000004",
		"malformed":    "12345",
		"garbage":      "not a phone",
	}
	for name, phone := range cases {
		code, body := e.forgot(phone)
		if code != http.StatusOK || body != neutralForgot {
			t.Errorf("%s: got %d %s, want 200 %s", name, code, body, neutralForgot)
		}
	}
	if n := e.sender.count(); n != 1 {
		t.Fatalf("sent %d codes, want exactly 1 (the known account)", n)
	}
	if m := e.sender.last(t); m.Phone != "+77001000001" || m.Purpose != models.PasswordCodePurposeReset {
		t.Fatalf("code went to %+v", m)
	}
}

// Production default: no channel → nothing sent, and still the same answer.
func TestForgotPasswordWithoutDeliveryLooksTheSame(t *testing.T) {
	e := newPwEnv(t, nil, nil)
	e.user("+77001000011", "oldpassword1", models.UserStatusActive)
	if code, body := e.forgot("+77001000011"); code != 200 || body != neutralForgot {
		t.Fatalf("got %d %s", code, body)
	}
	var live int64
	e.db.Model(&models.PasswordResetCode{}).Where("used_at IS NULL AND invalidated_at IS NULL").Count(&live)
	if live != 0 {
		t.Fatal("an undelivered code must not stay redeemable")
	}
}

// 6, 12, 13: a valid code resets; the old password stops working, the new
// one works.
func TestResetWithValidCode(t *testing.T) {
	e := newPwEnv(t, &fakeCodeSender{}, nil)
	u := e.user("+77001000021", "oldpassword1", models.UserStatusActive)
	e.forgot("+77001000021")
	code := e.sender.last(t).Code

	if status, body := e.reset("+7 700 100 00 21", code, "newpassword1"); status != 200 || body != `{"message":"password_changed"}` {
		t.Fatalf("reset: %d %s", status, body)
	}
	if e.login("+77001000021", "oldpassword1") != http.StatusUnauthorized {
		t.Fatal("old password must stop working")
	}
	if e.login("+77001000021", "newpassword1") != http.StatusOK {
		t.Fatal("new password must work")
	}
	var after models.User
	e.db.First(&after, u.ID)
	if after.PasswordChangedAt == nil || after.PhoneVerifiedAt == nil {
		t.Fatal("password_changed_at and phone_verified_at must be set")
	}
}

// 7, 8, 9: wrong, expired and already-used codes are all "invalid_code".
func TestResetRejectsWrongExpiredAndUsedCodes(t *testing.T) {
	e := newPwEnv(t, &fakeCodeSender{}, nil)
	e.user("+77001000031", "oldpassword1", models.UserStatusActive)
	e.forgot("+77001000031")
	code := e.sender.last(t).Code
	wrong := "000000"
	if code == wrong {
		wrong = "111111"
	}

	if s, b := e.reset("+77001000031", wrong, "newpassword1"); s != 400 || b != `{"error":"invalid_code"}` {
		t.Fatalf("wrong code: %d %s", s, b)
	}
	if s, _ := e.reset("+77001000031", code, "newpassword1"); s != 200 {
		t.Fatalf("one wrong guess must not burn the code: %d", s)
	}
	if s, b := e.reset("+77001000031", code, "newpassword2"); s != 400 || b != `{"error":"invalid_code"}` {
		t.Fatalf("used code: %d %s", s, b)
	}

	// Expired: a fresh code whose expiry has passed.
	e.backdateCodes("+77001000031", 2*time.Minute) // past the resend cooldown
	e.forgot("+77001000031")
	expired := e.sender.last(t).Code
	e.db.Model(&models.PasswordResetCode{}).Where("used_at IS NULL AND invalidated_at IS NULL").
		Update("expires_at", time.Now().Add(-time.Second))
	if s, b := e.reset("+77001000031", expired, "newpassword3"); s != 400 || b != `{"error":"invalid_code"}` {
		t.Fatalf("expired code: %d %s", s, b)
	}
	if e.login("+77001000031", "newpassword1") != 200 {
		t.Fatal("rejected codes must leave the password alone")
	}
}

// Unknown number and a code for someone else's number: same answer.
func TestResetForUnknownNumberIsJustInvalid(t *testing.T) {
	e := newPwEnv(t, &fakeCodeSender{}, nil)
	if s, b := e.reset("+77009999998", "123456", "newpassword1"); s != 400 || b != `{"error":"invalid_code"}` {
		t.Fatalf("got %d %s", s, b)
	}
}

// 10: requesting a new code kills the previous one.
func TestNewCodeInvalidatesPrevious(t *testing.T) {
	e := newPwEnv(t, &fakeCodeSender{}, nil)
	e.user("+77001000041", "oldpassword1", models.UserStatusActive)
	e.forgot("+77001000041")
	first := e.sender.last(t).Code
	e.backdateCodes("+77001000041", 2*time.Minute)
	e.forgot("+77001000041")
	second := e.sender.last(t).Code
	if first == second {
		t.Skip("two random codes collided (1 in 10^6) — nothing to compare")
	}
	if s, _ := e.reset("+77001000041", first, "newpassword1"); s != 400 {
		t.Fatalf("superseded code accepted: %d", s)
	}
	if s, _ := e.reset("+77001000041", second, "newpassword1"); s != 200 {
		t.Fatalf("current code rejected: %d", s)
	}
}

// 11: five wrong guesses kill the code — the right one no longer works.
func TestCodeDiesAfterFiveWrongAttempts(t *testing.T) {
	e := newPwEnv(t, &fakeCodeSender{}, nil)
	e.user("+77001000051", "oldpassword1", models.UserStatusActive)
	e.forgot("+77001000051")
	code := e.sender.last(t).Code
	for i := 0; i < passwordreset.MaxAttempts; i++ {
		guess := fmt.Sprintf("%06d", i)
		if guess == code {
			guess = "999999"
		}
		e.reset("+77001000051", guess, "newpassword1")
	}
	if s, b := e.reset("+77001000051", code, "newpassword1"); s != 400 || b != `{"error":"invalid_code"}` {
		t.Fatalf("code must be dead after %d wrong attempts: %d %s", passwordreset.MaxAttempts, s, b)
	}
}

// A too-short password is refused before the code is even looked at, so it
// doesn't cost an attempt.
func TestResetWeakPasswordDoesNotSpendAttempt(t *testing.T) {
	e := newPwEnv(t, &fakeCodeSender{}, nil)
	e.user("+77001000061", "oldpassword1", models.UserStatusActive)
	e.forgot("+77001000061")
	code := e.sender.last(t).Code
	for i := 0; i < passwordreset.MaxAttempts+1; i++ {
		if s, b := e.reset("+77001000061", code, "short"); s != 400 || !strings.Contains(b, "weak_password") {
			t.Fatalf("got %d %s", s, b)
		}
	}
	if s, _ := e.reset("+77001000061", code, "longenough1"); s != 200 {
		t.Fatalf("weak-password rejections must not use up the code: %d", s)
	}
}

// 14, 15, 17, 18: change with the current password; the old session dies,
// the returned one works.
func TestChangePasswordWithCurrent(t *testing.T) {
	e := newPwEnv(t, &fakeCodeSender{}, nil)
	u := e.user("+77001000071", "oldpassword1", models.UserStatusActive)
	oldToken := tokenFor(t, u.ID, time.Now().Add(-2*time.Minute))
	me := func(tok string) int {
		s, _ := e.do(req{method: "GET", path: "/api/auth/me", token: tok})
		return s
	}
	if me(oldToken) != 200 {
		t.Fatal("token should work before the change")
	}

	if s, b := e.do(req{method: "PUT", path: "/api/users/me/password", token: oldToken,
		body: map[string]string{"current_password": "wrongpassword", "new_password": "newpassword1"}}); s != 400 || b != `{"error":"wrong_current_password"}` {
		t.Fatalf("wrong current: %d %s", s, b)
	}

	s, b := e.do(req{method: "PUT", path: "/api/users/me/password", token: oldToken,
		body: map[string]string{"current_password": "oldpassword1", "new_password": "newpassword1"}})
	if s != 200 {
		t.Fatalf("change: %d %s", s, b)
	}
	var resp struct{ Token string }
	_ = json.Unmarshal([]byte(b), &resp)

	if s, body := e.do(req{method: "GET", path: "/api/auth/me", token: oldToken}); s != 401 || body != `{"error":"session_expired"}` {
		t.Fatalf("old token after change: %d %s", s, body)
	}
	if me(resp.Token) != 200 {
		t.Fatal("the token returned by the change must work")
	}
	if e.login("+77001000071", "oldpassword1") != 401 || e.login("+77001000071", "newpassword1") != 200 {
		t.Fatal("old password must fail, new must work")
	}
}

// 16: five wrong current passwords per user, then 429 — even for the right one.
func TestWrongCurrentPasswordIsRateLimited(t *testing.T) {
	e := newPwEnv(t, &fakeCodeSender{}, nil)
	u := e.user("+77001000081", "oldpassword1", models.UserStatusActive)
	tok := tokenFor(t, u.ID, time.Now().Add(-time.Minute))
	change := func(current string) (int, string) {
		return e.do(req{method: "PUT", path: "/api/users/me/password", token: tok,
			body: map[string]string{"current_password": current, "new_password": "newpassword1"}})
	}
	for i := 0; i < 5; i++ {
		if s, _ := change(fmt.Sprintf("guess%d-wrong", i)); s != 400 {
			t.Fatalf("attempt %d: got %d, want 400", i+1, s)
		}
	}
	if s, b := change("oldpassword1"); s != 429 || b != `{"error":"too_many_requests"}` {
		t.Fatalf("6th attempt: got %d %s, want 429", s, b)
	}
}

// Option B: a signed-in user changes the password with a code instead of
// the current password; a reset code can't stand in for a change code.
func TestChangePasswordWithCodeNoOldPassword(t *testing.T) {
	e := newPwEnv(t, &fakeCodeSender{}, nil)
	u := e.user("+77001000091", "forgotten-pw1", models.UserStatusActive)
	tok := tokenFor(t, u.ID, time.Now().Add(-time.Minute))

	// A "reset" code (forgot flow) is the wrong purpose here.
	e.forgot("+77001000091")
	resetCode := e.sender.last(t).Code
	if s, b := e.do(req{method: "PUT", path: "/api/users/me/password", token: tok,
		body: map[string]string{"code": resetCode, "new_password": "newpassword1"}}); s != 400 || b != `{"error":"invalid_code"}` {
		t.Fatalf("reset code used for change: %d %s", s, b)
	}

	e.backdateCodes("+77001000091", 2*time.Minute)
	s, b := e.do(req{method: "POST", path: "/api/users/me/password/code", token: tok})
	e.svc.Flush()
	if s != 200 || !strings.Contains(b, `"phone_hint":"+7 ••• ••• 00 91"`) {
		t.Fatalf("request change code: %d %s", s, b)
	}
	m := e.sender.last(t)
	if m.Purpose != models.PasswordCodePurposeChange || m.UserID != u.ID {
		t.Fatalf("wrong code sent: %+v", m)
	}
	s, b = e.do(req{method: "PUT", path: "/api/users/me/password", token: tok,
		body: map[string]string{"code": m.Code, "new_password": "newpassword1"}})
	if s != 200 || !strings.Contains(b, `"token"`) {
		t.Fatalf("change with code: %d %s", s, b)
	}
	if e.login("+77001000091", "newpassword1") != 200 {
		t.Fatal("new password must work")
	}
}

func TestChangeCodeErrorsForOwnAccount(t *testing.T) {
	e := newPwEnv(t, nil, nil) // production default: no delivery
	u := e.user("+77001000101", "oldpassword1", models.UserStatusActive)
	tok := tokenFor(t, u.ID, time.Now().Add(-time.Minute))
	if s, b := e.do(req{method: "POST", path: "/api/users/me/password/code", token: tok}); s != 503 || b != `{"error":"delivery_unavailable"}` {
		t.Fatalf("no delivery: %d %s", s, b)
	}
	// With delivery off, "unavailable" comes first even for an account
	// with no phone; phone_missing needs a working channel to matter.
	withDelivery := newPwEnv(t, &fakeCodeSender{}, nil)
	nophone := withDelivery.user("", "oldpassword1", models.UserStatusActive)
	if s, b := withDelivery.do(req{method: "POST", path: "/api/users/me/password/code", token: tokenFor(t, nophone.ID, time.Now())}); s != 409 || b != `{"error":"phone_missing"}` {
		t.Fatalf("no phone: %d %s", s, b)
	}
	if s, b := e.do(req{method: "PUT", path: "/api/users/me/password", token: tok,
		body: map[string]string{"new_password": "newpassword1"}}); s != 400 || b != `{"error":"current_password_or_code_required"}` {
		t.Fatalf("neither: %d %s", s, b)
	}
}

// 21: one code per phone per 60 s — the second request is silently dropped.
func TestForgotCooldownPerPhone(t *testing.T) {
	e := newPwEnv(t, &fakeCodeSender{}, nil)
	e.user("+77001000111", "oldpassword1", models.UserStatusActive)
	_, b1 := e.forgot("+77001000111")
	_, b2 := e.forgot("+77001000111")
	if b1 != neutralForgot || b2 != neutralForgot {
		t.Fatal("throttled request must look exactly the same")
	}
	if e.sender.count() != 1 {
		t.Fatalf("sent %d, want 1 within the cooldown", e.sender.count())
	}
	e.backdateCodes("+77001000111", 61*time.Second)
	e.forgot("+77001000111")
	if e.sender.count() != 2 {
		t.Fatal("after the cooldown a new code must go out")
	}
}

// 22: at most 5 codes per phone per hour.
func TestForgotHourlyCapPerPhone(t *testing.T) {
	e := newPwEnv(t, &fakeCodeSender{}, nil)
	e.user("+77001000121", "oldpassword1", models.UserStatusActive)
	for i := 0; i < passwordreset.MaxPerHour; i++ {
		e.forgot("+77001000121")
		e.backdateCodes("+77001000121", 2*time.Minute) // clear the cooldown, stay inside the hour
	}
	if e.sender.count() != passwordreset.MaxPerHour {
		t.Fatalf("sent %d, want %d", e.sender.count(), passwordreset.MaxPerHour)
	}
	if _, b := e.forgot("+77001000121"); b != neutralForgot {
		t.Fatal("capped request must look the same")
	}
	if e.sender.count() != passwordreset.MaxPerHour {
		t.Fatal("6th code within the hour must not be sent")
	}
	e.backdateCodes("+77001000121", time.Hour)
	e.forgot("+77001000121")
	if e.sender.count() != passwordreset.MaxPerHour+1 {
		t.Fatal("an hour later codes flow again")
	}
}

// 23: per-IP limit on the public endpoint.
func TestForgotLimitedPerIP(t *testing.T) {
	e := newPwEnv(t, &fakeCodeSender{}, nil)
	for i := 0; i < 10; i++ {
		if s, _ := e.do(req{method: "POST", path: "/api/auth/password/forgot", remote: "198.51.100.1:1000",
			body: map[string]string{"phone": fmt.Sprintf("+7700200%04d", i)}}); s != 200 {
			t.Fatalf("request %d: %d", i+1, s)
		}
	}
	if s, b := e.do(req{method: "POST", path: "/api/auth/password/forgot", remote: "198.51.100.1:1000",
		body: map[string]string{"phone": "+77002009999"}}); s != 429 || b != `{"error":"too_many_requests"}` {
		t.Fatalf("11th from same IP: %d %s", s, b)
	}
	if s, _ := e.do(req{method: "POST", path: "/api/auth/password/forgot", remote: "198.51.100.2:1000",
		body: map[string]string{"phone": "+77002009999"}}); s != 200 {
		t.Fatal("another IP has its own budget")
	}
}

// 24: X-Forwarded-For is ignored from untrusted peers, and from a trusted
// proxy only the address it appended counts — a client can't rotate its IP
// by inventing headers.
func TestSpoofedForwardedForCannotBypassIPLimit(t *testing.T) {
	e := newPwEnv(t, &fakeCodeSender{}, []string{"172.16.0.0/12"})
	forgot := func(remote, xff string) int {
		s, _ := e.do(req{method: "POST", path: "/api/auth/password/forgot", remote: remote, xff: xff,
			body: map[string]string{"phone": "+77003000000"}})
		return s
	}
	// Direct, untrusted client inventing a new X-Forwarded-For every time.
	for i := 0; i < 10; i++ {
		forgot("203.0.113.7:4000", fmt.Sprintf("10.9.9.%d", i))
	}
	if s := forgot("203.0.113.7:4000", "10.9.9.200"); s != 429 {
		t.Fatalf("untrusted peer bypassed the limit with X-Forwarded-For: %d", s)
	}
	// Through the trusted proxy: client-supplied left part varies, the
	// address the proxy appended (the real client) doesn't.
	for i := 0; i < 10; i++ {
		forgot("172.18.0.1:4000", fmt.Sprintf("6.6.6.%d, 198.51.100.9", i))
	}
	if s := forgot("172.18.0.1:4000", "6.6.6.250, 198.51.100.9"); s != 429 {
		t.Fatalf("spoofed left-hand X-Forwarded-For bypassed the limit: %d", s)
	}
	// …while a genuinely different client behind the same proxy is fine.
	if s := forgot("172.18.0.1:4000", "198.51.100.10"); s != 200 {
		t.Fatalf("other real client: %d", s)
	}
}

// 20: nothing secret ever reaches the log.
func TestPasswordFlowsNeverLogSecrets(t *testing.T) {
	var logs syncBuffer
	orig := log.Writer()
	log.SetOutput(&logs)
	t.Cleanup(func() { log.SetOutput(orig) })

	e := newPwEnv(t, &fakeCodeSender{}, nil)
	u := e.user("+77001000131", "oldpassword1", models.UserStatusActive)
	e.forgot("+77001000131")
	code := e.sender.last(t).Code
	e.reset("+77001000131", "000001", "newpassword1")
	e.reset("+77001000131", code, "newpassword1")
	tok := tokenFor(t, u.ID, time.Now())
	e.do(req{method: "PUT", path: "/api/users/me/password", token: tok,
		body: map[string]string{"current_password": "wrong-pass-1", "new_password": "newpassword2"}})
	s, b := e.do(req{method: "PUT", path: "/api/users/me/password", token: tok,
		body: map[string]string{"current_password": "newpassword1", "new_password": "newpassword2"}})
	if s != 200 {
		t.Fatalf("change: %d %s", s, b)
	}
	var resp struct{ Token string }
	_ = json.Unmarshal([]byte(b), &resp)
	var stored models.User
	e.db.First(&stored, u.ID)
	var row models.PasswordResetCode
	e.db.Where("user_id = ?", u.ID).First(&row)

	out := logs.String()
	if !strings.Contains(out, fmt.Sprintf("user #%d", u.ID)) {
		t.Fatalf("expected user-id-only log lines, got:\n%s", out)
	}
	for name, secret := range map[string]string{
		"code": code, "old password": "oldpassword1", "new password": "newpassword1",
		"newer password": "newpassword2", "wrong password": "wrong-pass-1",
		"password hash": stored.PasswordHash, "code hash": row.CodeHash,
		"phone": "77001000131", "jwt": tok, "new jwt": resp.Token,
	} {
		if secret != "" && strings.Contains(out, secret) {
			t.Errorf("log contains the %s:\n%s", name, out)
		}
	}
}

// The codes table never holds a code in the clear.
func TestCodeStoredOnlyAsHash(t *testing.T) {
	e := newPwEnv(t, &fakeCodeSender{}, nil)
	e.user("+77001000141", "oldpassword1", models.UserStatusActive)
	e.forgot("+77001000141")
	code := e.sender.last(t).Code
	var row models.PasswordResetCode
	e.db.First(&row)
	if row.CodeHash == code || strings.Contains(row.CodeHash, code) || len(row.CodeHash) != 64 {
		t.Fatalf("stored %q for code %q", row.CodeHash, code)
	}
	if !row.ExpiresAt.After(time.Now().Add(9*time.Minute)) || row.ExpiresAt.After(time.Now().Add(11*time.Minute)) {
		t.Fatalf("expiry %v is not ~10 minutes out", row.ExpiresAt)
	}
}

// Concurrent requests for one account never leave two live codes, and the
// database itself refuses a second live code for the same user/purpose.
func TestAtMostOneLiveCode(t *testing.T) {
	e := newPwEnv(t, &fakeCodeSender{}, nil)
	u := e.user("+77001000151", "oldpassword1", models.UserStatusActive)
	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			e.do(req{method: "POST", path: "/api/auth/password/forgot", remote: fmt.Sprintf("198.51.100.%d:1", 50+i),
				body: map[string]string{"phone": "+77001000151"}})
		}(i)
	}
	wg.Wait()
	e.svc.Flush()
	var live int64
	e.db.Model(&models.PasswordResetCode{}).Where("user_id = ? AND used_at IS NULL AND invalidated_at IS NULL", u.ID).Count(&live)
	if live != 1 {
		t.Fatalf("%d live codes, want 1", live)
	}
	dup := models.PasswordResetCode{UserID: u.ID, PhoneNormalized: "+77001000151", Purpose: models.PasswordCodePurposeReset,
		CodeHash: strings.Repeat("0", 64), ExpiresAt: time.Now().Add(time.Minute)}
	if err := e.db.Create(&dup).Error; err == nil {
		t.Fatal("the partial unique index must refuse a second live code")
	}
}
