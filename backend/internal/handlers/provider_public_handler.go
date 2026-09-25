package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// providerDetailOut is the public-safe, full-contact shape of a Provider —
// shared by the public profile endpoint below and by
// listing_handler.go's loadListingProvider (the service detail page's
// contact block). Deliberately omits UserID (Этап 11G brief: "не показывать
// внутренние user_id/provider_id" — the account's own internal id is never
// a client concern) and Status (draft/pending/rejected/suspended providers
// never reach either call site to begin with, so it'd always read
// "active" and add nothing). ID *is* included — it's the provider's own
// public routing handle (GET /api/providers/:id, and the provider_id a
// client passes to POST /api/provider-chat/start), not an internal detail.
type providerDetailOut struct {
	ID          uint   `json:"id"`
	DisplayName string `json:"display_name"`
	City        string `json:"city,omitempty"`
	Description string `json:"description,omitempty"`
	AvatarURL   string `json:"avatar_url,omitempty"`
	Phone       string `json:"phone,omitempty"`
	WhatsApp    string `json:"whatsapp,omitempty"`
	Telegram    string `json:"telegram,omitempty"`
}

func providerDetailFrom(p models.Provider) providerDetailOut {
	return providerDetailOut{
		ID:          p.ID,
		DisplayName: p.DisplayName,
		City:        p.City,
		Description: p.Description,
		AvatarURL:   p.AvatarURL,
		Phone:       p.Phone,
		WhatsApp:    p.WhatsApp,
		Telegram:    p.Telegram,
	}
}

// PublicProviderHandler exposes a provider's public profile — Этап 11G
// brief section 1. Deliberately its own handler/file (not a method on
// ProviderHandler) since ProviderHandler's own routes are all
// RequireAuth+"caller's own profile only"; this one is the opposite: no
// auth, and any provider's profile by id.
type PublicProviderHandler struct {
	DB *gorm.DB
}

func NewPublicProviderHandler(db *gorm.DB) *PublicProviderHandler {
	return &PublicProviderHandler{DB: db}
}

// Get — GET /api/providers/:id (public). Shows the provider's own contact
// block plus every currently-published listing they own, and how many —
// brief section 1's "список опубликованных услуг" + "количество услуг". A
// suspended/rejected/draft/deleted provider 404s exactly like a listing
// that doesn't exist, rather than exposing a half-populated profile.
func (h *PublicProviderHandler) Get(c *gin.Context) {
	id, ok := atoiParam(c, "id")
	if !ok {
		return
	}

	var provider models.Provider
	if err := h.DB.Where("status = ?", models.ProviderStatusActive).First(&provider, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "provider not found"})
		return
	}

	var managers []models.ListingManager
	h.DB.Where("user_id = ? AND role = ?", provider.UserID, models.ListingManagerRoleOwner).Find(&managers)
	listingIDs := make([]uint, len(managers))
	for i, m := range managers {
		listingIDs[i] = m.ListingID
	}

	var listings []models.Listing
	if len(listingIDs) > 0 {
		h.DB.Where("id IN ? AND is_active = ?", listingIDs, true).Order("rating desc").Find(&listings)
	}
	out := attachListingCounts(h.DB, listings)

	c.JSON(http.StatusOK, gin.H{
		"provider":      providerDetailFrom(provider),
		"listings":      out,
		"listing_count": len(out),
	})
}
