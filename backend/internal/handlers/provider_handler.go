package handlers

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// ProviderHandler is the "Стать услугодателем" / "Профиль услугодателя"
// surface — Этап 11. Deliberately tiny: no moderation, no verification,
// no separate provider login (see models/provider.go's own doc comment).
type ProviderHandler struct {
	DB *gorm.DB
}

func NewProviderHandler(db *gorm.DB) *ProviderHandler {
	return &ProviderHandler{DB: db}
}

type providerInput struct {
	DisplayName string `json:"display_name" binding:"required"`
	City        string `json:"city"`
	Description string `json:"description"`
	Phone       string `json:"phone"`
	WhatsApp    string `json:"whatsapp"`
	Telegram    string `json:"telegram"`
	AvatarURL   string `json:"avatar_url"`
}

// Me — GET /api/provider/me. 404 when the caller has no provider profile
// yet — the frontend's own "Стать услугодателем" vs. "Профиль
// услугодателя" button swap (brief section 3) is driven directly off this.
func (h *ProviderHandler) Me(c *gin.Context) {
	userID := currentUserID(c)
	var provider models.Provider
	if err := h.DB.Where("user_id = ?", userID).First(&provider).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "no provider profile"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"provider": provider})
}

// Create — POST /api/provider. One per user (brief section 2's unique
// index); a second attempt is a 409, not a silent overwrite — the caller
// should PUT /api/provider/me instead.
func (h *ProviderHandler) Create(c *gin.Context) {
	userID := currentUserID(c)

	var existing models.Provider
	if err := h.DB.Where("user_id = ?", userID).First(&existing).Error; err == nil {
		c.JSON(http.StatusConflict, gin.H{"error": "provider profile already exists"})
		return
	}

	var in providerInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	displayName := strings.TrimSpace(in.DisplayName)
	if displayName == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "display_name is required"})
		return
	}

	provider := models.Provider{
		UserID:      userID,
		DisplayName: displayName,
		City:        in.City,
		Description: in.Description,
		Phone:       in.Phone,
		WhatsApp:    in.WhatsApp,
		Telegram:    in.Telegram,
		AvatarURL:   in.AvatarURL,
		// Straight to active — see models/provider.go's own doc comment on
		// why (no moderation UI exists this stage).
		Status: models.ProviderStatusActive,
	}
	if err := h.DB.Create(&provider).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create provider profile"})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"provider": provider})
}

// UpdateMe — PUT /api/provider/me. Only ever the caller's own row —
// scoped by the JWT's own user id, never a client-supplied provider id.
func (h *ProviderHandler) UpdateMe(c *gin.Context) {
	userID := currentUserID(c)

	var provider models.Provider
	if err := h.DB.Where("user_id = ?", userID).First(&provider).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "no provider profile"})
		return
	}

	var in providerInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	displayName := strings.TrimSpace(in.DisplayName)
	if displayName == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "display_name is required"})
		return
	}

	provider.DisplayName = displayName
	provider.City = in.City
	provider.Description = in.Description
	provider.Phone = in.Phone
	provider.WhatsApp = in.WhatsApp
	provider.Telegram = in.Telegram
	provider.AvatarURL = in.AvatarURL

	if err := h.DB.Save(&provider).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update provider profile"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"provider": provider})
}
