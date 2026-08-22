package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

type CategoryHandler struct {
	DB *gorm.DB
}

func NewCategoryHandler(db *gorm.DB) *CategoryHandler {
	return &CategoryHandler{DB: db}
}

func (h *CategoryHandler) List(c *gin.Context) {
	var categories []models.Category
	if err := h.DB.Order("position asc").Find(&categories).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch categories"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"categories": categories})
}

func (h *CategoryHandler) GetBySlug(c *gin.Context) {
	slug := c.Param("slug")

	var category models.Category
	if err := h.DB.Where("slug = ?", slug).First(&category).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "category not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"category": category})
}

type categoryInput struct {
	Slug     string `json:"slug" binding:"required"`
	NameRu   string `json:"name_ru" binding:"required"`
	NameKz   string `json:"name_kz" binding:"required"`
	Position int    `json:"position"`
}

func (h *CategoryHandler) Create(c *gin.Context) {
	var in categoryInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var existing models.Category
	if err := h.DB.Where("slug = ?", in.Slug).First(&existing).Error; err == nil {
		c.JSON(http.StatusConflict, gin.H{"error": "category with this slug already exists"})
		return
	}

	category := models.Category{
		Slug:     in.Slug,
		NameRu:   in.NameRu,
		NameKz:   in.NameKz,
		Position: in.Position,
	}
	if err := h.DB.Create(&category).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create category"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"category": category})
}

func (h *CategoryHandler) Update(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}

	var category models.Category
	if err := h.DB.First(&category, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "category not found"})
		return
	}

	var in categoryInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if in.Slug != category.Slug {
		var existing models.Category
		if err := h.DB.Where("slug = ? AND id <> ?", in.Slug, category.ID).First(&existing).Error; err == nil {
			c.JSON(http.StatusConflict, gin.H{"error": "category with this slug already exists"})
			return
		}
	}

	category.Slug = in.Slug
	category.NameRu = in.NameRu
	category.NameKz = in.NameKz
	category.Position = in.Position

	if err := h.DB.Save(&category).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update category"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"category": category})
}

// Delete refuses to remove a category that still has listings — deleting it
// would silently orphan/cascade-delete all services in that category, which
// is rarely what an admin actually wants from a single click.
func (h *CategoryHandler) Delete(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}

	var count int64
	if err := h.DB.Model(&models.Listing{}).Where("category_id = ?", id).Count(&count).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check category listings"})
		return
	}
	if count > 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "category has listings and cannot be deleted"})
		return
	}

	if err := h.DB.Delete(&models.Category{}, id).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete category"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "category deleted"})
}
