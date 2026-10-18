package routes_test

import (
	"fmt"
	"net/http"
	"testing"
	"time"

	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// Provider marketplace Stage A: own-profile create/update, experience_years,
// rating protection and GET /api/provider/me/bookings ownership scoping.

func userIDByEmail(t *testing.T, db *gorm.DB, email string) uint {
	t.Helper()
	var u models.User
	if err := db.Where("email = ?", email).First(&u).Error; err != nil {
		t.Fatalf("user %s: %v", email, err)
	}
	return u.ID
}

func becomeProvider(t *testing.T, c apiClient, name string) map[string]any {
	t.Helper()
	status, out := c.do("POST", "/api/provider", map[string]any{"display_name": name})
	if status != http.StatusCreated {
		t.Fatalf("create provider %s: %d %v", name, status, out)
	}
	return out["provider"].(map[string]any)
}

func createOwnListing(t *testing.T, c apiClient, categoryID uint, name string, extra map[string]any) uint {
	t.Helper()
	body := map[string]any{
		"category_id": categoryID, "name_ru": name, "name_kz": name, "price": 50000,
	}
	for k, v := range extra {
		body[k] = v
	}
	status, out := c.do("POST", "/api/provider/me/listings", body)
	if status != http.StatusCreated {
		t.Fatalf("create own listing %s: %d %v", name, status, out)
	}
	return uint(out["listing"].(map[string]any)["id"].(float64))
}

func stageACategory(t *testing.T, db *gorm.DB, slug string) models.Category {
	t.Helper()
	cat := models.Category{Slug: slug, NameRu: slug, NameKz: slug}
	if err := db.Create(&cat).Error; err != nil {
		t.Fatalf("create category: %v", err)
	}
	return cat
}

func TestStageAProviderCreateIsBoundToCaller(t *testing.T) {
	srv, db := setupTestServer(t)
	alice := registerUser(t, srv.URL, "Alice", "stagea-bind-alice@example.com")
	registerUser(t, srv.URL, "Bob", "stagea-bind-bob@example.com")
	aliceID := userIDByEmail(t, db, "stagea-bind-alice@example.com")
	bobID := userIDByEmail(t, db, "stagea-bind-bob@example.com")

	// A body naming someone else's user_id, a status and an id is ignored:
	// the profile belongs to the caller and starts with the server status.
	status, out := alice.do("POST", "/api/provider", map[string]any{
		"display_name": "Alice Events", "user_id": bobID, "id": 999,
		"status": "suspended",
	})
	if status != http.StatusCreated {
		t.Fatalf("create: %d %v", status, out)
	}
	p := out["provider"].(map[string]any)
	if uint(p["user_id"].(float64)) != aliceID {
		t.Fatalf("provider must belong to the caller (%d), got user_id %v", aliceID, p["user_id"])
	}
	if p["status"] != models.ProviderStatusActive {
		t.Fatalf("status must be server-controlled, got %v", p["status"])
	}
	var bobProviders int64
	db.Model(&models.Provider{}).Where("user_id = ?", bobID).Count(&bobProviders)
	if bobProviders != 0 {
		t.Fatal("no provider may be created for another user")
	}
}

func TestStageAOwnerUpdatesOnlyOwnProfile(t *testing.T) {
	srv, db := setupTestServer(t)
	alice := registerUser(t, srv.URL, "Alice", "stagea-upd-alice@example.com")
	bob := registerUser(t, srv.URL, "Bob", "stagea-upd-bob@example.com")
	becomeProvider(t, alice, "Alice Events")
	bobProvider := becomeProvider(t, bob, "Bob Shows")
	bobID := userIDByEmail(t, db, "stagea-upd-bob@example.com")

	status, out := alice.do("PUT", "/api/provider/me", map[string]any{
		"display_name": "Alice Events KZ", "city": "Астана", "description": "Ведущая",
		"user_id": bobID, "id": bobProvider["id"], "status": "suspended",
	})
	if status != http.StatusOK {
		t.Fatalf("update: %d %v", status, out)
	}
	p := out["provider"].(map[string]any)
	if p["display_name"] != "Alice Events KZ" || p["city"] != "Астана" || p["description"] != "Ведущая" {
		t.Fatalf("allowed fields not updated: %v", p)
	}
	if p["status"] != models.ProviderStatusActive {
		t.Fatalf("status must not be client-settable, got %v", p["status"])
	}

	var bobRow models.Provider
	db.Where("user_id = ?", bobID).First(&bobRow)
	if bobRow.DisplayName != "Bob Shows" {
		t.Fatalf("another user's provider must be untouched, got %q", bobRow.DisplayName)
	}
}

func TestStageAExperienceYears(t *testing.T) {
	srv, _ := setupTestServer(t)
	alice := registerUser(t, srv.URL, "Alice", "stagea-exp-alice@example.com")

	for _, bad := range []any{-1, 81, "five"} {
		status, _ := alice.do("POST", "/api/provider", map[string]any{
			"display_name": "Alice", "experience_years": bad,
		})
		if status != http.StatusBadRequest {
			t.Fatalf("experience_years=%v must be rejected, got %d", bad, status)
		}
	}

	status, out := alice.do("POST", "/api/provider", map[string]any{
		"display_name": "Alice", "experience_years": 7,
	})
	if status != http.StatusCreated || out["provider"].(map[string]any)["experience_years"] != float64(7) {
		t.Fatalf("experience_years must be saved: %d %v", status, out)
	}

	// An update that doesn't mention it (older clients) keeps it.
	status, out = alice.do("PUT", "/api/provider/me", map[string]any{"display_name": "Alice 2"})
	if status != http.StatusOK || out["provider"].(map[string]any)["experience_years"] != float64(7) {
		t.Fatalf("omitted experience_years must be kept: %d %v", status, out)
	}
	// 0 is a real value ("less than a year").
	status, out = alice.do("PUT", "/api/provider/me", map[string]any{
		"display_name": "Alice 2", "experience_years": 0,
	})
	if status != http.StatusOK || out["provider"].(map[string]any)["experience_years"] != float64(0) {
		t.Fatalf("experience_years=0 must be saved: %d %v", status, out)
	}
	// Explicit null clears it.
	status, out = alice.do("PUT", "/api/provider/me", map[string]any{
		"display_name": "Alice 2", "experience_years": nil,
	})
	if status != http.StatusOK || out["provider"].(map[string]any)["experience_years"] != nil {
		t.Fatalf("explicit null must clear experience_years: %d %v", status, out)
	}
}

func TestStageALegacyProviderWithNullExperience(t *testing.T) {
	srv, db := setupTestServer(t)
	old := registerUser(t, srv.URL, "Old", "stagea-legacy@example.com")
	oldID := userIDByEmail(t, db, "stagea-legacy@example.com")
	// A row as it existed before the column: no experience_years at all.
	if err := db.Create(&models.Provider{
		UserID: oldID, DisplayName: "Legacy", Status: models.ProviderStatusActive,
	}).Error; err != nil {
		t.Fatal(err)
	}

	status, out := old.do("GET", "/api/provider/me", nil)
	if status != http.StatusOK || out["provider"].(map[string]any)["experience_years"] != nil {
		t.Fatalf("legacy row must read back with null experience: %d %v", status, out)
	}
	status, out = old.do("PUT", "/api/provider/me", map[string]any{"display_name": "Legacy 2"})
	if status != http.StatusOK || out["provider"].(map[string]any)["experience_years"] != nil {
		t.Fatalf("legacy row must stay editable and null: %d %v", status, out)
	}
}

func TestStageARatingIsProtected(t *testing.T) {
	srv, db := setupTestServer(t)
	cat := stageACategory(t, db, "stagea-rating")
	owner := registerUser(t, srv.URL, "Owner", "stagea-rating-owner@example.com")
	admin := registerAdmin(t, srv.URL, db, "Admin", "stagea-rating-admin@example.com")
	becomeProvider(t, owner, "Owner Co")

	id := createOwnListing(t, owner, cat.ID, "Ведущий", map[string]any{"rating": 5.0})
	var l models.Listing
	db.First(&l, id)
	if l.Rating != 0 {
		t.Fatalf("a self-created service must start unrated, got %v", l.Rating)
	}

	// An earned rating, as an admin would have set it.
	db.Model(&l).Update("rating", 4.2)

	update := func(c apiClient, extra map[string]any) int {
		body := map[string]any{"category_id": cat.ID, "name_ru": "Ведущий", "name_kz": "Ведущий"}
		for k, v := range extra {
			body[k] = v
		}
		status, _ := c.do("PUT", fmt.Sprintf("/api/listings/%d", id), body)
		return status
	}
	readRating := func() float32 {
		var r models.Listing
		db.First(&r, id)
		return r.Rating
	}

	if status := update(owner, map[string]any{"rating": 5.0}); status != http.StatusOK {
		t.Fatalf("owner update: %d", status)
	}
	if got := readRating(); got != 4.2 {
		t.Fatalf("owner must not change the rating, got %v", got)
	}
	if status := update(owner, nil); status != http.StatusOK {
		t.Fatalf("owner update: %d", status)
	}
	if got := readRating(); got != 4.2 {
		t.Fatalf("an owner update without rating must not reset it, got %v", got)
	}
	if status := update(admin, map[string]any{"rating": 3.5}); status != http.StatusOK {
		t.Fatalf("admin update: %d", status)
	}
	if got := readRating(); got != 3.5 {
		t.Fatalf("an admin may still set the rating, got %v", got)
	}
}

func TestStageAOwnerCannotManageAnotherProvidersService(t *testing.T) {
	srv, db := setupTestServer(t)
	cat := stageACategory(t, db, "stagea-foreign")
	alice := registerUser(t, srv.URL, "Alice", "stagea-foreign-alice@example.com")
	bob := registerUser(t, srv.URL, "Bob", "stagea-foreign-bob@example.com")
	becomeProvider(t, alice, "Alice Co")
	becomeProvider(t, bob, "Bob Co")
	aliceListing := createOwnListing(t, alice, cat.ID, "Alice service", nil)

	status, _ := bob.do("PUT", fmt.Sprintf("/api/listings/%d", aliceListing), map[string]any{
		"category_id": cat.ID, "name_ru": "Hijacked", "name_kz": "Hijacked",
	})
	if status != http.StatusForbidden {
		t.Fatalf("editing another provider's service must be 403, got %d", status)
	}
	status, _ = bob.do("DELETE", fmt.Sprintf("/api/listings/%d", aliceListing), nil)
	if status != http.StatusForbidden {
		t.Fatalf("deleting another provider's service must be 403, got %d", status)
	}
}

func TestStageAProviderBookings(t *testing.T) {
	srv, db := setupTestServer(t)
	cat := stageACategory(t, db, "stagea-bookings")
	alice := registerUser(t, srv.URL, "Alice", "stagea-bk-alice@example.com")
	bob := registerUser(t, srv.URL, "Bob", "stagea-bk-bob@example.com")
	plain := registerUser(t, srv.URL, "Plain", "stagea-bk-plain@example.com")
	empty := registerUser(t, srv.URL, "Empty", "stagea-bk-empty@example.com")
	becomeProvider(t, alice, "Alice Co")
	becomeProvider(t, bob, "Bob Co")
	becomeProvider(t, empty, "Empty Co")
	aliceListing := createOwnListing(t, alice, cat.ID, "Alice host", nil)
	bobListing := createOwnListing(t, bob, cat.ID, "Bob show", nil)

	ownerID := userIDByEmail(t, db, "stagea-bk-plain@example.com")
	date := time.Date(2027, 6, 12, 0, 0, 0, 0, time.UTC)
	event := models.Event{OwnerID: ownerID, Title: "Той", EventDate: &date}
	if err := db.Create(&event).Error; err != nil {
		t.Fatal(err)
	}

	mk := func(ref, name string, eventID *uint, items ...models.BookingItem) models.Booking {
		b := models.Booking{
			PublicRef: ref, Name: name, Phone: "+77001112233", Message: "Здравствуйте",
			Items: items, EventID: eventID, Status: "new",
		}
		if err := db.Create(&b).Error; err != nil {
			t.Fatal(err)
		}
		return b
	}
	onlyAlice := mk("stagea-b1", "Клиент 1", nil,
		models.BookingItem{ListingID: aliceListing, Name: "Alice host", UnitPrice: 50000, TotalPrice: 50000})
	onlyBob := mk("stagea-b2", "Клиент 2", nil,
		models.BookingItem{ListingID: bobListing, Name: "Bob show", UnitPrice: 70000, TotalPrice: 70000})
	mixed := mk("stagea-b3", "Клиент 3", &event.ID,
		models.BookingItem{ListingID: aliceListing, Name: "Alice host", UnitPrice: 50000, TotalPrice: 50000},
		models.BookingItem{ListingID: bobListing, Name: "Bob show", UnitPrice: 70000, TotalPrice: 70000})

	type row = map[string]any
	get := func(c apiClient, path string) (int, []row) {
		t.Helper()
		status, out := c.do("GET", path, nil)
		var rows []row
		if list, ok := out["bookings"].([]any); ok {
			for _, r := range list {
				rows = append(rows, r.(row))
			}
		}
		return status, rows
	}
	ids := func(rows []row) []uint {
		var out []uint
		for _, r := range rows {
			out = append(out, uint(r["id"].(float64)))
		}
		return out
	}

	t.Run("provider sees bookings of own services only, newest first", func(t *testing.T) {
		status, rows := get(alice, "/api/provider/me/bookings")
		if status != http.StatusOK {
			t.Fatalf("status %d", status)
		}
		got := ids(rows)
		if len(got) != 2 || got[0] != mixed.ID || got[1] != onlyAlice.ID {
			t.Fatalf("alice must see [mixed, onlyAlice], got %v", got)
		}
		for _, id := range got {
			if id == onlyBob.ID {
				t.Fatal("alice must not see a booking with only Bob's service")
			}
		}
	})

	t.Run("mixed booking shows only own items, own subtotal, contact and event date", func(t *testing.T) {
		_, rows := get(alice, "/api/provider/me/bookings")
		m := rows[0]
		items := m["items"].([]any)
		if len(items) != 1 || uint(items[0].(row)["listing_id"].(float64)) != aliceListing {
			t.Fatalf("mixed booking must carry only alice's item, got %v", items)
		}
		if items[0].(row)["title"] != "Alice host" {
			t.Fatalf("item title missing: %v", items[0])
		}
		if m["total"] != float64(50000) {
			t.Fatalf("total must be alice's own subtotal, got %v", m["total"])
		}
		if m["client_name"] != "Клиент 3" || m["client_phone"] != "+77001112233" || m["status"] != "new" {
			t.Fatalf("contact/status missing: %v", m)
		}
		if m["created_at"] == nil || m["event_date"] == nil {
			t.Fatalf("created_at/event_date missing: %v", m)
		}
		parsed, err := time.Parse(time.RFC3339, m["event_date"].(string))
		if err != nil || !parsed.Equal(date) {
			t.Fatalf("event_date = %v, want %v", m["event_date"], date)
		}
	})

	t.Run("the other provider gets their own view of the same mixed booking", func(t *testing.T) {
		_, rows := get(bob, "/api/provider/me/bookings")
		got := ids(rows)
		if len(got) != 2 || got[0] != mixed.ID || got[1] != onlyBob.ID {
			t.Fatalf("bob must see [mixed, onlyBob], got %v", got)
		}
		items := rows[0]["items"].([]any)
		if len(items) != 1 || uint(items[0].(row)["listing_id"].(float64)) != bobListing {
			t.Fatalf("bob must see only his own item, got %v", items)
		}
	})

	t.Run("ids and query params cannot widen the scope", func(t *testing.T) {
		bobID := userIDByEmail(t, db, "stagea-bk-bob@example.com")
		for _, q := range []string{
			fmt.Sprintf("?user_id=%d", bobID),
			fmt.Sprintf("?provider_id=%d", bobID),
			fmt.Sprintf("?listing_id=%d", bobListing),
			fmt.Sprintf("?id=%d", onlyBob.ID),
		} {
			_, rows := get(alice, "/api/provider/me/bookings"+q)
			for _, id := range ids(rows) {
				if id == onlyBob.ID {
					t.Fatalf("query %s leaked bob's booking", q)
				}
			}
		}
		// There is no per-id route to guess at.
		status, _ := alice.do("GET", fmt.Sprintf("/api/provider/me/bookings/%d", onlyBob.ID), nil)
		if status != http.StatusNotFound {
			t.Fatalf("a per-id route must not exist, got %d", status)
		}
	})

	t.Run("a user without a provider profile gets 404 provider_not_found", func(t *testing.T) {
		status, out := plain.do("GET", "/api/provider/me/bookings", nil)
		if status != http.StatusNotFound || out["error"] != "provider_not_found" {
			t.Fatalf("got %d %v", status, out)
		}
	})

	t.Run("unauthenticated is 401", func(t *testing.T) {
		anon := apiClient{t: t, base: srv.URL}
		status, _ := anon.do("GET", "/api/provider/me/bookings", nil)
		if status != http.StatusUnauthorized {
			t.Fatalf("got %d", status)
		}
	})

	t.Run("a provider with no services gets 200 with an empty list", func(t *testing.T) {
		status, out := empty.do("GET", "/api/provider/me/bookings", nil)
		list, ok := out["bookings"].([]any)
		if status != http.StatusOK || !ok || len(list) != 0 {
			t.Fatalf("got %d %v", status, out)
		}
	})
}
