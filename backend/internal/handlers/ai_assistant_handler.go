package handlers

import (
	"context"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/aiassistant"
	"github.com/almukhanbetov/mereytoi/backend/internal/config"
)

// AIAssistantHandler is the AI event-planning assistant's HTTP surface —
// Этап 1: "минимальный работающий прототип на веб-сайте". Deliberately a
// separate handler from ManagerChatHandler and BookingHandler; nothing here
// reads or writes ManagerConversation/Booking, so a provider outage here
// can never take either of those down (brief section 4, scenario 5).
type AIAssistantHandler struct {
	Service *aiassistant.Service
	Cfg     config.Config
}

func NewAIAssistantHandler(db *gorm.DB, cfg config.Config) *AIAssistantHandler {
	var provider aiassistant.Provider
	if cfg.AIAssistantAnthropicAPIKey != "" {
		provider = aiassistant.NewAnthropicProvider(cfg.AIAssistantAnthropicAPIKey, cfg.AIAssistantModel)
	}
	// provider stays nil when no key is configured — Service.Ask returns
	// aiassistant.ErrNotConfigured for that case, handled below, rather
	// than the handler needing its own separate "configured?" branch.
	return &AIAssistantHandler{
		Service: aiassistant.NewService(provider, db),
		Cfg:     cfg,
	}
}

// maxAssistantMessages bounds one request's conversation history —
// independent of per-message length (Cfg.AIAssistantMaxMessageLen); keeps
// a very long back-and-forth from turning into an unbounded prompt (this
// stage keeps history client-side and resent whole, see the stage report).
const maxAssistantMessages = 20

type chatMessageInput struct {
	Role    string `json:"role" binding:"required,oneof=user assistant"`
	Content string `json:"content" binding:"required"`
}

type chatInput struct {
	Locale   string             `json:"locale"`
	Messages []chatMessageInput `json:"messages" binding:"required,min=1,dive"`
}

type chatListingOut struct {
	ID             uint    `json:"id"`
	Name           string  `json:"name"`
	City           string  `json:"city,omitempty"`
	Address        string  `json:"address,omitempty"`
	Capacity       uint    `json:"capacity,omitempty"`
	CapacityKnown  bool    `json:"capacity_known"`
	PriceFrom      uint    `json:"price_from,omitempty"`
	PriceUnit      string  `json:"price_unit,omitempty"`
	PriceKnown     bool    `json:"price_known"`
	EstimatedTotal uint    `json:"estimated_total,omitempty"`
	Rating         float32 `json:"rating"`
	URL            string  `json:"url"`
}

// Chat — POST /api/ai-assistant/chat. Public (no auth), same reasoning as
// the guest lead-capture form: a visitor deciding whether to book at all
// shouldn't need an account first. No caller identity/phone/cabinet data is
// ever available to reach the model here in the first place, so brief
// section 3's "не передавай... данные кабинета" holds by construction, not
// by a filter that could be forgotten.
func (h *AIAssistantHandler) Chat(c *gin.Context) {
	var in chatInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if len(in.Messages) > maxAssistantMessages {
		c.JSON(http.StatusBadRequest, gin.H{"error": "too many messages"})
		return
	}
	maxLen := h.Cfg.AIAssistantMaxMessageLen
	if maxLen <= 0 {
		maxLen = 1000
	}
	messages := make([]aiassistant.ChatMessage, 0, len(in.Messages))
	for _, m := range in.Messages {
		content := strings.TrimSpace(m.Content)
		if content == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "message content is required"})
			return
		}
		if len(content) > maxLen {
			c.JSON(http.StatusBadRequest, gin.H{"error": "message too long"})
			return
		}
		role := aiassistant.RoleUser
		if m.Role == "assistant" {
			role = aiassistant.RoleAssistant
		}
		messages = append(messages, aiassistant.ChatMessage{Role: role, Content: content})
	}

	timeoutSeconds := h.Cfg.AIAssistantTimeoutSeconds
	if timeoutSeconds <= 0 {
		timeoutSeconds = 20
	}
	ctx, cancel := context.WithTimeout(c.Request.Context(), time.Duration(timeoutSeconds)*time.Second)
	defer cancel()

	resp, err := h.Service.Ask(ctx, aiassistant.AskRequest{Locale: in.Locale, Messages: messages})
	if err != nil {
		if err == aiassistant.ErrNotConfigured {
			c.JSON(http.StatusServiceUnavailable, gin.H{
				"error":       "assistant_unavailable",
				"unavailable": true,
			})
			return
		}
		// A provider/network/timeout failure — never leaks the underlying
		// error text (could echo request internals); the rest of the site
		// (catalog, bookings, Manager Chat) runs on entirely separate
		// handlers and is unaffected by this failing.
		c.JSON(http.StatusBadGateway, gin.H{
			"error":       "assistant_error",
			"unavailable": true,
		})
		return
	}

	listings := make([]chatListingOut, 0, len(resp.Listings))
	for _, v := range resp.Listings {
		name := v.NameRu
		if in.Locale == "kz" && v.NameKz != "" {
			name = v.NameKz
		}
		listings = append(listings, chatListingOut{
			ID:             v.ID,
			Name:           name,
			City:           v.City,
			Address:        v.Address,
			Capacity:       v.Capacity,
			CapacityKnown:  v.CapacityKnown,
			PriceFrom:      v.PriceFrom,
			PriceUnit:      v.PriceUnit,
			PriceKnown:     v.PriceKnown,
			EstimatedTotal: v.EstimatedTotal,
			Rating:         v.Rating,
			URL:            v.URL,
		})
	}

	c.JSON(http.StatusOK, gin.H{"reply": resp.Reply, "listings": listings})
}
