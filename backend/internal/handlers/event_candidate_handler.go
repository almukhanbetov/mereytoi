package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

type EventCandidateHandler struct {
	DB *gorm.DB
}

func NewEventCandidateHandler(db *gorm.DB) *EventCandidateHandler {
	return &EventCandidateHandler{DB: db}
}

// candidateOut is what the shortlist screen actually needs per row — the
// candidate + listing, vote tallies, the caller's own vote, and how many
// comments are waiting in its thread — assembled in one response so the
// frontend isn't firing N+1 requests per card.
type candidateOut struct {
	models.EventCandidate
	Votes        map[string]int `json:"votes"`
	MyVote       string         `json:"my_vote,omitempty"`
	CommentCount int64          `json:"comment_count"`
}

type addCandidateInput struct {
	ListingID uint `json:"listing_id" binding:"required"`
	// HallID/MenuID — restaurant/venue variant identity (see
	// models/event.go's own doc comment on EventCandidate). Both optional
	// and independent of each other; every other category simply never
	// sends them.
	HallID *uint `json:"hall_id"`
	MenuID *uint `json:"menu_id"`
	// Guests — the guest count this candidate was shortlisted for (brief
	// section 3). Trusted as supplied, same as the calculator's own
	// guestCount that produced it — not re-derived from anything server-side.
	Guests *uint `json:"guests"`
	// EstimatedTotal — the calculator's own final total (menu×guests +
	// selected extras), same trust model as Guests above and as
	// BookingItem's own EstimatedTotal already has (see booking_handler.go)
	// — this endpoint has never re-verified a candidate's price against
	// the live Menu/extras, so this follows that same established pattern
	// rather than introducing server-side recomputation nothing else here
	// does either.
	EstimatedTotal *uint `json:"estimated_total"`
}

// AddCandidate — POST /api/events/:id/candidates (editor+). Idempotent on
// the full variant identity — (listing_id, hall_id, menu_id), NULLs
// included — not on listing_id alone: two different hall/menu
// combinations of the same restaurant are two different candidates a
// member can shortlist and compare side by side; only re-adding the exact
// same combination returns the existing row instead of duplicating it.
func (h *EventCandidateHandler) AddCandidate(c *gin.Context) {
	var in addCandidateInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var listing models.Listing
	if err := h.DB.First(&listing, in.ListingID).Error; err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "listing not found"})
		return
	}

	var hall *models.ListingHall
	if in.HallID != nil {
		var h2 models.ListingHall
		if err := h.DB.Where("id = ? AND listing_id = ?", *in.HallID, in.ListingID).First(&h2).Error; err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "hall not found for this listing"})
			return
		}
		hall = &h2
	}

	var menu *models.ListingMenu
	if in.MenuID != nil {
		var m2 models.ListingMenu
		if err := h.DB.Where("id = ? AND listing_id = ?", *in.MenuID, in.ListingID).First(&m2).Error; err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "menu not found for this listing"})
			return
		}
		// A hall-scoped menu must match the explicitly chosen hall, if
		// any — never silently accepted for a mismatched/no hall (this is
		// the one bit of cross-field validation worth doing here; nothing
		// downstream re-checks it once the candidate exists).
		if m2.HallID != nil && (in.HallID == nil || *m2.HallID != *in.HallID) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "menu does not belong to the selected hall"})
			return
		}
		menu = &m2
	}

	eventID := currentEventID(c)

	// NULL-safe variant-identity lookup — `hall_id = ?`/`menu_id = ?` would
	// never match a NULL column in Postgres, so the nil/non-nil cases are
	// spelled out explicitly rather than relying on `= ?` alone.
	existQuery := h.DB.Where("event_id = ? AND listing_id = ?", eventID, in.ListingID)
	if in.HallID != nil {
		existQuery = existQuery.Where("hall_id = ?", *in.HallID)
	} else {
		existQuery = existQuery.Where("hall_id IS NULL")
	}
	if in.MenuID != nil {
		existQuery = existQuery.Where("menu_id = ?", *in.MenuID)
	} else {
		existQuery = existQuery.Where("menu_id IS NULL")
	}
	var existing models.EventCandidate
	if err := existQuery.First(&existing).Error; err == nil {
		c.JSON(http.StatusOK, gin.H{"candidate": existing, "already_added": true})
		return
	}

	candidate := models.EventCandidate{
		EventID:        eventID,
		ListingID:      in.ListingID,
		HallID:         in.HallID,
		MenuID:         in.MenuID,
		Guests:         in.Guests,
		EstimatedTotal: in.EstimatedTotal,
		Status:         models.CandidateShortlisted,
		AddedByID:      currentUserID(c),
	}
	// Snapshot at add-time — a defensive fallback only; List() below
	// Preloads the live Hall/Menu rows as the actual display source while
	// the candidate is still pre-booking (brief section 5).
	if hall != nil {
		candidate.HallName = hall.NameRu
	}
	if menu != nil {
		candidate.MenuName = menu.NameRu
		candidate.MenuPricePerGuest = menu.PricePerGuest
	}
	if err := h.DB.Create(&candidate).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to add candidate"})
		return
	}
	candidate.Listing = &listing
	candidate.Hall = hall
	candidate.Menu = menu

	displayName := listing.NameRu
	if hall != nil {
		displayName += " · " + hall.NameRu
	}
	if menu != nil {
		displayName += " · " + menu.NameRu
	}

	actorID := currentUserID(c)
	logActivity(h.DB, eventID, actorID, "candidate.added", map[string]any{"name": displayName, "price": listing.Price})
	notifyMany(h.DB, memberUserIDs(h.DB, eventID, models.EventRoleViewer), actorID, eventID, models.NotifCandidateAdded, "candidate", candidate.ID,
		map[string]any{"name": displayName, "price": listing.Price})

	c.JSON(http.StatusCreated, gin.H{"candidate": candidate, "already_added": false})
}

