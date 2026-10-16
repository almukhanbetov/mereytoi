package routes_test

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"sort"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"gorm.io/driver/postgres"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/config"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
	"github.com/almukhanbetov/mereytoi/backend/internal/routes"
)

// GET /api/cities and the `?city_id=` filter on GET /api/listings. The
// fixture mirrors the free-text variants found in prod listings.city.

var cityDBSeq int

func setupCityServer(t *testing.T, db *gorm.DB) *httptest.Server {
	t.Helper()
	gin.SetMode(gin.TestMode)
	if err := db.AutoMigrate(
		&models.User{}, &models.Category{}, &models.Listing{},
		&models.ListingHall{}, &models.ListingMenu{}, &models.ListingManager{}, &models.Provider{},
	); err != nil {
		t.Fatalf("failed to migrate: %v", err)
	}
	r := gin.New()
	routes.Register(r, db, config.Config{JWTSecret: "test-secret-only"})
	srv := httptest.NewServer(r)
	t.Cleanup(srv.Close)
	return srv
}

func openCitySQLite(t *testing.T) *gorm.DB {
	t.Helper()
	cityDBSeq++
	db, err := gorm.Open(sqlite.Open(fmt.Sprintf("file:cityfilter%d?mode=memory&cache=shared", cityDBSeq)), &gorm.Config{})
	if err != nil {
		t.Fatalf("failed to open in-memory db: %v", err)
	}
	return db
}

// seedCityFixture creates two categories and one listing per (name, city,
// category) row. Returns the two category slugs.
func seedCityFixture(t *testing.T, db *gorm.DB) (venues, hosts string) {
	t.Helper()
	v := models.Category{Slug: "venues", NameRu: "Рестораны", NameKz: "Мейрамханалар"}
	h := models.Category{Slug: "hosts", NameRu: "Ведущие", NameKz: "Жүргізушілер", Position: 1}
	for _, c := range []*models.Category{&v, &h} {
		if err := db.Create(c).Error; err != nil {
			t.Fatalf("create category: %v", err)
		}
	}
	rows := []struct {
		name, city string
		cat        uint
	}{
		{"Той залы Алматы", "Алматы", v.ID},
		{"Банкет холл", "Алматы ", v.ID},
		{"Той ведущий", "Almaty", h.ID},
		{"Той холл Астана", "Астана", v.ID},
		{"Шымкент зал", "Шымкент", v.ID},
		{"Туркестан зал", "Туркестан", v.ID},
		{"Той Түркістан", "Түркістан", h.ID},
		{"Туркістан ведущий", "Туркістан", h.ID},
		{"Turkistan hall", "Turkistan", v.ID},
		{"Без города", "", v.ID},
	}
	for _, r := range rows {
		l := models.Listing{CategoryID: r.cat, NameRu: r.name, NameKz: r.name, City: r.city, IsActive: true}
		if err := db.Create(&l).Error; err != nil {
			t.Fatalf("create listing: %v", err)
		}
	}
	// An inactive Almaty listing must stay hidden under the city filter too.
	inactive := models.Listing{CategoryID: v.ID, NameRu: "Закрыт", NameKz: "Жабық", City: "Алматы", IsActive: true}
	db.Create(&inactive)
	db.Model(&inactive).Update("is_active", false)
	return v.Slug, h.Slug
}

func listingNames(t *testing.T, out map[string]any) []string {
	t.Helper()
	raw, ok := out["listings"].([]any)
	if !ok {
		t.Fatalf("no listings array in %v", out)
	}
	names := make([]string, 0, len(raw))
	for _, item := range raw {
		names = append(names, item.(map[string]any)["name_ru"].(string))
	}
	sort.Strings(names)
	return names
}

func assertNames(t *testing.T, c apiClient, path string, want ...string) {
	t.Helper()
	status, out := c.do("GET", path, nil)
	if status != http.StatusOK {
		t.Fatalf("GET %s: status %d, body %v", path, status, out)
	}
	sort.Strings(want)
	if got := listingNames(t, out); strings.Join(got, "|") != strings.Join(want, "|") {
		t.Fatalf("GET %s:\n got  %v\n want %v", path, got, want)
	}
}

func TestCitiesEndpoint(t *testing.T) {
	srv := setupCityServer(t, openCitySQLite(t))
	c := apiClient{t: t, base: srv.URL}

	for range 2 { // same order on repeated calls
		status, out := c.do("GET", "/api/cities", nil)
		if status != http.StatusOK {
			t.Fatalf("status %d", status)
		}
		list, _ := out["cities"].([]any)
		if len(list) != 17 {
			t.Fatalf("want 17 cities, got %d", len(list))
		}
		for i, item := range list {
			m := item.(map[string]any)
			if int(m["id"].(float64)) != i+1 {
				t.Fatalf("position %d has id %v", i, m["id"])
			}
		}
		first := list[0].(map[string]any)
		if first["name_ru"] != "Алматы" || first["name_kz"] != "Алматы" || first["name_en"] != "Almaty" {
			t.Fatalf("unexpected first city: %v", first)
		}
		if len(first) != 4 {
			t.Fatalf("city object should have exactly id/name_ru/name_kz/name_en, got %v", first)
		}
	}
}

