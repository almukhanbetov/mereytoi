package routes_test

import (
	"net/http"
	"testing"

	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// Restaurant halls & menus (variant identity) — brief section 12's tests
// A-J. Uses setupTestServer (event_security_test.go) — the flag-off,
// zero-onboarding baseline every other non-onboarding test in this
// package already uses — since none of this needs AUTO_ACCOUNT_FROM_BOOKING.

// seedListingInCategory is seedListing (event_security_test.go) minus its
// own "always make a brand-new category" behavior — Test G specifically
// needs two Listings sharing one category, to prove the category-wide
// selected-demotion logic (unchanged by this stage) still applies across
// restaurants, not just across variants of the same one.
func seedListingInCategory(t *testing.T, db *gorm.DB, categoryID uint, name string, price uint) models.Listing {
	t.Helper()
	listing := models.Listing{CategoryID: categoryID, NameRu: name, NameKz: name, Price: price, IsActive: true}
	if err := db.Create(&listing).Error; err != nil {
		t.Fatalf("seed listing: %v", err)
	}
	return listing
}

// TestCreateHallAndMenuRespectExplicitInactive is a regression guard for a
// real bug found live while building the admin UI's "Дублировать меню"
// (a duplicate meant to be created inactive kept coming back active): a
// bool field tagged `gorm:"default:..."` whose value is explicitly false
// (the same as its own Go zero value) used to get silently dropped from
// the INSERT, letting the DB's own DEFAULT win instead. Fixed by removing
// the `default:` tag from ListingHall.IsActive/ListingMenu.IsActive (see
// their own doc comments) — this asserts the fix holds through the real
// HTTP route/JSON-binding path the admin UI actually uses, not just a
// direct db.Create call.
func TestCreateHallAndMenuRespectExplicitInactive(t *testing.T) {
	srv, db := setupTestServer(t)
	admin := registerAdmin(t, srv.URL, db, "Admin Inactive", "restaurant-inactive-admin@example.com")
	listing := seedListing(t, db, "Inactive Create Venue", 0)

	status, out := admin.do("POST", "/api/listings/"+itoa(int(listing.ID))+"/halls", map[string]any{
		"name_ru": "Draft Hall", "name_kz": "Draft Hall", "is_active": false,
	})
	if status != http.StatusCreated {
		t.Fatalf("create hall: %d %v", status, out)
	}
	if out["hall"].(map[string]any)["is_active"] != false {
		t.Fatalf("a hall explicitly created with is_active:false must stay inactive, got %v", out["hall"])
	}

	status, out = admin.do("POST", "/api/listings/"+itoa(int(listing.ID))+"/menus", map[string]any{
		"name_ru": "Draft Menu", "name_kz": "Draft Menu", "price_per_guest": 1000, "is_active": false,
	})
	if status != http.StatusCreated {
		t.Fatalf("create menu: %d %v", status, out)
	}
	if out["menu"].(map[string]any)["is_active"] != false {
		t.Fatalf("a menu explicitly created with is_active:false (e.g. a duplicate) must stay inactive, got %v", out["menu"])
	}
}

func TestListingWithoutHallOrMenuWorksAsBefore(t *testing.T) {
	// Test A/B — brief section 12: a plain Listing (any category,
	// including "venues") with zero halls/menus behaves exactly as
	// before: AddCandidate with no hall_id/menu_id, one candidate, no
	// variant machinery visible anywhere in the response.
	srv, db := setupTestServer(t)
	owner := registerUser(t, srv.URL, "Ержан", "restaurant-plain-owner@example.com")
	_, evOut := owner.do("POST", "/api/events", map[string]any{"title": "Той", "type": "toi"})
	eventID := int(evOut["event"].(map[string]any)["id"].(float64))

	listing := seedListing(t, db, "Plain Host", 300000)

	status, out := owner.do("POST", "/api/events/"+itoa(eventID)+"/candidates", map[string]any{"listing_id": listing.ID})
	if status != http.StatusCreated {
		t.Fatalf("add candidate: %d %v", status, out)
	}
	candidate := out["candidate"].(map[string]any)
	if _, has := candidate["hall_id"]; has {
		t.Fatalf("a plain listing's candidate must not carry a hall_id key at all, got %v", candidate)
	}
	if _, has := candidate["menu_id"]; has {
		t.Fatalf("a plain listing's candidate must not carry a menu_id key at all, got %v", candidate)
	}

	// Re-adding the exact same listing (still no hall/menu) must still be
	// idempotent, exactly as before this stage.
	status, out = owner.do("POST", "/api/events/"+itoa(eventID)+"/candidates", map[string]any{"listing_id": listing.ID})
	if status != http.StatusOK || out["already_added"] != true {
		t.Fatalf("re-adding the same plain listing should be idempotent, got %d %v", status, out)
	}
}

func TestRestaurantWithTwoHalls(t *testing.T) {
	// Test C.
	srv, db := setupTestServer(t)
	admin := registerAdmin(t, srv.URL, db, "Admin C", "restaurant-halls-admin@example.com")
	listing := seedListing(t, db, "Sultan Palace", 0)

	status, out := admin.do("POST", "/api/listings/"+itoa(int(listing.ID))+"/halls", map[string]any{
		"name_ru": "Большой зал", "name_kz": "Үлкен зал", "capacity": 300,
	})
	if status != http.StatusCreated {
		t.Fatalf("create hall 1: %d %v", status, out)
	}
	status, out = admin.do("POST", "/api/listings/"+itoa(int(listing.ID))+"/halls", map[string]any{
		"name_ru": "Малый зал", "name_kz": "Кіші зал", "capacity": 80,
	})
	if status != http.StatusCreated {
		t.Fatalf("create hall 2: %d %v", status, out)
	}

	status, out = admin.do("GET", "/api/listings/"+itoa(int(listing.ID))+"/halls", nil)
	if status != http.StatusOK {
		t.Fatalf("list halls: %d %v", status, out)
	}
	halls, _ := out["halls"].([]any)
	if len(halls) != 2 {
		t.Fatalf("expected exactly 2 halls, got %d (%v)", len(halls), out)
	}
}

func TestRestaurantWithThreeMenus(t *testing.T) {
	// Test D.
	srv, db := setupTestServer(t)
	admin := registerAdmin(t, srv.URL, db, "Admin D", "restaurant-menus-admin@example.com")
	listing := seedListing(t, db, "Shymkent Saraishyq", 0)

	for _, price := range []int{20000, 25000, 30000} {
		status, out := admin.do("POST", "/api/listings/"+itoa(int(listing.ID))+"/menus", map[string]any{
			"name_ru": "Меню", "name_kz": "Меню", "price_per_guest": price,
		})
		if status != http.StatusCreated {
			t.Fatalf("create menu %d: %d %v", price, status, out)
		}
	}

	status, out := admin.do("GET", "/api/listings/"+itoa(int(listing.ID))+"/menus", nil)
	if status != http.StatusOK {
		t.Fatalf("list menus: %d %v", status, out)
	}
	menus, _ := out["menus"].([]any)
	if len(menus) != 3 {
		t.Fatalf("expected exactly 3 menus, got %d (%v)", len(menus), out)
	}
}

// TestRestaurantVariantsCoexistAndSelection covers brief section 12 Tests
// E, F and G together — the natural sequence one event workspace would
// actually go through: shortlist two menu variants of the same
// restaurant, select one (the other stays shortlisted), then select a
// different restaurant in the same category (the first is demoted, not
// deleted).
func TestRestaurantVariantsCoexistAndSelection(t *testing.T) {
	srv, db := setupTestServer(t)
	owner := registerUser(t, srv.URL, "Данияр", "restaurant-variants-owner@example.com")
	_, evOut := owner.do("POST", "/api/events", map[string]any{"title": "Той", "type": "toi"})
	eventID := int(evOut["event"].(map[string]any)["id"].(float64))

	sultan := seedListing(t, db, "Sultan Hall Listing", 0)
	menu25 := seedMenu(t, db, sultan.ID, "Меню 25000", 25000)
	menu30 := seedMenu(t, db, sultan.ID, "Меню 30000", 30000)

	// Test E: two variants of the *same* listing, both shortlisted, no
	// dedup collapsing them into one candidate.
	status, out := owner.do("POST", "/api/events/"+itoa(eventID)+"/candidates", map[string]any{
		"listing_id": sultan.ID, "menu_id": menu25.ID,
	})
	if status != http.StatusCreated || out["already_added"] != false {
		t.Fatalf("add menu25 candidate: %d %v", status, out)
	}
	cand25 := out["candidate"].(map[string]any)
	cand25ID := int(cand25["id"].(float64))
	if cand25["menu_name"] != "Меню 25000" {
		t.Fatalf("expected a menu_name snapshot, got %v", cand25)
	}

	status, out = owner.do("POST", "/api/events/"+itoa(eventID)+"/candidates", map[string]any{
		"listing_id": sultan.ID, "menu_id": menu30.ID,
	})
	if status != http.StatusCreated || out["already_added"] != false {
		t.Fatalf("add menu30 candidate (must NOT be deduped against menu25): %d %v", status, out)
	}
	cand30 := out["candidate"].(map[string]any)
	cand30ID := int(cand30["id"].(float64))
	if cand25ID == cand30ID {
		t.Fatalf("menu25 and menu30 must be two distinct candidates, got the same id %d for both", cand25ID)
	}

	// Re-adding menu25 again (same listing+menu combo) must still be
	// idempotent — the dedup key is variant identity, not "any add".
	status, out = owner.do("POST", "/api/events/"+itoa(eventID)+"/candidates", map[string]any{
		"listing_id": sultan.ID, "menu_id": menu25.ID,
	})
	if status != http.StatusOK || out["already_added"] != true {
		t.Fatalf("re-adding the exact same listing+menu should be idempotent, got %d %v", status, out)
	}

	status, out = owner.do("GET", "/api/events/"+itoa(eventID)+"/candidates", nil)
	if status != http.StatusOK {
		t.Fatalf("list candidates: %d %v", status, out)
	}
	candidates, _ := out["candidates"].([]any)
	if len(candidates) != 2 {
		t.Fatalf("expected exactly 2 distinct candidates (menu25, menu30), got %d: %v", len(candidates), candidates)
	}

	// Test F: select menu25 — menu30 stays shortlisted, not selected.
	status, _ = owner.do("PUT", "/api/events/"+itoa(eventID)+"/candidates/"+itoa(cand25ID), map[string]any{"status": "selected"})
	if status != http.StatusOK {
		t.Fatalf("select menu25: %d", status)
	}

	_, out = owner.do("GET", "/api/events/"+itoa(eventID)+"/candidates", nil)
	statusByID := map[int]string{}
	for _, raw := range out["candidates"].([]any) {
		c := raw.(map[string]any)
		statusByID[int(c["id"].(float64))] = c["status"].(string)
	}
	if statusByID[cand25ID] != "selected" {
		t.Fatalf("expected menu25 to be selected, got %q", statusByID[cand25ID])
	}
	if statusByID[cand30ID] != "shortlisted" {
		t.Fatalf("expected menu30 to remain shortlisted (not selected), got %q", statusByID[cand30ID])
	}

	// Test G: a *different* restaurant in the same category, selected —
	// must demote menu25 back to shortlisted (never delete it).
	otherVenue := seedListingInCategory(t, db, sultan.CategoryID, "Other Venue", 500000)
	status, out = owner.do("POST", "/api/events/"+itoa(eventID)+"/candidates", map[string]any{"listing_id": otherVenue.ID})
	if status != http.StatusCreated {
		t.Fatalf("add other venue candidate: %d %v", status, out)
	}
	otherCandID := int(out["candidate"].(map[string]any)["id"].(float64))

	status, _ = owner.do("PUT", "/api/events/"+itoa(eventID)+"/candidates/"+itoa(otherCandID), map[string]any{"status": "selected"})
	if status != http.StatusOK {
		t.Fatalf("select other venue: %d", status)
	}

	_, out = owner.do("GET", "/api/events/"+itoa(eventID)+"/candidates", nil)
	statusByID = map[int]string{}
	ids := map[int]bool{}
	for _, raw := range out["candidates"].([]any) {
		c := raw.(map[string]any)
		id := int(c["id"].(float64))
		statusByID[id] = c["status"].(string)
		ids[id] = true
	}
	if !ids[cand25ID] {
		t.Fatalf("menu25's candidate must still exist (demoted, not deleted), got candidates %v", ids)
	}
	if statusByID[cand25ID] != "shortlisted" {
		t.Fatalf("expected menu25 to be demoted back to shortlisted once another venue is selected, got %q", statusByID[cand25ID])
	}
	if statusByID[otherCandID] != "selected" {
		t.Fatalf("expected the other venue to be selected, got %q", statusByID[otherCandID])
	}
}

func TestBookingSnapshotPreservesHallAndMenu(t *testing.T) {
	// Test H.
	srv, db := setupTestServer(t)
	c := apiClient{t: t, base: srv.URL}
	listing := seedListing(t, db, "Snapshot Venue", 0)
	hall := models.ListingHall{ListingID: listing.ID, NameRu: "Большой зал", NameKz: "Үлкен зал", Capacity: 200}
	if err := db.Create(&hall).Error; err != nil {
		t.Fatalf("seed hall: %v", err)
	}
	menu := seedMenu(t, db, listing.ID, "Меню 25000", 25000)

	status, out := c.do("POST", "/api/bookings", map[string]any{
		"name": "Тестовый Клиент", "phone": "+7 707 000 11 22",
		"items": []any{
			map[string]any{
				"listing_id": listing.ID, "name": listing.NameRu, "category": "venues",
				"guests": 150, "unit_price": 25000, "total_price": 25000 * 150,
				"hall_id": hall.ID, "hall_name": hall.NameRu,
				"menu_id": menu.ID, "menu_name": menu.NameRu, "menu_price_per_guest": menu.PricePerGuest,
			},
		},
	})
	if status != http.StatusCreated {
		t.Fatalf("booking create: %d %v", status, out)
	}
	items := out["booking"].(map[string]any)["items"].([]any)
	if len(items) != 1 {
		t.Fatalf("expected exactly 1 item, got %d", len(items))
	}
	item := items[0].(map[string]any)
	if item["hall_name"] != "Большой зал" || item["menu_name"] != "Меню 25000" || uint(item["menu_price_per_guest"].(float64)) != 25000 {
		t.Fatalf("expected the hall/menu snapshot in the booking response, got %v", item)
	}

	// And it round-trips through the DB exactly the same way.
	var booking models.Booking
	if err := db.Where("public_ref = ?", out["booking"].(map[string]any)["public_ref"]).First(&booking).Error; err != nil {
		t.Fatalf("reload booking: %v", err)
	}
	if len(booking.Items) != 1 || booking.Items[0].MenuName != "Меню 25000" || booking.Items[0].MenuPricePerGuest != 25000 {
		t.Fatalf("expected the DB row's own Items[0] to carry the same snapshot, got %+v", booking.Items)
	}
}

func TestMenuPriceChangeDoesNotAffectPastBooking(t *testing.T) {
	// Test I.
	srv, db := setupTestServer(t)
	admin := registerAdmin(t, srv.URL, db, "Admin I", "restaurant-price-admin@example.com")
	c := apiClient{t: t, base: srv.URL}
	listing := seedListing(t, db, "Price Change Venue", 0)
	menu := seedMenu(t, db, listing.ID, "Меню", 25000)

	status, out := c.do("POST", "/api/bookings", map[string]any{
		"name": "Клиент", "phone": "+7 707 000 33 44",
		"items": []any{
			map[string]any{
				"listing_id": listing.ID, "name": listing.NameRu, "category": "venues",
				"unit_price": 25000, "total_price": 25000,
				"menu_id": menu.ID, "menu_name": menu.NameRu, "menu_price_per_guest": menu.PricePerGuest,
			},
		},
	})
	if status != http.StatusCreated {
		t.Fatalf("booking create: %d %v", status, out)
	}
	publicRef := out["booking"].(map[string]any)["public_ref"].(string)

	// Admin changes the menu's price well after the booking exists.
	status, updOut := admin.do("PUT", "/api/listings/"+itoa(int(listing.ID))+"/menus/"+itoa(int(menu.ID)), map[string]any{
		"name_ru": menu.NameRu, "name_kz": menu.NameKz, "price_per_guest": 99999,
	})
	if status != http.StatusOK {
		t.Fatalf("update menu price: %d %v", status, updOut)
	}

	var booking models.Booking
	if err := db.Where("public_ref = ?", publicRef).First(&booking).Error; err != nil {
		t.Fatalf("reload booking: %v", err)
	}
	if booking.Items[0].MenuPricePerGuest != 25000 {
		t.Fatalf("a later menu price change must not alter a historical booking's frozen snapshot, got %d", booking.Items[0].MenuPricePerGuest)
	}

	var freshMenu models.ListingMenu
	db.First(&freshMenu, menu.ID)
	if freshMenu.PricePerGuest != 99999 {
		t.Fatalf("sanity check: the menu's own live price should now be 99999, got %d", freshMenu.PricePerGuest)
	}
}

func TestListingListDoesNotLoadFullMenuTree(t *testing.T) {
	// Test J.
	srv, db := setupTestServer(t)
	admin := registerAdmin(t, srv.URL, db, "Admin J", "restaurant-list-admin@example.com")
	listing := seedListing(t, db, "N Plus One Venue", 0)

	status, out := admin.do("POST", "/api/listings/"+itoa(int(listing.ID))+"/menus", map[string]any{
		"name_ru": "Меню", "name_kz": "Меню", "price_per_guest": 20000,
	})
	if status != http.StatusCreated {
		t.Fatalf("create menu: %d %v", status, out)
	}
	menuID := int(out["menu"].(map[string]any)["id"].(float64))

	status, out = admin.do("POST", "/api/listings/"+itoa(int(listing.ID))+"/menus/"+itoa(menuID)+"/sections", map[string]any{
		"title_ru": "Салаты", "title_kz": "Салаттар",
	})
	if status != http.StatusCreated {
		t.Fatalf("create section: %d %v", status, out)
	}
	sectionID := int(out["section"].(map[string]any)["id"].(float64))

	status, out = admin.do("POST", "/api/listings/"+itoa(int(listing.ID))+"/menus/"+itoa(menuID)+"/sections/"+itoa(sectionID)+"/items", map[string]any{
		"name_ru": "Оливье", "name_kz": "Оливье",
	})
	if status != http.StatusCreated {
		t.Fatalf("create item: %d %v", status, out)
	}

	status, out = admin.do("POST", "/api/listings/"+itoa(int(listing.ID))+"/menus/"+itoa(menuID)+"/extras", map[string]any{
		"type": "drink", "title_ru": "Доп. напитки", "title_kz": "Қосымша сусын", "price": 3000,
	})
	if status != http.StatusCreated {
		t.Fatalf("create extra: %d %v", status, out)
	}

	// The list endpoint: aggregates only, never the tree.
	status, out = admin.do("GET", "/api/listings", nil)
	if status != http.StatusOK {
		t.Fatalf("list: %d %v", status, out)
	}
	var found map[string]any
	for _, raw := range out["listings"].([]any) {
		l := raw.(map[string]any)
		if uint(l["id"].(float64)) == listing.ID {
			found = l
		}
	}
	if found == nil {
		t.Fatalf("expected to find the seeded listing in the list response")
	}
	if _, has := found["menus"]; has {
		t.Fatalf("the list endpoint must never include a full menus tree, got %v", found)
	}
	if _, has := found["halls"]; has {
		t.Fatalf("the list endpoint must never include a full halls tree, got %v", found)
	}
	if found["menu_count"] != float64(1) {
		t.Fatalf("expected menu_count=1 aggregate, got %v", found["menu_count"])
	}
	if found["min_menu_price_per_guest"] != float64(20000) {
		t.Fatalf("expected min_menu_price_per_guest=20000 aggregate, got %v", found["min_menu_price_per_guest"])
	}

	// The detail endpoint: full tree, sections/items/extras included.
	status, out = admin.do("GET", "/api/listings/"+itoa(int(listing.ID)), nil)
	if status != http.StatusOK {
		t.Fatalf("get: %d %v", status, out)
	}
	detail := out["listing"].(map[string]any)
	menus, _ := detail["menus"].([]any)
	if len(menus) != 1 {
		t.Fatalf("expected exactly 1 menu in the detail response, got %v", detail)
	}
	sections, _ := menus[0].(map[string]any)["sections"].([]any)
	if len(sections) != 1 {
		t.Fatalf("expected exactly 1 section nested in the detail response, got %v", menus[0])
	}
	items, _ := sections[0].(map[string]any)["items"].([]any)
	if len(items) != 1 {
		t.Fatalf("expected exactly 1 item nested in the detail response, got %v", sections[0])
	}
	extras, _ := menus[0].(map[string]any)["extras"].([]any)
	if len(extras) != 1 {
		t.Fatalf("expected exactly 1 extra nested in the detail response, got %v", menus[0])
	}
}

// seedMenu is a small DB-level helper — the admin-API path for creating a
// menu is exercised separately (TestRestaurantWithThreeMenus,
// TestListingListDoesNotLoadFullMenuTree); tests that just need a
// ListingMenu to already exist use this instead.
func seedMenu(t *testing.T, db *gorm.DB, listingID uint, name string, pricePerGuest uint) models.ListingMenu {
	t.Helper()
	menu := models.ListingMenu{ListingID: listingID, NameRu: name, NameKz: name, PricePerGuest: pricePerGuest, IsActive: true}
	if err := db.Create(&menu).Error; err != nil {
		t.Fatalf("seed menu: %v", err)
	}
	return menu
}

// TestEventCandidateStoresGuests — final integration stage, brief section
// 3: "Listing + Hall + Menu + Guests" saved as one unit when adding a
// restaurant to an event.
func TestEventCandidateStoresGuests(t *testing.T) {
	srv, db := setupTestServer(t)
	owner := registerUser(t, srv.URL, "Гостевой Тест", "final-guests-owner@example.com")
	_, evOut := owner.do("POST", "/api/events", map[string]any{"title": "Той", "type": "toi"})
	eventID := int(evOut["event"].(map[string]any)["id"].(float64))

	listing := seedListing(t, db, "Guests Venue", 0)
	menu := seedMenu(t, db, listing.ID, "Меню", 25000)

	status, out := owner.do("POST", "/api/events/"+itoa(eventID)+"/candidates", map[string]any{
		"listing_id": listing.ID, "menu_id": menu.ID, "guests": 150,
	})
	if status != http.StatusCreated {
		t.Fatalf("add candidate: %d %v", status, out)
	}
	candidate := out["candidate"].(map[string]any)
	if uint(candidate["guests"].(float64)) != 150 {
		t.Fatalf("expected guests=150 stored on the candidate, got %v", candidate["guests"])
	}
}

// TestBookingStoresSelectedExtrasAndEstimatedTotal — brief section 5's own
// addition (fields that didn't exist on BookingItem before this stage).
func TestBookingStoresSelectedExtrasAndEstimatedTotal(t *testing.T) {
	srv, db := setupTestServer(t)
	c := apiClient{t: t, base: srv.URL}
	listing := seedListing(t, db, "Extras Snapshot Venue", 0)
	menu := seedMenu(t, db, listing.ID, "Меню", 25000)

	status, out := c.do("POST", "/api/bookings", map[string]any{
		"name": "Клиент Финал", "phone": "+7 707 111 22 99",
		"items": []any{
			map[string]any{
				"listing_id": listing.ID, "name": listing.NameRu, "category": "venues",
				"guests": 150, "unit_price": 25000, "total_price": 3750000,
				"menu_id": menu.ID, "menu_name": menu.NameRu, "menu_price_per_guest": menu.PricePerGuest,
				"selected_extras": []any{
					map[string]any{"title": "Детский стол", "price": 100000, "unit": ""},
					map[string]any{"title": "Сервисный сбор", "price": 10, "unit": "percent"},
				},
				"estimated_total": 4235000,
			},
		},
	})
	if status != http.StatusCreated {
		t.Fatalf("booking create: %d %v", status, out)
	}
	item := out["booking"].(map[string]any)["items"].([]any)[0].(map[string]any)
	if uint(item["estimated_total"].(float64)) != 4235000 {
		t.Fatalf("expected estimated_total=4235000, got %v", item["estimated_total"])
	}
	extras, _ := item["selected_extras"].([]any)
	if len(extras) != 2 {
		t.Fatalf("expected exactly 2 selected_extras, got %v", item["selected_extras"])
	}

	var booking models.Booking
	db.Where("public_ref = ?", out["booking"].(map[string]any)["public_ref"]).First(&booking)
	if len(booking.Items[0].SelectedExtras) != 2 || booking.Items[0].EstimatedTotal != 4235000 {
		t.Fatalf("expected the DB row itself to carry the same snapshot, got %+v", booking.Items[0])
	}
}

// TestEventCandidateStoresEstimatedTotal — Budget-fix pass: an
// EventCandidate saved with its own estimated_total (menu×guests + extras,
// exactly what the brief's own worked example computes:
// 25000×150+100000=3850000) must round-trip that number unchanged, so
// candidateEstimate on the frontend can use it instead of recomputing a
// lower, extras-less figure.
func TestEventCandidateStoresEstimatedTotal(t *testing.T) {
	srv, db := setupTestServer(t)
	owner := registerUser(t, srv.URL, "Бюджет Тест", "budget-fix-owner@example.com")
	_, evOut := owner.do("POST", "/api/events", map[string]any{"title": "Той", "type": "toi"})
	eventID := int(evOut["event"].(map[string]any)["id"].(float64))

	listing := seedListing(t, db, "Estimated Total Venue", 0)
	menu := seedMenu(t, db, listing.ID, "Меню", 25000)

	status, out := owner.do("POST", "/api/events/"+itoa(eventID)+"/candidates", map[string]any{
		"listing_id": listing.ID, "menu_id": menu.ID, "guests": 150, "estimated_total": 3850000,
	})
	if status != http.StatusCreated {
		t.Fatalf("add candidate: %d %v", status, out)
	}
	candidate := out["candidate"].(map[string]any)
	if uint(candidate["estimated_total"].(float64)) != 3850000 {
		t.Fatalf("expected estimated_total=3850000 stored on the candidate, got %v", candidate["estimated_total"])
	}

	// Re-fetch (simulates a page reload) — must still be 3850000, not
	// recomputed from menu_price_per_guest×guests (which alone would be
	// 3750000, missing the 100000 extra).
	status, out = owner.do("GET", "/api/events/"+itoa(eventID)+"/candidates", nil)
	if status != http.StatusOK {
		t.Fatalf("list candidates: %d %v", status, out)
	}
	cands := out["candidates"].([]any)
	reloaded := cands[0].(map[string]any)
	if uint(reloaded["estimated_total"].(float64)) != 3850000 {
		t.Fatalf("expected estimated_total to survive a reload unchanged, got %v", reloaded["estimated_total"])
	}

	// A candidate added *without* estimated_total (every pre-existing
	// candidate, and any caller that doesn't send it) must round-trip as
	// nil/omitted — never silently defaulted to 0 — so
	// candidateEstimate's own fallback to menuPricePerGuest×guests still
	// fires for it exactly as before this change.
	status, out = owner.do("POST", "/api/events/"+itoa(eventID)+"/candidates", map[string]any{
		"listing_id": listing.ID,
	})
	if status != http.StatusCreated {
		t.Fatalf("add plain candidate: %d %v", status, out)
	}
	plain := out["candidate"].(map[string]any)
	if _, present := plain["estimated_total"]; present {
		t.Fatalf("expected no estimated_total key on a candidate that never sent one, got %v", plain["estimated_total"])
	}
}
