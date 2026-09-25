package handlers

import (
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// ProviderChatHandler — Этап 11G. Direct chat between a customer and a
// marketplace provider, deliberately its own model/handler rather than
// reused ManagerChat (see models/provider_chat.go's own doc comment: this
// is a different channel entirely, "Спросить менеджера" vs "Написать
// услугодателю" are two separate buttons on the same service page).
type ProviderChatHandler struct {
	DB *gorm.DB
}

func NewProviderChatHandler(db *gorm.DB) *ProviderChatHandler {
	return &ProviderChatHandler{DB: db}
}

// providerConversationOut/providerChatParty — the public-safe response
// shape for a conversation: embeds the raw ProviderConversation (id/
// customer_user_id/provider_id/listing_id/timestamps — customer_user_id
// and provider_id are the caller's own routing handles, not a leak, same
// reasoning as providerDetailOut.ID) but overrides Provider/Customer with a
// display-only shape (no user_id/email/phone) — same "outer field shadows
// the promoted field" idiom myListingOut/conversationSummary already use
// elsewhere in this package.
type providerConversationOut struct {
	models.ProviderConversation
	Provider *providerChatParty `json:"provider,omitempty"`
	Customer *providerChatParty `json:"customer,omitempty"`
}

type providerChatParty struct {
	DisplayName string `json:"display_name"`
	AvatarURL   string `json:"avatar_url,omitempty"`
}

func buildConversationOut(conv models.ProviderConversation) providerConversationOut {
	out := providerConversationOut{ProviderConversation: conv}
	if conv.Provider != nil {
		out.Provider = &providerChatParty{DisplayName: conv.Provider.DisplayName, AvatarURL: conv.Provider.AvatarURL}
	}
	if conv.Customer != nil {
		out.Customer = &providerChatParty{DisplayName: conv.Customer.Name}
	}
	out.ProviderConversation.Provider = nil
	out.ProviderConversation.Customer = nil
	return out
}

// conversationRole resolves which side (if any) viewerUserID is on. A
// stranger — neither the customer nor the provider account owning
// conv.ProviderID — gets ("", false); every handler below turns that into
// a 404, never a 403, so a stranger can't even confirm the conversation
// exists (same convention manager_chat_handler.go already uses).
func conversationRole(conv models.ProviderConversation, viewerUserID uint) (role string, ok bool) {
	if conv.CustomerUserID == viewerUserID {
		return "customer", true
	}
	if conv.Provider != nil && conv.Provider.UserID == viewerUserID {
		return "provider", true
	}
	return "", false
}

type startProviderConversationInput struct {
	ProviderID uint   `json:"provider_id" binding:"required"`
	ListingID  *uint  `json:"listing_id"`
	Message    string `json:"message"`
}

// Start — POST /api/provider-chat/start (auth only). Finds-or-creates the
// one conversation matching (this customer, this provider, this
// listing_id) exactly and, if a non-empty message was given, posts it —
// same "peek without creating" shape as manager_chat_handler.Start, so the
// service page's "Написать услугодателю" button can call this every time
// it opens without spawning a new thread per open.
func (h *ProviderChatHandler) Start(c *gin.Context) {
	userID := currentUserID(c)

	var in startProviderConversationInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	body := strings.TrimSpace(in.Message)

	// provider_id is never trusted blindly: it must be a real, active
	// provider profile, not a client-supplied number that happens to
	// collide with someone's Provider.ID.
	var provider models.Provider
	if err := h.DB.Where("status = ?", models.ProviderStatusActive).First(&provider, in.ProviderID).Error; err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "provider not found"})
		return
	}
	if provider.UserID == userID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "cannot message your own provider profile"})
		return
	}

	// listing_id, like manager chat's event_id, is never trusted blindly
	// either: it must actually belong to the provider being contacted, or a
	// crafted request could attribute an unrelated listing to this
	// conversation (Этап 11G brief section 8: "нельзя подменить
	// provider_id/listing_id").
	if in.ListingID != nil {
		var owner models.ListingManager
		err := h.DB.Where("listing_id = ? AND role = ?", *in.ListingID, models.ListingManagerRoleOwner).First(&owner).Error
		if err != nil || owner.UserID != provider.UserID {
			c.JSON(http.StatusBadRequest, gin.H{"error": "listing does not belong to this provider"})
			return
		}
	}

	query := h.DB.Where("customer_user_id = ? AND provider_id = ?", userID, in.ProviderID)
	if in.ListingID != nil {
		query = query.Where("listing_id = ?", *in.ListingID)
	} else {
		query = query.Where("listing_id IS NULL")
	}

	var conv models.ProviderConversation
	err := query.First(&conv).Error
	if err == gorm.ErrRecordNotFound {
		if body == "" {
			c.JSON(http.StatusOK, gin.H{"conversation": nil, "messages": []models.ProviderMessage{}})
			return
		}
		conv = models.ProviderConversation{ProviderID: in.ProviderID, CustomerUserID: userID, ListingID: in.ListingID}
		if err := h.DB.Create(&conv).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to start conversation"})
			return
		}
	} else if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load conversation"})
		return
	}

	if body == "" {
		h.respondDetail(c, conv.ID, userID)
		return
	}

	msg := models.ProviderMessage{ConversationID: conv.ID, SenderUserID: userID, Body: body}
	if err := h.DB.Create(&msg).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to send message"})
		return
	}
	h.DB.Model(&conv).Update("updated_at", time.Now())

	createNotification(h.DB, provider.UserID, userID, 0, models.NotifProviderMessageReceived, "provider_conversation", conv.ID, map[string]any{"body": body})

	h.respondDetail(c, conv.ID, userID)
}

