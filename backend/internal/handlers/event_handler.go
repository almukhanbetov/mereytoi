package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/middleware"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

type EventHandler struct {
	DB *gorm.DB
}

func NewEventHandler(db *gorm.DB) *EventHandler {
	return &EventHandler{DB: db}
}

// logActivity is shared by every event-scoped handler that needs to append
// to the workspace's activity feed. Payload is a small denormalized
// snapshot (e.g. a listing's name/price at the time of the action) so the
// feed still reads correctly even after the underlying row changes.
func logActivity(db *gorm.DB, eventID uint, actorID uint, verb string, payload map[string]any) {
	data, _ := json.Marshal(payload)
	actor := actorID
	db.Create(&models.EventActivity{EventID: eventID, ActorID: &actor, Verb: verb, Payload: string(data)})
}

func currentUserID(c *gin.Context) uint {
	v, _ := c.Get(middleware.ContextUserIDKey)
	id, _ := v.(uint)
	return id
}

func currentEventID(c *gin.Context) uint {
	v, _ := c.Get(middleware.ContextEventIDKey)
	id, _ := v.(uint)
	return id
}

func currentEventRole(c *gin.Context) string {
	v, _ := c.Get(middleware.ContextEventRoleKey)
	role, _ := v.(string)
	return role
}

type eventInput struct {
	Title       string  `json:"title" binding:"required"`
	Type        string  `json:"type"`
	EventDate   *string `json:"event_date"` // "2027-06-20" — parsed below
	City        string  `json:"city"`
	Guests      uint    `json:"guests"`
	BudgetTotal uint    `json:"budget_total"`
	Comment     string  `json:"comment"`
}

func parseEventDate(raw *string) *time.Time {
	if raw == nil || *raw == "" {
		return nil
	}
	t, err := time.Parse("2006-01-02", *raw)
	if err != nil {
		return nil
	}
	return &t
}

var allowedEventTypes = map[string]bool{
	"wedding": true, "toi": true, "anniversary": true, "corporate": true, "other": true,
}

func normalizeEventType(t string) string {
	if allowedEventTypes[t] {
		return t
	}
	return "other"
}

// Create — POST /api/events. The creator becomes the event's owner both via
// Event.OwnerID and as an EventMember row (role=owner), so every later
// membership/role query is a single table regardless of who created it.
func (h *EventHandler) Create(c *gin.Context) {
	var in eventInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	userID := currentUserID(c)
	event := models.Event{
		OwnerID:     userID,
		Title:       in.Title,
		Type:        normalizeEventType(in.Type),
		EventDate:   parseEventDate(in.EventDate),
		City:        in.City,
		Guests:      in.Guests,
		BudgetTotal: in.BudgetTotal,
		Comment:     in.Comment,
		Status:      "planning",
	}

	err := h.DB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(&event).Error; err != nil {
			return err
		}
		member := models.EventMember{EventID: event.ID, UserID: userID, Role: models.EventRoleOwner, JoinedAt: time.Now()}
		return tx.Create(&member).Error
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create event"})
		return
	}

	logActivity(h.DB, event.ID, userID, "event.created", map[string]any{"title": event.Title})

	c.JSON(http.StatusCreated, gin.H{"event": event})
}

// List — GET /api/events. Every event the caller belongs to, in any role,
// newest first. Never returns another user's events, membership or not.
func (h *EventHandler) List(c *gin.Context) {
	userID := currentUserID(c)

	var memberships []models.EventMember
	if err := h.DB.Where("user_id = ?", userID).Find(&memberships).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch events"})
		return
	}
	if len(memberships) == 0 {
		c.JSON(http.StatusOK, gin.H{"events": []models.Event{}})
		return
	}

	roleByEvent := make(map[uint]string, len(memberships))
	eventIDs := make([]uint, 0, len(memberships))
	for _, m := range memberships {
		roleByEvent[m.EventID] = m.Role
		eventIDs = append(eventIDs, m.EventID)
	}

	var events []models.Event
	if err := h.DB.Where("id IN ?", eventIDs).Order("created_at desc").Find(&events).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch events"})
		return
	}

	type eventWithRole struct {
		models.Event
		MyRole string `json:"my_role"`
	}
	out := make([]eventWithRole, 0, len(events))
	for _, e := range events {
		out = append(out, eventWithRole{Event: e, MyRole: roleByEvent[e.ID]})
	}

	c.JSON(http.StatusOK, gin.H{"events": out})
}

