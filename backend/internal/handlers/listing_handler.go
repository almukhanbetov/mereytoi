package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/middleware"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// listingOut is what the public list actually needs per row — brief
// section 9: aggregates only (how many halls/menus this listing has, and
// its cheapest per-guest menu price), never the full hall/menu/section/
// item tree. Zero-value aggregates (0/nil) for every non-restaurant
// listing and every restaurant listing with no halls/menus yet — exactly
// today's shape, just with three extra omitempty fields nobody has to
// handle specially.
type listingOut struct {
	models.Listing
	HallCount            int64 `json:"hall_count,omitempty"`
	MenuCount            int64 `json:"menu_count,omitempty"`
	MinMenuPricePerGuest *uint `json:"min_menu_price_per_guest,omitempty"`
	// Provider — Этап 11 (brief section 8: "карточка ... должна при
	// возможности отображать ... имя услугодателя"). nil for every listing
	// with no owning ListingManager row, or whose owner has no Provider
	// profile — exactly today's shape for every pre-existing listing.
	Provider *providerBrief `json:"provider,omitempty"`
}

// providerBrief is the small, display-only slice of Provider a listing
// card/page actually needs — never the full row (no phone/whatsapp/
// telegram/description leak into the public catalog response via this
// type; the service detail page's contact block gets the full contact
// shape separately, see Get below). ID — Этап 11G: the provider's own
// public routing handle, so a card's name/avatar can be tapped to open
// ProviderProfileScreen (GET /api/providers/:id) without a second lookup.
type providerBrief struct {
	ID          uint   `json:"id"`
	DisplayName string `json:"display_name"`
	City        string `json:"city,omitempty"`
	AvatarURL   string `json:"avatar_url,omitempty"`
}

type ListingHandler struct {
	DB *gorm.DB
}

func NewListingHandler(db *gorm.DB) *ListingHandler {
	return &ListingHandler{DB: db}
}

// List returns listings, optionally filtered by category slug/id and a
// name search term, e.g. GET /api/listings?category=hosts&search=Ерлан
func (h *ListingHandler) List(c *gin.Context) {
	query := h.DB.Model(&models.Listing{}).Where("is_active = ?", true)

	if slug := c.Query("category"); slug != "" {
		var category models.Category
		if err := h.DB.Where("slug = ?", slug).First(&category).Error; err != nil {
			c.JSON(http.StatusOK, gin.H{"listings": []models.Listing{}})
			return
		}
		query = query.Where("category_id = ?", category.ID)
	}

	if search := c.Query("search"); search != "" {
		like := "%" + search + "%"
		query = query.Where("name_ru ILIKE ? OR name_kz ILIKE ?", like, like)
	}

	var listings []models.Listing
	if err := query.Order("rating desc").Find(&listings).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch listings"})
		return
	}
	if len(listings) == 0 {
		c.JSON(http.StatusOK, gin.H{"listings": []listingOut{}})
		return
	}

	c.JSON(http.StatusOK, gin.H{"listings": attachListingCounts(h.DB, listings)})
}

// attachListingCounts computes hall_count/menu_count/min_menu_price_per_
// guest for a batch of listings in exactly two grouped queries total,
// regardless of how many listings were passed in — brief section 9's
// "не создавать N+1" — shared by List and MyListings below so the two
// management/catalog views can never drift out of sync on how a count is
// computed.
func attachListingCounts(db *gorm.DB, listings []models.Listing) []listingOut {
	if len(listings) == 0 {
		return []listingOut{}
	}
	listingIDs := make([]uint, len(listings))
	for i, l := range listings {
		listingIDs[i] = l.ID
	}

	type hallCountRow struct {
		ListingID uint
		Count     int64
	}
	var hallCounts []hallCountRow
	db.Model(&models.ListingHall{}).Select("listing_id, count(*) as count").
		Where("listing_id IN ? AND is_active = ?", listingIDs, true).Group("listing_id").Scan(&hallCounts)
	hallByListing := map[uint]int64{}
	for _, row := range hallCounts {
		hallByListing[row.ListingID] = row.Count
	}

	type menuAggRow struct {
		ListingID uint
		Count     int64
		MinPrice  uint
	}
	var menuAggs []menuAggRow
	db.Model(&models.ListingMenu{}).Select("listing_id, count(*) as count, min(price_per_guest) as min_price").
		Where("listing_id IN ? AND is_active = ?", listingIDs, true).Group("listing_id").Scan(&menuAggs)
	menuByListing := map[uint]menuAggRow{}
	for _, row := range menuAggs {
		menuByListing[row.ListingID] = row
	}

	providerByListing := attachProviderBriefs(db, listingIDs)

	out := make([]listingOut, 0, len(listings))
	for _, l := range listings {
		row := listingOut{Listing: l, HallCount: hallByListing[l.ID], Provider: providerByListing[l.ID]}
		if agg, ok := menuByListing[l.ID]; ok {
			row.MenuCount = agg.Count
			minPrice := agg.MinPrice
			row.MinMenuPricePerGuest = &minPrice
		}
		out = append(out, row)
	}
	return out
}

