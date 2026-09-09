package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

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

	listingIDs := make([]uint, len(listings))
	for i, l := range listings {
		listingIDs[i] = l.ID
	}

	// Two grouped queries total, regardless of how many listings are on
	// the page — brief section 9's "не создавать N+1" — never one query
	// per listing.
	type hallCountRow struct {
		ListingID uint
		Count     int64
	}
	var hallCounts []hallCountRow
	h.DB.Model(&models.ListingHall{}).Select("listing_id, count(*) as count").
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
	h.DB.Model(&models.ListingMenu{}).Select("listing_id, count(*) as count, min(price_per_guest) as min_price").
		Where("listing_id IN ? AND is_active = ?", listingIDs, true).Group("listing_id").Scan(&menuAggs)
	menuByListing := map[uint]menuAggRow{}
	for _, row := range menuAggs {
		menuByListing[row.ListingID] = row
	}

	out := make([]listingOut, 0, len(listings))
	for _, l := range listings {
		row := listingOut{Listing: l, HallCount: hallByListing[l.ID]}
		if agg, ok := menuByListing[l.ID]; ok {
			row.MenuCount = agg.Count
			minPrice := agg.MinPrice
			row.MinMenuPricePerGuest = &minPrice
		}
		out = append(out, row)
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
	c.JSON(http.StatusOK, gin.H{"listing": listingDetailOut{Listing: listing, Halls: halls, Menus: menus}})
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

	listing := models.Listing{
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
	}
	if err := h.DB.Create(&listing).Error; err != nil {
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

	if err := h.DB.Delete(&models.Listing{}, id).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete listing"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "listing deleted"})
}
