package routes_test

import (
	"bytes"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
	"github.com/almukhanbetov/mereytoi/backend/internal/recoverycode"
)

const (
	supRequestPath = "/api/auth/recovery/support-request"
	supResetPath   = "/api/auth/recovery/support-reset"
	supAdminPath   = "/api/admin/recovery-requests"
)

// A code shaped like a real one that was never issued.
const supWrongCode = "ABCD-EFGH-JKMN-PQRS"

func newSupEnv(t *testing.T) *recEnv {
	t.Helper()
	e := newRecEnv(t, nil)
	if err := e.db.AutoMigrate(&models.PasswordRecoveryRequest{}, &models.RecoveryAuditEvent{}); err != nil {
		t.Fatal(err)
	}
	return e
}

func (e *recEnv) supAdmin(email string) regResult {
	e.t.Helper()
	r := e.register(email, "", "adminpass1")
	e.db.Model(&models.User{}).Where("id = ?", r.id).Update("role", "admin")
	st, out, _ := e.do(recReq{method: "POST", path: "/api/auth/login", body: map[string]string{"email": email, "password": "adminpass1"}})
	if st != 200 {
		e.t.Fatalf("admin login: %d %v", st, out)
	}
	r.token = out["token"].(string)
	return r
}

func (e *recEnv) supRequest(login string, opt ...string) (int, string) {
	e.t.Helper()
	q := recReq{method: "POST", path: supRequestPath, body: map[string]string{"login": login}}
	if len(opt) > 0 {
		q.remote = opt[0]
	}
	st, out, hdr := e.do(q)
	if hdr.Get("Cache-Control") != "no-store" {
		e.t.Fatal("support request response is cacheable")
	}
	return st, fmt.Sprint(out)
}

func (e *recEnv) supReset(login, code, newPassword string, opt ...string) (int, map[string]any) {
	e.t.Helper()
	q := recReq{method: "POST", path: supResetPath,
		body: map[string]string{"login": login, "temp_code": code, "new_password": newPassword}}
	if len(opt) > 0 {
		q.remote = opt[0]
	}
	st, out, hdr := e.do(q)
	if hdr.Get("Cache-Control") != "no-store" {
		e.t.Fatal("support reset response is cacheable")
	}
	return st, out
}

func (e *recEnv) supOnly(userID uint) models.PasswordRecoveryRequest {
	e.t.Helper()
	var req models.PasswordRecoveryRequest
	if err := e.db.Where("user_id = ?", userID).Order("id DESC").First(&req).Error; err != nil {
		e.t.Fatalf("no request: %v", err)
	}
	return req
}

func (e *recEnv) supApprove(adminToken string, id uint) (string, map[string]any) {
	e.t.Helper()
	st, out, hdr := e.do(recReq{method: "POST", path: fmt.Sprintf("%s/%d/approve", supAdminPath, id), token: adminToken})
	if st != 200 {
		e.t.Fatalf("approve: %d %v", st, out)
	}
	if hdr.Get("Cache-Control") != "no-store" {
		e.t.Fatal("approve response is cacheable")
	}
	return out["temp_code"].(string), out
}

func (e *recEnv) supAudit(requestID uint) []string {
	e.t.Helper()
	var events []models.RecoveryAuditEvent
	e.db.Where("request_id = ?", requestID).Order("id").Find(&events)
	actions := make([]string, 0, len(events))
	for _, ev := range events {
		actions = append(actions, ev.Action)
	}
	return actions
}

