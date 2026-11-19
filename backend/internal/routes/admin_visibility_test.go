package routes_test

import (
	"fmt"
	"net/http"
	"reflect"
	"testing"
	"time"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// adminVisibility reads the computed visibility of listing id from the
// admin's GET /api/users/me/listings.
func (e *adminEnv) adminVisibility(id int) map[string]any {
	e.t.Helper()
	s, out := e.admin.do("GET", "/api/users/me/listings", nil)
	if s != http.StatusOK {
		e.t.Fatalf("admin listings: %d %v", s, out)
	}
	for _, it := range out["listings"].([]any) {
		m := it.(map[string]any)
		if int(m["id"].(float64)) == id {
			return m
		}
	}
	e.t.Fatalf("listing %d not in the admin list", id)
	return nil
}

func reasons(m map[string]any) []string {
	out := []string{}
	for _, r := range m["visibility_reasons"].([]any) {
		out = append(out, r.(string))
	}
	return out
}

// The computed flag must agree with what a visitor actually gets.
func (e *adminEnv) checkVisibility(id int, wantVisible bool, wantReasons ...string) map[string]any {
	e.t.Helper()
	m := e.adminVisibility(id)
	if wantReasons == nil {
		wantReasons = []string{}
	}
	if m["publicly_visible"] != wantVisible || !reflect.DeepEqual(reasons(m), wantReasons) {
		e.t.Fatalf("listing %d: visible=%v reasons=%v, want %v %v", id, m["publicly_visible"], reasons(m), wantVisible, wantReasons)
	}
	s, _ := e.guest.do("GET", fmt.Sprintf("/api/listings/%d", id), nil)
	if (s == http.StatusOK) != wantVisible {
		e.t.Fatalf("listing %d: guest got %d but publicly_visible=%v", id, s, wantVisible)
	}
	return m
}

func TestAdminListingVisibility(t *testing.T) {
	e := setupAdmin(t)
	// A third listing that stays published and unhidden by the admin.
	s, out := e.owner.do("POST", "/api/provider/me/listings", map[string]any{
		"category_id": e.catID(), "name_ru": "Plain", "name_kz": "Plain", "price": 1000, "city": "Алматы",
	})
	if s != http.StatusCreated {
		t.Fatalf("listing: %d %v", s, out)
	}
	plain := int(out["listing"].(map[string]any)["id"].(float64))

	e.checkVisibility(e.visible, true)
	e.checkVisibility(e.unpublish, false, "owner_unpublished")

	// Owners and managers don't get the admin-only fields.
	_, own := e.owner.do("GET", "/api/users/me/listings", nil)
	for _, it := range own["listings"].([]any) {
		m := it.(map[string]any)
		for _, k := range []string{"publicly_visible", "visibility_reasons", "owner_blocked_until"} {
			if _, has := m[k]; has {
				t.Fatalf("owner sees %s: %v", k, m)
			}
		}
	}

	if s, out := e.admin.do("POST", fmt.Sprintf("/api/admin/listings/%d/hide", e.visible), map[string]any{"reason": "Чужие фото"}); s != http.StatusOK {
		t.Fatalf("hide: %d %v", s, out)
	}
	e.checkVisibility(e.visible, false, "admin_hidden")

	// Blocked for a day: every listing of the owner is out, with the term.
	if s, out := e.admin.do("POST", fmt.Sprintf("/api/admin/users/%d/block", e.ownerID), map[string]any{"reason": "Нарушения", "duration": "1d"}); s != http.StatusOK {
		t.Fatalf("block: %d %v", s, out)
	}
	m := e.checkVisibility(plain, false, "owner_blocked")
	if m["owner_blocked_until"] == nil {
		t.Fatalf("no block term: %v", m)
	}
	e.checkVisibility(e.visible, false, "admin_hidden", "owner_blocked")
	e.checkVisibility(e.unpublish, false, "owner_unpublished", "owner_blocked")

	// Unblock: only what was visible before comes back.
	if s, out := e.admin.do("POST", fmt.Sprintf("/api/admin/users/%d/unblock", e.ownerID), map[string]any{"reason": "Разобрались"}); s != http.StatusOK {
		t.Fatalf("unblock: %d %v", s, out)
	}
	if m := e.checkVisibility(plain, true); m["owner_blocked_until"] != nil {
		t.Fatalf("term after unblock: %v", m)
	}
	e.checkVisibility(e.visible, false, "admin_hidden")
	e.checkVisibility(e.unpublish, false, "owner_unpublished")

	// A block whose term has run out no longer counts.
	e.admin.do("POST", fmt.Sprintf("/api/admin/users/%d/block", e.ownerID), map[string]any{"reason": "Снова", "duration": "1d"})
	e.checkVisibility(plain, false, "owner_blocked")
	past := time.Now().UTC().Add(-time.Minute)
	if err := e.db.Model(&models.User{}).Where("id = ?", e.ownerID).Update("blocked_until", past).Error; err != nil {
		t.Fatal(err)
	}
	e.checkVisibility(plain, true)
	e.checkVisibility(e.visible, false, "admin_hidden")
	e.checkVisibility(e.unpublish, false, "owner_unpublished")

	// A permanent block: the reason without an end date.
	if err := e.db.Model(&models.User{}).Where("id = ?", e.ownerID).Updates(map[string]any{"blocked_at": time.Now().UTC(), "blocked_until": nil}).Error; err != nil {
		t.Fatal(err)
	}
	if m := e.checkVisibility(plain, false, "owner_blocked"); m["owner_blocked_until"] != nil {
		t.Fatalf("permanent block has a term: %v", m)
	}
}
