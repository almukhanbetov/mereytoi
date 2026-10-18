package handlers

import (
	"encoding/json"
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

// newProviderStatus is the status a self-serve profile starts with. It is
// active because no moderation flow exists yet; a later moderation stage
// switches this one constant to ProviderStatusPending (the enum and column
// already exist) without touching the create flow itself.
const newProviderStatus = models.ProviderStatusActive

// maxExperienceYears bounds experience_years to a plausible range.
const maxExperienceYears = 80

// providerInput is everything a caller may set on their own profile. It
// deliberately has no user_id, id or status: the owner is always the
// authenticated user and the status is server-controlled, so those keys in
// a request body are simply ignored.
type providerInput struct {
	DisplayName     string      `json:"display_name" binding:"required"`
	City            string      `json:"city"`
	Description     string      `json:"description"`
	Phone           string      `json:"phone"`
	WhatsApp        string      `json:"whatsapp"`
	Telegram        string      `json:"telegram"`
	AvatarURL       string      `json:"avatar_url"`
	ExperienceYears optionalInt `json:"experience_years"`
}

// optionalInt tells a missing JSON key apart from an explicit null: on
// update, a client that doesn't know about experience_years (older app
// builds) must not wipe it, while one that sends null clears it.
type optionalInt struct {
	Set   bool
	Value *int
}

func (o *optionalInt) UnmarshalJSON(b []byte) error {
	o.Set = true
	if string(b) == "null" {
		o.Value = nil
		return nil
	}
	var v int
	if err := json.Unmarshal(b, &v); err != nil {
		return err
	}
	o.Value = &v
	return nil
}

func validExperience(o optionalInt) bool {
	return o.Value == nil || (*o.Value >= 0 && *o.Value <= maxExperienceYears)
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
	if !validExperience(in.ExperienceYears) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid experience_years"})
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
		// Owner always comes from the JWT (UserID above), never the body.
		ExperienceYears: in.ExperienceYears.Value,
		Status:          newProviderStatus,
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
	if !validExperience(in.ExperienceYears) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid experience_years"})
		return
	}

	provider.DisplayName = displayName
	provider.City = in.City
	provider.Description = in.Description
	provider.Phone = in.Phone
	provider.WhatsApp = in.WhatsApp
	provider.Telegram = in.Telegram
	provider.AvatarURL = in.AvatarURL
	if in.ExperienceYears.Set {
		provider.ExperienceYears = in.ExperienceYears.Value
	}

	if err := h.DB.Save(&provider).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update provider profile"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"provider": provider})
}
