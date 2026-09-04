package handlers

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/mail"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

type EventRequestHandler struct {
	DB   *gorm.DB
	Mail *mail.Service
}

func NewEventRequestHandler(db *gorm.DB, mailer *mail.Service) *EventRequestHandler {
	return &EventRequestHandler{DB: db, Mail: mailer}
}

// getOrCreate returns the event's single EventRequest row, creating a fresh
// draft the first time anyone (any member) opens the "Заявка" tab. This
// keeps event→request a real 1:1 without requiring a separate "create"
// step the organizer has to remember to click first.
func (h *EventRequestHandler) getOrCreate(eventID, userID uint) (*models.EventRequest, error) {
	var req models.EventRequest
	err := h.DB.Where("event_id = ?", eventID).First(&req).Error
	if err == nil {
		return &req, nil
	}
	if err != gorm.ErrRecordNotFound {
		return nil, err
	}
	req = models.EventRequest{EventID: eventID, CreatedByID: userID, Status: models.RequestDraft}
	if err := h.DB.Create(&req).Error; err != nil {
		return nil, err
	}
	logActivity(h.DB, eventID, userID, "request_created", map[string]any{})
	return &req, nil
}

// Get — GET /api/events/:id/request (any member).
func (h *EventRequestHandler) Get(c *gin.Context) {
	eventID := currentEventID(c)
	req, err := h.getOrCreate(eventID, currentUserID(c))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load request"})
		return
	}

	var revisions []models.EventRequestRevision
	h.DB.Preload("SubmittedBy").Where("event_request_id = ?", req.ID).Order("revision_number desc").Find(&revisions)
	for i := range revisions {
		var snap map[string]any
		if json.Unmarshal([]byte(revisions[i].SnapshotJSON), &snap) == nil {
			revisions[i].Snapshot = snap
		}
	}

	c.JSON(http.StatusOK, gin.H{"request": req, "revisions": revisions})
}

type updateRequestInput struct {
	OrganizerComment string `json:"organizer_comment"`
}

// Update — PUT /api/events/:id/request (owner only). Only while the
// request is actually editable (draft, or the manager asked for changes) —
// there is nothing sensible to "edit" on a request already awaiting or past
// review.
func (h *EventRequestHandler) Update(c *gin.Context) {
	eventID := currentEventID(c)
	req, err := h.getOrCreate(eventID, currentUserID(c))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load request"})
		return
	}
	if !models.RequestEditable(req.Status) {
		c.JSON(http.StatusConflict, gin.H{"error": "request is not editable in its current status"})
		return
	}

	var in updateRequestInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	req.OrganizerComment = in.OrganizerComment
	if err := h.DB.Save(req).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update request"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"request": req})
}

// buildSnapshot freezes the event's current selected-candidates picture
// into the JSON shape stored on each revision — never re-derived from live
// rows once written, per the brief's "do not rely only on current
// candidate rows".
func (h *EventRequestHandler) buildSnapshot(event *models.Event, organizerComment string) (string, uint, error) {
	var selected []models.EventCandidate
	if err := h.DB.Preload("Listing").Preload("Listing.Category").
		Where("event_id = ? AND status = ?", event.ID, models.CandidateSelected).Find(&selected).Error; err != nil {
		return "", 0, err
	}

	candidateIDs := make([]uint, len(selected))
	for i, s := range selected {
		candidateIDs[i] = s.ID
	}
	voteTally := map[uint]map[string]int{}
	commentCounts := map[uint]int64{}
	if len(candidateIDs) > 0 {
		var votes []models.EventVote
		h.DB.Where("candidate_id IN ?", candidateIDs).Find(&votes)
		for _, v := range votes {
			if voteTally[v.CandidateID] == nil {
				voteTally[v.CandidateID] = map[string]int{}
			}
			voteTally[v.CandidateID][v.Value]++
		}
		type countRow struct {
			CandidateID uint
			Count       int64
		}
		var counts []countRow
		h.DB.Model(&models.EventComment{}).Select("candidate_id, count(*) as count").Where("candidate_id IN ?", candidateIDs).Group("candidate_id").Scan(&counts)
		for _, row := range counts {
			commentCounts[row.CandidateID] = row.Count
		}
	}

	var total uint
	items := make([]map[string]any, 0, len(selected))
	for _, s := range selected {
		if s.Listing == nil {
			continue
		}
		total += s.Listing.Price
		categoryName := ""
		if s.Listing.Category != nil {
			categoryName = s.Listing.Category.NameRu
		}
		items = append(items, map[string]any{
			"candidate_id":  s.ID,
			"listing_id":    s.ListingID,
			"category_name": categoryName,
			"name":          s.Listing.NameRu,
			"price":         s.Listing.Price,
			"votes":         voteTally[s.ID],
			"comment_count": commentCounts[s.ID],
		})
	}

	snapshot := map[string]any{
		"event_title":       event.Title,
		"event_type":        event.Type,
		"event_date":        event.EventDate,
		"city":              event.City,
		"guests":            event.Guests,
		"budget_total":      event.BudgetTotal,
		"organizer_comment": organizerComment,
		"items":             items,
		"total":             total,
	}
	data, err := json.Marshal(snapshot)
	return string(data), total, err
}

