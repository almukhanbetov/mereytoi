package routes_test

import (
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"

	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// adminEnv — one owner (provider) with three listings: visible, unpublished
// by the owner, and hidden by an administrator; plus an admin, a second
// admin and a plain user. Emails are unique per test: the package shares
// one in-memory database.
type adminEnv struct {
	t         *testing.T
	base      string
	db        *gorm.DB
	admin     apiClient
	admin2    apiClient
	user      apiClient
	owner     apiClient
	guest     apiClient
	ownerID   uint
	userID    uint
	admin2ID  uint
	visible   int
	unpublish int
	slug      string
}

func setupAdmin(t *testing.T) *adminEnv {
	t.Helper()
	srv, db := setupTestServer(t)
	tag := strings.ToLower(strings.NewReplacer("/", "-", "_", "-").Replace(t.Name()))
	e := &adminEnv{t: t, base: srv.URL, db: db, guest: apiClient{t: t, base: srv.URL}, slug: "adm-" + tag}
	e.admin = registerAdmin(t, e.base, db, "Admin One", tag+"-admin@example.com")
	e.admin2 = registerAdmin(t, e.base, db, "Admin Two", tag+"-admin2@example.com")
	e.user = registerUser(t, e.base, "Plain User", tag+"-user@example.com")
	e.owner = registerUser(t, e.base, "Owner Person", tag+"-owner@example.com")
	e.ownerID = e.idOf(tag + "-owner@example.com")
	e.userID = e.idOf(tag + "-user@example.com")
	e.admin2ID = e.idOf(tag + "-admin2@example.com")

	if s, out := e.owner.do("POST", "/api/provider", map[string]any{
		"display_name": "Owner Biz " + tag, "city": "Алматы", "phone": "+77001112233",
	}); s != http.StatusCreated {
		t.Fatalf("provider: %d %v", s, out)
	}
	cat := models.Category{Slug: e.slug, NameRu: "Тест", NameKz: "Тест"}
	if err := db.Create(&cat).Error; err != nil {
		t.Fatal(err)
	}
	mk := func(name string) int {
		s, out := e.owner.do("POST", "/api/provider/me/listings", map[string]any{
			"category_id": cat.ID, "name_ru": name, "name_kz": name, "price": 1000, "city": "Алматы",
		})
		if s != http.StatusCreated {
			t.Fatalf("listing %s: %d %v", name, s, out)
		}
		return int(out["listing"].(map[string]any)["id"].(float64))
	}
	e.visible = mk("Visible " + tag)
	e.unpublish = mk("Unpublished " + tag)
	if s, out := e.ownerSetActive(e.unpublish, false, nil); s != http.StatusOK {
		t.Fatalf("unpublish: %d %v", s, out)
	}
	return e
}

// ownerSetActive — the owner's own full edit (PUT needs the whole form),
// flipping is_active; extra fields are merged in to try to smuggle others.
func (e *adminEnv) ownerSetActive(id int, active bool, extra map[string]any) (int, map[string]any) {
	body := map[string]any{
		"category_id": e.catID(), "name_ru": fmt.Sprintf("L%d", id), "name_kz": fmt.Sprintf("L%d", id),
		"price": 1000, "city": "Алматы", "is_active": active,
	}
	for k, v := range extra {
		body[k] = v
	}
	return e.owner.do("PUT", fmt.Sprintf("/api/listings/%d", id), body)
}

func (e *adminEnv) idOf(email string) uint {
	var u models.User
	if err := e.db.Where("email = ?", email).First(&u).Error; err != nil {
		e.t.Fatalf("user %s: %v", email, err)
	}
	return u.ID
}

func (e *adminEnv) catalogIDs() map[int]bool {
	s, out := e.guest.do("GET", "/api/listings?category="+e.slug, nil)
	if s != http.StatusOK {
		e.t.Fatalf("catalog: %d %v", s, out)
	}
	ids := map[int]bool{}
	for _, it := range out["listings"].([]any) {
		ids[int(it.(map[string]any)["id"].(float64))] = true
	}
	return ids
}

func (e *adminEnv) feedIDs() map[int]bool {
	s, out := e.guest.do("GET", "/api/listings/feed?category="+e.slug, nil)
	if s != http.StatusOK {
		e.t.Fatalf("feed: %d %v", s, out)
	}
	ids := map[int]bool{}
	for _, it := range out["items"].([]any) {
		ids[int(it.(map[string]any)["id"].(float64))] = true
	}
	return ids
}

func (e *adminEnv) status(c apiClient, path string) int {
	s, _ := c.do("GET", path, nil)
	return s
}

func (e *adminEnv) isActive(id int) bool {
	var l models.Listing
	if err := e.db.First(&l, id).Error; err != nil {
		e.t.Fatal(err)
	}
	return l.IsActive
}

func (e *adminEnv) auditCount(action string, targetID uint) int64 {
	var n int64
	e.db.Model(&models.AdminAuditEvent{}).Where("action = ? AND target_id = ?", action, targetID).Count(&n)
	return n
}

func TestAdminAPIsRequireAdmin(t *testing.T) {
	e := setupAdmin(t)
	paths := []struct{ method, path string }{
		{"GET", "/api/admin/users"},
		{"GET", fmt.Sprintf("/api/admin/users/%d", e.userID)},
		{"POST", fmt.Sprintf("/api/admin/users/%d/warn", e.userID)},
		{"POST", fmt.Sprintf("/api/admin/users/%d/block", e.userID)},
		{"POST", fmt.Sprintf("/api/admin/users/%d/unblock", e.userID)},
		{"POST", fmt.Sprintf("/api/admin/listings/%d/hide", e.visible)},
		{"POST", fmt.Sprintf("/api/admin/listings/%d/restore", e.visible)},
		{"GET", "/api/admin/audit-events"},
	}
	body := map[string]any{"reason": "проверка прав", "duration": "1d"}
	for _, p := range paths {
		if s, _ := e.guest.do(p.method, p.path, body); s != http.StatusUnauthorized {
			t.Fatalf("guest %s %s: %d", p.method, p.path, s)
		}
		if s, _ := e.user.do(p.method, p.path, body); s != http.StatusForbidden {
			t.Fatalf("user %s %s: %d", p.method, p.path, s)
		}
		if s, _ := e.owner.do(p.method, p.path, body); s != http.StatusForbidden {
			t.Fatalf("provider %s %s: %d", p.method, p.path, s)
		}
	}
	// Nothing happened through the refused calls.
	var u models.User
	e.db.First(&u, e.userID)
	if u.BlockedAt != nil || e.auditCount(models.AdminActionUserBlock, e.userID) != 0 {
		t.Fatalf("refused call changed state: %+v", u)
	}
	if s, out := e.admin.do("GET", "/api/admin/users", nil); s != http.StatusOK {
		t.Fatalf("admin: %d %v", s, out)
	}
}

func TestAdminRoleComesFromDatabase(t *testing.T) {
	e := setupAdmin(t)
	if s := e.status(e.admin2, "/api/admin/users"); s != http.StatusOK {
		t.Fatalf("admin before demotion: %d", s)
	}
	// Demoted: the same, still unexpired token loses admin rights at once
	// but keeps working as a normal session.
	e.db.Model(&models.User{}).Where("id = ?", e.admin2ID).Update("role", "user")
	if s := e.status(e.admin2, "/api/admin/users"); s != http.StatusForbidden {
		t.Fatalf("demoted admin's old token still admin: %d", s)
	}
	if s := e.status(e.admin2, "/api/categories"); s != http.StatusOK {
		t.Fatalf("demoted user lost the normal session: %d", s)
	}
	if s, _ := e.admin2.do("POST", "/api/categories", map[string]any{"slug": "x-demoted", "name_ru": "x", "name_kz": "x"}); s != http.StatusForbidden {
		t.Fatalf("demoted admin used an old admin route: %d", s)
	}
	// Promoted: a plain user's existing token gains admin without re-login.
	e.db.Model(&models.User{}).Where("id = ?", e.userID).Update("role", "admin")
	if s := e.status(e.user, "/api/admin/users"); s != http.StatusOK {
		t.Fatalf("promoted user's token: %d", s)
	}
}

func TestDeletedUsersTokenIsRefused(t *testing.T) {
	e := setupAdmin(t)
	if s := e.status(e.user, "/api/auth/me"); s != http.StatusOK {
		t.Fatalf("before delete: %d", s)
	}
	e.db.Delete(&models.User{}, e.userID)
	if s := e.status(e.user, "/api/auth/me"); s != http.StatusUnauthorized {
		t.Fatalf("deleted user's token accepted: %d", s)
	}
}

func TestBlockStopsExistingTokenAndNewLogin(t *testing.T) {
	e := setupAdmin(t)
	path := fmt.Sprintf("/api/admin/users/%d/block", e.userID)

	// Validation: reason and an agreed duration are required.
	for _, bad := range []map[string]any{
		{"duration": "7d"},
		{"reason": "  ", "duration": "7d"},
		{"reason": "спам", "duration": "2d"},
		{"reason": "спам"},
	} {
		if s, out := e.admin.do("POST", path, bad); s != http.StatusBadRequest {
			t.Fatalf("bad input %v: %d %v", bad, s, out)
		}
	}
	// Never oneself nor another admin.
	adminID := e.idOf(strings.ToLower(strings.NewReplacer("/", "-", "_", "-").Replace(t.Name())) + "-admin@example.com")
	if s, out := e.admin.do("POST", fmt.Sprintf("/api/admin/users/%d/block", adminID), map[string]any{"reason": "self", "duration": "1d"}); s != http.StatusBadRequest || out["error"] != "cannot_target_self" {
		t.Fatalf("self block: %d %v", s, out)
	}
	if s, out := e.admin.do("POST", fmt.Sprintf("/api/admin/users/%d/block", e.admin2ID), map[string]any{"reason": "other", "duration": "1d"}); s != http.StatusForbidden || out["error"] != "cannot_block_admin" {
		t.Fatalf("admin block: %d %v", s, out)
	}
	if s, out := e.admin.do("POST", "/api/admin/users/999999/block", map[string]any{"reason": "nobody", "duration": "1d"}); s != http.StatusNotFound {
		t.Fatalf("unknown user: %d %v", s, out)
	}

	if s := e.status(e.user, "/api/auth/me"); s != http.StatusOK {
		t.Fatalf("before block: %d", s)
	}
	s, out := e.admin.do("POST", path, map[string]any{"reason": "Нарушение правил", "duration": "7d"})
	if s != http.StatusOK || out["blocked_until"] == nil {
		t.Fatalf("block: %d %v", s, out)
	}
	// The token issued before the block is refused on the next request.
	s, out = e.user.do("GET", "/api/auth/me", nil)
	if s != http.StatusUnauthorized || out["error"] != "account_blocked" || out["blocked_until"] == nil {
		t.Fatalf("blocked token: %d %v", s, out)
	}
	// Optional-auth routes treat it as a guest instead of failing.
	if st := e.status(e.user, "/api/listings"); st != http.StatusOK {
		t.Fatalf("blocked token on a public route: %d", st)
	}
	// No new token: a wrong password still says invalid credentials (no
	// account disclosure); the right one says blocked, with the reason.
	email := strings.ToLower(strings.NewReplacer("/", "-", "_", "-").Replace(t.Name())) + "-user@example.com"
	if st, o := e.guest.do("POST", "/api/auth/login", map[string]any{"email": email, "password": "wrong-pass"}); st != http.StatusUnauthorized || o["error"] != "invalid credentials" {
		t.Fatalf("wrong password while blocked: %d %v", st, o)
	}
	st, o := e.guest.do("POST", "/api/auth/login", map[string]any{"email": email, "password": "password123"})
	if st != http.StatusForbidden || o["error"] != "account_blocked" || o["reason"] != "Нарушение правил" || o["token"] != nil {
		t.Fatalf("login while blocked: %d %v", st, o)
	}
	if e.auditCount(models.AdminActionUserBlock, e.userID) != 1 {
		t.Fatal("block not audited exactly once")
	}
}

func TestTemporaryBlockExpires(t *testing.T) {
	e := setupAdmin(t)
	if s, out := e.admin.do("POST", fmt.Sprintf("/api/admin/users/%d/block", e.ownerID), map[string]any{"reason": "Временная блокировка", "duration": "1d"}); s != http.StatusOK {
		t.Fatalf("block: %d %v", s, out)
	}
	var u models.User
	e.db.First(&u, e.ownerID)
	if u.BlockedUntil == nil || u.BlockedUntil.Sub(time.Now()) < 23*time.Hour || u.BlockedUntil.Sub(time.Now()) > 25*time.Hour {
		t.Fatalf("1d block until: %v", u.BlockedUntil)
	}
	if s := e.status(e.owner, "/api/auth/me"); s != http.StatusUnauthorized {
		t.Fatalf("during block: %d", s)
	}
	if e.catalogIDs()[e.visible] {
		t.Fatal("blocked owner's listing in catalog")
	}
	// The term runs out (moved into the past, as the clock would): access
	// and the listings come back without anyone unblocking.
	e.db.Model(&models.User{}).Where("id = ?", e.ownerID).Update("blocked_until", time.Now().UTC().Add(-time.Minute))
	if s := e.status(e.owner, "/api/auth/me"); s != http.StatusOK {
		t.Fatalf("after expiry: %d", s)
	}
	email := strings.ToLower(strings.NewReplacer("/", "-", "_", "-").Replace(t.Name())) + "-owner@example.com"
	if s, out := e.guest.do("POST", "/api/auth/login", map[string]any{"email": email, "password": "password123"}); s != http.StatusOK || out["token"] == nil {
		t.Fatalf("login after expiry: %d %v", s, out)
	}
	if !e.catalogIDs()[e.visible] || e.status(e.guest, fmt.Sprintf("/api/listings/%d", e.visible)) != http.StatusOK {
		t.Fatal("listing not back after the term")
	}
	// A permanent block has no end date.
	if s, out := e.admin.do("POST", fmt.Sprintf("/api/admin/users/%d/block", e.ownerID), map[string]any{"reason": "Бессрочно", "duration": "permanent"}); s != http.StatusOK || out["blocked_until"] != nil {
		t.Fatalf("permanent: %d %v", s, out)
	}
	if s := e.status(e.owner, "/api/auth/me"); s != http.StatusUnauthorized {
		t.Fatalf("permanent block not in force: %d", s)
	}
}

func TestHiddenListingsAndBlockedOwnerAreUnreachableByLink(t *testing.T) {
	e := setupAdmin(t)
	hidden := e.visible
	// A third listing that stays visible until the owner is blocked.
	s, out := e.owner.do("POST", "/api/provider/me/listings", map[string]any{
		"category_id": e.catID(), "name_ru": "Third", "name_kz": "Third", "price": 1000, "city": "Алматы",
	})
	if s != http.StatusCreated {
		t.Fatalf("third: %d %v", s, out)
	}
	third := int(out["listing"].(map[string]any)["id"].(float64))

	// Reason required for hiding.
	if s, _ := e.admin.do("POST", fmt.Sprintf("/api/admin/listings/%d/hide", hidden), map[string]any{"reason": ""}); s != http.StatusBadRequest {
		t.Fatalf("hide without reason: %d", s)
	}
	if s, out := e.admin.do("POST", fmt.Sprintf("/api/admin/listings/%d/hide", hidden), map[string]any{"reason": "Недостоверные данные"}); s != http.StatusOK {
		t.Fatalf("hide: %d %v", s, out)
	}
	if !e.isActive(hidden) {
		t.Fatal("hiding changed the owner's is_active")
	}
	lp := fmt.Sprintf("/api/listings/%d", hidden)
	for _, p := range []string{lp, lp + "/halls", lp + "/menus", lp + "/comments"} {
		if s := e.status(e.guest, p); s != http.StatusNotFound {
			t.Fatalf("guest %s: %d", p, s)
		}
		if s := e.status(e.user, p); s != http.StatusNotFound {
			t.Fatalf("other user %s: %d", p, s)
		}
	}
	if s := e.status(e.owner, lp); s != http.StatusOK {
		t.Fatalf("owner can't see own hidden listing: %d", s)
	}
	if s := e.status(e.admin, lp); s != http.StatusOK {
		t.Fatalf("admin can't see hidden listing: %d", s)
	}
	if e.catalogIDs()[hidden] || e.feedIDs()[hidden] {
		t.Fatal("hidden listing in catalog/feed")
	}
	if s, _ := e.guest.do("POST", lp+"/view", nil); s != http.StatusNotFound {
		t.Fatalf("view counted on hidden: %d", s)
	}
	// The owner can't undo it: their switch changes is_active only.
	if s, out := e.ownerSetActive(hidden, true, map[string]any{"moderation_hidden_at": nil, "moderation_reason": ""}); s != http.StatusOK {
		t.Fatalf("owner update: %d %v", s, out)
	}
	if e.status(e.guest, lp) != http.StatusNotFound || e.catalogIDs()[hidden] {
		t.Fatal("owner undid the administrator's hiding")
	}

	// Blocking the owner takes every listing of theirs out, by link too.
	if !e.catalogIDs()[third] {
		t.Fatal("third should be visible before the block")
	}
	if s, out := e.admin.do("POST", fmt.Sprintf("/api/admin/users/%d/block", e.ownerID), map[string]any{"reason": "Жалобы клиентов", "duration": "30d"}); s != http.StatusOK {
		t.Fatalf("block: %d %v", s, out)
	}
	tp := fmt.Sprintf("/api/listings/%d", third)
	if e.status(e.guest, tp) != http.StatusNotFound || e.catalogIDs()[third] || e.feedIDs()[third] {
		t.Fatal("blocked owner's listing still reachable")
	}
	var p models.Provider
	e.db.Where("user_id = ?", e.ownerID).First(&p)
	if s := e.status(e.guest, fmt.Sprintf("/api/providers/%d", p.ID)); s != http.StatusNotFound {
		t.Fatalf("blocked owner's provider profile: %d", s)
	}
	if s, _ := e.user.do("POST", "/api/provider-chat/start", map[string]any{"provider_id": p.ID, "message": "hi"}); s == http.StatusCreated || s == http.StatusOK {
		t.Fatalf("chat started with a blocked provider: %d", s)
	}
	if s := e.status(e.admin, tp); s != http.StatusOK {
		t.Fatalf("admin can't inspect blocked owner's listing: %d", s)
	}
}

func (e *adminEnv) catID() uint {
	var c models.Category
	e.db.Where("slug = ?", e.slug).First(&c)
	return c.ID
}

func TestUnblockRestoresOnlyPreviouslyVisibleListings(t *testing.T) {
	e := setupAdmin(t)
	s, out := e.owner.do("POST", "/api/provider/me/listings", map[string]any{
		"category_id": e.catID(), "name_ru": "AdminHidden", "name_kz": "AdminHidden", "price": 1000, "city": "Алматы",
	})
	if s != http.StatusCreated {
		t.Fatalf("listing: %d %v", s, out)
	}
	adminHidden := int(out["listing"].(map[string]any)["id"].(float64))
	if s, out := e.admin.do("POST", fmt.Sprintf("/api/admin/listings/%d/hide", adminHidden), map[string]any{"reason": "Отдельное скрытие"}); s != http.StatusOK {
		t.Fatalf("hide: %d %v", s, out)
	}
	before := map[int]bool{e.visible: e.isActive(e.visible), e.unpublish: e.isActive(e.unpublish), adminHidden: e.isActive(adminHidden)}

	if s, out := e.admin.do("POST", fmt.Sprintf("/api/admin/users/%d/block", e.ownerID), map[string]any{"reason": "Проверка", "duration": "permanent"}); s != http.StatusOK {
		t.Fatalf("block: %d %v", s, out)
	}
	if len(e.catalogIDs()) != 0 {
		t.Fatalf("blocked owner's listings visible: %v", e.catalogIDs())
	}
	// Unblock: reason required; not_blocked on a second try.
	up := fmt.Sprintf("/api/admin/users/%d/unblock", e.ownerID)
	if s, _ := e.admin.do("POST", up, map[string]any{}); s != http.StatusBadRequest {
		t.Fatalf("unblock without reason: %d", s)
	}
	if s, out := e.admin.do("POST", up, map[string]any{"reason": "Разобрались"}); s != http.StatusOK {
		t.Fatalf("unblock: %d %v", s, out)
	}
	if s, out := e.admin.do("POST", up, map[string]any{"reason": "Снова"}); s != http.StatusConflict || out["error"] != "not_blocked" {
		t.Fatalf("second unblock: %d %v", s, out)
	}
	cat := e.catalogIDs()
	if !cat[e.visible] || cat[e.unpublish] || cat[adminHidden] || len(cat) != 1 {
		t.Fatalf("after unblock catalog = %v, want only %d", cat, e.visible)
	}
	if e.status(e.guest, fmt.Sprintf("/api/listings/%d", adminHidden)) != http.StatusNotFound {
		t.Fatal("admin-hidden listing published by unblock")
	}
	for id, was := range before {
		if e.isActive(id) != was {
			t.Fatalf("listing %d is_active changed by block/unblock", id)
		}
	}
	if s := e.status(e.owner, "/api/auth/me"); s != http.StatusOK {
		t.Fatalf("owner's old token after unblock: %d", s)
	}
	// Restore brings the hidden one back; the owner's unpublished stays out.
	if s, out := e.admin.do("POST", fmt.Sprintf("/api/admin/listings/%d/restore", adminHidden), map[string]any{"reason": "Исправлено"}); s != http.StatusOK {
		t.Fatalf("restore: %d %v", s, out)
	}
	if s, out := e.admin.do("POST", fmt.Sprintf("/api/admin/listings/%d/restore", adminHidden), map[string]any{"reason": "Ещё раз"}); s != http.StatusConflict {
		t.Fatalf("second restore: %d %v", s, out)
	}
	if cat := e.catalogIDs(); !cat[adminHidden] || cat[e.unpublish] {
		t.Fatalf("after restore: %v", cat)
	}
}

func TestAdminActionsAndAuditAreConsistent(t *testing.T) {
	e := setupAdmin(t)
	adminEmail := strings.ToLower(strings.NewReplacer("/", "-", "_", "-").Replace(t.Name())) + "-admin@example.com"
	adminID := e.idOf(adminEmail)

	steps := []struct {
		path, action string
		target       uint
		body         map[string]any
	}{
		{fmt.Sprintf("/api/admin/users/%d/warn", e.userID), models.AdminActionUserWarn, e.userID, map[string]any{"reason": "Предупреждение за спам"}},
		{fmt.Sprintf("/api/admin/users/%d/block", e.userID), models.AdminActionUserBlock, e.userID, map[string]any{"reason": "Блок", "duration": "7d"}},
		{fmt.Sprintf("/api/admin/users/%d/unblock", e.userID), models.AdminActionUserUnblock, e.userID, map[string]any{"reason": "Снят"}},
		{fmt.Sprintf("/api/admin/listings/%d/hide", e.visible), models.AdminActionListingHide, uint(e.visible), map[string]any{"reason": "Скрыть"}},
		{fmt.Sprintf("/api/admin/listings/%d/restore", e.visible), models.AdminActionListingRestore, uint(e.visible), map[string]any{"reason": "Вернуть"}},
	}
	for _, st := range steps {
		if s, out := e.admin.do("POST", st.path, st.body); s != http.StatusOK {
			t.Fatalf("%s: %d %v", st.path, s, out)
		}
		var ev models.AdminAuditEvent
		if err := e.db.Where("action = ? AND target_id = ?", st.action, st.target).Order("id desc").First(&ev).Error; err != nil {
			t.Fatalf("%s not audited: %v", st.action, err)
		}
		if ev.ActorID != adminID || ev.Reason != st.body["reason"] || ev.CreatedAt.IsZero() {
			t.Fatalf("%s audit row wrong: %+v", st.action, ev)
		}
		if strings.Contains(strings.ToLower(ev.Changes), "password") || strings.Contains(strings.ToLower(ev.Changes), "token") {
			t.Fatalf("audit changes carry a secret-looking field: %s", ev.Changes)
		}
	}
	// Notifications for the user: warning, block, unblock — none names the admin.
	var notes []models.Notification
	e.db.Where("user_id = ? AND type IN ?", e.userID, []string{models.NotifAdminWarning, models.NotifAccountBlocked, models.NotifAccountUnblocked}).Find(&notes)
	if len(notes) != 3 {
		t.Fatalf("notifications: %d", len(notes))
	}
	for _, n := range notes {
		if n.ActorID != nil || !strings.Contains(n.Payload, "reason") {
			t.Fatalf("notification %+v", n)
		}
	}
	// Self-warning refused, nothing written.
	if s, _ := e.admin.do("POST", fmt.Sprintf("/api/admin/users/%d/warn", adminID), map[string]any{"reason": "сам себе"}); s != http.StatusBadRequest {
		t.Fatalf("self warn: %d", s)
	}
	if e.auditCount(models.AdminActionUserWarn, adminID) != 0 {
		t.Fatal("refused action audited")
	}

	// The log API: filter by target, newest first, with actor name.
	s, out := e.admin.do("GET", fmt.Sprintf("/api/admin/audit-events?target_type=user&target_id=%d", e.userID), nil)
	if s != http.StatusOK {
		t.Fatalf("audit list: %d %v", s, out)
	}
	evs := out["events"].([]any)
	if len(evs) != 3 || evs[0].(map[string]any)["action"] != models.AdminActionUserUnblock || evs[0].(map[string]any)["actor_name"] != "Admin One" {
		t.Fatalf("audit list content: %v", evs)
	}

	// Atomicity: if the audit row can't be written, the action rolls back.
	if err := e.db.Migrator().RenameTable("admin_audit_events", "admin_audit_events_off"); err != nil {
		t.Fatal(err)
	}
	s, out = e.admin.do("POST", fmt.Sprintf("/api/admin/users/%d/block", e.userID), map[string]any{"reason": "Без журнала", "duration": "1d"})
	hs, _ := e.admin.do("POST", fmt.Sprintf("/api/admin/listings/%d/hide", e.visible), map[string]any{"reason": "Без журнала"})
	if err := e.db.Migrator().RenameTable("admin_audit_events_off", "admin_audit_events"); err != nil {
		t.Fatal(err)
	}
	if s != http.StatusInternalServerError || hs != http.StatusInternalServerError {
		t.Fatalf("actions without audit: block %d %v, hide %d", s, out, hs)
	}
	var u models.User
	e.db.First(&u, e.userID)
	var l models.Listing
	e.db.First(&l, e.visible)
	if u.BlockedAt != nil || l.ModerationHiddenAt != nil {
		t.Fatalf("action applied without its audit row: user %v listing %v", u.BlockedAt, l.ModerationHiddenAt)
	}
	var n int64
	e.db.Model(&models.Notification{}).Where("user_id = ? AND type = ?", e.userID, models.NotifAccountBlocked).Count(&n)
	if n != 1 {
		t.Fatalf("notification of the rolled-back block kept: %d", n)
	}
}

func TestAdminUserSearchAndProfile(t *testing.T) {
	e := setupAdmin(t)
	tag := strings.ToLower(strings.NewReplacer("/", "-", "_", "-").Replace(t.Name()))

	find := func(query string) map[string]any {
		s, out := e.admin.do("GET", "/api/admin/users?"+query, nil)
		if s != http.StatusOK {
			t.Fatalf("search %s: %d %v", query, s, out)
		}
		return out
	}
	ids := func(out map[string]any) []uint {
		var r []uint
		for _, u := range out["users"].([]any) {
			r = append(r, uint(u.(map[string]any)["id"].(float64)))
		}
		return r
	}
	if got := ids(find("q=" + tag + "-owner")); len(got) != 1 || got[0] != e.ownerID {
		t.Fatalf("by email: %v", got)
	}
	if got := ids(find("q=Owner+Biz+" + tag)); len(got) != 1 || got[0] != e.ownerID {
		t.Fatalf("by provider name: %v", got)
	}
	if got := ids(find("q=7001112233&provider=1")); !containsUserID(got, e.ownerID) {
		t.Fatalf("by provider phone digits: %v", got)
	}
	out := find("q=" + tag + "&per_page=2&page=1")
	if out["total"].(float64) != 4 || len(out["users"].([]any)) != 2 {
		t.Fatalf("paging: %v", out)
	}
	if len(find("q=" + tag + "&per_page=2&page=3")["users"].([]any)) != 0 {
		t.Fatal("page past the end not empty")
	}
	// No secret column in the DTO.
	raw := fmt.Sprint(out)
	for _, k := range []string{"password", "recovery_code", "telegram_chat"} {
		if strings.Contains(strings.ToLower(raw), k) {
			t.Fatalf("search response leaks %s: %s", k, raw)
		}
	}
	e.admin.do("POST", fmt.Sprintf("/api/admin/users/%d/block", e.userID), map[string]any{"reason": "Фильтр", "duration": "1d"})
	if got := ids(find("q=" + tag + "&blocked=1")); len(got) != 1 || got[0] != e.userID {
		t.Fatalf("blocked filter: %v", got)
	}

	s, prof := e.admin.do("GET", fmt.Sprintf("/api/admin/users/%d", e.ownerID), nil)
	if s != http.StatusOK {
		t.Fatalf("profile: %d %v", s, prof)
	}
	user := prof["user"].(map[string]any)
	if user["provider"] == nil || user["listings_count"].(float64) != 2 {
		t.Fatalf("profile user: %v", user)
	}
	vis := map[int]bool{}
	for _, l := range prof["listings"].([]any) {
		m := l.(map[string]any)
		vis[int(m["id"].(float64))] = m["publicly_visible"].(bool)
	}
	if !vis[e.visible] || vis[e.unpublish] {
		t.Fatalf("profile listing visibility: %v", vis)
	}
	if s, _ := e.admin.do("GET", "/api/admin/users/999999", nil); s != http.StatusNotFound {
		t.Fatalf("unknown profile: %d", s)
	}
}

// TestBlockedOwnerAndHiddenListingLeaveAds — no ad for a blocked owner or an
// administrator-hidden listing; the paid term isn't touched.
func TestBlockedOwnerAndHiddenListingLeaveAds(t *testing.T) {
	e := setupPromotions(t, nil, true)
	e.settings(true, 2500)
	owner := e.provider("Owner Blocked Ads")
	var ids []uint
	for i := 0; i < 3; i++ {
		ids = append(ids, e.listing(owner, fmt.Sprintf("BA%d", i), "Алматы", e.cat))
	}
	e.buyGoogle(owner, ids[0], "GPA.BLOCKADS")
	viewer := registerUser(t, e.base, "Viewer BA", "viewer@blockads.test")
	if got := promotedIDs(e.feed(viewer, "category=hosts").items); len(got) != 1 {
		t.Fatalf("ad expected: %v", got)
	}
	var promo models.Promotion
	e.db.Where("listing_id = ?", ids[0]).First(&promo)

	// Administrator hides the advertised listing: the ad goes at once.
	if s, out := e.admin.do("POST", fmt.Sprintf("/api/admin/listings/%d/hide", ids[0]), map[string]any{"reason": "Проверка рекламы"}); s != http.StatusOK {
		t.Fatalf("hide: %d %v", s, out)
	}
	if got := promotedIDs(e.feed(viewer, "category=hosts").items); len(got) != 0 {
		t.Fatalf("hidden listing advertised: %v", got)
	}
	e.admin.do("POST", fmt.Sprintf("/api/admin/listings/%d/restore", ids[0]), map[string]any{"reason": "Вернуть"})
	if got := promotedIDs(e.feed(viewer, "category=hosts").items); len(got) != 1 {
		t.Fatalf("ad not back after restore: %v", got)
	}

	// Owner blocked: no ad, no organic listing.
	var ownerUser models.User
	e.db.Where("email LIKE ?", "owner.blocked.ads@%").First(&ownerUser)
	if s, out := e.admin.do("POST", fmt.Sprintf("/api/admin/users/%d/block", ownerUser.ID), map[string]any{"reason": "Реклама", "duration": "permanent"}); s != http.StatusOK {
		t.Fatalf("block: %d %v", s, out)
	}
	page := e.feed(viewer, "category=hosts")
	if got := promotedIDs(page.items); len(got) != 0 {
		t.Fatalf("blocked owner advertised: %v", got)
	}
	for _, it := range page.items {
		for _, id := range ids {
			if uint(it["id"].(float64)) == id {
				t.Fatalf("blocked owner's listing %d in feed", id)
			}
		}
	}
	// The paid promotion row itself is untouched (no compensation yet).
	var after models.Promotion
	e.db.First(&after, promo.ID)
	if after.Status != promo.Status || !after.EndsAt.Equal(promo.EndsAt) {
		t.Fatalf("promotion changed by block: %+v -> %+v", promo, after)
	}
}

func containsUserID(ids []uint, id uint) bool {
	for _, x := range ids {
		if x == id {
			return true
		}
	}
	return false
}

// TestUnpublishedListingClosedByLinkPublicOneUnchanged — an owner-unpublished
// listing is closed to visitors by direct link and on every public
// sub-resource, still readable by its owner and admins; a published one
// opens exactly as before.
func TestUnpublishedListingClosedByLinkPublicOneUnchanged(t *testing.T) {
	e := setupAdmin(t)
	pub := fmt.Sprintf("/api/listings/%d", e.visible)
	unp := fmt.Sprintf("/api/listings/%d", e.unpublish)
	for _, sub := range []string{"", "/halls", "/menus", "/comments"} {
		if s := e.status(e.guest, pub+sub); s != http.StatusOK {
			t.Fatalf("public listing %s for a guest: %d", sub, s)
		}
		if s := e.status(e.user, pub+sub); s != http.StatusOK {
			t.Fatalf("public listing %s for another user: %d", sub, s)
		}
		if s := e.status(e.guest, unp+sub); s != http.StatusNotFound {
			t.Fatalf("unpublished %s for a guest: %d", sub, s)
		}
		if s := e.status(e.user, unp+sub); s != http.StatusNotFound {
			t.Fatalf("unpublished %s for another user: %d", sub, s)
		}
		if s := e.status(e.owner, unp+sub); s != http.StatusOK {
			t.Fatalf("unpublished %s for its owner: %d", sub, s)
		}
		if s := e.status(e.admin, unp+sub); s != http.StatusOK {
			t.Fatalf("unpublished %s for an admin: %d", sub, s)
		}
	}
	if s, _ := e.guest.do("POST", unp+"/view", nil); s != http.StatusNotFound {
		t.Fatalf("view counted on unpublished: %d", s)
	}
	if s, _ := e.user.do("POST", unp+"/comments", map[string]any{"rating": 5, "text": "x"}); s != http.StatusNotFound {
		t.Fatalf("review on unpublished: %d", s)
	}
	// The public listing's payload is unchanged: no moderation fields.
	_, out := e.guest.do("GET", pub, nil)
	l := out["listing"].(map[string]any)
	if _, has := l["moderation_hidden_at"]; has {
		t.Fatalf("public payload grew a moderation field: %v", l)
	}
	if _, has := l["moderation_reason"]; has {
		t.Fatalf("moderation reason exposed: %v", l)
	}
	// Republishing by the owner opens it again; an admin's hiding can't be
	// bypassed that way.
	if s, out := e.ownerSetActive(e.unpublish, true, nil); s != http.StatusOK {
		t.Fatalf("republish: %d %v", s, out)
	}
	if s := e.status(e.guest, unp); s != http.StatusOK {
		t.Fatalf("republished listing for a guest: %d", s)
	}
	e.admin.do("POST", fmt.Sprintf("/api/admin/listings/%d/hide", e.unpublish), map[string]any{"reason": "Модерация"})
	for _, active := range []bool{false, true} {
		if s, out := e.ownerSetActive(e.unpublish, active, map[string]any{"moderation_hidden_at": nil}); s != http.StatusOK {
			t.Fatalf("owner toggle: %d %v", s, out)
		}
		if s := e.status(e.guest, unp); s != http.StatusNotFound || e.catalogIDs()[e.unpublish] {
			t.Fatalf("owner bypassed the hiding with is_active=%v: %d", active, s)
		}
	}
}