// attachProviderBriefs resolves each listing's owning Provider (brief
// section 8/9), reusing ListingManager as the one source of truth for
// "who owns this listing" (brief section 6) rather than a new FK — two
// grouped queries total regardless of how many listings were passed in,
// same "no N+1" shape as the hall/menu aggregates above. A listing with no
// owner row, or whose owner has no (or a non-active) Provider profile,
// simply gets no entry in the returned map — exactly today's shape.
func attachProviderBriefs(db *gorm.DB, listingIDs []uint) map[uint]*providerBrief {
	out := map[uint]*providerBrief{}
	if len(listingIDs) == 0 {
		return out
	}

	var owners []models.ListingManager
	db.Where("listing_id IN ? AND role = ?", listingIDs, models.ListingManagerRoleOwner).Find(&owners)
	if len(owners) == 0 {
		return out
	}
	userIDs := make([]uint, 0, len(owners))
	listingByUser := map[uint][]uint{}
	for _, o := range owners {
		userIDs = append(userIDs, o.UserID)
		listingByUser[o.UserID] = append(listingByUser[o.UserID], o.ListingID)
	}

	var providers []models.Provider
	db.Where("user_id IN ? AND status = ?", userIDs, models.ProviderStatusActive).Find(&providers)
	for _, p := range providers {
		brief := &providerBrief{ID: p.ID, DisplayName: p.DisplayName, City: p.City, AvatarURL: p.AvatarURL}
		for _, listingID := range listingByUser[p.UserID] {
			out[listingID] = brief
		}
	}
	return out
}

// myListingOut adds the current caller's own role for that listing — an
// always-admin sentinel for a global admin (who never has a real
// ListingManager row), the actual ListingManager.Role otherwise. Never
// added to listingOut/List itself — that response is the public catalog
// shape every other client already parses, unrelated to "who manages
// this."
type myListingOut struct {
	listingOut
	Role string `json:"role,omitempty"`
}

// MyListings — GET /api/users/me/listings (brief section: "Мои
// рестораны"). A global admin sees every listing regardless of category
// or is_active (this is a management view, not the public catalog, which
// filters to active-only); anyone else sees only listings they're an
// owner/manager of via ListingManager. Deliberately not scoped to the
// `venues` category — ListingManager itself carries no such restriction,
// so a future non-restaurant use of this same ownership table (if any)
// isn't silently filtered out here.
func (h *ListingHandler) MyListings(c *gin.Context) {
	role, _ := c.Get(middleware.ContextUserRoleKey)
	userIDVal, _ := c.Get(middleware.ContextUserIDKey)
	userID, _ := userIDVal.(uint)

	var listings []models.Listing
	roleByListing := map[uint]string{}

	if role == "admin" {
		if err := h.DB.Order("name_ru").Find(&listings).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch listings"})
			return
		}
		for _, l := range listings {
			roleByListing[l.ID] = "admin"
		}
	} else {
		var managers []models.ListingManager
		h.DB.Where("user_id = ?", userID).Find(&managers)
		if len(managers) == 0 {
			c.JSON(http.StatusOK, gin.H{"listings": []myListingOut{}})
			return
		}
		listingIDs := make([]uint, len(managers))
		for i, m := range managers {
			listingIDs[i] = m.ListingID
			roleByListing[m.ListingID] = m.Role
		}
		if err := h.DB.Where("id IN ?", listingIDs).Order("name_ru").Find(&listings).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch listings"})
			return
		}
	}

	counted := attachListingCounts(h.DB, listings)
	out := make([]myListingOut, 0, len(counted))
	for _, row := range counted {
		out = append(out, myListingOut{listingOut: row, Role: roleByListing[row.Listing.ID]})
	}
	c.JSON(http.StatusOK, gin.H{"listings": out})
}