// Submit — POST /api/events/:id/request/submit (owner only). Idempotent:
// calling it again while already submitted/in_review just returns the
// current state instead of creating a duplicate revision or erroring.
func (h *EventRequestHandler) Submit(c *gin.Context) {
	eventID := currentEventID(c)
	userID := currentUserID(c)

	req, err := h.getOrCreate(eventID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load request"})
		return
	}

	// Already in flight or decided — submitting again is a no-op, not an
	// error, so a doubled click or a retried request can never create two
	// revisions.
	if !models.RequestEditable(req.Status) {
		c.JSON(http.StatusOK, gin.H{"request": req, "already_submitted": true})
		return
	}

	var event models.Event
	if err := h.DB.First(&event, eventID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "event not found"})
		return
	}

	snapshotJSON, total, err := h.buildSnapshot(&event, req.OrganizerComment)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to build snapshot"})
		return
	}

	wasChangesRequested := req.Status == models.RequestChangesRequested
	now := time.Now()
	nextRevision := req.LatestRevision + 1

	err = h.DB.Transaction(func(tx *gorm.DB) error {
		revision := models.EventRequestRevision{
			EventRequestID: req.ID,
			RevisionNumber: nextRevision,
			SubmittedByID:  userID,
			SnapshotJSON:   snapshotJSON,
			Total:          total,
			SubmittedAt:    now,
		}
		if err := tx.Create(&revision).Error; err != nil {
			return err
		}

		// First submission also creates the linked Booking so the order
		// shows up in the existing admin Bookings pipeline — later
		// revisions intentionally don't touch it further; the request
		// review flow (this API + /api/admin/event-requests) is the source
		// of truth for what happens after that.
		if req.BookingID == nil {
			var owner models.User
			tx.First(&owner, event.OwnerID)
			items := snapshotItemsToBookingItems(snapshotJSON)
			booking := models.Booking{
				PublicRef: generateRef(),
				UserID:    &event.OwnerID,
				EventID:   &event.ID,
				Name:      owner.Name,
				Phone:     owner.Phone,
				Message:   req.OrganizerComment,
				Items:     items,
				Total:     total,
				Status:    "new",
			}
			if err := tx.Create(&booking).Error; err != nil {
				return err
			}
			req.BookingID = &booking.ID
		}

		req.Status = models.RequestSubmitted
		req.SubmittedAt = &now
		req.LatestRevision = nextRevision
		return tx.Save(req).Error
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to submit request"})
		return
	}

	verb, notifType := "request_submitted", models.NotifRequestSubmitted
	if wasChangesRequested {
		verb, notifType = "request_resubmitted", models.NotifRequestResubmitted
	}
	payload := map[string]any{"revision": nextRevision, "total": total}
	logActivity(h.DB, eventID, userID, verb, payload)

	// The organizer submitting is never notified about their own submission
	// (createNotification already guards actor==recipient); every admin
	// account is — see adminUserIDs for why "every admin" rather than one
	// hard-coded user.
	notifyMany(h.DB, adminUserIDs(h.DB), userID, eventID, notifType, "request", req.ID, payload)

	// Brief section 6C/11 — same "every admin" resolution as the in-app
	// notification above, not a second, separately-hard-coded recipient
	// list. Fired only on the exact branch that just performed a real
	// status transition (Submit's own editable-status guard above already
	// makes this whole function idempotent — a retried/duplicate submit
	// call hits the early `already_submitted` return before this line ever
	// runs, so no duplicate admin emails on a retry, per brief section 18).
	h.emailAdminsRequestSubmitted(event.Title, req.ID, uint(nextRevision), wasChangesRequested)

	c.JSON(http.StatusOK, gin.H{"request": req, "already_submitted": false})
}

