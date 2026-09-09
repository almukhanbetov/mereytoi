package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// ListingMenuHandler is the admin CRUD for the whole menu-builder
// aggregate — ListingMenu, ListingMenuSection, ListingMenuItem,
// ListingMenuExtra — bundled in one file/handler the same way
// EventCandidateHandler already bundles candidate+vote CRUD together
// (brief section 10 — extend the existing style, don't invent a new one).
type ListingMenuHandler struct {
	DB *gorm.DB
}

func NewListingMenuHandler(db *gorm.DB) *ListingMenuHandler {
	return &ListingMenuHandler{DB: db}
}

// ---- Menu ----

type listingMenuInput struct {
	HallID        *uint      `json:"hall_id"`
	NameRu        string     `json:"name_ru" binding:"required"`
	NameKz        string     `json:"name_kz" binding:"required"`
	DescriptionRu string     `json:"description_ru"`
	DescriptionKz string     `json:"description_kz"`
	PricePerGuest uint       `json:"price_per_guest"`
	MinGuests     *uint      `json:"min_guests"`
	MaxGuests     *uint      `json:"max_guests"`
	IsActive      *bool      `json:"is_active"`
	SortOrder     int        `json:"sort_order"`
	ValidFrom     *time.Time `json:"valid_from"`
	ValidUntil    *time.Time `json:"valid_until"`
}

// validateMenuHall confirms a menu's optional HallID actually belongs to
// the same listing — used by both Create and Update below.
func validateMenuHall(db *gorm.DB, listingID int, hallID *uint) bool {
	if hallID == nil {
		return true
	}
	return db.Where("id = ? AND listing_id = ?", *hallID, listingID).First(&models.ListingHall{}).Error == nil
}

// CreateMenu — POST /api/listings/:id/menus (admin).
func (h *ListingMenuHandler) CreateMenu(c *gin.Context) {
	listingID, ok := atoiParam(c, "id")
	if !ok {
		return
	}
	if err := h.DB.First(&models.Listing{}, listingID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "listing not found"})
		return
	}

	var in listingMenuInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if !validateMenuHall(h.DB, listingID, in.HallID) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "hall not found for this listing"})
		return
	}

	menu := models.ListingMenu{
		ListingID:     uint(listingID),
		HallID:        in.HallID,
		NameRu:        in.NameRu,
		NameKz:        in.NameKz,
		DescriptionRu: in.DescriptionRu,
		DescriptionKz: in.DescriptionKz,
		PricePerGuest: in.PricePerGuest,
		MinGuests:     in.MinGuests,
		MaxGuests:     in.MaxGuests,
		IsActive:      true,
		SortOrder:     in.SortOrder,
		ValidFrom:     in.ValidFrom,
		ValidUntil:    in.ValidUntil,
	}
	if in.IsActive != nil {
		menu.IsActive = *in.IsActive
	}
	if err := h.DB.Create(&menu).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create menu"})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"menu": menu})
}

// UpdateMenu — PUT /api/listings/:id/menus/:menuId (admin).
func (h *ListingMenuHandler) UpdateMenu(c *gin.Context) {
	listingID, ok := atoiParam(c, "id")
	if !ok {
		return
	}
	menuID, ok := atoiParam(c, "menuId")
	if !ok {
		return
	}

	var menu models.ListingMenu
	if err := h.DB.Where("id = ? AND listing_id = ?", menuID, listingID).First(&menu).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "menu not found"})
		return
	}

	var in listingMenuInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if !validateMenuHall(h.DB, listingID, in.HallID) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "hall not found for this listing"})
		return
	}

	menu.HallID = in.HallID
	menu.NameRu = in.NameRu
	menu.NameKz = in.NameKz
	menu.DescriptionRu = in.DescriptionRu
	menu.DescriptionKz = in.DescriptionKz
	menu.PricePerGuest = in.PricePerGuest
	menu.MinGuests = in.MinGuests
	menu.MaxGuests = in.MaxGuests
	menu.SortOrder = in.SortOrder
	menu.ValidFrom = in.ValidFrom
	menu.ValidUntil = in.ValidUntil
	if in.IsActive != nil {
		menu.IsActive = *in.IsActive
	}

	if err := h.DB.Save(&menu).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update menu"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"menu": menu})
}

