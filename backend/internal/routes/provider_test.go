package routes_test

import (
	"net/http"
	"testing"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// TestProviderProfileLifecycle covers brief sections 2-4: no profile yet ->
// 404, create it, can't create a second one, can update it.
func TestProviderProfileLifecycle(t *testing.T) {
	srv, _ := setupTestServer(t)
	base := srv.URL
	user := registerUser(t, base, "Dana", "provider-lifecycle@example.com")

	status, out := user.do("GET", "/api/provider/me", nil)
	if status != http.StatusNotFound {
		t.Fatalf("expected 404 before any profile exists, got %d %v", status, out)
	}

	status, out = user.do("POST", "/api/provider", map[string]any{
		"display_name": "Dana Events", "city": "Алматы", "phone": "+77001234567",
	})
	if status != http.StatusCreated {
		t.Fatalf("create provider: %d %v", status, out)
	}
	provider := out["provider"].(map[string]any)
	if provider["status"] != "active" {
		t.Fatalf("expected a self-serve profile to land on active (no moderation UI this stage), got %v", provider["status"])
	}

	status, out = user.do("POST", "/api/provider", map[string]any{"display_name": "Second Attempt"})
	if status != http.StatusConflict {
		t.Fatalf("a second provider profile for the same user must be rejected, got %d %v", status, out)
	}

	status, out = user.do("PUT", "/api/provider/me", map[string]any{
		"display_name": "Dana Events KZ", "city": "Астана",
	})
	if status != http.StatusOK {
		t.Fatalf("update provider: %d %v", status, out)
	}
	if out["provider"].(map[string]any)["city"] != "Астана" {
		t.Fatalf("expected updated city, got %v", out["provider"])
	}

	status, out = user.do("GET", "/api/provider/me", nil)
	if status != http.StatusOK || out["provider"].(map[string]any)["display_name"] != "Dana Events KZ" {
		t.Fatalf("expected the updated profile back: %d %v", status, out)
	}
}

// TestProviderMustExistBeforeCreatingListings covers brief section 4: "Мои
// услуги" is gated on having a provider profile first.
func TestProviderMustExistBeforeCreatingListings(t *testing.T) {
	srv, _ := setupTestServer(t)
	base := srv.URL
	user := registerUser(t, base, "NoProfile", "no-provider-yet@example.com")

	status, out := user.do("POST", "/api/provider/me/listings", map[string]any{
		"category_id": 1, "name_ru": "Тест", "name_kz": "Тест",
	})
	if status != http.StatusForbidden {
		t.Fatalf("expected 403 with no provider profile yet, got %d %v", status, out)
	}
}

// TestProviderListingLifecycleAndOwnership is the end-to-end path: create a
// provider profile, list a service, see it in "Мои услуги"
// (/api/users/me/listings, reused rather than duplicated — brief section
// 12), toggle publication, and delete it — while another random user can
// touch none of it and an admin can touch all of it (brief section 13).
func TestProviderListingLifecycleAndOwnership(t *testing.T) {
	srv, db := setupTestServer(t)
	base := srv.URL

	owner := registerUser(t, base, "Aigerim Host", "provider-owner@example.com")
	stranger := registerUser(t, base, "Stranger", "provider-stranger@example.com")
	admin := registerAdmin(t, base, db, "Admin", "provider-admin@example.com")

	status, out := owner.do("POST", "/api/provider", map[string]any{"display_name": "Aigerim MC", "city": "Алматы"})
	if status != http.StatusCreated {
		t.Fatalf("create provider: %d %v", status, out)
	}

	// Seeded directly (not via seedListing/HTTP) with a clean, space-free
	// slug: this package's tests all share one process-wide in-memory DB
	// (see setupTestServer's own fixed DSN), so category=<slug> query
	// params built by simple string concatenation below must never risk
	// picking up another test's slug containing spaces.
	category := models.Category{Slug: "provider-test-hosts", NameRu: "Ведущие", NameKz: "Ведущие"}
	if err := db.Create(&category).Error; err != nil {
		t.Fatalf("seed category: %v", err)
	}
	categoryID := int(category.ID)

	status, out = owner.do("POST", "/api/provider/me/listings", map[string]any{
		"category_id": categoryID, "name_ru": "Ведущая Айгерим", "name_kz": "Жүргізуші Айгерім",
		"price": 150000, "price_type": "per_event", "city": "Алматы",
	})
	if status != http.StatusCreated {
		t.Fatalf("create own listing: %d %v", status, out)
	}
	listing := out["listing"].(map[string]any)
	listingID := int(listing["id"].(float64))
	if listing["price_type"] != "per_event" {
		t.Fatalf("expected price_type to round-trip, got %v", listing)
	}

	// Shows up in "Мои услуги" — the reused /api/users/me/listings.
	status, out = owner.do("GET", "/api/users/me/listings", nil)
	if status != http.StatusOK {
		t.Fatalf("my listings: %d %v", status, out)
	}
	mine := out["listings"].([]any)
	if len(mine) != 1 || int(mine[0].(map[string]any)["id"].(float64)) != listingID {
		t.Fatalf("expected exactly the new listing in Мои услуги, got %v", mine)
	}
	if mine[0].(map[string]any)["role"] != "owner" {
		t.Fatalf("expected owner role on Мои услуги row, got %v", mine[0])
	}

	// Shows up in the public catalog with the provider's name attached
	// (brief section 8).
	status, out = owner.do("GET", "/api/listings?category="+category.Slug, nil)
	if status != http.StatusOK {
		t.Fatalf("public catalog: %d %v", status, out)
	}
	found := false
	for _, row := range out["listings"].([]any) {
		m := row.(map[string]any)
		if int(m["id"].(float64)) == listingID {
			found = true
			prov, ok := m["provider"].(map[string]any)
			if !ok || prov["display_name"] != "Aigerim MC" {
				t.Fatalf("expected provider brief on the catalog card, got %v", m["provider"])
			}
		}
	}
	if !found {
		t.Fatalf("new listing should appear in the public catalog")
	}

	// Service detail page's provider block (brief section 9).
	status, out = owner.do("GET", "/api/listings/"+itoa(listingID), nil)
	if status != http.StatusOK {
		t.Fatalf("get listing: %d %v", status, out)
	}
	detail := out["listing"].(map[string]any)
	prov, ok := detail["provider"].(map[string]any)
	if !ok || prov["display_name"] != "Aigerim MC" || prov["city"] != "Алматы" {
		t.Fatalf("expected full provider block on detail, got %v", detail["provider"])
	}

	// A stranger can neither edit nor delete this listing (brief section 13).
	status, _ = stranger.do("PUT", "/api/listings/"+itoa(listingID), map[string]any{
		"category_id": categoryID, "name_ru": "Hijacked", "name_kz": "Hijacked",
	})
	if status != http.StatusForbidden {
		t.Fatalf("expected 403 for a non-owner edit, got %d", status)
	}
	status, _ = stranger.do("DELETE", "/api/listings/"+itoa(listingID), nil)
	if status != http.StatusForbidden {
		t.Fatalf("expected 403 for a non-owner delete, got %d", status)
	}

	// Anonymous has no management access at all (brief section 13).
	anon := apiClient{t: t, base: base}
	status, _ = anon.do("PUT", "/api/listings/"+itoa(listingID), map[string]any{})
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401 for an anonymous edit attempt, got %d", status)
	}

	// The owner can toggle publication off without touching anything else.
	status, out = owner.do("PUT", "/api/listings/"+itoa(listingID), map[string]any{
		"category_id": categoryID, "name_ru": "Ведущая Айгерим", "name_kz": "Жүргізуші Айгерім",
		"price": 150000, "price_type": "per_event", "city": "Алматы", "is_active": false,
	})
	if status != http.StatusOK || out["listing"].(map[string]any)["is_active"] != false {
		t.Fatalf("expected the owner to unpublish their own listing: %d %v", status, out)
	}
	status, out = anon.do("GET", "/api/listings?category="+category.Slug, nil)
	for _, row := range out["listings"].([]any) {
		if int(row.(map[string]any)["id"].(float64)) == listingID {
			t.Fatalf("an unpublished listing must not appear in the public catalog")
		}
	}

	// Admin can still manage it despite having no ListingManager row.
	status, out = admin.do("PUT", "/api/listings/"+itoa(listingID), map[string]any{
		"category_id": categoryID, "name_ru": "Ведущая Айгерим", "name_kz": "Жүргізуші Айгерім",
		"price": 150000, "price_type": "per_event", "city": "Алматы", "is_active": true,
	})
	if status != http.StatusOK {
		t.Fatalf("admin should be able to manage any listing: %d %v", status, out)
	}

	// The owner deletes their own listing.
	status, out = owner.do("DELETE", "/api/listings/"+itoa(listingID), nil)
	if status != http.StatusOK {
		t.Fatalf("owner delete: %d %v", status, out)
	}
	status, out = owner.do("GET", "/api/users/me/listings", nil)
	if status != http.StatusOK || len(out["listings"].([]any)) != 0 {
		t.Fatalf("Мои услуги should be empty after delete: %d %v", status, out)
	}
}

