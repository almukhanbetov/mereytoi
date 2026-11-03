package routes_test

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/driver/postgres"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/config"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
	"github.com/almukhanbetov/mereytoi/backend/internal/recoverycode"
	"github.com/almukhanbetov/mereytoi/backend/internal/routes"
)

const recSecret = "recovery-test-secret"

type recEnv struct {
	t  *testing.T
	r  *gin.Engine
	db *gorm.DB
}

var recDBSeq int

func newRecEnvOn(t *testing.T, db *gorm.DB, trusted []string) *recEnv {
	t.Helper()
	gin.SetMode(gin.TestMode)
	if err := db.AutoMigrate(&models.User{}, &models.PasswordResetCode{}, &models.RecoveryAttempt{}); err != nil {
		t.Fatal(err)
	}
	r := gin.New()
	routes.RegisterWithOptions(r, db, config.Config{JWTSecret: recSecret, TrustedProxies: trusted}, routes.Options{})
	return &recEnv{t: t, r: r, db: db}
}

func newRecEnv(t *testing.T, trusted []string) *recEnv {
	t.Helper()
	recDBSeq++
	db, err := gorm.Open(sqlite.Open(fmt.Sprintf("file:recovery%d?mode=memory&cache=shared", recDBSeq)), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	// In-memory SQLite answers concurrent writers with "database is locked"
	// (which the limiter, failing closed, would turn into 429s): one
	// connection serializes them. Real concurrency is covered by the
	// *Postgres tests.
	sqlDB, err := db.DB()
	if err != nil {
		t.Fatal(err)
	}
	sqlDB.SetMaxOpenConns(1)
	return newRecEnvOn(t, db, trusted)
}

type recReq struct {
	method, path string
	body         any
	token        string
	remote       string
	xff          string
}

func (e *recEnv) do(q recReq) (int, map[string]any, http.Header) {
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
	out := map[string]any{}
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	return rec.Code, out, rec.Header()
}

type regResult struct {
	id    uint
	token string
	code  string
}

func (e *recEnv) register(email, phone, password string) regResult {
	e.t.Helper()
	st, out, hdr := e.do(recReq{method: "POST", path: "/api/auth/register",
		body: map[string]string{"name": "R", "email": email, "phone": phone, "password": password}})
	if st != http.StatusCreated {
		e.t.Fatalf("register: %d %v", st, out)
	}
	if hdr.Get("Cache-Control") != "no-store" {
		e.t.Fatalf("register response is cacheable: %q", hdr.Get("Cache-Control"))
	}
	code, _ := out["recovery_code"].(string)
	user := out["user"].(map[string]any)
	return regResult{id: uint(user["id"].(float64)), token: out["token"].(string), code: code}
}

func (e *recEnv) recover(login, code, newPassword string, opt ...recReq) (int, map[string]any) {
	e.t.Helper()
	q := recReq{method: "POST", path: "/api/auth/recovery/reset",
		body: map[string]string{"login": login, "code": code, "new_password": newPassword}}
	if len(opt) > 0 {
		q.remote, q.xff = opt[0].remote, opt[0].xff
	}
	st, out, hdr := e.do(q)
	if hdr.Get("Cache-Control") != "no-store" {
		e.t.Fatalf("recovery response is cacheable")
	}
	return st, out
}

func (e *recEnv) login(email, password string) int {
	st, _, _ := e.do(recReq{method: "POST", path: "/api/auth/login", body: map[string]string{"email": email, "password": password}})
	return st
}

func (e *recEnv) me(token string) (int, map[string]any) {
	st, out, _ := e.do(recReq{method: "GET", path: "/api/auth/me", token: token})
	return st, out
}

func TestRegistrationIssuesBackupCodeStoredOnlyAsHash(t *testing.T) {
	e := newRecEnv(t, nil)
	r := e.register("a@test.local", "+7 700 111 22 33", "secret12")
	canonical, ok := recoverycode.Normalize(r.code)
	if !ok || strings.Count(r.code, "-") != 6 {
		t.Fatalf("code %q not a grouped 28-symbol code", r.code)
	}
	var u models.User
	e.db.First(&u, r.id)
	if u.RecoveryCodeHash != recoverycode.Hash(canonical) || u.RecoveryCodeCreatedAt == nil {
		t.Fatal("hash not stored")
	}
	// The code itself appears nowhere in the row.
	row := map[string]any{}
	e.db.Model(&models.User{}).Where("id = ?", r.id).Take(&row)
	if strings.Contains(fmt.Sprint(row), canonical) || strings.Contains(fmt.Sprint(row), r.code) {
		t.Fatal("plaintext code stored")
	}
	st, me := e.me(r.token)
	if st != 200 || me["has_recovery_code"] != true {
		t.Fatalf("/me: %d %v", st, me)
	}
	if _, leaked := me["recovery_code"]; leaked {
		t.Fatal("/me exposes the code")
	}
}

func TestRecoverWithCodeSetsPasswordRotatesCodeAndRevokesSessions(t *testing.T) {
	e := newRecEnv(t, nil)
	r := e.register("b@test.local", "+7 700 222 33 44", "oldpass1")
	// Sessions are compared by whole seconds; make the old one strictly older.
	time.Sleep(1100 * time.Millisecond)

	// Typed differently from how it was shown: phone with 8, code in lower case.
	st, out := e.recover("8 700 222 33 44", strings.ToLower(r.code), "NewPass123")
	if st != 200 {
		t.Fatalf("recover: %d %v", st, out)
	}
	newCode, _ := out["recovery_code"].(string)
	newToken, _ := out["token"].(string)
	if newCode == "" || newCode == r.code || newToken == "" {
		t.Fatalf("result %v", out)
	}
	if st, _ := e.me(r.token); st != http.StatusUnauthorized {
		t.Fatalf("old session still valid: %d", st)
	}
	if st, _ := e.me(newToken); st != 200 {
		t.Fatalf("new session rejected: %d", st)
	}
	if e.login("b@test.local", "NewPass123") != 200 || e.login("b@test.local", "oldpass1") != 401 {
		t.Fatal("password not replaced")
	}
	// Recovering with the backup code doesn't verify the phone.
	var u models.User
	e.db.First(&u, r.id)
	if u.PhoneVerifiedAt != nil {
		t.Fatal("phone marked verified")
	}
	// The used code is dead; the new one works (by email this time).
	if st, out := e.recover("b@test.local", r.code, "Another123"); st != 400 || out["error"] != "invalid_recovery_code" {
		t.Fatalf("reuse: %d %v", st, out)
	}
	if st, _ := e.recover("B@Test.Local", newCode, "Another123"); st != 200 {
		t.Fatalf("new code: %d", st)
	}
}

func TestWrongCodeAndUnknownAccountLookTheSame(t *testing.T) {
	e := newRecEnv(t, nil)
	r := e.register("c@test.local", "+7 700 333 44 55", "oldpass1")
	other, _ := recoverycode.Generate()
	st1, out1 := e.recover("+77003334455", other, "NewPass123")
	st2, out2 := e.recover("+77009999999", r.code, "NewPass123")
	st3, out3 := e.recover("nobody@test.local", r.code, "NewPass123")
	st4, out4 := e.recover("+77003334455", "not-a-code", "NewPass123")
	for i, o := range []map[string]any{out1, out2, out3, out4} {
		if o["error"] != "invalid_recovery_code" || len(o) != 1 {
			t.Fatalf("answer %d: %v", i, o)
		}
	}
	if st1 != 400 || st2 != 400 || st3 != 400 || st4 != 400 {
		t.Fatalf("statuses %d %d %d %d", st1, st2, st3, st4)
	}
	if e.login("c@test.local", "oldpass1") != 200 {
		t.Fatal("password changed by a failed attempt")
	}
	// A weak new password is refused before the code is even checked.
	if st, out := e.recover("+77003334455", r.code, "short"); st != 400 || out["error"] != "weak_password" {
		t.Fatalf("weak: %d %v", st, out)
	}
}

func TestPendingAccountCannotRecover(t *testing.T) {
	e := newRecEnv(t, nil)
	r := e.register("d@test.local", "+7 700 444 55 66", "oldpass1")
	e.db.Model(&models.User{}).Where("id = ?", r.id).Update("status", models.UserStatusPending)
	if st, out := e.recover("d@test.local", r.code, "NewPass123"); st != 400 || out["error"] != "invalid_recovery_code" {
		t.Fatalf("pending: %d %v", st, out)
	}
}

func TestReplaceCodeNeedsCurrentPasswordAndKillsTheOldOne(t *testing.T) {
	e := newRecEnv(t, nil)
	r := e.register("e@test.local", "+7 700 555 66 77", "oldpass1")
	path := "/api/users/me/recovery-code"
	if st, _, _ := e.do(recReq{method: "POST", path: path, body: map[string]string{"current_password": "oldpass1"}}); st != 401 {
		t.Fatalf("no auth: %d", st)
	}
	st, out, _ := e.do(recReq{method: "POST", path: path, token: r.token, body: map[string]string{"current_password": "wrong"}})
	if st != 400 || out["error"] != "wrong_current_password" {
		t.Fatalf("wrong password: %d %v", st, out)
	}
	st, out, hdr := e.do(recReq{method: "POST", path: path, token: r.token, body: map[string]string{"current_password": "oldpass1"}})
	newCode, _ := out["recovery_code"].(string)
	if st != 200 || newCode == "" || newCode == r.code || hdr.Get("Cache-Control") != "no-store" {
		t.Fatalf("replace: %d %v", st, out)
	}
	if st, _ := e.recover("e@test.local", r.code, "NewPass123"); st != 400 {
		t.Fatalf("old code still works: %d", st)
	}
	if st, _ := e.recover("e@test.local", newCode, "NewPass123"); st != 200 {
		t.Fatalf("new code: %d", st)
	}
}

func TestReplaceCodeThrottlesWrongPasswords(t *testing.T) {
	e := newRecEnv(t, nil)
	r := e.register("f@test.local", "", "oldpass1")
	path := "/api/users/me/recovery-code"
	for i := 0; i < 5; i++ {
		e.do(recReq{method: "POST", path: path, token: r.token, body: map[string]string{"current_password": "wrong"}})
	}
	if st, _, _ := e.do(recReq{method: "POST", path: path, token: r.token, body: map[string]string{"current_password": "oldpass1"}}); st != 429 {
		t.Fatalf("not throttled: %d", st)
	}
}

func TestRecoveryThrottledPerAccount(t *testing.T) {
	e := newRecEnv(t, nil)
	r := e.register("g@test.local", "+7 700 666 77 88", "oldpass1")
	wrong, _ := recoverycode.Generate()
	for i := 0; i < 5; i++ {
		// Different client addresses: the account limit still counts them.
		e.recover("+77006667788", wrong, "NewPass123", recReq{remote: fmt.Sprintf("192.0.2.%d:1", 20+i)})
	}
	if st, out := e.recover("8 700 666 77 88", r.code, "NewPass123", recReq{remote: "192.0.2.99:1"}); st != 429 || out["error"] != "too_many_attempts" {
		t.Fatalf("right code after 5 failures: %d %v", st, out)
	}
	// An unknown number is throttled the same way, so the limit leaks nothing.
	for i := 0; i < 5; i++ {
		e.recover("+77001230000", wrong, "NewPass123", recReq{remote: fmt.Sprintf("192.0.2.%d:1", 40+i)})
	}
	if st, _ := e.recover("+77001230000", wrong, "NewPass123", recReq{remote: "192.0.2.98:1"}); st != 429 {
		t.Fatalf("unknown number not throttled: %d", st)
	}
	if e.login("g@test.local", "oldpass1") != 200 {
		t.Fatal("password changed")
	}
}

func TestRecoveryThrottledPerIPAndSpoofedForwardedForIgnored(t *testing.T) {
	e := newRecEnv(t, []string{"10.0.0.1"})
	r := e.register("h@test.local", "+7 700 777 88 99", "oldpass1")
	wrong, _ := recoverycode.Generate()
	// 20 failures from one untrusted client, each claiming another origin.
	for i := 0; i < 20; i++ {
		e.recover(fmt.Sprintf("+7700000%04d", i), wrong, "NewPass123",
			recReq{remote: "198.51.100.7:1", xff: fmt.Sprintf("203.0.113.%d", i)})
	}
	if st, _ := e.recover("h@test.local", r.code, "NewPass123", recReq{remote: "198.51.100.7:1", xff: "203.0.113.200"}); st != 429 {
		t.Fatalf("spoofed X-Forwarded-For bypassed the IP limit: %d", st)
	}
	// Behind the trusted proxy the real client address counts instead.
	if st, _ := e.recover("h@test.local", r.code, "NewPass123", recReq{remote: "10.0.0.1:1", xff: "203.0.113.201"}); st != 200 {
		t.Fatalf("other client behind trusted proxy: %d", st)
	}
}

// After a successful reset whose response never reached the client, the
// user still has the new password and can make a fresh code.
func TestLostResponseRecoversByLoginAndNewCode(t *testing.T) {
	e := newRecEnv(t, nil)
	r := e.register("i@test.local", "+7 700 888 99 00", "oldpass1")
	if st, _ := e.recover("i@test.local", r.code, "NewPass123"); st != 200 {
		t.Fatal("recover")
	}
	// (response "lost") — sign in with the password just set…
	st, out, _ := e.do(recReq{method: "POST", path: "/api/auth/login", body: map[string]string{"email": "i@test.local", "password": "NewPass123"}})
	if st != 200 {
		t.Fatalf("login: %d", st)
	}
	tok := out["token"].(string)
	// …and replace the unseen code.
	st, out, _ = e.do(recReq{method: "POST", path: "/api/users/me/recovery-code", token: tok, body: map[string]string{"current_password": "NewPass123"}})
	if st != 200 || out["recovery_code"] == "" {
		t.Fatalf("new code: %d %v", st, out)
	}
}

// concurrentRedeem fires n recoveries with the same code at once and
// reports how many succeeded.
func concurrentRedeem(t *testing.T, e *recEnv, login, code string, n int) (ok int, statuses []int) {
	var wg sync.WaitGroup
	var mu sync.Mutex
	start := make(chan struct{})
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			<-start
			st, _ := e.recover(login, code, fmt.Sprintf("Parallel%03d", i), recReq{remote: fmt.Sprintf("192.0.2.%d:1", 100+i)})
			mu.Lock()
			statuses = append(statuses, st)
			if st == 200 {
				ok++
			}
			mu.Unlock()
		}(i)
	}
	close(start)
	wg.Wait()
	return ok, statuses
}

