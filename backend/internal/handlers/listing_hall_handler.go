package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// ListingHallHandler is the admin CRUD for ListingHall — mirrors
// ListingHandler's own Create/Update/Delete shape exactly (brief section
// 10 — "не создавать новую архитектуру API, если можно расширить
// текущую").
type ListingHallHandler struct {
	DB *gorm.DB
}

func NewListingHallHandler(db *gorm.DB) *ListingHallHandler {
	return &ListingHallHandler{DB: db}
}

type listingHallInput struct {
	NameRu        string   `json:"name_ru" binding:"required"`
	NameKz        string   `json:"name_kz" binding:"required"`
	DescriptionRu string   `json:"description_ru"`
	DescriptionKz string   `json:"description_kz"`
	Capacity      uint     `json:"capacity"`
	Price         uint     `json:"price"`
	ImageURLs     []string `json:"image_urls"`
	IsActive      *bool    `json:"is_active"`
	SortOrder     int      `json:"sort_order"`
}

// Create — POST /api/listings/:id/halls (admin).
func (h *ListingHallHandler) Create(c *gin.Context) {
	listingID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid listing id"})
		return
	}
	if err := h.DB.First(&models.Listing{}, listingID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "listing not found"})
		return
	}

	var in listingHallInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	hall := models.ListingHall{
		ListingID:     uint(listingID),
		NameRu:        in.NameRu,
		NameKz:        in.NameKz,
		DescriptionRu: in.DescriptionRu,
		DescriptionKz: in.DescriptionKz,
		Capacity:      in.Capacity,
		Price:         in.Price,
		ImageURLs:     in.ImageURLs,
		IsActive:      true,
		SortOrder:     in.SortOrder,
	}
	if in.IsActive != nil {
		hall.IsActive = *in.IsActive
	}
	if err := h.DB.Create(&hall).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create hall"})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"hall": hall})
}

// Update — PUT /api/listings/:id/halls/:hallId (admin). Scoped to the
// listing in the URL — a hallId that belongs to a different listing 404s,
// the same guard pattern EventCandidateHandler already uses for
// :id/:cid.
func (h *ListingHallHandler) Update(c *gin.Context) {
	listingID, ok := atoiParam(c, "id")
	if !ok {
		return
	}
	hallID, ok := atoiParam(c, "hallId")
	if !ok {
		return
	}

	var hall models.ListingHall
	if err := h.DB.Where("id = ? AND listing_id = ?", hallID, listingID).First(&hall).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "hall not found"})
		return
	}

	var in listingHallInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	hall.NameRu = in.NameRu
	hall.NameKz = in.NameKz
	hall.DescriptionRu = in.DescriptionRu
	hall.DescriptionKz = in.DescriptionKz
	hall.Capacity = in.Capacity
	hall.Price = in.Price
	hall.ImageURLs = in.ImageURLs
	hall.SortOrder = in.SortOrder
	if in.IsActive != nil {
		hall.IsActive = *in.IsActive
	}

	if err := h.DB.Save(&hall).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update hall"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"hall": hall})
}

// Delete — DELETE /api/listings/:id/halls/:hallId (admin). Any
// EventCandidate/ListingMenu still referencing this hall keeps its
// existing HallID/HallName — HallID becomes a "dangling" FK-less pointer
// (no DB-level FK constraint enforces this — see listing_hall.go's own
// doc comment on why there's no back-reference association at all), but
// the already-captured HallName snapshot on any EventCandidate means past
// selections still display correctly; only the *live* Hall preload for a
// still-shortlisted candidate would come back nil, same as if it had
// never Preloaded successfully.
func (h *ListingHallHandler) Delete(c *gin.Context) {
	listingID, ok := atoiParam(c, "id")
	if !ok {
		return
	}
	hallID, ok := atoiParam(c, "hallId")
	if !ok {
		return
	}

	if err := h.DB.Where("id = ? AND listing_id = ?", hallID, listingID).Delete(&models.ListingHall{}).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete hall"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "hall deleted"})
}
