package routes_test

import (
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// loginToken signs in through the real endpoint and returns the session.
func (e *pwEnv) loginToken(phone, password string) string {
	e.t.Helper()
	s, b := e.do(req{method: "POST", path: "/api/auth/login",
		body: map[string]string{"phone": phone, "password": password}})
	if s != http.StatusOK {
		e.t.Fatalf("login %s: %d %s", phone, s, b)
	}
	var out struct{ Token string }
	_ = json.Unmarshal([]byte(b), &out)
	return out.Token
}

func (e *pwEnv) me(token string) (int, string) {
	return e.do(req{method: "GET", path: "/api/auth/me", token: token})
}

// A. Forgot password: active user → code → reset → old password out, new in.
func TestE2EForgotPassword(t *testing.T) {
	e := newPwEnv(t, &fakeCodeSender{}, nil)
	e.account("+77000000501", "+77000000501", "oldpassword1", models.UserStatusActive)
	if _, b := e.forgot("8 700 000 05 01"); b != neutralForgot {
		t.Fatalf("forgot: %s", b)
	}
	if s, b := e.reset("+77000000501", e.sender.last(t).Code, "newpassword1"); s != 200 {
		t.Fatalf("reset: %d %s", s, b)
	}
	if e.login("87000000501", "oldpassword1") != 401 || e.login("87000000501", "newpassword1") != 200 {
		t.Fatal("old password must fail, new must work")
	}
}

// B. Change password with the current one: old session dies, the returned
// one works, the new password signs in.
func TestE2EChangePasswordWithCurrent(t *testing.T) {
	e := newPwEnv(t, &fakeCodeSender{}, nil)
	e.account("+77000000502", "+77000000502", "oldpassword1", models.UserStatusActive)
	oldToken := e.loginToken("+77000000502", "oldpassword1")
	time.Sleep(1100 * time.Millisecond) // the change happens in a later second than the login
	s, b := e.do(req{method: "PUT", path: "/api/users/me/password", token: oldToken,
		body: map[string]string{"current_password": "oldpassword1", "new_password": "newpassword1"}})
	if s != 200 {
		t.Fatalf("change: %d %s", s, b)
	}
	var out struct{ Token string }
	_ = json.Unmarshal([]byte(b), &out)
	if s, b := e.me(oldToken); s != 401 || b != `{"error":"session_expired"}` {
		t.Fatalf("old JWT: %d %s", s, b)
	}
	if s, _ := e.me(out.Token); s != 200 {
		t.Fatalf("new JWT: %d", s)
	}
	if e.login("+7 700 000 05 02", "newpassword1") != 200 || e.login("+77000000502", "oldpassword1") != 401 {
		t.Fatal("new password must work, old must fail")
	}
}

// C. Change password with a code: same session behaviour.
func TestE2EChangePasswordWithCode(t *testing.T) {
	e := newPwEnv(t, &fakeCodeSender{}, nil)
	e.account("+77000000503", "+77000000503", "forgotten-pw1", models.UserStatusActive)
	oldToken := e.loginToken("87000000503", "forgotten-pw1")
	time.Sleep(1100 * time.Millisecond)
	if s, b := e.do(req{method: "POST", path: "/api/users/me/password/code", token: oldToken}); s != 200 {
		t.Fatalf("code: %d %s", s, b)
	}
	e.svc.Flush()
	s, b := e.do(req{method: "PUT", path: "/api/users/me/password", token: oldToken,
		body: map[string]string{"code": e.sender.last(t).Code, "new_password": "newpassword1"}})
	if s != 200 {
		t.Fatalf("change by code: %d %s", s, b)
	}
	var out struct{ Token string }
	_ = json.Unmarshal([]byte(b), &out)
	if s, _ := e.me(oldToken); s != 401 {
		t.Fatalf("old JWT: %d", s)
	}
	if s, _ := e.me(out.Token); s != 200 {
		t.Fatalf("new JWT: %d", s)
	}
	if e.login("+77000000503", "newpassword1") != 200 {
		t.Fatal("new password must work")
	}
}

// D. A pending (onboarding) account can't change its password at all —
// not with a password, not with a code, and can't even ask for a code.
func TestE2EPendingAccountCannotChangePassword(t *testing.T) {
	e := newPwEnv(t, &fakeCodeSender{}, nil)
	u := e.account("+77000000504", "+77000000504", "somepassword", models.UserStatusPending)
	tok := tokenFor(t, u.ID, time.Now())

	if s, b := e.do(req{method: "POST", path: "/api/users/me/password/code", token: tok}); s != 403 || b != `{"error":"not_allowed"}` {
		t.Fatalf("pending code request: %d %s", s, b)
	}
	e.svc.Flush()
	if e.sender.count() != 0 {
		t.Fatal("no code may be sent for a pending account")
	}
	for name, body := range map[string]map[string]string{
		"current": {"current_password": "somepassword", "new_password": "newpassword1"},
		"code":    {"code": "123456", "new_password": "newpassword1"},
	} {
		if s, b := e.do(req{method: "PUT", path: "/api/users/me/password", token: tok, body: body}); s != 403 || b != `{"error":"not_allowed"}` {
			t.Fatalf("pending change by %s: %d %s", name, s, b)
		}
	}
	var after models.User
	e.db.First(&after, u.ID)
	if after.PasswordChangedAt != nil || after.Status != models.UserStatusPending {
		t.Fatal("pending account must be left exactly as it was")
	}
	// Forgot password stays silent for it, too.
	if _, b := e.forgot("+77000000504"); b != neutralForgot || e.sender.count() != 0 {
		t.Fatal("forgot password must not reach a pending account")
	}
	// And refused attempts don't count as wrong-password guesses.
	for i := 0; i < 6; i++ {
		e.do(req{method: "PUT", path: "/api/users/me/password", token: tok,
			body: map[string]string{"current_password": "x", "new_password": "newpassword1"}})
	}
	if s, _ := e.do(req{method: "PUT", path: "/api/users/me/password", token: tok,
		body: map[string]string{"current_password": "x", "new_password": "newpassword1"}}); s != 403 {
		t.Fatalf("still a plain refusal, not a rate limit: %d", s)
	}
}

// E + F. Unknown and duplicated numbers: neutral forgot answer, no send,
// no login, no reset.
func TestE2EUnknownAndDuplicateNumbers(t *testing.T) {
	e := newPwEnv(t, &fakeCodeSender{}, nil)
	e.account("+77000000505", "+77000000505", "firstpassword", models.UserStatusActive)
	e.account("87000000505", "+77000000505", "secondpassword", models.UserStatusActive)
	for _, phone := range []string{"+77000000599", "+77000000505"} {
		if _, b := e.forgot(phone); b != neutralForgot {
			t.Fatalf("%s: %s", phone, b)
		}
	}
	if e.sender.count() != 0 {
		t.Fatal("no code for an unknown or ambiguous number")
	}
	if s, _ := e.reset("+77000000505", "123456", "newpassword1"); s != 400 {
		t.Fatalf("reset on ambiguous number: %d", s)
	}
	if e.login("+77000000505", "firstpassword") != 401 || e.login("+77000000505", "secondpassword") != 401 {
		t.Fatal("ambiguous number must not sign anyone in")
	}
}
