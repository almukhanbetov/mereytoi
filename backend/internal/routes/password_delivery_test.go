package routes_test

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/config"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
	"github.com/almukhanbetov/mereytoi/backend/internal/passwordreset"
	"github.com/almukhanbetov/mereytoi/backend/internal/routes"
)

const (
	waToken  = "EAAG-test-access-token"
	waPhone  = "1234567890"
	waTpl    = "mereytoi_password_code"
	otpHMAC  = "0123456789abcdef0123456789abcdef-test"
	pathCode = "/v21.0/" + waPhone + "/messages"
)

// metaStub stands in for graph.facebook.com: answers status after delay
// and keeps every request body.
type metaStub struct {
	mu     sync.Mutex
	bodies []string
	status int
	delay  time.Duration
}

func newMetaStub(t *testing.T, status int, delay time.Duration) (*metaStub, *httptest.Server) {
	m := &metaStub{status: status, delay: delay}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		raw, _ := io.ReadAll(r.Body)
		m.mu.Lock()
		m.bodies = append(m.bodies, string(raw))
		m.mu.Unlock()
		if r.URL.Path != pathCode || r.Header.Get("Authorization") != "Bearer "+waToken {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		select {
		case <-time.After(m.delay):
		case <-r.Context().Done():
			return
		}
		w.WriteHeader(m.status)
	}))
	t.Cleanup(srv.Close)
	return m, srv
}

func (m *metaStub) body(i int) string {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.bodies[i]
}

func (m *metaStub) count() int {
	m.mu.Lock()
	defer m.mu.Unlock()
	return len(m.bodies)
}

// syncBuffer is a log sink the test can read while background delivery
// workers are still writing to it.
type syncBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *syncBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *syncBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.String()
}

// waitFor polls cond for up to 3 s (background delivery has no other
// completion signal on the production wiring).
func waitFor(t *testing.T, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for %s", what)
}

// codeFrom pulls the OTP out of a captured Graph API request body.
func codeFrom(t *testing.T, body string) string {
	t.Helper()
	var p struct {
		Template struct {
			Components []struct {
				Parameters []struct{ Text string }
			}
		}
	}
	if err := json.Unmarshal([]byte(body), &p); err != nil || len(p.Template.Components) == 0 {
		t.Fatalf("unexpected body %s", body)
	}
	return p.Template.Components[0].Parameters[0].Text
}

func readyConfig(metaURL string) config.Config {
	return config.Config{
		JWTSecret:                    pwSecret,
		WhatsAppBaseURL:              metaURL,
		WhatsAppAccessToken:          waToken,
		WhatsAppPhoneNumberID:        waPhone,
		WhatsAppOTPTemplateName:      waTpl,
		WhatsAppOTPTemplateLanguage:  "ru",
		OTPHMACSecret:                otpHMAC,
		PasswordResetDeliveryEnabled: true,
	}
}