// List — GET /api/events/:id/candidates (any member).
func (h *EventCandidateHandler) List(c *gin.Context) {
	eventID := currentEventID(c)
	userID := currentUserID(c)

	var candidates []models.EventCandidate
	if err := h.DB.Preload("Listing").Preload("Listing.Category").Preload("Hall").Preload("Menu").
		Where("event_id = ?", eventID).Order("created_at asc").Find(&candidates).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch candidates"})
		return
	}
	if len(candidates) == 0 {
		c.JSON(http.StatusOK, gin.H{"candidates": []candidateOut{}})
		return
	}

	candidateIDs := make([]uint, len(candidates))
	for i, cand := range candidates {
		candidateIDs[i] = cand.ID
	}

	var votes []models.EventVote
	h.DB.Where("candidate_id IN ?", candidateIDs).Find(&votes)
	voteTally := map[uint]map[string]int{}
	myVotes := map[uint]string{}
	for _, v := range votes {
		if voteTally[v.CandidateID] == nil {
			voteTally[v.CandidateID] = map[string]int{}
		}
		voteTally[v.CandidateID][v.Value]++
		if v.UserID == userID {
			myVotes[v.CandidateID] = v.Value
		}
	}

	type countRow struct {
		CandidateID uint
		Count       int64
	}
	var counts []countRow
	h.DB.Model(&models.EventComment{}).Select("candidate_id, count(*) as count").Where("candidate_id IN ?", candidateIDs).Group("candidate_id").Scan(&counts)
	commentCounts := map[uint]int64{}
	for _, row := range counts {
		commentCounts[row.CandidateID] = row.Count
	}

	out := make([]candidateOut, 0, len(candidates))
	for _, cand := range candidates {
		tally := voteTally[cand.ID]
		if tally == nil {
			tally = map[string]int{}
		}
		out = append(out, candidateOut{
			EventCandidate: cand,
			Votes:          tally,
			MyVote:         myVotes[cand.ID],
			CommentCount:   commentCounts[cand.ID],
		})
	}
	c.JSON(http.StatusOK, gin.H{"candidates": out})
}

type updateCandidateInput struct {
	Status string `json:"status" binding:"required,oneof=shortlisted selected rejected"`
}

// UpdateStatus — PUT /api/events/:id/candidates/:cid (editor+). Selecting a
// candidate demotes any other currently-selected candidate in the same
// category back to shortlisted — "заменить выбор другим кандидатом" from
// the brief, enforced server-side so the dashboard's one-decision-per-
// category view (Ресторан ✓ …) can never show two. This already covers
// the restaurant hall/menu-variant case with no change needed: the
// demotion query below joins purely on listings.category_id, so selecting
// "Sultan Hall / Menu 25k" demotes "Sultan Hall / Menu 30k" (same
// listing, different candidate row) exactly the same way it demotes a
// wholly different restaurant in the same category — demoted candidates
// go back to shortlisted, never deleted, so a member can still compare
// them again later.
func (h *EventCandidateHandler) UpdateStatus(c *gin.Context) {
	candID, ok := atoiParam(c, "cid")
	if !ok {
		return
	}
	eventID := currentEventID(c)

	var candidate models.EventCandidate
	if err := h.DB.Preload("Listing").Where("id = ? AND event_id = ?", candID, eventID).First(&candidate).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "candidate not found"})
		return
	}

	var in updateCandidateInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if in.Status == models.CandidateSelected && candidate.Listing != nil {
		var siblings []models.EventCandidate
		h.DB.Joins("JOIN listings ON listings.id = event_candidates.listing_id").
			Where("event_candidates.event_id = ? AND event_candidates.status = ? AND listings.category_id = ? AND event_candidates.id <> ?",
				eventID, models.CandidateSelected, candidate.Listing.CategoryID, candidate.ID).
			Find(&siblings)
		for _, s := range siblings {
			h.DB.Model(&models.EventCandidate{}).Where("id = ?", s.ID).Update("status", models.CandidateShortlisted)
		}
	}

	candidate.Status = in.Status
	if err := h.DB.Save(&candidate).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update candidate"})
		return
	}

	if in.Status == models.CandidateSelected {
		name := ""
		var price uint
		if candidate.Listing != nil {
			name, price = candidate.Listing.NameRu, candidate.Listing.Price
		}
		if candidate.HallName != "" {
			name += " · " + candidate.HallName
		}
		if candidate.MenuName != "" {
			name += " · " + candidate.MenuName
		}
		logActivity(h.DB, eventID, currentUserID(c), "candidate.selected", map[string]any{"name": name, "price": price})
	}

	c.JSON(http.StatusOK, gin.H{"candidate": candidate})
}

