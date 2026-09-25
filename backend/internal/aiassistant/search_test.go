package aiassistant_test

import (
	"testing"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/aiassistant"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// setupDB is a minimal in-memory sqlite DB with just what SearchVenues
// touches — same sqlite-in-memory pattern internal/routes' own tests use
// (see event_security_test.go's setupTestServer), but named per-test (via
// t.Name()) rather than the fixed "file::memory:?cache=shared" DSN that
// pattern uses: this package's tests all seed a fixed "venues" category
// slug, and a shared-cache in-memory sqlite DB stays alive for the whole
// test binary process as long as any connection pool keeps one idle
// connection open — a fixed DSN across multiple test functions collides
// on that slug's unique index instead of each test getting a clean DB.
func setupDB(t *testing.T) *gorm.DB {
	t.Helper()
	dsn := "file:" + t.Name() + "?mode=memory&cache=shared"
	db, err := gorm.Open(sqlite.Open(dsn), &gorm.Config{})
	if err != nil {
		t.Fatalf("open db: %v", err)
	}
	if err := db.AutoMigrate(&models.Category{}, &models.Listing{}, &models.ListingHall{}, &models.ListingMenu{}); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	if err := db.Create(&models.Category{Slug: "venues", NameRu: "Рестораны и локации", NameKz: "Мейрамханалар"}).Error; err != nil {
		t.Fatalf("seed category: %v", err)
	}
	return db
}

func venuesCategory(t *testing.T, db *gorm.DB) models.Category {
	t.Helper()
	var c models.Category
	if err := db.Where("slug = ?", "venues").First(&c).Error; err != nil {
		t.Fatalf("find venues category: %v", err)
	}
	return c
}

// Scenario 1 (stage brief section 4): a matching hall exists — the search
// must return the real listing, its real URL, and its real (non-guessed)
// capacity/price.
func TestSearchVenuesFindsMatch(t *testing.T) {
	db := setupDB(t)
	cat := venuesCategory(t, db)

	listing := models.Listing{CategoryID: cat.ID, NameRu: "Panorama", NameKz: "Panorama", City: "Алматы", IsActive: true}
	if err := db.Create(&listing).Error; err != nil {
		t.Fatalf("seed listing: %v", err)
	}
	db.Create(&models.ListingHall{ListingID: listing.ID, NameRu: "Большой зал", NameKz: "Большой зал", Capacity: 150, IsActive: true})
	db.Create(&models.ListingMenu{ListingID: listing.ID, NameRu: "Банкетное", NameKz: "Банкетное", PricePerGuest: 15000, IsActive: true})

	results, err := aiassistant.SearchVenues(db, aiassistant.SearchVenuesArgs{City: "Алматы", GuestCount: 120, BudgetTotal: 3_000_000})
	if err != nil {
		t.Fatalf("search: %v", err)
	}
	if len(results) != 1 {
		t.Fatalf("expected 1 match, got %d: %+v", len(results), results)
	}
	r := results[0]
	if r.NameRu != "Panorama" || r.URL != "/services/1" {
		t.Fatalf("expected real name/url, got %+v", r)
	}
	if !r.CapacityKnown || r.Capacity != 150 {
		t.Fatalf("expected real capacity 150, got %+v", r)
	}
	if !r.PriceKnown || r.PriceUnit != "per_guest" || r.PriceFrom != 15000 {
		t.Fatalf("expected real per-guest price 15000, got %+v", r)
	}
	if r.EstimatedTotal != 15000*120 {
		t.Fatalf("expected computed estimate, got %d", r.EstimatedTotal)
	}
}

// Scenario 2: no hall fits the requested city/guest count — the search must
// honestly return an empty list, never a made-up fallback.
func TestSearchVenuesNoMatch(t *testing.T) {
	db := setupDB(t)
	cat := venuesCategory(t, db)

	listing := models.Listing{CategoryID: cat.ID, NameRu: "Small Place", NameKz: "Small Place", City: "Алматы", IsActive: true}
	db.Create(&listing)
	db.Create(&models.ListingHall{ListingID: listing.ID, NameRu: "Зал", NameKz: "Зал", Capacity: 40, IsActive: true})

	results, err := aiassistant.SearchVenues(db, aiassistant.SearchVenuesArgs{City: "Алматы", GuestCount: 120})
	if err != nil {
		t.Fatalf("search: %v", err)
	}
	if len(results) != 0 {
		t.Fatalf("expected no match for a too-small hall, got %+v", results)
	}

	results, err = aiassistant.SearchVenues(db, aiassistant.SearchVenuesArgs{City: "Астана"})
	if err != nil {
		t.Fatalf("search: %v", err)
	}
	if len(results) != 0 {
		t.Fatalf("expected no match for a city with no listings, got %+v", results)
	}
}

// Scenario 3: a listing with no menu/price on file must still come back
// (capacity can still match), but flagged price_known=false rather than
// carrying a guessed number — and it must never be silently dropped by a
// budget filter it can't actually be checked against.
func TestSearchVenuesPriceUnknownIsHonest(t *testing.T) {
	db := setupDB(t)
	cat := venuesCategory(t, db)

	listing := models.Listing{CategoryID: cat.ID, NameRu: "No Price Yet", NameKz: "No Price Yet", City: "Алматы", IsActive: true}
	db.Create(&listing)
	db.Create(&models.ListingHall{ListingID: listing.ID, NameRu: "Зал", NameKz: "Зал", Capacity: 200, IsActive: true})

	results, err := aiassistant.SearchVenues(db, aiassistant.SearchVenuesArgs{City: "Алматы", GuestCount: 120, BudgetTotal: 3_000_000})
	if err != nil {
		t.Fatalf("search: %v", err)
	}
	if len(results) != 1 {
		t.Fatalf("expected the listing to still appear despite unknown price, got %+v", results)
	}
	if results[0].PriceKnown {
		t.Fatalf("expected price_known=false, got %+v", results[0])
	}
	if results[0].EstimatedTotal != 0 {
		t.Fatalf("must never fabricate an estimated total with no known price, got %+v", results[0])
	}
}

// A listing whose known price actually exceeds the stated budget must be
// excluded — the honest inverse of the price-unknown case above.
func TestSearchVenuesOverBudgetExcluded(t *testing.T) {
	db := setupDB(t)
	cat := venuesCategory(t, db)

	listing := models.Listing{CategoryID: cat.ID, NameRu: "Expensive Place", NameKz: "Expensive Place", City: "Алматы", IsActive: true}
	db.Create(&listing)
	db.Create(&models.ListingHall{ListingID: listing.ID, NameRu: "Зал", NameKz: "Зал", Capacity: 200, IsActive: true})
	db.Create(&models.ListingMenu{ListingID: listing.ID, NameRu: "VIP", NameKz: "VIP", PricePerGuest: 50000, IsActive: true})

	results, err := aiassistant.SearchVenues(db, aiassistant.SearchVenuesArgs{City: "Алматы", GuestCount: 120, BudgetTotal: 1_000_000})
	if err != nil {
		t.Fatalf("search: %v", err)
	}
	if len(results) != 0 {
		t.Fatalf("expected the over-budget listing to be excluded, got %+v", results)
	}
}
