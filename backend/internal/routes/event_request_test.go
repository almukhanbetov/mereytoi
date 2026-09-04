package routes_test

import (
	"net/http"
	"testing"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// Covers the final event-request/booking flow end to end: draft → submit →
// changes_requested → edit → resubmit (revision 2) → approve, plus every
// permission/validation rule called out in the brief's section 13.
func TestEventRequestFullLifecycle(t *testing.T) {
	srv, db := setupTestServer(t)
	base := srv.URL

	owner := registerUser(t, base, "Мухтар", "req-owner@example.com")
	spouse := registerUser(t, base, "Айжан", "req-spouse@example.com")
	admin := registerAdmin(t, base, db, "Manager", "req-admin@example.com")

	status, out := owner.do("POST", "/api/events", map[string]any{"title": "Той", "type": "toi", "city": "Алматы", "guests": 100, "budget_total": 2000000})
	if status != http.StatusCreated {
		t.Fatalf("create event: %d %v", status, out)
	}
	eventID := int(out["event"].(map[string]any)["id"].(float64))
	ep := func(p string) string { return "/api/events/" + itoa(eventID) + p }

	// Invite the spouse as editor, a mother-in-law as viewer.
	_, inv := owner.do("POST", ep("/invitations"), map[string]any{"role": "editor"})
	spouseToken := inv["invitation"].(map[string]any)["token"].(string)
	if status, _ := spouse.do("POST", "/api/invitations/"+spouseToken+"/accept", nil); status != http.StatusOK {
		t.Fatalf("spouse accept failed: %d", status)
	}
	viewer := registerUser(t, base, "Мама", "req-viewer@example.com")
	_, inv2 := owner.do("POST", ep("/invitations"), map[string]any{"role": "viewer"})
	viewerToken := inv2["invitation"].(map[string]any)["token"].(string)
	if status, _ := viewer.do("POST", "/api/invitations/"+viewerToken+"/accept", nil); status != http.StatusOK {
		t.Fatalf("viewer accept failed: %d", status)
	}

	// Select one service.
	listing := seedListing(t, db, "Grand Hall", 1200000)
	_, candOut := owner.do("POST", ep("/candidates"), map[string]any{"listing_id": listing.ID})
	candID := int(candOut["candidate"].(map[string]any)["id"].(float64))
	if status, _ := owner.do("PUT", ep("/candidates/"+itoa(candID)), map[string]any{"status": "selected"}); status != http.StatusOK {
		t.Fatalf("select candidate failed: %d", status)
	}
	spouse.do("POST", ep("/candidates/"+itoa(candID)+"/vote"), map[string]any{"value": "up"})

	// GET request — get-or-create, readable by any member.
	status, reqOut := spouse.do("GET", ep("/request"), nil)
	if status != http.StatusOK {
		t.Fatalf("spouse GET request: %d %v", status, reqOut)
	}
	if reqOut["request"].(map[string]any)["status"] != "draft" {
		t.Fatalf("new request should start as draft, got %v", reqOut["request"])
	}

	// Participant (editor) cannot submit.
	if status, _ := spouse.do("POST", ep("/request/submit"), nil); status != http.StatusForbidden {
		t.Fatalf("participant should not be able to submit, got %d", status)
	}
	// Viewer cannot submit.
	if status, _ := viewer.do("POST", ep("/request/submit"), nil); status != http.StatusForbidden {
		t.Fatalf("viewer should not be able to submit, got %d", status)
	}

	// Organizer prepares a comment and submits — revision 1.
	owner.do("PUT", ep("/request"), map[string]any{"organizer_comment": "Пожалуйста, побыстрее"})
	status, submitOut := owner.do("POST", ep("/request/submit"), nil)
	if status != http.StatusOK {
		t.Fatalf("organizer submit failed: %d %v", status, submitOut)
	}
	submitted := submitOut["request"].(map[string]any)
	if submitted["status"] != "submitted" || submitted["latest_revision"].(float64) != 1 {
		t.Fatalf("expected status=submitted, revision=1, got %v", submitted)
	}
	if submitOut["already_submitted"] != false {
		t.Fatalf("first submit should not report already_submitted")
	}

	// Duplicate submit is a no-op, not a second revision.
	status, dupOut := owner.do("POST", ep("/request/submit"), nil)
	if status != http.StatusOK || dupOut["already_submitted"] != true {
		t.Fatalf("duplicate submit should be idempotent: %d %v", status, dupOut)
	}
	_, afterDup := owner.do("GET", ep("/request"), nil)
	if revs, ok := afterDup["revisions"].([]any); !ok || len(revs) != 1 {
		t.Fatalf("duplicate submit must not create a second revision, got %v", afterDup["revisions"])
	}

	// A user with no relationship to this event gets 404, not 403.
	outsider := registerUser(t, base, "Чужой", "req-outsider@example.com")
	if status, _ := outsider.do("GET", ep("/request"), nil); status != http.StatusNotFound {
		t.Fatalf("outsider should get 404 on the request too, got %d", status)
	}

	// Non-admin cannot reach the manager review API at all.
	if status, _ := spouse.do("GET", "/api/admin/event-requests", nil); status != http.StatusForbidden {
		t.Fatalf("non-admin should be forbidden from admin review, got %d", status)
	}

	// Admin sees it in the review list.
	status, listOut := admin.do("GET", "/api/admin/event-requests", nil)
	if status != http.StatusOK {
		t.Fatalf("admin list failed: %d %v", status, listOut)
	}
	var reqID int
	for _, r := range listOut["requests"].([]any) {
		rm := r.(map[string]any)
		if int(rm["event_id"].(float64)) == eventID {
			reqID = int(rm["id"].(float64))
		}
	}
	if reqID == 0 {
		t.Fatalf("admin should see the submitted request in the list: %v", listOut["requests"])
	}

	// Admin detail view.
	status, detailOut := admin.do("GET", "/api/admin/event-requests/"+itoa(reqID), nil)
	if status != http.StatusOK {
		t.Fatalf("admin get failed: %d %v", status, detailOut)
	}
	if revs, ok := detailOut["revisions"].([]any); !ok || len(revs) != 1 {
		t.Fatalf("admin detail should show 1 revision, got %v", detailOut["revisions"])
	}

	// (Draft requests can't be jumped straight to a decision either — see
	// TestEventRequestDraftHasNoAdminTransitions.)

	// Invalid transition: the binding itself rejects a target status outside
	// the allowed enum (e.g. "submitted" is a source-only state here).
	if status, _ := admin.do("POST", "/api/admin/event-requests/"+itoa(reqID)+"/status", map[string]any{"status": "bogus"}); status != http.StatusBadRequest {
		t.Fatalf("unknown status value should be rejected by binding, got %d", status)
	}

	// Valid transition: submitted → in_review.
	if status, _ := admin.do("POST", "/api/admin/event-requests/"+itoa(reqID)+"/status", map[string]any{"status": "in_review"}); status != http.StatusOK {
		t.Fatalf("submitted -> in_review should succeed, got %d", status)
	}
	// Invalid transition: in_review -> "submitted" is not a reachable target
	// (not in the allowed-status enum for admin review at all).
	if status, _ := admin.do("POST", "/api/admin/event-requests/"+itoa(reqID)+"/status", map[string]any{"status": "submitted"}); status != http.StatusBadRequest {
		t.Fatalf("transitioning back to submitted should be rejected, got %d", status)
	}

	// Manager requests changes, with a comment.
	status, crOut := admin.do("POST", "/api/admin/event-requests/"+itoa(reqID)+"/status", map[string]any{"status": "changes_requested", "manager_comment": "Уточните дату мероприятия"})
	if status != http.StatusOK {
		t.Fatalf("in_review -> changes_requested failed: %d %v", status, crOut)
	}

	// Organizer sees the manager's comment and the new status.
	_, afterCR := owner.do("GET", ep("/request"), nil)
	afterCRReq := afterCR["request"].(map[string]any)
	if afterCRReq["status"] != "changes_requested" || afterCRReq["manager_comment"] != "Уточните дату мероприятия" {
		t.Fatalf("organizer should see changes_requested + manager comment, got %v", afterCRReq)
	}

	// Organizer edits and resubmits — revision 2, and revision 1 must be untouched.
	if status, _ := owner.do("PUT", ep("/request"), map[string]any{"organizer_comment": "Дата уточнена: 20 июня"}); status != http.StatusOK {
		t.Fatalf("editing during changes_requested should be allowed, got %d", status)
	}
	status, resubmitOut := owner.do("POST", ep("/request/submit"), nil)
	if status != http.StatusOK {
		t.Fatalf("resubmit failed: %d %v", status, resubmitOut)
	}
	resubmitted := resubmitOut["request"].(map[string]any)
	if resubmitted["latest_revision"].(float64) != 2 {
		t.Fatalf("expected revision 2 after resubmit, got %v", resubmitted["latest_revision"])
	}

	_, afterResubmit := owner.do("GET", ep("/request"), nil)
	revisions := afterResubmit["revisions"].([]any)
	if len(revisions) != 2 {
		t.Fatalf("expected 2 revisions preserved, got %d", len(revisions))
	}
	var rev1Comment, rev2Comment any
	for _, r := range revisions {
		rm := r.(map[string]any)
		snap := rm["snapshot"].(map[string]any)
		switch rm["revision_number"].(float64) {
		case 1:
			rev1Comment = snap["organizer_comment"]
		case 2:
			rev2Comment = snap["organizer_comment"]
		}
	}
	if rev1Comment != "Пожалуйста, побыстрее" {
		t.Fatalf("revision 1's frozen snapshot must not change, got %v", rev1Comment)
	}
	if rev2Comment != "Дата уточнена: 20 июня" {
		t.Fatalf("revision 2 should carry the new comment, got %v", rev2Comment)
	}

	// Manager approves.
	status, approveOut := admin.do("POST", "/api/admin/event-requests/"+itoa(reqID)+"/status", map[string]any{"status": "approved", "manager_comment": "Всё отлично!"})
	if status != http.StatusOK {
		t.Fatalf("approve failed: %d %v", status, approveOut)
	}

	// Terminal: no further transition is allowed out of approved.
	if status, _ := admin.do("POST", "/api/admin/event-requests/"+itoa(reqID)+"/status", map[string]any{"status": "rejected"}); status != http.StatusConflict {
		t.Fatalf("transitioning out of approved should be rejected, got %d", status)
	}

	// Event workspace reflects the approval, with a linked booking/order number.
	_, finalReq := owner.do("GET", ep("/request"), nil)
	finalMap := finalReq["request"].(map[string]any)
	if finalMap["status"] != "approved" {
		t.Fatalf("workspace should show approved, got %v", finalMap["status"])
	}
	if finalMap["booking_id"] == nil {
		t.Fatalf("an approved request should have a linked booking id")
	}

	// Owner cannot cancel an approved request.
	if status, _ := owner.do("POST", ep("/request/cancel"), nil); status != http.StatusConflict {
		t.Fatalf("cancelling an approved request should be refused, got %d", status)
	}

	// Database proof: the linked Booking exists, points back at the event,
	// carries the frozen total, and its status label followed the approval.
	bookingID := uint(finalMap["booking_id"].(float64))
	var booking models.Booking
	if err := db.First(&booking, bookingID).Error; err != nil {
		t.Fatalf("linked booking not found in DB: %v", err)
	}
	if booking.EventID == nil || *booking.EventID != uint(eventID) {
		t.Fatalf("booking.EventID should point back at the event, got %v", booking.EventID)
	}
	if booking.Status != "confirmed" {
		t.Fatalf("booking status should follow approval to 'confirmed', got %q", booking.Status)
	}
	if booking.Total != 1200000 {
		t.Fatalf("booking total should match the selected service's price, got %d", booking.Total)
	}

	var revisionRows []models.EventRequestRevision
	db.Where("event_request_id = ?", reqID).Find(&revisionRows)
	if len(revisionRows) != 2 {
		t.Fatalf("expected 2 revision rows in DB, got %d", len(revisionRows))
	}
}

// A brand-new event's request has never been submitted (still draft) — an
// admin should not be able to force it straight to a decision, since
// "draft" has no outgoing transitions in the admin state machine at all.
func TestEventRequestDraftHasNoAdminTransitions(t *testing.T) {
	srv, db := setupTestServer(t)
	base := srv.URL

	owner := registerUser(t, base, "Ерлан", "req-draft-owner@example.com")
	admin := registerAdmin(t, base, db, "Manager2", "req-draft-admin@example.com")

	status, out := owner.do("POST", "/api/events", map[string]any{"title": "Юбилей", "type": "anniversary"})
	if status != http.StatusCreated {
		t.Fatalf("create event: %d", status)
	}
	eventID := int(out["event"].(map[string]any)["id"].(float64))

	// Touch GET so the draft EventRequest row actually exists.
	_, reqOut := owner.do("GET", "/api/events/"+itoa(eventID)+"/request", nil)
	reqID := int(reqOut["request"].(map[string]any)["id"].(float64))

	// A draft doesn't even show up in the admin list...
	_, listOut := admin.do("GET", "/api/admin/event-requests", nil)
	for _, r := range listOut["requests"].([]any) {
		if int(r.(map[string]any)["id"].(float64)) == reqID {
			t.Fatalf("a never-submitted draft should not appear in admin review list")
		}
	}

	// ...and even if an admin knows its ID directly, no transition applies.
	if status, _ := admin.do("POST", "/api/admin/event-requests/"+itoa(reqID)+"/status", map[string]any{"status": "approved"}); status != http.StatusConflict {
		t.Fatalf("approving a draft request should be rejected, got %d", status)
	}
}