// prodEnv is the production wiring: the service is built from cfg.
func prodEnv(t *testing.T, cfg config.Config) *pwEnv {
	t.Helper()
	gin.SetMode(gin.TestMode)
	pwDBSeq++
	db, err := gorm.Open(sqlite.Open(fmt.Sprintf("file:pwdeliv%d?mode=memory&cache=shared", pwDBSeq)), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(&models.User{}, &models.PasswordResetCode{}); err != nil {
		t.Fatal(err)
	}
	r := gin.New()
	routes.RegisterWithOptions(r, db, cfg, routes.Options{})
	return &pwEnv{t: t, r: r, db: db}
}

func (e *pwEnv) resetAvailable() string {
	_, body := e.do(req{method: "GET", path: "/api/auth/password/config"})
	return body
}

func (e *pwEnv) liveCodes() int64 {
	var n int64
	e.db.Model(&models.PasswordResetCode{}).Where("used_at IS NULL AND invalidated_at IS NULL").Count(&n)
	return n
}

// 4, 5, 6 (+ disabled, short secret): the config endpoint is exactly one
// boolean, true only for a complete configuration.
func TestPasswordConfigEndpoint(t *testing.T) {
	_, meta := newMetaStub(t, 200, 0)
	full := readyConfig(meta.URL)
	cases := map[string]struct {
		mutate func(*config.Config)
		want   string
	}{
		"valid":            {func(*config.Config) {}, `{"reset_available":true}`},
		"disabled":         {func(c *config.Config) { c.PasswordResetDeliveryEnabled = false }, `{"reset_available":false}`},
		"missing template": {func(c *config.Config) { c.WhatsAppOTPTemplateName = "" }, `{"reset_available":false}`},
		"missing token":    {func(c *config.Config) { c.WhatsAppAccessToken = "" }, `{"reset_available":false}`},
		"missing phone id": {func(c *config.Config) { c.WhatsAppPhoneNumberID = "" }, `{"reset_available":false}`},
		"short hmac":       {func(c *config.Config) { c.OTPHMACSecret = "too-short" }, `{"reset_available":false}`},
		"no hmac":          {func(c *config.Config) { c.OTPHMACSecret = "" }, `{"reset_available":false}`},
	}
	for name, tc := range cases {
		cfg := full
		tc.mutate(&cfg)
		body := prodEnv(t, cfg).resetAvailable()
		if body != tc.want {
			t.Errorf("%s: got %s, want %s", name, body, tc.want)
		}
		for _, secret := range []string{waToken, waPhone, waTpl, otpHMAC} {
			if strings.Contains(body, secret) {
				t.Errorf("%s: config response leaks %q", name, secret)
			}
		}
	}
}

// 3: delivery switched off (everything else configured) — Meta is never
// called and no code is created.
func TestDeliveryDisabledSendsNothing(t *testing.T) {
	meta, srv := newMetaStub(t, 200, 0)
	cfg := readyConfig(srv.URL)
	cfg.PasswordResetDeliveryEnabled = false
	e := prodEnv(t, cfg)
	e.user("+77004000001", "oldpassword1", models.UserStatusActive)
	if _, b := e.do(req{method: "POST", path: "/api/auth/password/forgot", body: map[string]string{"phone": "+77004000001"}}); b != neutralForgot {
		t.Fatalf("got %s", b)
	}
	time.Sleep(200 * time.Millisecond)
	var rows int64
	e.db.Model(&models.PasswordResetCode{}).Count(&rows)
	if meta.count() != 0 || rows != 0 {
		t.Fatalf("disabled delivery: %d Meta calls, %d codes", meta.count(), rows)
	}
}

// End to end on the production wiring: the code arrives through the OTP
// template and resets the password.
func TestWhatsAppDeliveryEndToEnd(t *testing.T) {
	meta, srv := newMetaStub(t, 200, 0)
	e := prodEnv(t, readyConfig(srv.URL))
	e.user("+77004000011", "oldpassword1", models.UserStatusActive)
	e.do(req{method: "POST", path: "/api/auth/password/forgot", body: map[string]string{"phone": "+77004000011"}})
	waitFor(t, "the OTP request to Meta", func() bool { return meta.count() == 1 })

	body := meta.body(0)
	if !strings.Contains(body, `"name":"`+waTpl+`"`) || !strings.Contains(body, `"sub_type":"url"`) || !strings.Contains(body, `"to":"77004000011"`) {
		t.Fatalf("not the OTP template payload: %s", body)
	}
	code := codeFrom(t, body)
	if s, b := e.reset("+77004000011", code, "newpassword1"); s != 200 {
		t.Fatalf("reset with delivered code: %d %s", s, b)
	}
	if e.login("+77004000011", "newpassword1") != 200 {
		t.Fatal("new password must work")
	}
}

// 12: Meta refuses (4xx, no retry) → the code is invalidated, so even the
// code itself (as Meta saw it) no longer works.
func TestFailedDeliveryInvalidatesCode(t *testing.T) {
	meta, srv := newMetaStub(t, 400, 0)
	e := prodEnv(t, readyConfig(srv.URL))
	e.user("+77004000021", "oldpassword1", models.UserStatusActive)
	e.do(req{method: "POST", path: "/api/auth/password/forgot", body: map[string]string{"phone": "+77004000021"}})
	waitFor(t, "the failed send", func() bool { return meta.count() == 1 })
	waitFor(t, "the code to be invalidated", func() bool {
		var n int64
		e.db.Model(&models.PasswordResetCode{}).Where("invalidated_at IS NOT NULL").Count(&n)
		return n == 1
	})
	if e.liveCodes() != 0 {
		t.Fatal("an undelivered code is still live")
	}
	if s, _ := e.reset("+77004000021", codeFrom(t, meta.body(0)), "newpassword1"); s != 400 {
		t.Fatalf("undelivered code accepted: %d", s)
	}
	time.Sleep(100 * time.Millisecond)
	if meta.count() != 1 {
		t.Fatalf("400 must not be retried, got %d calls", meta.count())
	}
}

// 13: with Meta taking 1.5 s, forgot-password still answers at once — for
// a known number exactly as for an unknown one.
func TestForgotDoesNotWaitForMeta(t *testing.T) {
	meta, srv := newMetaStub(t, 200, 1500*time.Millisecond)
	e := prodEnv(t, readyConfig(srv.URL))
	e.user("+77004000031", "oldpassword1", models.UserStatusActive)

	timeIt := func(phone string) (time.Duration, string) {
		start := time.Now()
		_, body := e.do(req{method: "POST", path: "/api/auth/password/forgot", body: map[string]string{"phone": phone}})
		return time.Since(start), body
	}
	known, kb := timeIt("+77004000031")
	unknown, ub := timeIt("+77004009999")
	if kb != neutralForgot || ub != neutralForgot {
		t.Fatalf("bodies differ: %s / %s", kb, ub)
	}
	if known > 200*time.Millisecond || unknown > 200*time.Millisecond {
		t.Fatalf("response waited: known %v, unknown %v", known, unknown)
	}
	waitFor(t, "the background send", func() bool { return meta.count() == 1 })
}

// 14: a sender that panics or errors never takes the backend down, and the
// code it was carrying is invalidated.
type panicSender struct{}

func (panicSender) SendPasswordResetCode(context.Context, passwordreset.CodeMessage) error {
	panic("boom: provider exploded")
}

func TestSenderPanicIsContained(t *testing.T) {
	var logs syncBuffer
	orig := log.Writer()
	log.SetOutput(&logs)
	t.Cleanup(func() { log.SetOutput(orig) })

	gin.SetMode(gin.TestMode)
	pwDBSeq++
	db, _ := gorm.Open(sqlite.Open(fmt.Sprintf("file:pwpanic%d?mode=memory&cache=shared", pwDBSeq)), &gorm.Config{})
	_ = db.AutoMigrate(&models.User{}, &models.PasswordResetCode{})
	svc := passwordreset.New(db, panicSender{}, "", pwSecret)
	r := gin.New()
	routes.RegisterWithOptions(r, db, config.Config{JWTSecret: pwSecret}, routes.Options{PasswordReset: svc})
	e := &pwEnv{t: t, r: r, db: db, svc: svc}
	u := e.user("+77004000041", "oldpassword1", models.UserStatusActive)

	for i := 0; i < 3; i++ {
		e.backdateCodes("+77004000041", 2*time.Minute)
		if s, b := e.forgot("+77004000041"); s != 200 || b != neutralForgot {
			t.Fatalf("after a panicking send: %d %s", s, b)
		}
	}
	if e.liveCodes() != 0 {
		t.Fatal("codes from panicked sends must be invalidated")
	}
	// The change flow, too — and the server keeps serving.
	e.backdateCodes("+77004000041", 2*time.Minute) // past the per-phone cooldown
	tok := tokenFor(t, u.ID, time.Now())
	if s, _ := e.do(req{method: "POST", path: "/api/users/me/password/code", token: tok}); s != 200 {
		t.Fatalf("change code: %d", s)
	}
	e.svc.Flush()
	if e.liveCodes() != 0 {
		t.Fatal("change code from a panicked send must be invalidated")
	}
	if strings.Contains(logs.String(), "boom") {
		t.Fatal("the panic value must not be logged")
	}
}

// 15: across real-shaped sends (success and failure), the log holds no
// code, phone, access token, template payload or HMAC secret.
func TestDeliveryLogsHoldNoSecrets(t *testing.T) {
	var logs syncBuffer
	orig := log.Writer()
	log.SetOutput(&logs)
	t.Cleanup(func() { log.SetOutput(orig) })

	okMeta, okSrv := newMetaStub(t, 200, 0)
	e := prodEnv(t, readyConfig(okSrv.URL))
	e.user("+77004000051", "oldpassword1", models.UserStatusActive)
	e.do(req{method: "POST", path: "/api/auth/password/forgot", body: map[string]string{"phone": "+77004000051"}})
	waitFor(t, "send", func() bool { return okMeta.count() == 1 })

	badMeta, badSrv := newMetaStub(t, 500, 0)
	f := prodEnv(t, readyConfig(badSrv.URL))
	f.user("+77004000052", "oldpassword1", models.UserStatusActive)
	f.do(req{method: "POST", path: "/api/auth/password/forgot", body: map[string]string{"phone": "+77004000052"}})
	waitFor(t, "retry", func() bool { return badMeta.count() == 2 })
	waitFor(t, "failure logged", func() bool { return strings.Contains(logs.String(), "provider_5xx") })

	out := logs.String()
	for name, secret := range map[string]string{
		"code": codeFrom(t, okMeta.body(0)), "failed code": codeFrom(t, badMeta.body(0)),
		"phone": "77004000051", "other phone": "77004000052",
		"access token": waToken, "hmac secret": otpHMAC, "template name": waTpl,
		"payload": `"messaging_product"`, "meta url": okSrv.URL,
	} {
		if strings.Contains(out, secret) {
			t.Errorf("log contains the %s:\n%s", name, out)
		}
	}
	if !strings.Contains(out, "code sent to user #") || !strings.Contains(out, "not delivered: provider_5xx") {
		t.Fatalf("expected outcome lines, got:\n%s", out)
	}
}