func TestSupportRequestAnswerIsTheSameForAnyAccount(t *testing.T) {
	e := newSupEnv(t)
	u := e.register("known@test.local", "+7 700 400 00 01", "oldpass12")

	stKnown, known := e.supRequest("known@test.local")
	stUnknown, unknown := e.supRequest("nobody@test.local")
	stPhone, phone := e.supRequest("+7 700 999 99 99")
	if stKnown != 200 || stUnknown != 200 || stPhone != 200 || known != unknown || unknown != phone {
		t.Fatalf("answers differ: %d %s / %d %s / %d %s", stKnown, known, stUnknown, unknown, stPhone, phone)
	}
	if known != "map[status:ok]" {
		t.Fatalf("answer %s", known)
	}

	var n int64
	e.db.Model(&models.PasswordRecoveryRequest{}).Count(&n)
	if n != 1 {
		t.Fatalf("requests %d", n)
	}
	req := e.supOnly(u.id)
	if req.Status != models.RecoveryRequestPending || req.TempCodeHash != "" || req.TempCodeExpiresAt != nil {
		t.Fatalf("request %+v", req)
	}
	if got := e.supAudit(req.ID); len(got) != 1 || got[0] != models.RecoveryAuditRequested {
		t.Fatalf("audit %v", got)
	}
	// Filing a request changes nothing about the account itself.
	if e.login("known@test.local", "oldpass12") != 200 {
		t.Fatal("password disturbed")
	}
}

func TestSupportRequestByPhoneFindsTheAccount(t *testing.T) {
	e := newSupEnv(t)
	u := e.register("bp@test.local", "+7 700 400 00 02", "oldpass12")
	if st, _ := e.supRequest("8 700 400 00 02"); st != 200 {
		t.Fatalf("status %d", st)
	}
	e.supOnly(u.id)
}

func TestSupportRequestSkipsPendingAccounts(t *testing.T) {
	e := newSupEnv(t)
	u := e.register("inactive@test.local", "", "oldpass12")
	e.db.Model(&models.User{}).Where("id = ?", u.id).Update("status", models.UserStatusPending)
	if st, _ := e.supRequest("inactive@test.local"); st != 200 {
		t.Fatalf("status %d", st)
	}
	var n int64
	e.db.Model(&models.PasswordRecoveryRequest{}).Count(&n)
	if n != 0 {
		t.Fatalf("requests %d", n)
	}
}

func TestSupportRequestSpamIsLimited(t *testing.T) {
	e := newSupEnv(t)
	u := e.register("spam@test.local", "+7 700 400 00 03", "oldpass12")

	// One open request per account, however often it's asked for, and the
	// per-account limit stays silent: its key joins email and phone.
	for i := 0; i < 8; i++ {
		login := "spam@test.local"
		if i%2 == 1 {
			login = "+7 700 400 00 03"
		}
		st, body := e.supRequest(login, fmt.Sprintf("198.51.100.%d:1", i+1))
		if st != 200 || body != "map[status:ok]" {
			t.Fatalf("attempt %d: %d %s", i, st, body)
		}
	}
	var n int64
	e.db.Model(&models.PasswordRecoveryRequest{}).Where("user_id = ?", u.id).Count(&n)
	if n != 1 {
		t.Fatalf("requests %d", n)
	}

	// Across accounts: the address limit answers 429, known or not.
	for i := 0; i < 10; i++ {
		if st, _ := e.supRequest(fmt.Sprintf("n%d@test.local", i), "198.51.100.200:1"); st != 200 {
			t.Fatalf("attempt %d: %d", i, st)
		}
	}
	if st, _ := e.supRequest("spam@test.local", "198.51.100.200:1"); st != http.StatusTooManyRequests {
		t.Fatalf("over the limit: %d", st)
	}
}

func TestOnlyAnAdminReachesRecoveryRequests(t *testing.T) {
	e := newSupEnv(t)
	u := e.register("plain@test.local", "", "oldpass12")
	e.supRequest("plain@test.local")
	req := e.supOnly(u.id)

	calls := []struct{ method, path string }{
		{"GET", supAdminPath},
		{"GET", fmt.Sprintf("%s/%d", supAdminPath, req.ID)},
		{"POST", fmt.Sprintf("%s/%d/approve", supAdminPath, req.ID)},
		{"POST", fmt.Sprintf("%s/%d/reject", supAdminPath, req.ID)},
	}
	for _, c := range calls {
		if st, _, _ := e.do(recReq{method: c.method, path: c.path}); st != http.StatusUnauthorized {
			t.Fatalf("%s %s as guest: %d", c.method, c.path, st)
		}
		if st, _, _ := e.do(recReq{method: c.method, path: c.path, token: u.token}); st != http.StatusForbidden {
			t.Fatalf("%s %s as user: %d", c.method, c.path, st)
		}
	}
	if got := e.supOnly(u.id); got.Status != models.RecoveryRequestPending || got.TempCodeHash != "" {
		t.Fatalf("request changed: %+v", got)
	}
}