// listingDetailOut is the full picture — used only by Get/Menus below,
// never List. Halls/Menus are assembled from explicit, flat, IN-based
// queries (see loadListingTree) rather than a GORM association/Preload on
// Listing itself, so Listing's own struct/JSON shape stays exactly what
// every other consumer (EventCandidate.Listing, Booking snapshots, etc.)
// already expects — no nested halls/menus ever silently appear there.
type listingDetailOut struct {
	models.Listing
	Halls []models.ListingHall `json:"halls,omitempty"`
	Menus []menuOut            `json:"menus,omitempty"`
	// Provider — Этап 11 (brief section 9's contact block), Этап 11G
	// redaction (no user_id) — the full contact shape, unlike listingOut's
	// providerBrief (see loadListingProvider).
	Provider *providerDetailOut `json:"provider,omitempty"`
}

type menuOut struct {
	models.ListingMenu
	Sections []menuSectionOut          `json:"sections,omitempty"`
	Extras   []models.ListingMenuExtra `json:"extras,omitempty"`
}

type menuSectionOut struct {
	models.ListingMenuSection
	Items []models.ListingMenuItem `json:"items,omitempty"`
}

// loadListingTree assembles the full halls/menus/sections/items/extras
// tree for one listing in exactly 5 queries total, regardless of how many
// halls/menus/sections/items exist — brief section 9's "не создавать
// N+1" applied to the detail view too, not just the list.
func loadListingTree(db *gorm.DB, listingID uint) ([]models.ListingHall, []menuOut) {
	var halls []models.ListingHall
	db.Where("listing_id = ?", listingID).Order("sort_order").Find(&halls)

	var menus []models.ListingMenu
	db.Where("listing_id = ?", listingID).Order("sort_order").Find(&menus)
	if len(menus) == 0 {
		return halls, []menuOut{}
	}

	menuIDs := make([]uint, len(menus))
	for i, m := range menus {
		menuIDs[i] = m.ID
	}

	var sections []models.ListingMenuSection
	db.Where("menu_id IN ?", menuIDs).Order("sort_order").Find(&sections)
	sectionIDs := make([]uint, len(sections))
	for i, s := range sections {
		sectionIDs[i] = s.ID
	}

	var items []models.ListingMenuItem
	if len(sectionIDs) > 0 {
		db.Where("section_id IN ?", sectionIDs).Order("sort_order").Find(&items)
	}
	itemsBySection := map[uint][]models.ListingMenuItem{}
	for _, it := range items {
		itemsBySection[it.SectionID] = append(itemsBySection[it.SectionID], it)
	}

	sectionsByMenu := map[uint][]menuSectionOut{}
	for _, s := range sections {
		sectionsByMenu[s.MenuID] = append(sectionsByMenu[s.MenuID], menuSectionOut{
			ListingMenuSection: s,
			Items:              itemsBySection[s.ID],
		})
	}

	var extras []models.ListingMenuExtra
	db.Where("menu_id IN ?", menuIDs).Order("sort_order").Find(&extras)
	extrasByMenu := map[uint][]models.ListingMenuExtra{}
	for _, e := range extras {
		extrasByMenu[e.MenuID] = append(extrasByMenu[e.MenuID], e)
	}

	out := make([]menuOut, 0, len(menus))
	for _, m := range menus {
		out = append(out, menuOut{
			ListingMenu: m,
			Sections:    sectionsByMenu[m.ID],
			Extras:      extrasByMenu[m.ID],
		})
	}
	return halls, out
}

// Get — GET /api/listings/:id. The one place (besides Menus below) that
// loads the full hall/menu tree — brief section 9's "полное дерево меню
// загружать только через detail или отдельный endpoint menus."
func (h *ListingHandler) Get(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}

	var listing models.Listing
	if err := h.DB.Preload("Category").First(&listing, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "listing not found"})
		return
	}

	halls, menus := loadListingTree(h.DB, listing.ID)
	provider := loadListingProvider(h.DB, listing.ID)
	c.JSON(http.StatusOK, gin.H{"listing": listingDetailOut{Listing: listing, Halls: halls, Menus: menus, Provider: provider}})
}