// snapshotItemsToBookingItems adapts a frozen request snapshot's items into
// the shape Booking.Items already expects, so the linked Booking reads
// exactly like any other booking to the existing admin UI.
func snapshotItemsToBookingItems(snapshotJSON string) []models.BookingItem {
	var snap struct {
		Items []struct {
			ListingID    uint   `json:"listing_id"`
			CategoryName string `json:"category_name"`
			Name         string `json:"name"`
			Price        uint   `json:"price"`
		} `json:"items"`
	}
	if json.Unmarshal([]byte(snapshotJSON), &snap) != nil {
		return nil
	}
	out := make([]models.BookingItem, 0, len(snap.Items))
	for _, it := range snap.Items {
		out = append(out, models.BookingItem{
			ListingID:  it.ListingID,
			Name:       it.Name,
			Category:   it.CategoryName,
			UnitPrice:  it.Price,
			TotalPrice: it.Price,
		})
	}
	return out
}

// Cancel — POST /api/events/:id/request/cancel (owner only). Refused once
// the request has already been decided (approved/rejected) or is already
// cancelled — those are terminal from the organizer's side.
func (h *EventRequestHandler) Cancel(c *gin.Context) {
	eventID := currentEventID(c)
	userID := currentUserID(c)

	req, err := h.getOrCreate(eventID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load request"})
		return
	}
	switch req.Status {
	case models.RequestApproved, models.RequestRejected, models.RequestCancelled:
		c.JSON(http.StatusConflict, gin.H{"error": "request can no longer be cancelled"})
		return
	}
	hadReachedManager := req.Status != models.RequestDraft

	req.Status = models.RequestCancelled
	if err := h.DB.Save(req).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to cancel request"})
		return
	}
	logActivity(h.DB, eventID, userID, "request_cancelled", map[string]any{})

	// The organizer who cancelled isn't notified about their own action.
	// Everyone else who was collaborating still hears about it; admins only
	// hear about it if the request had actually reached them already —
	// cancelling an untouched local draft they never saw isn't their concern.
	payload := map[string]any{}
	others := memberUserIDs(h.DB, eventID, models.EventRoleViewer)
	notifyMany(h.DB, others, userID, eventID, models.NotifRequestCancelled, "request", req.ID, payload)
	if hadReachedManager {
		notifyMany(h.DB, adminUserIDs(h.DB), userID, eventID, models.NotifRequestCancelled, "request", req.ID, payload)
	}

	c.JSON(http.StatusOK, gin.H{"request": req})
}

// ---- Admin/manager review — mounted under /api/admin/event-requests,
// guarded by the same middleware.RequireAuth+RequireAdmin every other admin
// route already uses (see routes.go). Not part of the event-membership
// world at all: an admin doesn't need to be a member of the event.

type eventRequestOut struct {
	models.EventRequest
	Event *models.Event `json:"event,omitempty"`
	Total uint          `json:"total"`
}

// AdminList — GET /api/admin/event-requests?status=submitted. Only requests
// that have actually been submitted at least once show up here — a fresh
// draft nobody has sent yet has nothing for a manager to review.
func (h *EventRequestHandler) AdminList(c *gin.Context) {
	query := h.DB.Model(&models.EventRequest{}).Where("status <> ?", models.RequestDraft)
	if status := c.Query("status"); status != "" {
		query = query.Where("status = ?", status)
	}

	var requests []models.EventRequest
	if err := query.Order("submitted_at desc").Find(&requests).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch requests"})
		return
	}

	out := make([]eventRequestOut, 0, len(requests))
	for _, r := range requests {
		var event models.Event
		h.DB.First(&event, r.EventID)
		var latest models.EventRequestRevision
		var total uint
		if h.DB.Where("event_request_id = ? AND revision_number = ?", r.ID, r.LatestRevision).First(&latest).Error == nil {
			total = latest.Total
		}
		out = append(out, eventRequestOut{EventRequest: r, Event: &event, Total: total})
	}
	c.JSON(http.StatusOK, gin.H{"requests": out})
}