func TestListingsCityFilter(t *testing.T) {
	db := openCitySQLite(t)
	srv := setupCityServer(t, db)
	venues, hosts := seedCityFixture(t, db)
	c := apiClient{t: t, base: srv.URL}

	all := []string{
		"Той залы Алматы", "Банкет холл", "Той ведущий", "Той холл Астана", "Шымкент зал",
		"Туркестан зал", "Той Түркістан", "Туркістан ведущий", "Turkistan hall", "Без города",
	}

	t.Run("no city_id keeps old behavior incl. blank city", func(t *testing.T) {
		assertNames(t, c, "/api/listings", all...)
		assertNames(t, c, "/api/listings?city_id=", all...)
	})

	t.Run("almaty matches all prod variants", func(t *testing.T) {
		assertNames(t, c, "/api/listings?city_id=1", "Той залы Алматы", "Банкет холл", "Той ведущий")
	})

	t.Run("turkistan matches every spelling", func(t *testing.T) {
		assertNames(t, c, "/api/listings?city_id=15", "Туркестан зал", "Той Түркістан", "Туркістан ведущий", "Turkistan hall")
	})

	t.Run("city with no listings is an empty list", func(t *testing.T) {
		assertNames(t, c, "/api/listings?city_id=17")
	})

	t.Run("blank city never lands in a specific city", func(t *testing.T) {
		for id := 1; id <= 17; id++ {
			_, out := c.do("GET", fmt.Sprintf("/api/listings?city_id=%d", id), nil)
			for _, n := range listingNames(t, out) {
				if n == "Без города" {
					t.Fatalf("blank-city listing returned for city_id=%d", id)
				}
			}
		}
	})

	t.Run("category AND city", func(t *testing.T) {
		assertNames(t, c, "/api/listings?category="+venues+"&city_id=1", "Той залы Алматы", "Банкет холл")
		assertNames(t, c, "/api/listings?category="+hosts+"&city_id=1", "Той ведущий")
		assertNames(t, c, "/api/listings?category="+hosts+"&city_id=2")
		assertNames(t, c, "/api/listings?category=missing&city_id=1")
	})

	t.Run("invalid and malformed city_id are 400", func(t *testing.T) {
		for _, q := range []string{"0", "18", "-1", "999999", "abc", "1.5", "1a", "%20"} {
			status, out := c.do("GET", "/api/listings?city_id="+q, nil)
			if status != http.StatusBadRequest || out["error"] != "invalid_city_id" {
				t.Fatalf("city_id=%q: status %d body %v", q, status, out)
			}
		}
	})
}

// Search uses Postgres-only ILIKE, which SQLite can't parse, so the
// search + city_id combinations run only against a real Postgres:
//
//	MEREYTOI_TEST_POSTGRES_DSN="host=... dbname=... sslmode=disable" go test ./internal/routes -run CitySearch
//
// The DB must be a disposable one — the test drops its tables first.
func TestListingsCitySearchPostgres(t *testing.T) {
	dsn := os.Getenv("MEREYTOI_TEST_POSTGRES_DSN")
	if dsn == "" {
		t.Skip("MEREYTOI_TEST_POSTGRES_DSN not set")
	}
	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		t.Fatalf("open postgres: %v", err)
	}
	if err := db.Migrator().DropTable(
		&models.ListingManager{}, &models.ListingMenu{}, &models.ListingHall{},
		&models.Listing{}, &models.Provider{}, &models.Category{}, &models.User{},
	); err != nil {
		t.Fatalf("drop tables: %v", err)
	}
	srv := setupCityServer(t, db)
	venues, hosts := seedCityFixture(t, db)
	c := apiClient{t: t, base: srv.URL}

	t.Run("search alone unchanged", func(t *testing.T) {
		assertNames(t, c, "/api/listings?search=той", "Той залы Алматы", "Той ведущий", "Той холл Астана", "Той Түркістан")
	})
	t.Run("search AND city", func(t *testing.T) {
		assertNames(t, c, "/api/listings?search=той&city_id=1", "Той залы Алматы", "Той ведущий")
		assertNames(t, c, "/api/listings?search=той&city_id=2", "Той холл Астана")
		assertNames(t, c, "/api/listings?search=той&city_id=3")
	})
	t.Run("category AND search AND city", func(t *testing.T) {
		assertNames(t, c, "/api/listings?category="+venues+"&search=той&city_id=1", "Той залы Алматы")
		assertNames(t, c, "/api/listings?category="+hosts+"&search=той&city_id=1", "Той ведущий")
		assertNames(t, c, "/api/listings?category="+hosts+"&search=той&city_id=15", "Той Түркістан")
	})
	t.Run("almaty variants on postgres", func(t *testing.T) {
		assertNames(t, c, "/api/listings?city_id=1", "Той залы Алматы", "Банкет холл", "Той ведущий")
	})
}