// loadListingProvider — the single-listing counterpart to
// attachProviderBriefs, used by Get. Returns the full contact shape (brief
// section 9's contact block needs phone/whatsapp/telegram, which the
// catalog-card providerBrief deliberately omits) minus internal fields
// (Этап 11G — see providerDetailOut's own doc comment), or nil under the
// exact same conditions attachProviderBriefs would omit an entry.
func loadListingProvider(db *gorm.DB, listingID uint) *providerDetailOut {
	var owner models.ListingManager
	if err := db.Where("listing_id = ? AND role = ?", listingID, models.ListingManagerRoleOwner).First(&owner).Error; err != nil {
		return nil
	}
	var provider models.Provider
	if err := db.Where("user_id = ? AND status = ?", owner.UserID, models.ProviderStatusActive).First(&provider).Error; err != nil {
		return nil
	}
	out := providerDetailFrom(provider)
	return &out
}

// Menus — GET /api/listings/:id/menus. The lean alternative to Get above
// when only the menu tree itself is needed (brief section 9's "отдельным
// endpoint menus") — same loadListingTree, same 5-query bound.
func (h *ListingHandler) Menus(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	if err := h.DB.First(&models.Listing{}, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "listing not found"})
		return
	}

	_, menus := loadListingTree(h.DB, uint(id))
	c.JSON(http.StatusOK, gin.H{"menus": menus})
}

// Halls — GET /api/listings/:id/halls. Lightweight, no nested menu data —
// just what a hall picker needs.
func (h *ListingHandler) Halls(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	if err := h.DB.First(&models.Listing{}, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "listing not found"})
		return
	}

	var halls []models.ListingHall
	h.DB.Where("listing_id = ? AND is_active = ?", id, true).Order("sort_order").Find(&halls)
	c.JSON(http.StatusOK, gin.H{"halls": halls})
}

type listingInput struct {
	CategoryID    uint     `json:"category_id" binding:"required"`
	NameRu        string   `json:"name_ru" binding:"required"`
	NameKz        string   `json:"name_kz" binding:"required"`
	DescriptionRu string   `json:"description_ru"`
	DescriptionKz string   `json:"description_kz"`
	City          string   `json:"city"`
	Phone         string   `json:"phone"`
	Price         uint     `json:"price"`
	MinGuests     uint     `json:"min_guests"`
	MaxGuests     uint     `json:"max_guests"`
	Rating        float32  `json:"rating"`
	Emoji         string   `json:"emoji"`
	ColorFrom     string   `json:"color_from"`
	ColorTo       string   `json:"color_to"`
	ImageURLs     []string `json:"image_urls"`
	VideoURLs     []string `json:"video_urls"`

	// Address/Latitude/Longitude/PlaceID/Capacity — additive location
	// fields (see models/listing.go's own doc comment). Every existing
	// caller simply omits them and gets the pre-existing zero values.
	Address   string   `json:"address"`
	Latitude  *float64 `json:"latitude"`
	Longitude *float64 `json:"longitude"`
	PlaceID   *string  `json:"place_id"`
	Capacity  uint     `json:"capacity"`

	// PriceType — Этап 11. Free-form on Create (defaults to "fixed" when
	// omitted, see Create below).
	PriceType string `json:"price_type"`

	// IsActive — Этап 11 "включить/выключить публикацию". A *bool,
	// deliberately: every pre-existing caller (the admin services form)
	// never sends this field at all, and a plain `bool` would silently
	// read as false and deactivate the listing on every single save. Only
	// applied in Update when explicitly non-nil — same "own value only
	// overrides when present" shape this codebase already uses for
	// Latitude/Longitude/PlaceID above. Create ignores it; a brand-new
	// listing is always published, matching pre-existing behavior exactly.
	IsActive *bool `json:"is_active"`
}

func (h *ListingHandler) Create(c *gin.Context) {
	var in listingInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var category models.Category
	if err := h.DB.First(&category, in.CategoryID).Error; err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "category not found"})
		return
	}

	listing := listingFromInput(in)
	if err := h.DB.Create(&listing).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create listing"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"listing": listing})
}