// AdminGet — GET /api/admin/event-requests/:id. Everything a manager needs
// to actually review: the event, its team, and the full revision history.
func (h *EventRequestHandler) AdminGet(c *gin.Context) {
	id, ok := atoiParam(c, "id")
	if !ok {
		return
	}

	var req models.EventRequest
	if err := h.DB.First(&req, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "request not found"})
		return
	}
	var event models.Event
	h.DB.First(&event, req.EventID)
	var members []models.EventMember
	h.DB.Preload("User").Where("event_id = ?", req.EventID).Find(&members)
	var revisions []models.EventRequestRevision
	h.DB.Preload("SubmittedBy").Where("event_request_id = ?", req.ID).Order("revision_number desc").Find(&revisions)
	for i := range revisions {
		var snap map[string]any
		if json.Unmarshal([]byte(revisions[i].SnapshotJSON), &snap) == nil {
			revisions[i].Snapshot = snap
		}
	}

	c.JSON(http.StatusOK, gin.H{"request": req, "event": event, "members": members, "revisions": revisions})
}

type adminStatusInput struct {
	Status         string  `json:"status" binding:"required,oneof=in_review changes_requested approved rejected"`
	ManagerComment *string `json:"manager_comment"`
}

// requestActivityVerbs and requestNotifTypes are deliberately two small,
// parallel maps rather than one — the EventActivity verb feeds the
// event's shared audit feed regardless of target status, while not every
// status necessarily needs its own notification type long-term; keeping
// them separate means adding/removing one doesn't silently affect the other.
var requestActivityVerbs = map[string]string{
	models.RequestInReview:         "request_in_review",
	models.RequestChangesRequested: "request_changes_requested",
	models.RequestApproved:         "request_approved",
	models.RequestRejected:         "request_rejected",
}

var requestNotifTypes = map[string]string{
	models.RequestInReview:         models.NotifRequestInReview,
	models.RequestChangesRequested: models.NotifRequestChangesRequested,
	models.RequestApproved:         models.NotifRequestApproved,
	models.RequestRejected:         models.NotifRequestRejected,
}