func TestAdminCannotIssueACodeForThemselves(t *testing.T) {
	e := newSupEnv(t)
	admin := e.supAdmin("self@test.local")
	e.supRequest("self@test.local")
	req := e.supOnly(admin.id)
	st, out, _ := e.do(recReq{method: "POST", path: fmt.Sprintf("%s/%d/approve", supAdminPath, req.ID), token: admin.token})
	if st != http.StatusForbidden || out["error"] != "self_approval_forbidden" {
		t.Fatalf("%d %v", st, out)
	}
	// Another admin can.
	other := e.supAdmin("other@test.local")
	if code, _ := e.supApprove(other.token, req.ID); code == "" {
		t.Fatal("no code")
	}
}

func TestApproveReturnsTheCodeOnceAndStoresOnlyItsHash(t *testing.T) {
	var logs bytes.Buffer
	log.SetOutput(&logs)
	defer log.SetOutput(os.Stderr)

	e := newSupEnv(t)
	admin := e.supAdmin("adm@test.local")
	u := e.register("hash@test.local", "+7 700 400 00 04", "oldpass12")
	e.supRequest("hash@test.local")
	req := e.supOnly(u.id)

	before := time.Now()
	code, out := e.supApprove(admin.token, req.ID)
	if len(code) != 19 || strings.Count(code, "-") != 3 {
		t.Fatalf("code %q", code)
	}
	canonical := strings.ReplaceAll(code, "-", "")

	req = e.supOnly(u.id)
	if req.Status != models.RecoveryRequestApproved || req.ApprovedBy == nil || *req.ApprovedBy != admin.id || req.ApprovedAt == nil {
		t.Fatalf("request %+v", req)
	}
	if req.TempCodeHash != recoverycode.Hash(canonical) {
		t.Fatal("hash not stored")
	}
	ttl := req.TempCodeExpiresAt.Sub(before)
	if ttl < 14*time.Minute || ttl > 16*time.Minute {
		t.Fatalf("ttl %v", ttl)
	}

	row := map[string]any{}
	e.db.Model(&models.PasswordRecoveryRequest{}).Where("id = ?", req.ID).Take(&row)
	if strings.Contains(fmt.Sprint(row), canonical) {
		t.Fatal("plaintext code stored")
	}

	if strings.Contains(fmt.Sprint(out["request"]), req.TempCodeHash) {
		t.Fatal("approve response exposes the hash")
	}

	// Nothing read back afterwards shows the code or any hash.
	st, list, _ := e.do(recReq{method: "GET", path: supAdminPath + "?status=approved", token: admin.token})
	if st != 200 {
		t.Fatalf("list: %d", st)
	}
	st2, detail, _ := e.do(recReq{method: "GET", path: fmt.Sprintf("%s/%d", supAdminPath, req.ID), token: admin.token})
	if st2 != 200 {
		t.Fatalf("detail: %d", st2)
	}
	for _, view := range []string{fmt.Sprint(list), fmt.Sprint(detail)} {
		for _, secret := range []string{code, canonical, req.TempCodeHash, "temp_code_hash", "password_hash", "recovery_code_hash"} {
			if strings.Contains(view, secret) {
				t.Fatalf("view exposes %q", secret)
			}
		}
	}
	user := list["requests"].([]any)[0].(map[string]any)["user"].(map[string]any)
	if user["email"] != "hash@test.local" || user["phone"] == "" || user["name"] == "" {
		t.Fatalf("user %v", user)
	}

	// The audit log says who did it, and no code reaches it or the log.
	var events []models.RecoveryAuditEvent
	e.db.Where("request_id = ?", req.ID).Find(&events)
	if strings.Contains(fmt.Sprintf("%+v", events), canonical) {
		t.Fatal("code in the audit log")
	}
	var approved models.RecoveryAuditEvent
	if err := e.db.Where("request_id = ? AND action = ?", req.ID, models.RecoveryAuditApproved).First(&approved).Error; err != nil {
		t.Fatal(err)
	}
	if approved.ActorID == nil || *approved.ActorID != admin.id || approved.IP == "" {
		t.Fatalf("audit %+v", approved)
	}
	for _, action := range []string{models.RecoveryAuditListed, models.RecoveryAuditViewed} {
		var n int64
		e.db.Model(&models.RecoveryAuditEvent{}).Where("action = ? AND actor_id = ?", action, admin.id).Count(&n)
		if n != 1 {
			t.Fatalf("%s audited %d times", action, n)
		}
	}
	if strings.Contains(logs.String(), canonical) || strings.Contains(logs.String(), code) {
		t.Fatal("code in the server log")
	}
}

