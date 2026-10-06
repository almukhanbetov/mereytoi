package routes_test

import (
	"fmt"
	"net/http"
	"testing"
	"time"

	"golang.org/x/crypto/bcrypt"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// account creates a user with exactly the stored phone/phone_normalized
// given (rows created before phone_normalized existed have it empty).
func (e *pwEnv) account(phone, normalized, password, status string) models.User {
	e.t.Helper()
	hash, _ := bcrypt.GenerateFromPassword([]byte(password), bcrypt.MinCost)
	u := models.User{
		Name: "L", Email: fmt.Sprintf("l%d@test.local", time.Now().UnixNano()),
		Phone: phone, PhoneNormalized: normalized, PasswordHash: string(hash), Role: "user", Status: status,
	}
	if err := e.db.Create(&u).Error; err != nil {
		e.t.Fatal(err)
	}
	return u
}

// Every spelling of the same Kazakhstani number signs in to the same
// account — whatever spelling it was registered with.
func TestLoginAcceptsEverySpellingOfTheNumber(t *testing.T) {
	e := newPwEnv(t, &fakeCodeSender{}, nil)
	// Registered as "8 …" (stored raw without spaces), normalized to +7.
	e.account("87000000201", "+77000000201", "rightpassword", models.UserStatusActive)

	for _, spelling := range []string{
		"+77000000201",     // canonical
		"87000000201",      // 8 format
		"8 700 000 02 01",  // 8 with spaces
		"+7 700 000 02 01", // +7 with spaces
		"77000000201",      // no plus
		"+7 (700) 000-02-01",
	} {
		if s := e.login(spelling, "rightpassword"); s != http.StatusOK {
			t.Errorf("%q + right password: %d, want 200", spelling, s)
		}
		if s := e.login(spelling, "wrongpassword"); s != http.StatusUnauthorized {
			t.Errorf("%q + wrong password: %d, want 401", spelling, s)
		}
	}
}

func TestLoginRejectsMalformedOrUnknownNumbers(t *testing.T) {
	e := newPwEnv(t, &fakeCodeSender{}, nil)
	e.account("+77000000211", "+77000000211", "rightpassword", models.UserStatusActive)
	for _, phone := range []string{"12345", "abc", "+7 700", "+77000000212", "+7700000021100"} {
		s, b := e.do(req{method: "POST", path: "/api/auth/login",
			body: map[string]string{"phone": phone, "password": "rightpassword"}})
		if s != http.StatusUnauthorized || b != `{"error":"invalid credentials"}` {
			t.Errorf("%q: got %d %s, want the plain 401", phone, s, b)
		}
	}
}

// Two active accounts on one number: neither is picked, both get the same
// 401 as a wrong password.
func TestLoginNeverPicksBetweenDuplicateAccounts(t *testing.T) {
	e := newPwEnv(t, &fakeCodeSender{}, nil)
	e.account("+77000000221", "+77000000221", "firstpassword", models.UserStatusActive)
	e.account("87000000221", "+77000000221", "secondpassword", models.UserStatusActive)
	for _, pw := range []string{"firstpassword", "secondpassword"} {
		if s, b := e.do(req{method: "POST", path: "/api/auth/login",
			body: map[string]string{"phone": "+77000000221", "password": pw}}); s != 401 || b != `{"error":"invalid credentials"}` {
			t.Errorf("duplicate number, %s: got %d %s", pw, s, b)
		}
	}
	// A legacy row with the same raw number counts as a duplicate too.
	f := newPwEnv(t, &fakeCodeSender{}, nil)
	f.account("+77000000222", "+77000000222", "newpassword1", models.UserStatusActive)
	f.account("+77000000222", "", "legacypass1", models.UserStatusActive)
	if s := f.login("+77000000222", "newpassword1"); s != 401 {
		t.Errorf("normalized + legacy duplicate must not authenticate: %d", s)
	}
}

// A pending (onboarding) account on the same number doesn't make the
// active one ambiguous — pending accounts never sign in with a password.
func TestLoginIgnoresPendingAccounts(t *testing.T) {
	e := newPwEnv(t, &fakeCodeSender{}, nil)
	e.account("+77000000231", "+77000000231", "activepassword", models.UserStatusActive)
	e.account("+77000000231", "+77000000231", "pendingpassword", models.UserStatusPending)
	if s := e.login("8 700 000 02 31", "activepassword"); s != 200 {
		t.Fatalf("active account: %d", s)
	}
	if s := e.login("+77000000231", "pendingpassword"); s != 401 {
		t.Fatalf("pending account must not sign in: %d", s)
	}
}

// Legacy rows (phone_normalized empty): exactly the old behaviour — the
// stored phone, spaces removed, must match — and nothing looser.
func TestLoginLegacyRowsKeepExactRawMatch(t *testing.T) {
	e := newPwEnv(t, &fakeCodeSender{}, nil)
	e.account("+77000000241", "", "legacypass1", models.UserStatusActive)
	if s := e.login("+77000000241", "legacypass1"); s != 200 {
		t.Errorf("exact stored spelling: %d, want 200", s)
	}
	if s := e.login("+7 700 000 02 41", "legacypass1"); s != 200 {
		t.Errorf("same spelling with spaces: %d, want 200", s)
	}
	// Documented limitation until the row gets phone_normalized (profile
	// save or a future backfill): another spelling doesn't reach it.
	if s := e.login("87000000241", "legacypass1"); s != 401 {
		t.Errorf("other spelling of a legacy row: %d, want 401", s)
	}
	// Non-Kazakhstani numbers never get phone_normalized; they keep working.
	e.account("+12025550100", "", "foreignpass1", models.UserStatusActive)
	if s := e.login("+1 202 555 0100", "foreignpass1"); s != 200 {
		t.Errorf("foreign number: %d, want 200 (no regression)", s)
	}
}

func TestLoginByEmailUnchanged(t *testing.T) {
	e := newPwEnv(t, &fakeCodeSender{}, nil)
	u := e.account("+77000000251", "+77000000251", "emailpass1", models.UserStatusActive)
	s, _ := e.do(req{method: "POST", path: "/api/auth/login",
		body: map[string]string{"email": u.Email, "password": "emailpass1"}})
	if s != 200 {
		t.Fatalf("email login: %d", s)
	}
}

// The QA finding itself: reset with one spelling, sign in with any other —
// new password works everywhere, the old one nowhere.
func TestPasswordResetThenLoginWithAnySpelling(t *testing.T) {
	e := newPwEnv(t, &fakeCodeSender{}, nil)
	e.account("+77000000101", "+77000000101", "oldpassword1", models.UserStatusActive)
	e.forgot("8 700 000 01 01")
	if s, b := e.reset("87000000101", e.sender.last(t).Code, "newpassword1"); s != 200 {
		t.Fatalf("reset: %d %s", s, b)
	}
	for _, spelling := range []string{"+77000000101", "87000000101", "8 700 000 01 01", "+7 700 000 01 01"} {
		if s := e.login(spelling, "newpassword1"); s != 200 {
			t.Errorf("%q + new password: %d, want 200", spelling, s)
		}
		if s := e.login(spelling, "oldpassword1"); s != 401 {
			t.Errorf("%q + old password: %d, want 401", spelling, s)
		}
	}
}
