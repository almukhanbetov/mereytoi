package handlers

import (
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/middleware"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

type ManagerChatHandler struct {
	DB *gorm.DB
}

func NewManagerChatHandler(db *gorm.DB) *ManagerChatHandler {
	return &ManagerChatHandler{DB: db}
}

func isAdminCtx(c *gin.Context) bool {
	role, _ := c.Get(middleware.ContextUserRoleKey)
	return role == "admin"
}

type startConversationInput struct {
	EventID   *uint  `json:"event_id"`
	ListingID *uint  `json:"listing_id"`
	Message   string `json:"message"`
}

// Start — POST /api/manager-chat/start (auth only). Finds-or-creates the
// one open conversation matching (this user, event_id, listing_id) exactly
// and, if a non-empty message was given, posts it into that conversation —
// the widget calls this every time it's opened with a context (brief
// sections 17/20/21), not just once, so reopening the same service's chat
// continues one thread instead of spawning a new row per open.
//
// Message is deliberately optional: opening the chat should show the
// service/event context (and any existing history) immediately, before
// the visitor has typed anything (brief section 17's whole point) — an
// empty message just "peeks" at whatever conversation already exists for
// this context without creating one, so a fresh context never has to
// force a throwaway first message just to render the context block.
func (h *ManagerChatHandler) Start(c *gin.Context) {
	userID := currentUserID(c)

	var in startConversationInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	body := strings.TrimSpace(in.Message)

	// Context refs are never trusted blindly — event_id in particular must
	// actually be an event this caller belongs to, or a crafted request
	// could otherwise make an unrelated event show up attributed to them
	// in the admin's inbox.
	if in.EventID != nil {
		var member models.EventMember
		if err := h.DB.Where("event_id = ? AND user_id = ?", *in.EventID, userID).First(&member).Error; err != nil {
			c.JSON(http.StatusForbidden, gin.H{"error": "not a member of this event"})
			return
		}
	}
	if in.ListingID != nil {
		if h.DB.First(&models.Listing{}, *in.ListingID).Error != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "listing not found"})
			return
		}
	}

	query := h.DB.Where("user_id = ? AND status = ?", userID, models.ConversationOpen)
	if in.EventID != nil {
		query = query.Where("event_id = ?", *in.EventID)
	} else {
		query = query.Where("event_id IS NULL")
	}
	if in.ListingID != nil {
		query = query.Where("listing_id = ?", *in.ListingID)
	} else {
		query = query.Where("listing_id IS NULL")
	}

	var conv models.ManagerConversation
	err := query.First(&conv).Error
	if err == gorm.ErrRecordNotFound {
		if body == "" {
			// Nothing to create yet and nothing to show — a bare "peek"
			// with no history and no message. The frontend renders its
			// own empty/suggestion-chips state for this.
			c.JSON(http.StatusOK, gin.H{"conversation": nil, "messages": []models.ManagerMessage{}})
			return
		}
		conv = models.ManagerConversation{UserID: userID, EventID: in.EventID, ListingID: in.ListingID, Status: models.ConversationOpen}
		if err := h.DB.Create(&conv).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to start conversation"})
			return
		}
	} else if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load conversation"})
		return
	}

	if body == "" {
		h.respondDetail(c, conv.ID, userID, false)
		return
	}

	msg := models.ManagerMessage{ConversationID: conv.ID, SenderType: models.SenderUser, SenderUserID: &userID, Body: body}
	if err := h.DB.Create(&msg).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to send message"})
		return
	}
	h.DB.Model(&conv).Update("updated_at", time.Now())

	h.respondDetail(c, conv.ID, userID, false)
}

// Get — GET /api/manager-chat/:id (customer, own conversation only) and
// GET /api/admin/manager-chat/:id (admin, any conversation) — the same
// method mounted under both route groups; the split is entirely in
// respondDetail's ownership check.
func (h *ManagerChatHandler) Get(c *gin.Context) {
	id, ok := atoiParam(c, "id")
	if !ok {
		return
	}
	h.respondDetail(c, uint(id), currentUserID(c), isAdminCtx(c))
}

type addMessageInput struct {
	Body string `json:"body" binding:"required"`
}