func TestSupportResetSetsPasswordRevokesSessionsAndSpendsTheCode(t *testing.T) {
	e := newSupEnv(t)
	admin := e.supAdmin("adm2@test.local")
	u := e.register("flow@test.local", "+7 700 400 00 05", "oldpass12")
	e.supRequest("flow@test.local")
	req := e.supOnly(u.id)
	code, _ := e.supApprove(admin.token, req.ID)
	// Sessions are compared by whole seconds; make the old one strictly older.
	time.Sleep(1100 * time.Millisecond)

	stWrong, wrong := e.supReset("flow@test.local", supWrongCode, "NewPass123")
	stNobody, nobody := e.supReset("nobody@test.local", code, "NewPass123")
	if stWrong != 400 || stNobody != 400 || fmt.Sprint(wrong) != fmt.Sprint(nobody) || wrong["error"] != "invalid_recovery_code" {
		t.Fatalf("%d %v / %d %v", stWrong, wrong, stNobody, nobody)
	}

	// A weak password is refused before the code is spent.
	if st, out := e.supReset("flow@test.local", code, "short"); st != 400 || out["error"] != "weak_password" {
		t.Fatalf("%d %v", st, out)
	}

	st, out := e.supReset("8 700 400 00 05", strings.ToLower(code), "NewPass123")
	if st != 200 {
		t.Fatalf("reset: %d %v", st, out)
	}
	newToken, _ := out["token"].(string)
	newBackup, _ := out["recovery_code"].(string)
	if newToken == "" || newBackup == "" || newBackup == u.code {
		t.Fatalf("result %v", out)
	}
	if e.login("flow@test.local", "NewPass123") != 200 || e.login("flow@test.local", "oldpass12") != 401 {
		t.Fatal("password not replaced")
	}
	if st, _ := e.me(u.token); st != http.StatusUnauthorized {
		t.Fatalf("old session still valid: %d", st)
	}
	if st, _ := e.me(newToken); st != 200 {
		t.Fatalf("new session rejected: %d", st)
	}

	// The lost backup code is retired; the new one works.
	if st, _ := e.recover("flow@test.local", u.code, "Another123"); st != 400 {
		t.Fatalf("old backup code: %d", st)
	}

	got := e.supOnly(u.id)
	if got.Status != models.RecoveryRequestUsed || got.UsedAt == nil || got.TempCodeHash != "" {
		t.Fatalf("request %+v", got)
	}
	if st, out := e.supReset("flow@test.local", code, "Another123"); st != 400 || out["error"] != "invalid_recovery_code" {
		t.Fatalf("second use: %d %v", st, out)
	}
	if e.login("flow@test.local", "NewPass123") != 200 {
		t.Fatal("second use changed the password")
	}
	actions := e.supAudit(req.ID)
	if actions[len(actions)-1] != models.RecoveryAuditUsed {
		t.Fatalf("audit %v", actions)
	}
	// A used request can't be turned into a new code.
	if st, out, _ := e.do(recReq{method: "POST", path: fmt.Sprintf("%s/%d/approve", supAdminPath, req.ID), token: admin.token}); st != http.StatusConflict {
		t.Fatalf("approve used: %d %v", st, out)
	}
}

