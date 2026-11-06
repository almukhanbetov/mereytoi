package routes_test

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

func orderCall(t *testing.T, method, url, token string, body any) map[string]any {
	t.Helper()
	var payload bytes.Buffer
	if body != nil {
		if err := json.NewEncoder(&payload).Encode(body); err != nil {
			t.Fatal(err)
		}
	}
	req, err := http.NewRequest(method, url, &payload)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.StatusCode >= 300 {
		t.Fatalf("%s %s: status %d", method, url, res.StatusCode)
	}
	var out map[string]any
	if err := json.NewDecoder(res.Body).Decode(&out); err != nil {
		t.Fatal(err)
	}
	return out
}

func catalogNames(t *testing.T, url string) []string {
	t.Helper()
	list := orderCall(t, http.MethodGet, url, "", nil)["listings"].([]any)
	names := make([]string, 0, len(list))
	for _, item := range list {
		names = append(names, item.(map[string]any)["name_ru"].(string))
	}
	return names
}

func wantNames(t *testing.T, got []string, want ...string) {
	t.Helper()
	if fmt.Sprint(got) != fmt.Sprint(want) {
		t.Fatalf("order\n got %v\nwant %v", got, want)
	}
}

// A provider's new service comes first whatever the ratings are; an edit
// doesn't lift an older one; rows created at one moment stay in a fixed order.
func TestListingsNewestFirst(t *testing.T) {
	db := openCitySQLite(t)
	srv := setupCityServer(t, db)
	category := models.Category{Slug: "hosts", NameRu: "Ведущие", NameKz: "Жүргізуші", Position: 1}
	other := models.Category{Slug: "shows", NameRu: "Шоу", NameKz: "Шоу", Position: 2}
	for _, c := range []*models.Category{&category, &other} {
		if err := db.Create(c).Error; err != nil {
			t.Fatal(err)
		}
	}
	base := time.Date(2026, 1, 1, 12, 0, 0, 0, time.UTC)
	for _, row := range []struct {
		name   string
		rating float32
		at     time.Time
		cat    uint
	}{
		{"Старая с высоким рейтингом", 5, base, category.ID},
		{"Тот же момент, первая", 1, base.Add(time.Hour), category.ID},
		{"Тот же момент, вторая", 1, base.Add(time.Hour), category.ID},
		{"Другая категория", 4, base.Add(2 * time.Hour), other.ID},
		{"Скрытая новая", 5, base.Add(3 * time.Hour), category.ID},
	} {
		l := models.Listing{CategoryID: row.cat, NameRu: row.name, NameKz: row.name, Rating: row.rating, IsActive: true, CreatedAt: row.at, UpdatedAt: row.at}
		if err := db.Create(&l).Error; err != nil {
			t.Fatal(err)
		}
	}
	if err := db.Model(&models.Listing{}).Where("name_ru = ?", "Скрытая новая").Update("is_active", false).Error; err != nil {
		t.Fatal(err)
	}

	all := srv.URL + "/api/listings"
	wantNames(t, catalogNames(t, all),
		"Другая категория", "Тот же момент, вторая", "Тот же момент, первая", "Старая с высоким рейтингом")
	// The filter sees the same order.
	wantNames(t, catalogNames(t, all+"?category=hosts"),
		"Тот же момент, вторая", "Тот же момент, первая", "Старая с высоким рейтингом")

	auth := orderCall(t, http.MethodPost, srv.URL+"/api/auth/register", "", map[string]any{
		"name": "Provider", "email": "order@example.test", "password": "qa-pass-x12345", "phone": "+77000000777",
	})
	token := auth["token"].(string)
	orderCall(t, http.MethodPost, srv.URL+"/api/provider", token, map[string]any{"display_name": "Бизнес"})

	create := func(name string) map[string]any {
		return orderCall(t, http.MethodPost, srv.URL+"/api/provider/me/listings", token, map[string]any{
			"category_id": category.ID, "name_ru": name, "name_kz": name, "price": 1000,
		})["listing"].(map[string]any)
	}
	first := create("Новая услуга")
	wantNames(t, catalogNames(t, all)[:2], "Новая услуга", "Другая категория")
	create("Ещё новее")
	wantNames(t, catalogNames(t, all)[:2], "Ещё новее", "Новая услуга")

	// Editing the older of the two changes it in place.
	first["name_ru"] = "Новая услуга (правка)"
	first["price"] = 2000
	orderCall(t, http.MethodPut, fmt.Sprintf("%s/api/listings/%v", srv.URL, first["id"]), token, first)
	wantNames(t, catalogNames(t, all)[:2], "Ещё новее", "Новая услуга (правка)")
}