// listingFromInput builds a brand-new Listing from Create's own input —
// shared with CreateOwn below so the admin path and the self-serve
// provider path can never drift on which fields a "new listing" actually
// sets.
func listingFromInput(in listingInput) models.Listing {
	priceType := in.PriceType
	if priceType == "" {
		priceType = models.PriceTypeFixed
	}
	return models.Listing{
		CategoryID:    in.CategoryID,
		NameRu:        in.NameRu,
		NameKz:        in.NameKz,
		DescriptionRu: in.DescriptionRu,
		DescriptionKz: in.DescriptionKz,
		City:          in.City,
		Phone:         in.Phone,
		Price:         in.Price,
		MinGuests:     in.MinGuests,
		MaxGuests:     in.MaxGuests,
		Rating:        in.Rating,
		Emoji:         in.Emoji,
		ColorFrom:     in.ColorFrom,
		ColorTo:       in.ColorTo,
		ImageURLs:     in.ImageURLs,
		VideoURLs:     in.VideoURLs,
		IsActive:      true,
		Address:       in.Address,
		Latitude:      in.Latitude,
		Longitude:     in.Longitude,
		PlaceID:       in.PlaceID,
		Capacity:      in.Capacity,
		PriceType:     priceType,
	}
}

// CreateOwn — POST /api/provider/me/listings (auth only, no RequireAdmin).
// Этап 11's self-serve "Добавить услугу": requires an existing Provider
// profile (brief section 4 — "После сохранения provider profile
// пользователь получает доступ к разделу «Мои услуги»") and, on success,
// creates the matching ListingManager(role=owner) row in the same
// transaction — reusing the exact ownership model restaurants/venues
// already use (brief section 6), rather than a parallel Provider->Listing
// FK. From that point on, PUT/DELETE /api/listings/:id (the existing
// `manage` route group) already authorize this caller via
// RequireListingAccess with zero new code.
func (h *ListingHandler) CreateOwn(c *gin.Context) {
	userID := currentUserID(c)

	var provider models.Provider
	if err := h.DB.Where("user_id = ?", userID).First(&provider).Error; err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": "create a provider profile first"})
		return
	}

	var in listingInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	var category models.Category
	if err := h.DB.First(&category, in.CategoryID).Error; err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "category not found"})
		return
	}

	listing := listingFromInput(in)
	err := h.DB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(&listing).Error; err != nil {
			return err
		}
		manager := models.ListingManager{ListingID: listing.ID, UserID: userID, Role: models.ListingManagerRoleOwner}
		return tx.Create(&manager).Error
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create listing"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"listing": listing})
}

func (h *ListingHandler) Update(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}

	var listing models.Listing
	if err := h.DB.First(&listing, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "listing not found"})
		return
	}

	var in listingInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	listing.CategoryID = in.CategoryID
	listing.NameRu = in.NameRu
	listing.NameKz = in.NameKz
	listing.DescriptionRu = in.DescriptionRu
	listing.DescriptionKz = in.DescriptionKz
	listing.City = in.City
	listing.Phone = in.Phone
	listing.Price = in.Price
	listing.MinGuests = in.MinGuests
	listing.MaxGuests = in.MaxGuests
	listing.Rating = in.Rating
	listing.Emoji = in.Emoji
	listing.ColorFrom = in.ColorFrom
	listing.ColorTo = in.ColorTo
	listing.ImageURLs = in.ImageURLs
	listing.VideoURLs = in.VideoURLs
	listing.Address = in.Address
	listing.Latitude = in.Latitude
	listing.Longitude = in.Longitude
	listing.PlaceID = in.PlaceID
	listing.Capacity = in.Capacity
	if in.PriceType != "" {
		listing.PriceType = in.PriceType
	}
	if in.IsActive != nil {
		listing.IsActive = *in.IsActive
	}

	if err := h.DB.Save(&listing).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update listing"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"listing": listing})
}

func (h *ListingHandler) Delete(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}

	// Этап 11E QA finding: ListingManager has a real GORM relation back to
	// Listing (`Listing *Listing`, unlike ListingHall/ListingMenu's
	// deliberately relation-less ListingID — see their own doc comments),
	// so the DB has a real FK constraint here. Deleting a listing that
	// still has any ListingManager row (every self-serve provider listing
	// has one — see CreateOwn) used to 500 with a foreign-key violation.
	// Owner rows are removed first, in the same transaction, so a failed
	// listing delete never leaves a dangling manager row behind either.
	err = h.DB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("listing_id = ?", id).Delete(&models.ListingManager{}).Error; err != nil {
			return err
		}
		return tx.Delete(&models.Listing{}, id).Error
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete listing"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "listing deleted"})
}