func TestParallelRecoveryUsesCodeOnce(t *testing.T) {
	e := newRecEnv(t, nil)
	r := e.register("j@test.local", "+7 700 999 00 11", "oldpass1")
	ok, statuses := concurrentRedeem(t, e, "j@test.local", r.code, 5) // within the per-account limit
	if ok != 1 {
		t.Fatalf("%d successes, statuses %v", ok, statuses)
	}
}

// The same race on real Postgres (row locks, READ COMMITTED):
//
//	MEREYTOI_TEST_POSTGRES_DSN="host=... dbname=... sslmode=disable" go test ./internal/routes -run RecoveryPostgres
//
// The database must be disposable: the test drops the tables it uses.
func TestParallelRecoveryPostgres(t *testing.T) {
	dsn := os.Getenv("MEREYTOI_TEST_POSTGRES_DSN")
	if dsn == "" {
		t.Skip("MEREYTOI_TEST_POSTGRES_DSN not set")
	}
	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.Migrator().DropTable(&models.RecoveryAttempt{}, &models.PasswordResetCode{}, &models.User{}); err != nil {
		t.Fatal(err)
	}
	e := newRecEnvOn(t, db, nil)
	r := e.register("pg@test.local", "+7 701 000 00 01", "oldpass1")
	ok, statuses := concurrentRedeem(t, e, "pg@test.local", r.code, 5) // within the per-account limit
	if ok != 1 {
		t.Fatalf("%d successes, statuses %v", ok, statuses)
	}
	for _, s := range statuses {
		if s != 200 && s != 400 {
			t.Fatalf("unexpected status %d in %v", s, statuses)
		}
	}
}