// List — GET /api/provider-chat (auth only). Every conversation the caller
// is a participant of, on either side: as a customer (customer_user_id
// match) and — if they have a provider profile — as that provider
// (provider_id match). Brief section 4: "Provider видит только свои
// conversations. Customer видит только свои conversations."
func (h *ProviderChatHandler) List(c *gin.Context) {
	userID := currentUserID(c)

	var providerIDs []uint
	h.DB.Model(&models.Provider{}).Where("user_id = ?", userID).Pluck("id", &providerIDs)

	q := h.DB.Preload("Provider").Preload("Customer").Preload("Listing")
	if len(providerIDs) > 0 {
		q = q.Where("customer_user_id = ? OR provider_id IN ?", userID, providerIDs)
	} else {
		q = q.Where("customer_user_id = ?", userID)
	}

	var convs []models.ProviderConversation
	if err := q.Order("updated_at desc").Find(&convs).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch conversations"})
		return
	}

	type summary struct {
		providerConversationOut
		LastMessage *models.ProviderMessage `json:"last_message,omitempty"`
		UnreadCount int64                   `json:"unread_count"`
	}

	out := make([]summary, 0, len(convs))
	for _, conv := range convs {
		role, _ := conversationRole(conv, userID)
		otherUserID := conv.CustomerUserID
		if role == "customer" && conv.Provider != nil {
			otherUserID = conv.Provider.UserID
		}

		var last models.ProviderMessage
		var lastPtr *models.ProviderMessage
		if h.DB.Where("conversation_id = ?", conv.ID).Order("created_at desc").First(&last).Error == nil {
			lastPtr = &last
		}
		var unread int64
		h.DB.Model(&models.ProviderMessage{}).
			Where("conversation_id = ? AND sender_user_id = ? AND read_at IS NULL", conv.ID, otherUserID).
			Count(&unread)

		out = append(out, summary{providerConversationOut: buildConversationOut(conv), LastMessage: lastPtr, UnreadCount: unread})
	}
	c.JSON(http.StatusOK, gin.H{"conversations": out})
}

// Get — GET /api/provider-chat/:id (auth only, participant only).
func (h *ProviderChatHandler) Get(c *gin.Context) {
	id, ok := atoiParam(c, "id")
	if !ok {
		return
	}
	h.respondDetail(c, uint(id), currentUserID(c))
}

type addProviderMessageInput struct {
	Body string `json:"body" binding:"required"`
}

// AddMessage — POST /api/provider-chat/:id/messages (auth only, participant
// only). Which side sent it is resolved from who's actually calling
// (conversationRole), never from client input.
func (h *ProviderChatHandler) AddMessage(c *gin.Context) {
	id, ok := atoiParam(c, "id")
	if !ok {
		return
	}
	var in addProviderMessageInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	body := strings.TrimSpace(in.Body)
	if body == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "message is required"})
		return
	}

	var conv models.ProviderConversation
	if err := h.DB.Preload("Provider").First(&conv, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "conversation not found"})
		return
	}

	userID := currentUserID(c)
	role, ok := conversationRole(conv, userID)
	if !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "conversation not found"})
		return
	}

	msg := models.ProviderMessage{ConversationID: conv.ID, SenderUserID: userID, Body: body}
	if err := h.DB.Create(&msg).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to send message"})
		return
	}
	h.DB.Model(&conv).Update("updated_at", time.Now())

	recipientUserID := conv.CustomerUserID
	if role == "customer" && conv.Provider != nil {
		recipientUserID = conv.Provider.UserID
	}
	createNotification(h.DB, recipientUserID, userID, 0, models.NotifProviderMessageReceived, "provider_conversation", conv.ID, map[string]any{"body": body})

	h.respondDetail(c, conv.ID, userID)
}

// respondDetail loads one conversation plus its full message list, and — as
// a side effect — marks whichever side's messages the *viewer* hasn't seen
// yet as read (same convention manager_chat_handler.respondDetail uses).
func (h *ProviderChatHandler) respondDetail(c *gin.Context, id uint, viewerUserID uint) {
	var conv models.ProviderConversation
	q := h.DB.Preload("Provider").Preload("Customer").Preload("Listing").Preload("Listing.Category")
	if err := q.First(&conv, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "conversation not found"})
		return
	}

	role, ok := conversationRole(conv, viewerUserID)
	if !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "conversation not found"})
		return
	}

	otherUserID := conv.CustomerUserID
	if role == "customer" && conv.Provider != nil {
		otherUserID = conv.Provider.UserID
	}
	if otherUserID != 0 {
		h.DB.Model(&models.ProviderMessage{}).
			Where("conversation_id = ? AND sender_user_id = ? AND read_at IS NULL", conv.ID, otherUserID).
			Update("read_at", time.Now())
	}

	var messages []models.ProviderMessage
	h.DB.Where("conversation_id = ?", conv.ID).Order("created_at asc").Find(&messages)

	c.JSON(http.StatusOK, gin.H{"conversation": buildConversationOut(conv), "messages": messages})
}