// DeleteMenu — DELETE /api/listings/:id/menus/:menuId (admin). Cascades
// its own sections/items/extras (nothing else references those); any
// EventCandidate/BookingItem referencing this menu keeps its own
// MenuID/MenuName/MenuPricePerGuest snapshot untouched — same "dangling
// pointer, snapshot still correct" reasoning as ListingHallHandler.Delete.
func (h *ListingMenuHandler) DeleteMenu(c *gin.Context) {
	listingID, ok := atoiParam(c, "id")
	if !ok {
		return
	}
	menuID, ok := atoiParam(c, "menuId")
	if !ok {
		return
	}

	var menu models.ListingMenu
	if err := h.DB.Where("id = ? AND listing_id = ?", menuID, listingID).First(&menu).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "menu not found"})
		return
	}

	var sectionIDs []uint
	h.DB.Model(&models.ListingMenuSection{}).Where("menu_id = ?", menu.ID).Pluck("id", &sectionIDs)
	if len(sectionIDs) > 0 {
		h.DB.Where("section_id IN ?", sectionIDs).Delete(&models.ListingMenuItem{})
	}
	h.DB.Where("menu_id = ?", menu.ID).Delete(&models.ListingMenuSection{})
	h.DB.Where("menu_id = ?", menu.ID).Delete(&models.ListingMenuExtra{})

	if err := h.DB.Delete(&menu).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete menu"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "menu deleted"})
}

// ---- Section ----

type listingMenuSectionInput struct {
	TitleRu   string `json:"title_ru" binding:"required"`
	TitleKz   string `json:"title_kz" binding:"required"`
	SortOrder int    `json:"sort_order"`
}

// CreateSection — POST /api/listings/:id/menus/:menuId/sections (admin).
func (h *ListingMenuHandler) CreateSection(c *gin.Context) {
	listingID, ok := atoiParam(c, "id")
	if !ok {
		return
	}
	menuID, ok := atoiParam(c, "menuId")
	if !ok {
		return
	}
	if err := h.DB.Where("id = ? AND listing_id = ?", menuID, listingID).First(&models.ListingMenu{}).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "menu not found"})
		return
	}

	var in listingMenuSectionInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	section := models.ListingMenuSection{MenuID: uint(menuID), TitleRu: in.TitleRu, TitleKz: in.TitleKz, SortOrder: in.SortOrder}
	if err := h.DB.Create(&section).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create section"})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"section": section})
}

// UpdateSection — PUT /api/listings/:id/menus/:menuId/sections/:sectionId (admin).
func (h *ListingMenuHandler) UpdateSection(c *gin.Context) {
	menuID, ok := atoiParam(c, "menuId")
	if !ok {
		return
	}
	sectionID, ok := atoiParam(c, "sectionId")
	if !ok {
		return
	}

	var section models.ListingMenuSection
	if err := h.DB.Where("id = ? AND menu_id = ?", sectionID, menuID).First(&section).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "section not found"})
		return
	}

	var in listingMenuSectionInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	section.TitleRu = in.TitleRu
	section.TitleKz = in.TitleKz
	section.SortOrder = in.SortOrder

	if err := h.DB.Save(&section).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update section"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"section": section})
}

// DeleteSection — DELETE /api/listings/:id/menus/:menuId/sections/:sectionId (admin).
func (h *ListingMenuHandler) DeleteSection(c *gin.Context) {
	menuID, ok := atoiParam(c, "menuId")
	if !ok {
		return
	}
	sectionID, ok := atoiParam(c, "sectionId")
	if !ok {
		return
	}

	var section models.ListingMenuSection
	if err := h.DB.Where("id = ? AND menu_id = ?", sectionID, menuID).First(&section).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "section not found"})
		return
	}
	h.DB.Where("section_id = ?", section.ID).Delete(&models.ListingMenuItem{})
	if err := h.DB.Delete(&section).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete section"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "section deleted"})
}

// ---- Item ----

type listingMenuItemInput struct {
	NameRu        string `json:"name_ru" binding:"required"`
	NameKz        string `json:"name_kz" binding:"required"`
	DescriptionRu string `json:"description_ru"`
	DescriptionKz string `json:"description_kz"`
	QuantityText  string `json:"quantity_text"`
	SortOrder     int    `json:"sort_order"`
}

// CreateItem — POST /api/listings/:id/menus/:menuId/sections/:sectionId/items (admin).
func (h *ListingMenuHandler) CreateItem(c *gin.Context) {
	sectionID, ok := atoiParam(c, "sectionId")
	if !ok {
		return
	}
	if err := h.DB.First(&models.ListingMenuSection{}, sectionID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "section not found"})
		return
	}

	var in listingMenuItemInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	item := models.ListingMenuItem{
		SectionID:     uint(sectionID),
		NameRu:        in.NameRu,
		NameKz:        in.NameKz,
		DescriptionRu: in.DescriptionRu,
		DescriptionKz: in.DescriptionKz,
		QuantityText:  in.QuantityText,
		SortOrder:     in.SortOrder,
	}
	if err := h.DB.Create(&item).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create item"})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"item": item})
}