// AddMessage — POST /api/manager-chat/:id/messages and POST
// /api/admin/manager-chat/:id/messages — again one method, sender_type
// resolved from who's actually calling rather than from a client-supplied
// field, so a customer can never post as "manager".
func (h *ManagerChatHandler) AddMessage(c *gin.Context) {
	id, ok := atoiParam(c, "id")
	if !ok {
		return
	}
	var in addMessageInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	body := strings.TrimSpace(in.Body)
	if body == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "message is required"})
		return
	}

	var conv models.ManagerConversation
	if err := h.DB.First(&conv, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "conversation not found"})
		return
	}

	userID := currentUserID(c)
	asAdmin := isAdminCtx(c)
	if !asAdmin && conv.UserID != userID {
		c.JSON(http.StatusNotFound, gin.H{"error": "conversation not found"})
		return
	}

	senderType := models.SenderUser
	if asAdmin {
		senderType = models.SenderManager
	}
	msg := models.ManagerMessage{ConversationID: conv.ID, SenderType: senderType, SenderUserID: &userID, Body: body}
	if err := h.DB.Create(&msg).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to send message"})
		return
	}
	h.DB.Model(&conv).Update("updated_at", time.Now())

	h.respondDetail(c, conv.ID, userID, asAdmin)
}

// respondDetail loads one conversation (with its event/service context)
// plus its full message list, and — as a side effect — marks whichever
// side's messages the *viewer* hasn't seen yet as read: an admin opening
// the thread marks the customer's messages read, the customer opening it
// marks the manager's replies read. This is the only read-tracking this
// stage needs, so there's no separate mark-read endpoint to call.
func (h *ManagerChatHandler) respondDetail(c *gin.Context, id uint, viewerUserID uint, asAdmin bool) {
	var conv models.ManagerConversation
	q := h.DB.Preload("User").Preload("Event").Preload("Listing").Preload("Listing.Category")
	if err := q.First(&conv, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "conversation not found"})
		return
	}
	if !asAdmin && conv.UserID != viewerUserID {
		c.JSON(http.StatusNotFound, gin.H{"error": "conversation not found"})
		return
	}

	otherSide := models.SenderManager
	if asAdmin {
		otherSide = models.SenderUser
	}
	h.DB.Model(&models.ManagerMessage{}).
		Where("conversation_id = ? AND sender_type = ? AND read_at IS NULL", conv.ID, otherSide).
		Update("read_at", time.Now())

	var messages []models.ManagerMessage
	h.DB.Where("conversation_id = ?", conv.ID).Order("created_at asc").Find(&messages)

	c.JSON(http.StatusOK, gin.H{"conversation": conv, "messages": messages})
}

// conversationSummary is what the admin dialog list (brief section 24)
// actually needs per row — the conversation itself plus a cheap preview
// that doesn't require the client to fetch every full thread.
type conversationSummary struct {
	models.ManagerConversation
	LastMessage *models.ManagerMessage `json:"last_message,omitempty"`
	UnreadCount int64                  `json:"unread_count"`
}

// AdminList — GET /api/admin/manager-chat?status=open. Deliberately not a
// CRM: name, event, service, last message, unread, time, status — exactly
// the brief's own list of what a manager needs, nothing more.
func (h *ManagerChatHandler) AdminList(c *gin.Context) {
	q := h.DB.Preload("User").Preload("Event").Preload("Listing")
	if status := c.Query("status"); status != "" && status != "all" {
		q = q.Where("status = ?", status)
	}

	var convs []models.ManagerConversation
	if err := q.Order("updated_at desc").Find(&convs).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch conversations"})
		return
	}

	out := make([]conversationSummary, 0, len(convs))
	for _, conv := range convs {
		var last models.ManagerMessage
		var lastPtr *models.ManagerMessage
		if h.DB.Where("conversation_id = ?", conv.ID).Order("created_at desc").First(&last).Error == nil {
			lastPtr = &last
		}
		var unread int64
		h.DB.Model(&models.ManagerMessage{}).
			Where("conversation_id = ? AND sender_type = ? AND read_at IS NULL", conv.ID, models.SenderUser).
			Count(&unread)
		out = append(out, conversationSummary{ManagerConversation: conv, LastMessage: lastPtr, UnreadCount: unread})
	}
	c.JSON(http.StatusOK, gin.H{"conversations": out})
}

type updateConversationStatusInput struct {
	Status string `json:"status" binding:"required,oneof=open closed"`
}

// AdminUpdateStatus — POST /api/admin/manager-chat/:id/status. The one
// manual lifecycle action this stage needs (brief's Conversation.status) —
// nothing auto-closes a thread.
func (h *ManagerChatHandler) AdminUpdateStatus(c *gin.Context) {
	id, ok := atoiParam(c, "id")
	if !ok {
		return
	}
	var in updateConversationStatusInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if err := h.DB.Model(&models.ManagerConversation{}).Where("id = ?", id).Update("status", in.Status).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update status"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "status updated"})
}
