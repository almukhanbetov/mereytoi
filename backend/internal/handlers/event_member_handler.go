package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

type EventMemberHandler struct {
	DB *gorm.DB
}

func NewEventMemberHandler(db *gorm.DB) *EventMemberHandler {
	return &EventMemberHandler{DB: db}
}

// Members — GET /api/events/:id/members (any member).
func (h *EventMemberHandler) Members(c *gin.Context) {
	var members []models.EventMember
	if err := h.DB.Preload("User").Where("event_id = ?", currentEventID(c)).Order("joined_at asc").Find(&members).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch members"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"members": members})
}

type changeRoleInput struct {
	Role string `json:"role" binding:"required,oneof=editor viewer"`
}

// ChangeRole — PUT /api/events/:id/members/:userId (owner only). Ownership
// transfer is deliberately out of scope — the owner role can only be
// granted at event creation, never reassigned through this endpoint, so
// there's no path to accidentally locking yourself out of your own event.
func (h *EventMemberHandler) ChangeRole(c *gin.Context) {
	targetUserID, ok := atoiParam(c, "userId")
	if !ok {
		return
	}

	var in changeRoleInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var member models.EventMember
	if err := h.DB.Where("event_id = ? AND user_id = ?", currentEventID(c), targetUserID).First(&member).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "member not found"})
		return
	}
	if member.Role == models.EventRoleOwner {
		c.JSON(http.StatusForbidden, gin.H{"error": "cannot change the owner's role"})
		return
	}

	member.Role = in.Role
	if err := h.DB.Save(&member).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update role"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"member": member})
}

// RemoveMember — DELETE /api/events/:id/members/:userId (owner only).
func (h *EventMemberHandler) RemoveMember(c *gin.Context) {
	targetUserID, ok := atoiParam(c, "userId")
	if !ok {
		return
	}

	var member models.EventMember
	if err := h.DB.Where("event_id = ? AND user_id = ?", currentEventID(c), targetUserID).First(&member).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "member not found"})
		return
	}
	if member.Role == models.EventRoleOwner {
		c.JSON(http.StatusForbidden, gin.H{"error": "the owner cannot be removed"})
		return
	}

	if err := h.DB.Delete(&member).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to remove member"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "member removed"})
}

type createInvitationInput struct {
	Role string `json:"role" binding:"required,oneof=editor viewer"`
}

// CreateInvitation — POST /api/events/:id/invitations (owner only). The
// token is a random 16-byte hex string (reusing generateRef from
// booking_handler.go — same "unguessable opaque reference" need). The link
// is reusable by design (revocable, not single-use) so one link can be
// dropped into a family WhatsApp group for several relatives to join with.
func (h *EventMemberHandler) CreateInvitation(c *gin.Context) {
	var in createInvitationInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	invitation := models.EventInvitation{
		EventID:     currentEventID(c),
		Token:       generateRef() + generateRef(), // 32 hex chars — plenty of entropy for a join link
		Role:        in.Role,
		CreatedByID: currentUserID(c),
	}
	if err := h.DB.Create(&invitation).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create invitation"})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"invitation": invitation})
}

// ListInvitations — GET /api/events/:id/invitations (owner only).
func (h *EventMemberHandler) ListInvitations(c *gin.Context) {
	var invitations []models.EventInvitation
	if err := h.DB.Where("event_id = ?", currentEventID(c)).Order("created_at desc").Find(&invitations).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch invitations"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"invitations": invitations})
}

// RevokeInvitation — DELETE /api/events/:id/invitations/:invId (owner only).
func (h *EventMemberHandler) RevokeInvitation(c *gin.Context) {
	invID, ok := atoiParam(c, "invId")
	if !ok {
		return
	}

	var invitation models.EventInvitation
	if err := h.DB.Where("id = ? AND event_id = ?", invID, currentEventID(c)).First(&invitation).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "invitation not found"})
		return
	}
	invitation.Revoked = true
	if err := h.DB.Save(&invitation).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to revoke invitation"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"invitation": invitation})
}

// PreviewInvitation — GET /api/invitations/:token. Public (no auth) so a
// freshly-shared link can render "X invites you to..." before asking
// anyone to log in. Reveals only what's needed for that preview — never
// the event's shortlist/budget/discussion.
func (h *EventMemberHandler) PreviewInvitation(c *gin.Context) {
	token := c.Param("token")

	var invitation models.EventInvitation
	if err := h.DB.Where("token = ?", token).First(&invitation).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "invitation not found"})
		return
	}
	if invitation.Revoked {
		c.JSON(http.StatusGone, gin.H{"error": "invitation revoked"})
		return
	}

	var event models.Event
	if err := h.DB.First(&event, invitation.EventID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "event not found"})
		return
	}
	var owner models.User
	h.DB.First(&owner, event.OwnerID)

	c.JSON(http.StatusOK, gin.H{
		"event":        gin.H{"title": event.Title, "type": event.Type, "event_date": event.EventDate, "city": event.City},
		"inviter_name": owner.Name,
		"role":         invitation.Role,
	})
}

// AcceptInvitation — POST /api/invitations/:token/accept (auth required).
// Idempotent: accepting a link you're already a member from just confirms
// membership rather than erroring or silently changing your existing role.
func (h *EventMemberHandler) AcceptInvitation(c *gin.Context) {
	token := c.Param("token")
	userID := currentUserID(c)

	var invitation models.EventInvitation
	if err := h.DB.Where("token = ?", token).First(&invitation).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "invitation not found"})
		return
	}
	if invitation.Revoked {
		c.JSON(http.StatusGone, gin.H{"error": "invitation revoked"})
		return
	}

	var existing models.EventMember
	if err := h.DB.Where("event_id = ? AND user_id = ?", invitation.EventID, userID).First(&existing).Error; err == nil {
		c.JSON(http.StatusOK, gin.H{"event_id": invitation.EventID, "role": existing.Role, "already_member": true})
		return
	}

	member := models.EventMember{EventID: invitation.EventID, UserID: userID, Role: invitation.Role, JoinedAt: time.Now()}
	if err := h.DB.Create(&member).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to join event"})
		return
	}

	now := time.Now()
	invitation.UsedByID = &userID
	invitation.UsedAt = &now
	h.DB.Save(&invitation)

	var user models.User
	h.DB.First(&user, userID)
	logActivity(h.DB, invitation.EventID, userID, "member.joined", map[string]any{"name": user.Name, "role": member.Role})

	c.JSON(http.StatusOK, gin.H{"event_id": invitation.EventID, "role": member.Role, "already_member": false})
}
