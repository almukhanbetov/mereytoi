package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

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

	c.JSON(http.StatusOK, gin.H{"listings": listings})
}

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
	c.JSON(http.StatusOK, gin.H{"listing": listing})
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
	VideoURL      string   `json:"video_url"`
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
		VideoURL:      in.VideoURL,
		IsActive:      true,
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
	listing.VideoURL = in.VideoURL

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
