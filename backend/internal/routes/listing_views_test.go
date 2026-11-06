package routes_test

import (
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

func TestListingViews(t *testing.T) {
	db := openCitySQLite(t)
	if err := db.AutoMigrate(&models.ListingView{}); err != nil {
		t.Fatal(err)
	}
	srv := setupCityServer(t, db)
	category := models.Category{Slug: "hosts", NameRu: "Ведущие", NameKz: "Жүргізуші", Position: 1}
	if err := db.Create(&category).Error; err != nil {
		t.Fatal(err)
	}
	before := time.Date(2026, 1, 1, 12, 0, 0, 0, time.UTC)
	seed := func(name string, active bool) models.Listing {
		l := models.Listing{CategoryID: category.ID, NameRu: name, NameKz: name, IsActive: true, CreatedAt: before, UpdatedAt: before}
		if err := db.Create(&l).Error; err != nil {
			t.Fatal(err)
		}
		if !active {
			if err := db.Model(&l).UpdateColumn("is_active", false).Error; err != nil {
				t.Fatal(err)
			}
		}
		return l
	}
	a, b, hidden := seed("А", true), seed("Б", true), seed("Скрытая", false)

	viewURL := func(id uint) string { return fmt.Sprintf("%s/api/listings/%d/view", srv.URL, id) }
	stored := func(id uint) uint {
		var l models.Listing
		if err := db.First(&l, id).Error; err != nil {
			t.Fatal(err)
		}
		return l.ViewCount
	}
	record := func(url, token string) (uint, bool) {
		out := orderCall(t, http.MethodPost, url, token, nil)
		return uint(out["view_count"].(float64)), out["counted"].(bool)
	}

	// Reading the list or the page counts nothing.
	orderCall(t, http.MethodGet, srv.URL+"/api/listings", "", nil)
	detail := orderCall(t, http.MethodGet, fmt.Sprintf("%s/api/listings/%d", srv.URL, a.ID), "", nil)["listing"].(map[string]any)
	if detail["view_count"].(float64) != 0 || stored(a.ID) != 0 {
		t.Fatalf("a read must not count: %v", detail["view_count"])
	}

	// A guest counts once however often the page reloads.
	if n, counted := record(viewURL(a.ID), ""); n != 1 || !counted {
		t.Fatalf("first view: %d %v", n, counted)
	}
	for i := 0; i < 5; i++ {
		if n, counted := record(viewURL(a.ID), ""); n != 1 || counted {
			t.Fatalf("repeat %d: %d %v", i, n, counted)
		}
	}
	// The counter belongs to one listing.
	if n, _ := record(viewURL(b.ID), ""); n != 1 || stored(a.ID) != 1 {
		t.Fatalf("listing b: %d, a: %d", n, stored(a.ID))
	}

	// A signed-in user is a viewer of their own, also once.
	auth := orderCall(t, http.MethodPost, srv.URL+"/api/auth/register", "", map[string]any{
		"name": "Зритель", "email": "views@example.test", "password": "qa-pass-x12345", "phone": "+77000000999",
	})
	token := auth["token"].(string)
	if n, counted := record(viewURL(a.ID), token); n != 2 || !counted {
		t.Fatalf("signed-in view: %d %v", n, counted)
	}
	if n, counted := record(viewURL(a.ID), token); n != 2 || counted {
		t.Fatalf("signed-in repeat: %d %v", n, counted)
	}

	// Both clients read the same stored number from both endpoints.
	list := orderCall(t, http.MethodGet, srv.URL+"/api/listings", "", nil)["listings"].([]any)
	seen := map[float64]float64{}
	for _, item := range list {
		m := item.(map[string]any)
		seen[m["id"].(float64)] = m["view_count"].(float64)
	}
	if seen[float64(a.ID)] != 2 || seen[float64(b.ID)] != 1 {
		t.Fatalf("list counts: %v", seen)
	}

	// A view isn't an edit, and the raw IP is never stored.
	var fresh models.Listing
	if err := db.First(&fresh, a.ID).Error; err != nil {
		t.Fatal(err)
	}
	if !fresh.UpdatedAt.Equal(before) {
		t.Fatalf("updated_at moved to %v", fresh.UpdatedAt)
	}
	var rows []models.ListingView
	if err := db.Find(&rows).Error; err != nil {
		t.Fatal(err)
	}
	for _, r := range rows {
		if len(r.ViewerHash) != 64 {
			t.Fatalf("viewer not hashed: %q", r.ViewerHash)
		}
	}

	// Past the window the same viewer counts again, and old rows go.
	if err := db.Model(&models.ListingView{}).Where("listing_id = ?", a.ID).
		UpdateColumn("last_viewed_at", time.Now().Add(-2*time.Hour)).Error; err != nil {
		t.Fatal(err)
	}
	if n, counted := record(viewURL(a.ID), ""); n != 3 || !counted {
		t.Fatalf("after the window: %d %v", n, counted)
	}

	// A hidden listing isn't counted; unknown ids are 404.
	for _, id := range []uint{hidden.ID, 999999} {
		res, err := http.Post(viewURL(id), "application/json", nil)
		if err != nil {
			t.Fatal(err)
		}
		res.Body.Close()
		if res.StatusCode != http.StatusNotFound {
			t.Fatalf("id %d: status %d", id, res.StatusCode)
		}
	}
	if stored(hidden.ID) != 0 {
		t.Fatal("hidden listing was counted")
	}

	// An owner's PUT can't set the number, and a stale one can't reset it.
	orderCall(t, http.MethodPost, srv.URL+"/api/provider", token, map[string]any{"display_name": "Бизнес"})
	own := orderCall(t, http.MethodPost, srv.URL+"/api/provider/me/listings", token, map[string]any{
		"category_id": category.ID, "name_ru": "Своя", "name_kz": "Своя", "view_count": 500,
	})["listing"].(map[string]any)
	if own["view_count"].(float64) != 0 {
		t.Fatalf("create accepted a client number: %v", own["view_count"])
	}
	ownID := uint(own["id"].(float64))
	record(viewURL(ownID), "")
	own["view_count"] = 500
	own["name_ru"] = "Своя правка"
	orderCall(t, http.MethodPut, fmt.Sprintf("%s/api/listings/%d", srv.URL, ownID), token, own)
	if stored(ownID) != 1 {
		t.Fatalf("PUT changed the count: %d", stored(ownID))
	}
}