// Get — GET /api/events/:id. Membership already verified by
// middleware.RequireEventRole; this just loads the row.
func (h *EventHandler) Get(c *gin.Context) {
	var event models.Event
	if err := h.DB.First(&event, currentEventID(c)).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "event not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"event": event, "my_role": currentEventRole(c)})
}

// Update — PUT /api/events/:id (editor+).
func (h *EventHandler) Update(c *gin.Context) {
	var event models.Event
	if err := h.DB.First(&event, currentEventID(c)).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "event not found"})
		return
	}

	var in eventInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	budgetChanged := event.BudgetTotal != in.BudgetTotal

	event.Title = in.Title
	event.Type = normalizeEventType(in.Type)
	event.EventDate = parseEventDate(in.EventDate)
	event.City = in.City
	event.Guests = in.Guests
	event.BudgetTotal = in.BudgetTotal
	event.Comment = in.Comment

	if err := h.DB.Save(&event).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update event"})
		return
	}

	if budgetChanged {
		actorID := currentUserID(c)
		logActivity(h.DB, event.ID, actorID, "budget.updated", map[string]any{"budget_total": event.BudgetTotal})
		// Viewers are explicitly excluded — the brief scopes this to
		// "organizer + participants", the people actually deciding.
		recipients := memberUserIDs(h.DB, event.ID, models.EventRoleEditor)
		notifyMany(h.DB, recipients, actorID, event.ID, models.NotifBudgetUpdated, "event", event.ID, map[string]any{"budget_total": event.BudgetTotal})
	}

	c.JSON(http.StatusOK, gin.H{"event": event})
}

// Summary — GET /api/events/:id/summary. The numbers the dashboard header
// needs: spend is always computed live from selected candidates (never
// stored), so it can't drift from the shortlist.
func (h *EventHandler) Summary(c *gin.Context) {
	eventID := currentEventID(c)

	var event models.Event
	if err := h.DB.First(&event, eventID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "event not found"})
		return
	}

	var selected []models.EventCandidate
	h.DB.Preload("Listing").Where("event_id = ? AND status = ?", eventID, models.CandidateSelected).Find(&selected)

	var spent uint
	categoriesCovered := map[uint]bool{}
	for _, cand := range selected {
		if cand.Listing != nil {
			spent += cand.Listing.Price
			categoriesCovered[cand.Listing.CategoryID] = true
		}
	}

	var categoriesTotal int64
	h.DB.Model(&models.Category{}).Count(&categoriesTotal)

	var membersCount int64
	h.DB.Model(&models.EventMember{}).Where("event_id = ?", eventID).Count(&membersCount)

	var shortlistedCount int64
	h.DB.Model(&models.EventCandidate{}).Where("event_id = ? AND status = ?", eventID, models.CandidateShortlisted).Count(&shortlistedCount)

	c.JSON(http.StatusOK, gin.H{
		"budget_total":       event.BudgetTotal,
		"spent":              spent,
		"remaining":          int(event.BudgetTotal) - int(spent),
		"categories_total":   categoriesTotal,
		"categories_covered": len(categoriesCovered),
		"members_count":      membersCount,
		"selected_count":     len(selected),
		"shortlisted_count":  shortlistedCount,
	})
}

// Delete — DELETE /api/events/:id (owner only, checked in the route setup
// via the min-role middleware at EventRoleOwner). Cascades every child row
// manually since GORM's soft-delete/AutoMigrate setup here has no FK
// ON DELETE CASCADE configured.
func (h *EventHandler) Delete(c *gin.Context) {
	eventID := currentEventID(c)

	err := h.DB.Transaction(func(tx *gorm.DB) error {
		var candidateIDs []uint
		tx.Model(&models.EventCandidate{}).Where("event_id = ?", eventID).Pluck("id", &candidateIDs)
		if len(candidateIDs) > 0 {
			tx.Where("candidate_id IN ?", candidateIDs).Delete(&models.EventVote{})
		}
		tx.Where("event_id = ?", eventID).Delete(&models.EventComment{})
		tx.Where("event_id = ?", eventID).Delete(&models.EventCandidate{})
		tx.Where("event_id = ?", eventID).Delete(&models.EventTask{})
		tx.Where("event_id = ?", eventID).Delete(&models.EventActivity{})
		tx.Where("event_id = ?", eventID).Delete(&models.EventInvitation{})
		tx.Where("event_id = ?", eventID).Delete(&models.EventMember{})
		return tx.Delete(&models.Event{}, eventID).Error
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete event"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "event deleted"})
}

func atoiParam(c *gin.Context, name string) (int, bool) {
	v, err := strconv.Atoi(c.Param(name))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid " + name})
		return 0, false
	}
	return v, true
}