// TestUploadsRequireAuthNotAdmin — Этап 11 opened image uploads to any
// authenticated user (a provider adding photos to their own service), but
// anonymous still can't reach it, and video stays admin-only.
func TestUploadsRequireAuthNotAdmin(t *testing.T) {
	srv, db := setupTestServer(t)
	base := srv.URL
	user := registerUser(t, base, "Uploader", "uploader@example.com")
	admin := registerAdmin(t, base, db, "UploadAdmin", "upload-admin@example.com")
	anon := apiClient{t: t, base: base}

	// Anonymous multipart POST with no file at all still proves the auth
	// gate: an unauthenticated caller must get 401, never reach the
	// "no files provided" 400 the handler itself would return.
	status, _ := anon.do("POST", "/api/uploads", nil)
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401 for anonymous upload, got %d", status)
	}
	// An authenticated non-admin reaches the handler (400 for the missing
	// file — proving it's not blocked by RequireAdmin, unlike before).
	status, _ = user.do("POST", "/api/uploads", nil)
	if status == http.StatusUnauthorized || status == http.StatusForbidden {
		t.Fatalf("a plain authenticated user should reach the upload handler, got %d", status)
	}
	// Video stays admin-only.
	status, _ = user.do("POST", "/api/uploads/video", nil)
	if status != http.StatusForbidden {
		t.Fatalf("video upload should still be admin-only, got %d", status)
	}
	status, _ = admin.do("POST", "/api/uploads/video", nil)
	if status == http.StatusForbidden {
		t.Fatalf("admin should still reach video upload, got %d", status)
	}
}
