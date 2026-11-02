package routes_test

import (
	"fmt"
	"net/http"
	"testing"
)

// publicListingIDs returns the ids GET <path> lists, for an anonymous client.
func publicListingIDs(t *testing.T, base, path string) []uint {
	t.Helper()
	guest := apiClient{t: t, base: base}
	status, out := guest.do("GET", path, nil)
	if status != http.StatusOK {
		t.Fatalf("GET %s: %d %v", path, status, out)
	}
	var ids []uint
	for _, l := range out["listings"].([]any) {
		ids = append(ids, uint(l.(map[string]any)["id"].(float64)))
	}
	return ids
}

func containsID(ids []uint, id uint) bool {
	for _, x := range ids {
		if x == id {
			return true
		}
	}
	return false
}

// A service a provider publishes through the onboarding / «Добавить
// услугу» is public at once: the client catalog lists it unfiltered and
// under its city, its category, both, and a name search — for any client,
// signed in or not. (Name search uses Postgres ILIKE, which the SQLite
// test database lacks; it is checked against Postgres in device QA.)
func TestProviderListingIsInPublicCatalog(t *testing.T) {
	srv, db := setupTestServer(t)
	hosts := stageACategory(t, db, "catalog-hosts")
	other := stageACategory(t, db, "catalog-shows")
	owner := registerUser(t, srv.URL, "Tamada", "catalog-owner@example.com")
	becomeProvider(t, owner, "tamada")
	id := createOwnListing(t, owner, hosts.ID, "toy", map[string]any{
		"city": "Алматы", "price": 600000, "price_type": "fixed",
	})

	for _, path := range []string{
		"/api/listings",
		"/api/listings?city_id=1", // Алматы
		"/api/listings?category=" + hosts.Slug,
		"/api/listings?category=" + hosts.Slug + "&city_id=1",
	} {
		if !containsID(publicListingIDs(t, srv.URL, path), id) {
			t.Fatalf("GET %s must list the provider's new service %d", path, id)
		}
	}
	for _, path := range []string{
		"/api/listings?city_id=2", // Астана
		"/api/listings?category=" + other.Slug,
	} {
		if containsID(publicListingIDs(t, srv.URL, path), id) {
			t.Fatalf("GET %s must not list service %d", path, id)
		}
	}

	// Another client sees it too.
	client := registerUser(t, srv.URL, "Client", "catalog-client@example.com")
	status, out := client.do("GET", "/api/listings", nil)
	if status != http.StatusOK {
		t.Fatalf("client catalog: %d %v", status, out)
	}
	found := false
	for _, l := range out["listings"].([]any) {
		if uint(l.(map[string]any)["id"].(float64)) == id {
			found = true
		}
	}
	if !found {
		t.Fatalf("another client must see service %d", id)
	}
}

// Only the owner's explicit «Скрыть» (is_active=false) takes a service out
// of the catalog; saving an edit with is_active kept true leaves it public.
func TestProviderListingVisibilityFollowsIsActive(t *testing.T) {
	srv, db := setupTestServer(t)
	hosts := stageACategory(t, db, "visibility-hosts")
	owner := registerUser(t, srv.URL, "Tamada", "visibility-owner@example.com")
	becomeProvider(t, owner, "tamada")
	id := createOwnListing(t, owner, hosts.ID, "toy", map[string]any{"city": "Алматы"})

	put := func(active bool) {
		t.Helper()
		status, out := owner.do("PUT", fmt.Sprintf("/api/listings/%d", id), map[string]any{
			"category_id": hosts.ID, "name_ru": "toy", "name_kz": "toy",
			"city": "Алматы", "price": 50000, "is_active": active,
		})
		if status != http.StatusOK {
			t.Fatalf("PUT is_active=%v: %d %v", active, status, out)
		}
	}

	put(true)
	if !containsID(publicListingIDs(t, srv.URL, "/api/listings"), id) {
		t.Fatalf("an edit that keeps is_active must keep the service public")
	}
	put(false)
	if containsID(publicListingIDs(t, srv.URL, "/api/listings"), id) {
		t.Fatalf("a hidden service must leave the public catalog")
	}
	put(true)
	if !containsID(publicListingIDs(t, srv.URL, "/api/listings"), id) {
		t.Fatalf("publishing again must bring it back")
	}
}