// An account from before backup codes has none to redeem: any code is refused
// with the usual answer, and support is still reachable by email and phone.
func TestAccountWithoutBackupCodeIsRefusedAndCanAskSupport(t *testing.T) {
	e := newSupEnv(t)
	u := e.register("old@test.local", "+7 700 400 00 09", "oldpass12")
	e.db.Model(&models.User{}).Where("id = ?", u.id).Updates(map[string]any{
		"recovery_code_hash": "", "recovery_code_created_at": nil,
	})
	for _, code := range []string{"12345678", "ABCD-EFGH-JKMN-PQRS-TVWX-YZ01-2345", ""} {
		st, out := e.recover("old@test.local", code, "NewPass123")
		if code == "" {
			if st != 400 {
				t.Fatalf("empty code: %d %v", st, out)
			}
			continue
		}
		if st != 400 || out["error"] != "invalid_recovery_code" {
			t.Fatalf("code %q: %d %v", code, st, out)
		}
	}
	if e.login("old@test.local", "oldpass12") != 200 {
		t.Fatal("password changed")
	}
	if st, _ := e.supRequest("old@test.local"); st != 200 {
		t.Fatalf("request by email: %d", st)
	}
	first := e.supOnly(u.id)
	e.db.Model(&models.PasswordRecoveryRequest{}).Where("id = ?", first.ID).Update("status", models.RecoveryRequestRejected)
	if st, _ := e.supRequest("8 700 400 00 09"); st != 200 {
		t.Fatalf("request by phone: %d", st)
	}
	if got := e.supOnly(u.id); got.ID == first.ID || got.Status != models.RecoveryRequestPending {
		t.Fatalf("request by phone %+v", got)
	}
}

func TestBackupAndTemporaryCodesAreNotInterchangeable(t *testing.T) {
	e := newSupEnv(t)
	admin := e.supAdmin("adm3@test.local")
	u := e.register("cross@test.local", "", "oldpass12")
	e.supRequest("cross@test.local")
	code, _ := e.supApprove(admin.token, e.supOnly(u.id).ID)

	if st, _ := e.supReset("cross@test.local", u.code, "NewPass123"); st != 400 {
		t.Fatalf("backup code on support reset: %d", st)
	}
	if st, _ := e.recover("cross@test.local", code, "NewPass123"); st != 400 {
		t.Fatalf("temporary code on backup reset: %d", st)
	}
	// The existing flow still works while a request is open.
	if st, _ := e.recover("cross@test.local", u.code, "NewPass123"); st != 200 {
		t.Fatalf("backup flow: %d", st)
	}
}

func TestANewApprovalInvalidatesTheEarlierCode(t *testing.T) {
	e := newSupEnv(t)
	admin := e.supAdmin("adm4@test.local")
	u := e.register("twice@test.local", "", "oldpass12")
	e.supRequest("twice@test.local")
	first := e.supOnly(u.id)
	code1, _ := e.supApprove(admin.token, first.ID)

	// Reissued on the same request.
	code2, _ := e.supApprove(admin.token, first.ID)
	if code1 == code2 {
		t.Fatal("same code")
	}
	if st, _ := e.supReset("twice@test.local", code1, "NewPass123"); st != 400 {
		t.Fatalf("first code after reissue: %d", st)
	}
	if got := e.supAudit(first.ID); got[len(got)-1] != models.RecoveryAuditReissued {
		t.Fatalf("audit %v", got)
	}

	// A new request approved while the old code is live supersedes it.
	e.supRequest("twice@test.local")
	second := e.supOnly(u.id)
	if second.ID == first.ID || second.Status != models.RecoveryRequestPending {
		t.Fatalf("second request %+v", second)
	}
	code3, _ := e.supApprove(admin.token, second.ID)
	if st, _ := e.supReset("twice@test.local", code2, "NewPass123"); st != 400 {
		t.Fatalf("superseded code: %d", st)
	}
	var old models.PasswordRecoveryRequest
	e.db.First(&old, first.ID)
	if old.Status != models.RecoveryRequestExpired || old.TempCodeHash != "" {
		t.Fatalf("old request %+v", old)
	}
	if got := e.supAudit(first.ID); got[len(got)-1] != models.RecoveryAuditSuperseded {
		t.Fatalf("audit %v", got)
	}
	if st, out := e.supReset("twice@test.local", code3, "NewPass123"); st != 200 {
		t.Fatalf("live code: %d %v", st, out)
	}
}

