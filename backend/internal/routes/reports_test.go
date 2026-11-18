package routes_test

import (
	"fmt"
	"net/http"
	"strings"
	"testing"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// reportEnv reuses the admin fixture: owner (provider with a visible and an
// unpublished listing), a plain user (the reporter), two admins.
func reportEnv(t *testing.T) *adminEnv { return setupAdmin(t) }

func (e *adminEnv) report(c apiClient, targetType string, id any, reason string, details string) (int, map[string]any) {
	return c.do("POST", "/api/reports", map[string]any{
		"target_type": targetType, "target_id": id, "reason": reason, "details": details,
	})
}

func (e *adminEnv) providerID() uint {
	var p models.Provider
	e.db.Where("user_id = ?", e.ownerID).First(&p)
	return p.ID
}

func TestReportRightsAndValidation(t *testing.T) {
	e := reportEnv(t)
	if s, _ := e.report(e.guest, "listing", e.visible, "spam", ""); s != http.StatusUnauthorized {
		t.Fatalf("guest report: %d", s)
	}
	for _, p := range []struct{ m, path string }{
		{"GET", "/api/admin/reports"}, {"GET", "/api/admin/reports/1"}, {"POST", "/api/admin/reports/1/take"},
		{"POST", "/api/admin/reports/1/decide"}, {"GET", "/api/admin/summary"},
	} {
		if s, _ := e.user.do(p.m, p.path, map[string]any{"decision": "resolved", "reason": "xxx"}); s != http.StatusForbidden {
			t.Fatalf("user %s %s: %d", p.m, p.path, s)
		}
		if s, _ := e.guest.do(p.m, p.path, nil); s != http.StatusUnauthorized {
			t.Fatalf("guest %s %s: %d", p.m, p.path, s)
		}
	}
	bad := []struct {
		typ    string
		id     any
		reason string
		det    string
		want   string
	}{
		{"chat", e.visible, "spam", "", "invalid_target"},
		{"listing", 0, "spam", "", "invalid_target"},
		{"listing", e.visible, "boring", "", "invalid_reason"},
		{"listing", e.visible, "other", "кр", "details_required"},
		{"listing", e.visible, "spam", strings.Repeat("я", 2001), "details_too_long"},
	}
	for _, b := range bad {
		if s, out := e.report(e.user, b.typ, b.id, b.reason, b.det); s != http.StatusBadRequest || out["error"] != b.want {
			t.Fatalf("%v: %d %v", b, s, out)
		}
	}
	// Not visible to the reporter (unpublished, not existing): 404, so a
	// report can't probe hidden content.
	if s, out := e.report(e.user, "listing", e.unpublish, "spam", ""); s != http.StatusNotFound {
		t.Fatalf("unpublished listing: %d %v", s, out)
	}
	if s, _ := e.report(e.user, "user", 9999999, "spam", ""); s != http.StatusNotFound {
		t.Fatalf("unknown user: %d", s)
	}
	// Never about yourself.
	for _, tc := range []struct {
		typ string
		id  any
	}{{"listing", e.visible}, {"provider", e.providerID()}, {"user", e.ownerID}} {
		if s, out := e.report(e.owner, tc.typ, tc.id, "spam", ""); s != http.StatusBadRequest || out["error"] != "cannot_report_self" {
			t.Fatalf("self %s: %d %v", tc.typ, s, out)
		}
	}
	// Every target type works.
	s, out := e.user.do("POST", fmt.Sprintf("/api/listings/%d/comments", e.visible), map[string]any{"rating": 4, "text": "Отзыв"})
	if s != http.StatusCreated && s != http.StatusOK {
		t.Fatalf("comment: %d %v", s, out)
	}
	commentID := out["comment"].(map[string]any)["id"]
	// The owner can't report a review that isn't public yet.
	if s, _ := e.report(e.owner, "comment", commentID, "abuse", ""); s != http.StatusNotFound {
		t.Fatalf("unapproved review reported: %d", s)
	}
	e.db.Model(&models.Comment{}).Where("id = ?", commentID).Update("approved", true)
	for _, tc := range []struct {
		c   apiClient
		typ string
		id  any
	}{{e.user, "listing", e.visible}, {e.user, "provider", e.providerID()}, {e.user, "user", e.ownerID}, {e.owner, "comment", commentID}} {
		if s, out := e.report(tc.c, tc.typ, tc.id, "fraud", "детали"); s != http.StatusCreated || out["report"].(map[string]any)["status"] != "new" {
			t.Fatalf("report %s: %d %v", tc.typ, s, out)
		}
	}
}

func TestReportDuplicatesRateLimitAndNoAutoAction(t *testing.T) {
	e := reportEnv(t)
	s, out := e.report(e.user, "listing", e.visible, "spam", "")
	if s != http.StatusCreated {
		t.Fatalf("first: %d %v", s, out)
	}
	first := int(out["report"].(map[string]any)["id"].(float64))
	// Another open report by the same person on the same thing — even with
	// another reason — is refused.
	if s, out := e.report(e.user, "listing", e.visible, "fraud", ""); s != http.StatusConflict || out["error"] != "duplicate_report" {
		t.Fatalf("duplicate: %d %v", s, out)
	}
	// While in review too.
	e.admin.do("POST", fmt.Sprintf("/api/admin/reports/%d/take", first), nil)
	if s, _ := e.report(e.user, "listing", e.visible, "spam", ""); s != http.StatusConflict {
		t.Fatalf("duplicate while in review: %d", s)
	}
	// A different person may report the same thing.
	if s, _ := e.report(e.admin2, "listing", e.visible, "spam", ""); s != http.StatusCreated {
		t.Fatalf("second reporter: %d", s)
	}
	// Once decided, the same person may report again.
	if s, out := e.admin.do("POST", fmt.Sprintf("/api/admin/reports/%d/decide", first), map[string]any{"decision": "rejected", "reason": "Нет нарушения"}); s != http.StatusOK {
		t.Fatalf("decide: %d %v", s, out)
	}
	if s, _ := e.report(e.user, "listing", e.visible, "spam", "снова"); s != http.StatusCreated {
		t.Fatalf("report after decision: %d", s)
	}

	// No automatic sanction: the listing stays public, nobody is blocked.
	if e.status(e.guest, fmt.Sprintf("/api/listings/%d", e.visible)) != http.StatusOK || !e.catalogIDs()[e.visible] {
		t.Fatal("reports hid the listing")
	}
	var owner models.User
	e.db.First(&owner, e.ownerID)
	if owner.BlockedAt != nil {
		t.Fatal("reports blocked the owner")
	}

	// Rate limit: 10 an hour per reporter (3 already used above).
	tag := strings.ToLower(strings.NewReplacer("/", "-", "_", "-").Replace(t.Name()))
	got429 := false
	for i := 0; i < 10; i++ {
		target := registerUser(t, e.base, "Target", fmt.Sprintf("%s-target%d@example.com", tag, i))
		_ = target
		id := e.idOf(fmt.Sprintf("%s-target%d@example.com", tag, i))
		s, out := e.report(e.user, "user", id, "spam", "")
		if s == http.StatusTooManyRequests {
			if out["error"] != "too_many_reports" || i != 8 {
				t.Fatalf("429 at %d: %v", i, out)
			}
			got429 = true
			break
		}
		if s != http.StatusCreated {
			t.Fatalf("report %d: %d %v", i, s, out)
		}
	}
	if !got429 {
		t.Fatal("no rate limit")
	}
}

func TestReporterIdentityStaysPrivate(t *testing.T) {
	e := reportEnv(t)
	if s, _ := e.report(e.user, "provider", e.providerID(), "abuse", "Грубит клиентам"); s != http.StatusCreated {
		t.Fatalf("report: %d", s)
	}
	// The reported owner: no access to the queue, nothing in their own
	// reports, nothing in their notifications, nothing on their listing.
	if s, _ := e.owner.do("GET", "/api/admin/reports", nil); s != http.StatusForbidden {
		t.Fatalf("owner reads queue: %d", s)
	}
	_, mine := e.owner.do("GET", "/api/reports/mine", nil)
	if len(mine["reports"].([]any)) != 0 {
		t.Fatalf("owner sees reports: %v", mine)
	}
	var n int64
	e.db.Model(&models.Notification{}).Where("user_id = ?", e.ownerID).Count(&n)
	if n != 0 {
		t.Fatalf("owner notified about a report: %d", n)
	}
	_, l := e.guest.do("GET", fmt.Sprintf("/api/providers/%d", e.providerID()), nil)
	if strings.Contains(fmt.Sprint(l), "Plain User") {
		t.Fatalf("provider page shows the reporter: %v", l)
	}
	for k := range l {
		if k != "provider" && k != "listings" && k != "listing_count" {
			t.Fatalf("provider page grew a key %q", k)
		}
	}
	// The reporter sees their own report without the admins' internals.
	_, mine = e.user.do("GET", "/api/reports/mine", nil)
	rs := mine["reports"].([]any)
	if len(rs) != 1 {
		t.Fatalf("reporter's list: %v", mine)
	}
	for _, k := range []string{"resolution", "assignee_id", "resolved_by", "reporter_id", "target_user_id"} {
		if _, has := rs[0].(map[string]any)[k]; has {
			t.Fatalf("reporter view has %s: %v", k, rs[0])
		}
	}
	// Admins do see who reported.
	_, list := e.admin.do("GET", "/api/admin/reports?target_type=provider&status=open", nil)
	r := list["reports"].([]any)[0].(map[string]any)
	if r["reporter"].(map[string]any)["id"].(float64) != float64(e.userID) || r["target_user"].(map[string]any)["id"].(float64) != float64(e.ownerID) {
		t.Fatalf("admin view: %v", r)
	}
}

func TestReportQueueDecisionAndAudit(t *testing.T) {
	e := reportEnv(t)
	adminEmail := strings.ToLower(strings.NewReplacer("/", "-", "_", "-").Replace(t.Name())) + "-admin@example.com"
	adminID := e.idOf(adminEmail)
	_, out := e.report(e.user, "listing", e.visible, "fraud", "Предоплата без договора")
	id := int(out["report"].(map[string]any)["id"].(float64))
	e.report(e.admin2, "listing", e.visible, "spam", "")

	// Filters and the summary.
	_, sum := e.admin.do("GET", "/api/admin/summary", nil)
	if sum["reports_new"].(float64) < 2 {
		t.Fatalf("summary: %v", sum)
	}
	_, list := e.admin.do("GET", fmt.Sprintf("/api/admin/reports?status=new&target_user_id=%d&reason=fraud", e.ownerID), nil)
	if list["total"].(float64) != 1 {
		t.Fatalf("filters: %v", list)
	}
	if s, _ := e.admin.do("GET", "/api/admin/reports?status=weird", nil); s != http.StatusBadRequest {
		t.Fatalf("bad status filter: %d", s)
	}
	s, det := e.admin.do("GET", fmt.Sprintf("/api/admin/reports/%d", id), nil)
	rep := det["report"].(map[string]any)
	if s != http.StatusOK || rep["target"].(map[string]any)["exists"] != true || rep["open_on_same_target"].(float64) != 2 || len(det["related"].([]any)) != 1 {
		t.Fatalf("detail: %d %v", s, det)
	}

	// Take: only once.
	if s, out := e.admin.do("POST", fmt.Sprintf("/api/admin/reports/%d/take", id), nil); s != http.StatusOK || out["status"] != "in_review" {
		t.Fatalf("take: %d %v", s, out)
	}
	if s, out := e.admin2.do("POST", fmt.Sprintf("/api/admin/reports/%d/take", id), nil); s != http.StatusConflict || out["error"] != "not_new" {
		t.Fatalf("second take: %d %v", s, out)
	}
	_, sum = e.admin.do("GET", "/api/admin/summary", nil)
	if sum["reports_mine"].(float64) != 1 {
		t.Fatalf("summary mine: %v", sum)
	}

	// Decide: reason and a valid decision required; exactly once.
	dp := fmt.Sprintf("/api/admin/reports/%d/decide", id)
	for _, bad := range []map[string]any{{"decision": "resolved"}, {"decision": "closed", "reason": "Причина"}, {"decision": "resolved", "reason": " "}} {
		if s, _ := e.admin.do("POST", dp, bad); s != http.StatusBadRequest {
			t.Fatalf("bad decision %v: %d", bad, s)
		}
	}
	// Atomicity: without the audit table the decision rolls back.
	e.db.Migrator().RenameTable("admin_audit_events", "admin_audit_events_off")
	s, _ = e.admin.do("POST", dp, map[string]any{"decision": "resolved", "reason": "Без журнала"})
	e.db.Migrator().RenameTable("admin_audit_events_off", "admin_audit_events")
	var r models.Report
	e.db.First(&r, id)
	if s != http.StatusInternalServerError || r.Status != "in_review" || r.OpenKey == nil {
		t.Fatalf("decision without audit: %d %+v", s, r)
	}
	if s, out := e.admin.do("POST", dp, map[string]any{"decision": "resolved", "reason": "Связались с услугодателем"}); s != http.StatusOK {
		t.Fatalf("decide: %d %v", s, out)
	}
	if s, out := e.admin2.do("POST", dp, map[string]any{"decision": "rejected", "reason": "Поздно"}); s != http.StatusConflict || out["error"] != "already_decided" {
		t.Fatalf("second decision: %d %v", s, out)
	}
	e.db.First(&r, id)
	if r.Status != "resolved" || r.ResolvedBy == nil || *r.ResolvedBy != adminID || r.Resolution != "Связались с услугодателем" || r.OpenKey != nil || r.ResolvedAt == nil {
		t.Fatalf("stored decision: %+v", r)
	}
	var evs []models.AdminAuditEvent
	e.db.Where("target_type = ? AND target_id = ?", "report", id).Order("id").Find(&evs)
	if len(evs) != 2 || evs[0].Action != "report.take" || evs[1].Action != "report.resolve" || evs[1].Reason != r.Resolution || evs[1].ActorID != adminID {
		t.Fatalf("audit: %+v", evs)
	}
	// Still no automatic sanction after a "resolved" decision.
	if e.status(e.guest, fmt.Sprintf("/api/listings/%d", e.visible)) != http.StatusOK {
		t.Fatal("decision hid the listing")
	}
	// The report's own history in the detail view.
	_, det = e.admin.do("GET", fmt.Sprintf("/api/admin/reports/%d", id), nil)
	if len(det["history"].([]any)) != 2 {
		t.Fatalf("history: %v", det["history"])
	}
	// Deleted target: the report remains, marked as gone.
	e.db.Delete(&models.Listing{}, e.visible)
	_, det = e.admin.do("GET", fmt.Sprintf("/api/admin/reports/%d", id), nil)
	if det["report"].(map[string]any)["target"].(map[string]any)["exists"] != false {
		t.Fatalf("deleted target: %v", det["report"])
	}
}

// Stage 4 additions: the reporter's list names the target; an owner sees
// why their listing was hidden; a live blocked session learns the reason.
func TestUserSideModerationFields(t *testing.T) {
	e := reportEnv(t)
	if s, _ := e.report(e.user, "listing", e.visible, "spam", ""); s != http.StatusCreated {
		t.Fatalf("report: %d", s)
	}
	_, mine := e.user.do("GET", "/api/reports/mine", nil)
	r := mine["reports"].([]any)[0].(map[string]any)
	if !strings.HasPrefix(r["target_title"].(string), "Visible ") {
		t.Fatalf("target_title: %v", r)
	}

	e.admin.do("POST", fmt.Sprintf("/api/admin/listings/%d/hide", e.visible), map[string]any{"reason": "Фото чужого агентства"})
	_, own := e.owner.do("GET", "/api/users/me/listings", nil)
	found := false
	for _, it := range own["listings"].([]any) {
		m := it.(map[string]any)
		if int(m["id"].(float64)) == e.visible {
			found = true
			if m["moderation_reason"] != "Фото чужого агентства" || m["moderation_hidden_at"] == nil {
				t.Fatalf("owner view: %v", m)
			}
		}
	}
	if !found {
		t.Fatal("hidden listing missing from the owner's list")
	}
	// The reason never reaches the public payload, even for the owner's own
	// listing page.
	_, pub := e.owner.do("GET", fmt.Sprintf("/api/listings/%d", e.visible), nil)
	if _, has := pub["listing"].(map[string]any)["moderation_reason"]; has {
		t.Fatalf("public payload has the reason: %v", pub)
	}

	e.admin.do("POST", fmt.Sprintf("/api/admin/users/%d/block", e.userID), map[string]any{"reason": "Оскорбления", "duration": "7d"})
	s, out := e.user.do("GET", "/api/auth/me", nil)
	if s != http.StatusUnauthorized || out["error"] != "account_blocked" || out["reason"] != "Оскорбления" || out["blocked_until"] == nil {
		t.Fatalf("live blocked session: %d %v", s, out)
	}
}
