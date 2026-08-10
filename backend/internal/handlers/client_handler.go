package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

type ClientHandler struct {
	DB *gorm.DB
}

func NewClientHandler(db *gorm.DB) *ClientHandler {
	return &ClientHandler{DB: db}
}

// List returns all showcased clients, newest first — GET /api/clients.
func (h *ClientHandler) List(c *gin.Context) {
	var clients []models.Client
	if err := h.DB.Order("created_at desc").Find(&clients).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch clients"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"clients": clients})
}

type clientInput struct {
	Name     string `json:"name" binding:"required"`
	PhotoURL string `json:"photo_url"`
}

// Create adds a new client entry — POST /api/clients (admin).
func (h *ClientHandler) Create(c *gin.Context) {
	var in clientInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	client := models.Client{
		Name:     in.Name,
		PhotoURL: in.PhotoURL,
	}
	if err := h.DB.Create(&client).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create client"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"client": client})
}

// Update edits a client entry — PUT /api/clients/:id (admin).
func (h *ClientHandler) Update(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}

	var client models.Client
	if err := h.DB.First(&client, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "client not found"})
		return
	}

	var in clientInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	client.Name = in.Name
	client.PhotoURL = in.PhotoURL

	if err := h.DB.Save(&client).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update client"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"client": client})
}

// Delete removes a client entry — DELETE /api/clients/:id (admin).
func (h *ClientHandler) Delete(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}

	if err := h.DB.Delete(&models.Client{}, id).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete client"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "client deleted"})
}