func TestExpiredCodeDoesNotWork(t *testing.T) {
	e := newSupEnv(t)
	admin := e.supAdmin("adm5@test.local")
	u := e.register("late@test.local", "", "oldpass12")
	e.supRequest("late@test.local")
	req := e.supOnly(u.id)
	code, _ := e.supApprove(admin.token, req.ID)

	past := time.Now().Add(-time.Second)
	e.db.Model(&models.PasswordRecoveryRequest{}).Where("id = ?", req.ID).Update("temp_code_expires_at", past)

	if st, out := e.supReset("late@test.local", code, "NewPass123"); st != 400 || out["error"] != "invalid_recovery_code" {
		t.Fatalf("%d %v", st, out)
	}
	if e.login("late@test.local", "oldpass12") != 200 {
		t.Fatal("password changed")
	}
	st, list, _ := e.do(recReq{method: "GET", path: supAdminPath + "?status=expired", token: admin.token})
	if st != 200 || len(list["requests"].([]any)) != 1 {
		t.Fatalf("expired list: %d %v", st, list)
	}
	if got := e.supOnly(u.id); got.TempCodeHash != "" {
		t.Fatal("expired hash kept")
	}
	if st, _, _ := e.do(recReq{method: "POST", path: fmt.Sprintf("%s/%d/approve", supAdminPath, req.ID), token: admin.token}); st != http.StatusConflict {
		t.Fatalf("approve expired: %d", st)
	}
}

func TestStalePendingRequestCannotBeApproved(t *testing.T) {
	e := newSupEnv(t)
	admin := e.supAdmin("adm6@test.local")
	u := e.register("stale@test.local", "", "oldpass12")
	e.supRequest("stale@test.local")
	req := e.supOnly(u.id)
	e.db.Model(&models.PasswordRecoveryRequest{}).Where("id = ?", req.ID).Update("requested_at", time.Now().Add(-8*24*time.Hour))
	if st, _, _ := e.do(recReq{method: "POST", path: fmt.Sprintf("%s/%d/approve", supAdminPath, req.ID), token: admin.token}); st != http.StatusConflict {
		t.Fatalf("approve stale: %d", st)
	}
	// And it no longer blocks a new request.
	e.supRequest("stale@test.local")
	if got := e.supOnly(u.id); got.ID == req.ID || got.Status != models.RecoveryRequestPending {
		t.Fatalf("new request %+v", got)
	}
}

func TestRejectClosesARequestAndRevokesItsCode(t *testing.T) {
	e := newSupEnv(t)
	admin := e.supAdmin("adm7@test.local")
	u := e.register("rej@test.local", "", "oldpass12")
	e.supRequest("rej@test.local")
	req := e.supOnly(u.id)
	code, _ := e.supApprove(admin.token, req.ID)

	st, out, _ := e.do(recReq{method: "POST", path: fmt.Sprintf("%s/%d/reject", supAdminPath, req.ID), token: admin.token,
		body: map[string]string{"note": "Личность не подтверждена"}})
	if st != 200 {
		t.Fatalf("reject: %d %v", st, out)
	}
	got := e.supOnly(u.id)
	if got.Status != models.RecoveryRequestRejected || got.TempCodeHash != "" || got.AdminNote != "Личность не подтверждена" {
		t.Fatalf("request %+v", got)
	}
	if st, _ := e.supReset("rej@test.local", code, "NewPass123"); st != 400 {
		t.Fatalf("revoked code: %d", st)
	}
	actions := e.supAudit(req.ID)
	if actions[len(actions)-1] != models.RecoveryAuditRejected {
		t.Fatalf("audit %v", actions)
	}
	for _, action := range []string{"approve", "reject"} {
		if st, _, _ := e.do(recReq{method: "POST", path: fmt.Sprintf("%s/%d/%s", supAdminPath, req.ID, action), token: admin.token}); st != http.StatusConflict {
			t.Fatalf("%s on rejected: %d", action, st)
		}
	}
}