// concurrentWrong fires n wrong-code recoveries at once; login(i) and
// remote(i) pick each request's account and client address.
func concurrentWrong(e *recEnv, n int, login, remote func(int) string) map[int]int {
	wrong, _ := recoverycode.Generate()
	var wg sync.WaitGroup
	var mu sync.Mutex
	counts := map[int]int{}
	start := make(chan struct{})
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			<-start
			st, _ := e.recover(login(i), wrong, "NewPass123", recReq{remote: remote(i)})
			mu.Lock()
			counts[st]++
			mu.Unlock()
		}(i)
	}
	close(start)
	wg.Wait()
	return counts
}

// Parallel wrong guesses on real Postgres can't get past the limits: at
// most 5 per account and 20 per client address are even checked, the rest
// are refused with 429 — and afterwards even the right code is refused.
func TestConcurrentRateLimitPostgres(t *testing.T) {
	dsn := os.Getenv("MEREYTOI_TEST_POSTGRES_DSN")
	if dsn == "" {
		t.Skip("MEREYTOI_TEST_POSTGRES_DSN not set")
	}
	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.Migrator().DropTable(&models.RecoveryAttempt{}, &models.PasswordResetCode{}, &models.User{}); err != nil {
		t.Fatal(err)
	}
	e := newRecEnvOn(t, db, nil)
	r := e.register("rl@test.local", "+7 701 000 00 02", "oldpass1")

	// 25 wrong guesses for one account from 25 addresses.
	acct := concurrentWrong(e, 25,
		func(int) string { return "+77010000002" },
		func(i int) string { return fmt.Sprintf("198.51.100.%d:1", i+1) })
	if acct[400] > 5 || acct[400]+acct[429] != 25 {
		t.Fatalf("per-account: %v (at most 5 may be checked)", acct)
	}
	if st, _ := e.recover("rl@test.local", r.code, "NewPass123", recReq{remote: "198.51.100.200:1"}); st != 429 {
		t.Fatalf("right code after the flood: %d", st)
	}

	// 30 wrong guesses from one address, each for a different account.
	ip := concurrentWrong(e, 30,
		func(i int) string { return fmt.Sprintf("+7702%07d", i) },
		func(int) string { return "203.0.113.50:1" })
	if ip[400] > 20 || ip[400]+ip[429] != 30 {
		t.Fatalf("per-IP: %v (at most 20 may be checked)", ip)
	}
}