// RemoveCandidate — DELETE /api/events/:id/candidates/:cid. The owner can
// remove any candidate; an editor only the ones they added themselves.
func (h *EventCandidateHandler) RemoveCandidate(c *gin.Context) {
	candID, ok := atoiParam(c, "cid")
	if !ok {
		return
	}

	var candidate models.EventCandidate
	if err := h.DB.Where("id = ? AND event_id = ?", candID, currentEventID(c)).First(&candidate).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "candidate not found"})
		return
	}

	if currentEventRole(c) != models.EventRoleOwner && candidate.AddedByID != currentUserID(c) {
		c.JSON(http.StatusForbidden, gin.H{"error": "you can only remove candidates you added"})
		return
	}

	h.DB.Where("candidate_id = ?", candidate.ID).Delete(&models.EventVote{})
	h.DB.Where("candidate_id = ?", candidate.ID).Delete(&models.EventComment{})
	if err := h.DB.Delete(&candidate).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to remove candidate"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "candidate removed"})
}

type voteInput struct {
	Value string `json:"value" binding:"required,oneof=up maybe down"`
}

// Vote — POST /api/events/:id/candidates/:cid/vote (any member, viewers
// included — per the brief, voting is the one action a Наблюдатель can
// still take). Upserts on the (candidate_id, user_id) unique index, so a
// member can change their mind but never registers two votes.
func (h *EventCandidateHandler) Vote(c *gin.Context) {
	candID, ok := atoiParam(c, "cid")
	if !ok {
		return
	}

	var candidate models.EventCandidate
	if err := h.DB.Where("id = ? AND event_id = ?", candID, currentEventID(c)).First(&candidate).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "candidate not found"})
		return
	}

	var in voteInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	userID := currentUserID(c)

	// Determine before the upsert whether this is a brand-new vote or a
	// genuine change of mind — re-submitting the *same* value (a retried or
	// doubled request, since this operation is meant to be idempotent) must
	// not spam the activity feed or create a duplicate notification.
	var existingVote models.EventVote
	hadVote := h.DB.Where("candidate_id = ? AND user_id = ?", candidate.ID, userID).First(&existingVote).Error == nil
	valueChanged := !hadVote || existingVote.Value != in.Value

	vote := models.EventVote{CandidateID: candidate.ID, UserID: userID, Value: in.Value}
	err := h.DB.Clauses(clause.OnConflict{
		Columns:   []clause.Column{{Name: "candidate_id"}, {Name: "user_id"}},
		DoUpdates: clause.AssignmentColumns([]string{"value", "updated_at"}),
	}).Create(&vote).Error
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save vote"})
		return
	}

	if valueChanged {
		name := ""
		if candidate.Listing != nil {
			name = candidate.Listing.NameRu
		} else {
			var listing models.Listing
			if h.DB.First(&listing, candidate.ListingID).Error == nil {
				name = listing.NameRu
			}
		}
		eventID := currentEventID(c)
		logActivity(h.DB, eventID, userID, "vote.cast", map[string]any{"name": name, "value": in.Value})

		notifType := models.NotifVoteChanged
		if !hadVote {
			notifType = models.NotifVoteAdded
		}
		recipients := []uint{eventOwnerID(h.DB, eventID), candidate.AddedByID}
		notifyMany(h.DB, recipients, userID, eventID, notifType, "candidate", candidate.ID, map[string]any{"name": name, "value": in.Value})
	}

	c.JSON(http.StatusOK, gin.H{"vote": vote})
}