func TestAdminEndpointsRefuseBadInput(t *testing.T) {
	e := newSupEnv(t)
	admin := e.supAdmin("adm8@test.local")
	if st, _, _ := e.do(recReq{method: "GET", path: supAdminPath + "?status=bogus", token: admin.token}); st != 400 {
		t.Fatalf("bad status: %d", st)
	}
	if st, _, _ := e.do(recReq{method: "GET", path: supAdminPath + "/abc", token: admin.token}); st != 400 {
		t.Fatalf("bad id: %d", st)
	}
	if st, _, _ := e.do(recReq{method: "POST", path: supAdminPath + "/999/approve", token: admin.token}); st != 404 {
		t.Fatalf("missing: %d", st)
	}
	u := e.register("note@test.local", "", "oldpass12")
	e.supRequest("note@test.local")
	req := e.supOnly(u.id)
	long := map[string]string{"note": strings.Repeat("я", 501)}
	if st, _, _ := e.do(recReq{method: "POST", path: fmt.Sprintf("%s/%d/approve", supAdminPath, req.ID), token: admin.token, body: long}); st != 400 {
		t.Fatalf("long note: %d", st)
	}
}

func TestSupportResetAttemptsAreLimited(t *testing.T) {
	e := newSupEnv(t)
	admin := e.supAdmin("adm9@test.local")
	u := e.register("guess@test.local", "", "oldpass12")
	e.supRequest("guess@test.local")
	req := e.supOnly(u.id)
	code, _ := e.supApprove(admin.token, req.ID)

	for i := 0; i < 5; i++ {
		remote := fmt.Sprintf("198.51.100.%d:1", i+1)
		if st, _ := e.supReset("guess@test.local", supWrongCode, "NewPass123", remote); st != 400 {
			t.Fatalf("attempt %d: %d", i, st)
		}
	}
	// Per account, from a fresh address, and the right code doesn't get through.
	if st, _ := e.supReset("guess@test.local", code, "NewPass123", "198.51.100.50:1"); st != http.StatusTooManyRequests {
		t.Fatalf("over the limit: %d", st)
	}
	// An unknown account sees the same limit.
	for i := 0; i < 5; i++ {
		e.supReset("ghost@test.local", supWrongCode, "NewPass123", fmt.Sprintf("198.51.100.%d:1", 60+i))
	}
	if st, _ := e.supReset("ghost@test.local", supWrongCode, "NewPass123", "198.51.100.70:1"); st != http.StatusTooManyRequests {
		t.Fatalf("unknown account over the limit: %d", st)
	}

	// The backup-code limit is a separate budget.
	if st, _ := e.recover("guess@test.local", "ABCD-EFGH-JKMN-PQRS-TVWX-YZ01-2345", "NewPass123", recReq{remote: "198.51.100.80:1"}); st != 400 {
		t.Fatalf("backup flow throttled: %d", st)
	}

	// A fresh code from support isn't held back by the guesses before it.
	fresh, _ := e.supApprove(admin.token, req.ID)
	if st, out := e.supReset("guess@test.local", fresh, "NewPass123", "198.51.100.90:1"); st != 200 {
		t.Fatalf("fresh code: %d %v", st, out)
	}

	// Per address, across accounts.
	for i := 0; i < 20; i++ {
		e.supReset(fmt.Sprintf("n%d@test.local", i), supWrongCode, "NewPass123", "198.51.100.100:1")
	}
	if st, _ := e.supReset("n99@test.local", supWrongCode, "NewPass123", "198.51.100.100:1"); st != http.StatusTooManyRequests {
		t.Fatalf("address over the limit: %d", st)
	}
}