// AdminUpdateStatus — POST /api/admin/event-requests/:id/status. Validates
// the transition server-side via models.CanTransition — an admin cannot,
// say, "approve" a request that's still a draft or already rejected.
func (h *EventRequestHandler) AdminUpdateStatus(c *gin.Context) {
	id, ok := atoiParam(c, "id")
	if !ok {
		return
	}

	var req models.EventRequest
	if err := h.DB.First(&req, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "request not found"})
		return
	}

	var in adminStatusInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if !models.CanTransition(req.Status, in.Status) {
		c.JSON(http.StatusConflict, gin.H{"error": "invalid status transition"})
		return
	}

	if in.ManagerComment != nil {
		req.ManagerComment = *in.ManagerComment
	}
	req.Status = in.Status
	if err := h.DB.Save(&req).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update request"})
		return
	}

	// Keep the linked Booking's own status label in sync for the existing
	// admin Bookings list — no payment/contract logic, just the label.
	if req.BookingID != nil {
		bookingStatus := ""
		switch in.Status {
		case models.RequestApproved:
			bookingStatus = "confirmed"
		case models.RequestRejected:
			bookingStatus = "cancelled"
		}
		if bookingStatus != "" {
			h.DB.Model(&models.Booking{}).Where("id = ?", *req.BookingID).Update("status", bookingStatus)
		}
	}

	actorID := currentUserID(c)
	// Revision number is captured so this notification always points at the
	// exact revision under review when the decision was made — if a newer
	// revision is submitted later, this row still correctly refers to the
	// one it was actually about (brief section 18).
	payload := map[string]any{"revision": req.LatestRevision}
	if req.ManagerComment != "" {
		payload["manager_comment"] = req.ManagerComment
	}
	if in.Status == models.RequestApproved {
		// "Final price / booking number" for the approval notification
		// (brief section 23) — both already exist on the record, nothing
		// new is added to Booking just for display here.
		var revision models.EventRequestRevision
		if h.DB.Where("event_request_id = ? AND revision_number = ?", req.ID, req.LatestRevision).First(&revision).Error == nil {
			payload["total"] = revision.Total
		}
		if req.BookingID != nil {
			payload["booking_id"] = *req.BookingID
		}
	}

	if verb, ok := requestActivityVerbs[in.Status]; ok {
		logActivity(h.DB, req.EventID, actorID, verb, payload)
	}

	if notifType, ok := requestNotifTypes[in.Status]; ok {
		switch in.Status {
		case models.RequestInReview, models.RequestChangesRequested:
			// Only the organizer needs to know/act right now — in_review is
			// informational, changes_requested is the actionable one; both
			// are strictly the organizer's business, not the whole team's.
			createNotification(h.DB, eventOwnerID(h.DB, req.EventID), actorID, req.EventID, notifType, "request", req.ID, payload)
		case models.RequestApproved, models.RequestRejected:
			// A terminal decision on the whole event's plan concerns
			// everyone collaborating on it — viewers included, unlike the
			// day-to-day editor-scoped notifications (e.g. budget_updated).
			recipients := memberUserIDs(h.DB, req.EventID, models.EventRoleViewer)
			notifyMany(h.DB, recipients, actorID, req.EventID, notifType, "request", req.ID, payload)
		}
	}

	// Brief sections 8/9/10 — organizer email. Deliberately not sent for
	// in_review (not in the brief's section 6 required-events list — it's
	// purely informational, same reasoning the in-app notification side
	// already applies elsewhere in this stage's own design). Reached only
	// once per real transition — CanTransition above already rejected this
	// call entirely (409, before any of this function's side effects run)
	// if `req.Status` had already moved past `in.Status`'s source state, so
	// a duplicate/retried admin decision call can't send a second email
	// (brief section 18).
	switch in.Status {
	case models.RequestChangesRequested, models.RequestApproved, models.RequestRejected:
		h.emailOrganizerRequestDecision(&req, in.Status)
	}

	c.JSON(http.StatusOK, gin.H{"request": req})
}

// emailAdminsRequestSubmitted — brief section 11: every admin account with
// an email, resolved the exact same way as adminUserIDs (notification_
// helpers.go) rather than a second, independently-maintained admin list.
// Every registered User.Email is required+validated at registration (see
// auth_handler.go's registerInput), so in practice this never actually
// skips anyone — the empty check is defensive (brief section 5), not
// reachable via normal signup today.
func (h *EventRequestHandler) emailAdminsRequestSubmitted(eventTitle string, requestID, revision uint, resubmitted bool) {
	var admins []models.User
	h.DB.Where("role = ?", "admin").Find(&admins)
	for _, admin := range admins {
		h.Mail.SendRequestSubmittedAdmin("ru", admin.Email, eventTitle, requestID, revision, resubmitted)
	}
}

// emailOrganizerRequestDecision loads what the three organizer-facing
// decision emails (changes_requested/approved/rejected) all need — the
// event's title and the owner's own account — once, then dispatches the
// one that matches `status`.
func (h *EventRequestHandler) emailOrganizerRequestDecision(req *models.EventRequest, status string) {
	var event models.Event
	if h.DB.First(&event, req.EventID).Error != nil {
		return
	}
	var owner models.User
	if h.DB.First(&owner, event.OwnerID).Error != nil {
		return
	}

	switch status {
	case models.RequestChangesRequested:
		h.Mail.SendRequestChangesRequested("ru", owner.Email, event.Title, req.ManagerComment, req.EventID, uint(req.LatestRevision))
	case models.RequestApproved:
		var revision models.EventRequestRevision
		h.DB.Where("event_request_id = ? AND revision_number = ?", req.ID, req.LatestRevision).First(&revision)
		bookingRef := ""
		if req.BookingID != nil {
			var booking models.Booking
			if h.DB.First(&booking, *req.BookingID).Error == nil {
				bookingRef = booking.PublicRef
			}
		}
		h.Mail.SendRequestApproved("ru", owner.Email, event.Title, req.ManagerComment, req.EventID, revision.Total, bookingRef)
	case models.RequestRejected:
		h.Mail.SendRequestRejected("ru", owner.Email, event.Title, req.ManagerComment, req.EventID)
	}
}
