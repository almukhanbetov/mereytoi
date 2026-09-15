package routes_test

import (
	"net/http"
	"testing"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// Listing ownership (brief "Этап 9" — restaurant/venue management access):
// anonymous -> 401, unrelated user -> 403, owner/manager/admin -> 200, and
// an owner of one listing can't touch another. Uses the exact same
// setupTestServer/registerUser/registerAdmin/seedListing helpers as
// event_security_test.go and restaurant_test.go — this is the same route
// tree production uses, not a handler unit test.

func TestListingManageAnonymousGetsUnauthorized(t *testing.T) {
	srv, db := setupTestServer(t)
	anon := apiClient{t: t, base: srv.URL}
	listing := seedListing(t, db, "Ownership Anon Venue", 0)

	status, _ := anon.do("PUT", "/api/listings/"+itoa(int(listing.ID)), map[string]any{
		"category_id": listing.CategoryID, "name_ru": "X", "name_kz": "X",
	})
	if status != http.StatusUnauthorized {
		t.Fatalf("anonymous listing update should be 401, got %d", status)
	}

	status, _ = anon.do("POST", "/api/listings/"+itoa(int(listing.ID))+"/halls", map[string]any{
		"name_ru": "Зал", "name_kz": "Зал",
	})
	if status != http.StatusUnauthorized {
		t.Fatalf("anonymous hall create should be 401, got %d", status)
	}
}

func TestListingManageUnrelatedUserGetsForbidden(t *testing.T) {
	srv, db := setupTestServer(t)
	outsider := registerUser(t, srv.URL, "Чужой", "listing-outsider@example.com")
	listing := seedListing(t, db, "Ownership Outsider Venue", 0)

	status, out := outsider.do("POST", "/api/listings/"+itoa(int(listing.ID))+"/halls", map[string]any{
		"name_ru": "Зал", "name_kz": "Зал",
	})
	if status != http.StatusForbidden {
		t.Fatalf("a user with no ListingManager row should get 403, got %d %v", status, out)
	}
}

func TestListingManageOwnerCanManageOwnListing(t *testing.T) {
	srv, db := setupTestServer(t)
	owner := registerUser(t, srv.URL, "Владелец", "listing-owner@example.com")
	listing := seedListing(t, db, "Ownership Owner Venue", 0)

	var user models.User
	if err := db.Where("email = ?", "listing-owner@example.com").First(&user).Error; err != nil {
		t.Fatalf("find owner user: %v", err)
	}
	manager := models.ListingManager{ListingID: listing.ID, UserID: user.ID, Role: models.ListingManagerRoleOwner}
	if err := db.Create(&manager).Error; err != nil {
		t.Fatalf("seed listing manager: %v", err)
	}

	status, out := owner.do("POST", "/api/listings/"+itoa(int(listing.ID))+"/halls", map[string]any{
		"name_ru": "Большой зал", "name_kz": "Үлкен зал", "capacity": 100,
	})
	if status != http.StatusCreated {
		t.Fatalf("owner should be able to create a hall on their own listing: %d %v", status, out)
	}
}

func TestListingManageManagerCanManageAssignedListing(t *testing.T) {
	srv, db := setupTestServer(t)
	manager := registerUser(t, srv.URL, "Менеджер", "listing-manager@example.com")
	listing := seedListing(t, db, "Ownership Manager Venue", 0)

	var user models.User
	if err := db.Where("email = ?", "listing-manager@example.com").First(&user).Error; err != nil {
		t.Fatalf("find manager user: %v", err)
	}
	lm := models.ListingManager{ListingID: listing.ID, UserID: user.ID, Role: models.ListingManagerRoleManager}
	if err := db.Create(&lm).Error; err != nil {
		t.Fatalf("seed listing manager: %v", err)
	}

	status, out := manager.do("POST", "/api/listings/"+itoa(int(listing.ID))+"/menus", map[string]any{
		"name_ru": "Меню", "name_kz": "Меню", "price_per_guest": 20000,
	})
	if status != http.StatusCreated {
		t.Fatalf("manager should be able to create a menu on their assigned listing: %d %v", status, out)
	}
}

func TestListingManageAdminCanManageAnyListing(t *testing.T) {
	srv, db := setupTestServer(t)
	admin := registerAdmin(t, srv.URL, db, "Админ", "listing-admin@example.com")
	listing := seedListing(t, db, "Ownership Admin Venue", 0)

	status, out := admin.do("POST", "/api/listings/"+itoa(int(listing.ID))+"/halls", map[string]any{
		"name_ru": "Зал", "name_kz": "Зал",
	})
	if status != http.StatusCreated {
		t.Fatalf("admin should be able to manage any listing without a ListingManager row: %d %v", status, out)
	}
}

func TestListingManageOwnerOfListingACannotEditListingB(t *testing.T) {
	srv, db := setupTestServer(t)
	owner := registerUser(t, srv.URL, "Владелец A", "listing-owner-a@example.com")
	listingA := seedListing(t, db, "Ownership Venue A", 0)
	listingB := seedListing(t, db, "Ownership Venue B", 0)

	var user models.User
	if err := db.Where("email = ?", "listing-owner-a@example.com").First(&user).Error; err != nil {
		t.Fatalf("find owner user: %v", err)
	}
	lm := models.ListingManager{ListingID: listingA.ID, UserID: user.ID, Role: models.ListingManagerRoleOwner}
	if err := db.Create(&lm).Error; err != nil {
		t.Fatalf("seed listing manager: %v", err)
	}

	status, out := owner.do("POST", "/api/listings/"+itoa(int(listingA.ID))+"/halls", map[string]any{
		"name_ru": "Зал A", "name_kz": "Зал A",
	})
	if status != http.StatusCreated {
		t.Fatalf("owner should manage their own listing A: %d %v", status, out)
	}

	status, out = owner.do("POST", "/api/listings/"+itoa(int(listingB.ID))+"/halls", map[string]any{
		"name_ru": "Зал B", "name_kz": "Зал B",
	})
	if status != http.StatusForbidden {
		t.Fatalf("owner of listing A must NOT be able to manage listing B, got %d %v", status, out)
	}
}

func TestMyListingsReturnsOnlyAssignedListingsForOrdinaryUser(t *testing.T) {
	srv, db := setupTestServer(t)
	owner := registerUser(t, srv.URL, "Мои Рестораны", "my-listings-owner@example.com")
	mine := seedListing(t, db, "My Listings Mine Venue", 0)
	_ = seedListing(t, db, "My Listings Other Venue", 0)

	var user models.User
	if err := db.Where("email = ?", "my-listings-owner@example.com").First(&user).Error; err != nil {
		t.Fatalf("find user: %v", err)
	}
	lm := models.ListingManager{ListingID: mine.ID, UserID: user.ID, Role: models.ListingManagerRoleOwner}
	if err := db.Create(&lm).Error; err != nil {
		t.Fatalf("seed listing manager: %v", err)
	}

	status, out := owner.do("GET", "/api/users/me/listings", nil)
	if status != http.StatusOK {
		t.Fatalf("my listings: %d %v", status, out)
	}
	listings, _ := out["listings"].([]any)
	if len(listings) != 1 {
		t.Fatalf("expected exactly 1 assigned listing, got %d: %v", len(listings), listings)
	}
	row := listings[0].(map[string]any)
	if uint(row["id"].(float64)) != mine.ID {
		t.Fatalf("expected the assigned listing %d, got %v", mine.ID, row["id"])
	}
	if row["role"] != "owner" {
		t.Fatalf("expected role=owner on the response row, got %v", row["role"])
	}
}

func TestMyListingsReturnsEmptyForUserWithNoAssignments(t *testing.T) {
	srv, db := setupTestServer(t)
	outsider := registerUser(t, srv.URL, "Никого", "my-listings-none@example.com")
	seedListing(t, db, "My Listings Untouched Venue", 0)

	status, out := outsider.do("GET", "/api/users/me/listings", nil)
	if status != http.StatusOK {
		t.Fatalf("my listings: %d %v", status, out)
	}
	listings, _ := out["listings"].([]any)
	if len(listings) != 0 {
		t.Fatalf("expected zero listings for an unassigned user, got %v", listings)
	}
}

func TestMyListingsReturnsAllListingsForAdmin(t *testing.T) {
	srv, db := setupTestServer(t)
	admin := registerAdmin(t, srv.URL, db, "Админ Мои", "my-listings-admin@example.com")
	seedListing(t, db, "My Listings Admin Venue 1", 0)
	seedListing(t, db, "My Listings Admin Venue 2", 0)

	status, out := admin.do("GET", "/api/users/me/listings", nil)
	if status != http.StatusOK {
		t.Fatalf("my listings: %d %v", status, out)
	}
	listings, _ := out["listings"].([]any)
	if len(listings) < 2 {
		t.Fatalf("expected admin to see at least 2 listings, got %d: %v", len(listings), listings)
	}
	for _, raw := range listings {
		row := raw.(map[string]any)
		if row["role"] != "admin" {
			t.Fatalf("expected role=admin on every row for a global admin, got %v", row)
		}
	}
}

func TestAdminCanAssignAndRemoveListingManager(t *testing.T) {
	srv, db := setupTestServer(t)
	admin := registerAdmin(t, srv.URL, db, "Админ Назначение", "assign-admin@example.com")
	target := registerUser(t, srv.URL, "Будущий Владелец", "assign-target@example.com")
	listing := seedListing(t, db, "Assign Venue", 0)

	var targetUser models.User
	if err := db.Where("email = ?", "assign-target@example.com").First(&targetUser).Error; err != nil {
		t.Fatalf("find target user: %v", err)
	}

	status, out := admin.do("POST", "/api/listings/"+itoa(int(listing.ID))+"/managers", map[string]any{
		"user_id": targetUser.ID, "role": "owner",
	})
	if status != http.StatusOK {
		t.Fatalf("assign manager: %d %v", status, out)
	}

	// Non-admin cannot assign managers, even for their own listing.
	status, _ = target.do("POST", "/api/listings/"+itoa(int(listing.ID))+"/managers", map[string]any{
		"user_id": targetUser.ID, "role": "manager",
	})
	if status != http.StatusForbidden {
		t.Fatalf("a non-admin owner should not be able to assign managers, got %d", status)
	}

	// The newly assigned owner can now manage the listing.
	status, out = target.do("POST", "/api/listings/"+itoa(int(listing.ID))+"/halls", map[string]any{
		"name_ru": "Зал", "name_kz": "Зал",
	})
	if status != http.StatusCreated {
		t.Fatalf("newly assigned owner should manage the listing: %d %v", status, out)
	}

	status, out = admin.do("DELETE", "/api/listings/"+itoa(int(listing.ID))+"/managers/"+itoa(int(targetUser.ID)), nil)
	if status != http.StatusOK {
		t.Fatalf("remove manager: %d %v", status, out)
	}

	status, _ = target.do("POST", "/api/listings/"+itoa(int(listing.ID))+"/halls", map[string]any{
		"name_ru": "Зал 2", "name_kz": "Зал 2",
	})
	if status != http.StatusForbidden {
		t.Fatalf("after removal the former owner should be forbidden, got %d", status)
	}
}