// Same request many times over one serialized connection: exactly one wins.
func TestConcurrentSupportResetSucceedsOnce(t *testing.T) {
	e := newSupEnv(t)
	admin := e.supAdmin("adm10@test.local")
	u := e.register("race@test.local", "", "oldpass12")
	e.supRequest("race@test.local")
	code, _ := e.supApprove(admin.token, e.supOnly(u.id).ID)
	wins := parallelSupportResets(e, "race@test.local", code, 4)
	if wins != 1 {
		t.Fatalf("%d resets succeeded", wins)
	}
}

func parallelSupportResets(e *recEnv, login, code string, n int) int {
	var wg sync.WaitGroup
	var mu sync.Mutex
	wins := 0
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			st, _, _ := e.do(recReq{method: "POST", path: supResetPath, remote: fmt.Sprintf("198.51.100.%d:1", 150+i),
				body: map[string]string{"login": login, "temp_code": code, "new_password": fmt.Sprintf("Parallel%d23", i)}})
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

func supPostgresEnv(t *testing.T) *recEnv {
	t.Helper()
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
	e := newRecEnvOn(t, db, nil)
	if err := db.AutoMigrate(&models.PasswordRecoveryRequest{}, &models.RecoveryAuditEvent{}); err != nil {
		t.Fatal(err)
	}
	return e
}

// Real parallel resets on Postgres. Needs a disposable database (the test
// drops its tables):
//
//	MEREYTOI_TEST_POSTGRES_DSN="host=... dbname=... sslmode=disable" go test ./internal/routes -run SupportPostgres
func TestParallelSupportResetPostgres(t *testing.T) {
	e := supPostgresEnv(t)
	admin := e.supAdmin("pg-adm@test.local")
	u := e.register("pg-race@test.local", "", "oldpass12")
	e.supRequest("pg-race@test.local")
	code, _ := e.supApprove(admin.token, e.supOnly(u.id).ID)
	if wins := parallelSupportResets(e, "pg-race@test.local", code, 5); wins != 1 {
		t.Fatalf("%d resets succeeded", wins)
	}
	if got := e.supOnly(u.id); got.Status != models.RecoveryRequestUsed || got.TempCodeHash != "" {
		t.Fatalf("request %+v", got)
	}
}

// However requests and approvals interleave on Postgres, an account has at
// most one open request and at most one live code.
func TestParallelRequestsAndApprovalsPostgres(t *testing.T) {
	e := supPostgresEnv(t)
	admin := e.supAdmin("pg-adm2@test.local")
	u := e.register("pg-many@test.local", "", "oldpass12")

	var wg sync.WaitGroup
	for i := 0; i < 3; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			e.do(recReq{method: "POST", path: supRequestPath, remote: fmt.Sprintf("198.51.100.%d:1", i+1),
				body: map[string]string{"login": "pg-many@test.local"}})
		}(i)
	}
	wg.Wait()
	var n int64
	e.db.Model(&models.PasswordRecoveryRequest{}).Where("user_id = ?", u.id).Count(&n)
	if n != 1 {
		t.Fatalf("requests %d", n)
	}

	req := e.supOnly(u.id)
	statuses := make([]int, 2)
	for i := range statuses {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			statuses[i], _, _ = e.do(recReq{method: "POST", path: fmt.Sprintf("%s/%d/approve", supAdminPath, req.ID), token: admin.token})
		}(i)
	}
	wg.Wait()
	var live int64
	e.db.Model(&models.PasswordRecoveryRequest{}).Where("user_id = ? AND status = ?", u.id, models.RecoveryRequestApproved).Count(&live)
	if live != 1 {
		t.Fatalf("live codes %d (statuses %v)", live, statuses)
	}
}