// One password policy for every new password (8+ characters); passwords
// set before it keep working.
func TestPasswordPolicyForNewPasswordsOnly(t *testing.T) {
	e := newRecEnv(t, nil)
	st, out, _ := e.do(recReq{method: "POST", path: "/api/auth/register",
		body: map[string]string{"name": "S", "email": "short@test.local", "password": "seven77"}})
	if st != 400 || out["error"] != "weak_password" || out["min_length"] != float64(8) {
		t.Fatalf("7-char registration: %d %v", st, out)
	}
	if st, _, _ := e.do(recReq{method: "POST", path: "/api/auth/register",
		body: map[string]string{"name": "S", "email": "long@test.local", "password": strings.Repeat("x", 73)}}); st != 400 {
		t.Fatalf("73-byte password accepted: %d", st)
	}
	r := e.register("eight@test.local", "", "eight888")

	// An account created under the old 6-character rule still signs in.
	legacy, _ := bcrypt.GenerateFromPassword([]byte("old666"), bcrypt.MinCost)
	e.db.Create(&models.User{Name: "L", Email: "legacy@test.local", PasswordHash: string(legacy), Role: "user", Status: models.UserStatusActive})
	if e.login("legacy@test.local", "old666") != 200 {
		t.Fatal("legacy 6-character password no longer works")
	}
	// …but a new one must follow the policy, in recovery and change alike.
	if st, out := e.recover("eight@test.local", r.code, "short1"); st != 400 || out["error"] != "weak_password" {
		t.Fatalf("recovery to a short password: %d %v", st, out)
	}
	st, out, _ = e.do(recReq{method: "PUT", path: "/api/users/me/password", token: r.token,
		body: map[string]string{"current_password": "eight888", "new_password": "short1"}})
	if st != 400 || out["error"] != "weak_password" {
		t.Fatalf("change to a short password: %d %v", st, out)
	}
}