// UpdateItem — PUT .../items/:itemId (admin).
func (h *ListingMenuHandler) UpdateItem(c *gin.Context) {
	sectionID, ok := atoiParam(c, "sectionId")
	if !ok {
		return
	}
	itemID, ok := atoiParam(c, "itemId")
	if !ok {
		return
	}

	var item models.ListingMenuItem
	if err := h.DB.Where("id = ? AND section_id = ?", itemID, sectionID).First(&item).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "item not found"})
		return
	}

	var in listingMenuItemInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	item.NameRu = in.NameRu
	item.NameKz = in.NameKz
	item.DescriptionRu = in.DescriptionRu
	item.DescriptionKz = in.DescriptionKz
	item.QuantityText = in.QuantityText
	item.SortOrder = in.SortOrder

	if err := h.DB.Save(&item).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update item"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"item": item})
}

// DeleteItem — DELETE .../items/:itemId (admin).
func (h *ListingMenuHandler) DeleteItem(c *gin.Context) {
	sectionID, ok := atoiParam(c, "sectionId")
	if !ok {
		return
	}
	itemID, ok := atoiParam(c, "itemId")
	if !ok {
		return
	}

	if err := h.DB.Where("id = ? AND section_id = ?", itemID, sectionID).Delete(&models.ListingMenuItem{}).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete item"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "item deleted"})
}

// ---- Extra ----

type listingMenuExtraInput struct {
	Type          string `json:"type" binding:"required"`
	TitleRu       string `json:"title_ru" binding:"required"`
	TitleKz       string `json:"title_kz" binding:"required"`
	Price         uint   `json:"price"`
	Unit          string `json:"unit"`
	DescriptionRu string `json:"description_ru"`
	DescriptionKz string `json:"description_kz"`
	SortOrder     int    `json:"sort_order"`
}

// CreateExtra — POST /api/listings/:id/menus/:menuId/extras (admin).
func (h *ListingMenuHandler) CreateExtra(c *gin.Context) {
	menuID, ok := atoiParam(c, "menuId")
	if !ok {
		return
	}
	if err := h.DB.First(&models.ListingMenu{}, menuID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "menu not found"})
		return
	}

	var in listingMenuExtraInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	extra := models.ListingMenuExtra{
		MenuID:        uint(menuID),
		Type:          in.Type,
		TitleRu:       in.TitleRu,
		TitleKz:       in.TitleKz,
		Price:         in.Price,
		Unit:          in.Unit,
		DescriptionRu: in.DescriptionRu,
		DescriptionKz: in.DescriptionKz,
		SortOrder:     in.SortOrder,
	}
	if err := h.DB.Create(&extra).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create extra"})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"extra": extra})
}

// UpdateExtra — PUT /api/listings/:id/menus/:menuId/extras/:extraId (admin).
func (h *ListingMenuHandler) UpdateExtra(c *gin.Context) {
	menuID, ok := atoiParam(c, "menuId")
	if !ok {
		return
	}
	extraID, ok := atoiParam(c, "extraId")
	if !ok {
		return
	}

	var extra models.ListingMenuExtra
	if err := h.DB.Where("id = ? AND menu_id = ?", extraID, menuID).First(&extra).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "extra not found"})
		return
	}

	var in listingMenuExtraInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	extra.Type = in.Type
	extra.TitleRu = in.TitleRu
	extra.TitleKz = in.TitleKz
	extra.Price = in.Price
	extra.Unit = in.Unit
	extra.DescriptionRu = in.DescriptionRu
	extra.DescriptionKz = in.DescriptionKz
	extra.SortOrder = in.SortOrder

	if err := h.DB.Save(&extra).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update extra"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"extra": extra})
}

// DeleteExtra — DELETE /api/listings/:id/menus/:menuId/extras/:extraId (admin).
func (h *ListingMenuHandler) DeleteExtra(c *gin.Context) {
	menuID, ok := atoiParam(c, "menuId")
	if !ok {
		return
	}
	extraID, ok := atoiParam(c, "extraId")
	if !ok {
		return
	}

	if err := h.DB.Where("id = ? AND menu_id = ?", extraID, menuID).Delete(&models.ListingMenuExtra{}).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete extra"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "extra deleted"})
}
