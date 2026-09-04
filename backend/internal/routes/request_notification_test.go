package routes_test

import (
	"net/http"
	"testing"
)

// TestRequestLifecycleNotifications walks the whole 10B lifecycle —
// submit -> in_review -> changes_requested -> resubmit -> approve — and
// checks every recipient/dedup/revision rule against the real API.
func TestRequestLifecycleNotifications(t *testing.T) {
	srv, db := setupTestServer(t)
	base := srv.URL

	owner := registerUser(t, base, "Айдан", "req-notif-owner@example.com")
	spouse := registerUser(t, base, "Али", "req-notif-spouse@example.com")
	admin := registerAdmin(t, base, db, "Manager", "req-notif-admin@example.com")

	status, out := owner.do("POST", "/api/events", map[string]any{"title": "Свадьба Айдана и Али", "type": "wedding", "budget_total": 1000000})
	if status != http.StatusCreated {
		t.Fatalf("create event: %d %v", status, out)
	}
	eventID := int(out["event"].(map[string]any)["id"].(float64))
	ep := func(p string) string { return "/api/events/" + itoa(eventID) + p }

	_, inv := owner.do("POST", ep("/invitations"), map[string]any{"role": "editor"})
	token := inv["invitation"].(map[string]any)["token"].(string)
	spouse.do("POST", "/api/invitations/"+token+"/accept", nil)

	listing := seedListing(t, db, "Notif Test Hall", 500000)
	_, candOut := owner.do("POST", ep("/candidates"), map[string]any{"listing_id": listing.ID})
	candID := int(candOut["candidate"].(map[string]any)["id"].(float64))
	owner.do("PUT", ep("/candidates/"+itoa(candID)), map[string]any{"status": "selected"})

	// --- (1) & (2): submit notifies admin, not the submitting organizer ---
	status, submitOut := owner.do("POST", ep("/request/submit"), nil)
	if status != http.StatusOK {
		t.Fatalf("submit failed: %d %v", status, submitOut)
	}

	_, adminNotifs := admin.do("GET", "/api/notifications", nil)
	submittedNotif := findNotif(adminNotifs, "request_submitted")
	if submittedNotif == nil {
		t.Fatalf("admin should be notified of request_submitted, got %v", adminNotifs["notifications"])
	}
	if submittedNotif["payload"].(map[string]any)["revision"].(float64) != 1 {
		t.Fatalf("request_submitted notification should reference revision 1, got %v", submittedNotif["payload"])
	}
	_, ownerNotifsAfterSubmit := owner.do("GET", "/api/notifications", nil)
	if findNotif(ownerNotifsAfterSubmit, "request_submitted") != nil {
		t.Fatalf("the submitting organizer must not be notified about their own submission")
	}

	// Get the EventRequest's own id (needed for admin endpoints) from the
	// admin's request list.
	_, adminList := admin.do("GET", "/api/admin/event-requests", nil)
	var reqID int
	for _, r := range adminList["requests"].([]any) {
		rm := r.(map[string]any)
		if int(rm["event_id"].(float64)) == eventID {
			reqID = int(rm["id"].(float64))
		}
	}
	if reqID == 0 {
		t.Fatalf("admin should see the submitted request")
	}
	adminReqPath := "/api/admin/event-requests/" + itoa(reqID) + "/status"

	// --- (10): duplicate submit does not duplicate the notification ---
	owner.do("POST", ep("/request/submit"), nil) // already submitted -> no-op per 10B design
	_, adminNotifs2 := admin.do("GET", "/api/notifications", nil)
	if got := countNotifs(adminNotifs2, "request_submitted"); got != 1 {
		t.Fatalf("retried submit must not duplicate the admin notification, got %d", got)
	}

	// --- (3): in_review notifies organizer ---
	if status, out := admin.do("POST", adminReqPath, map[string]any{"status": "in_review"}); status != http.StatusOK {
		t.Fatalf("submitted -> in_review failed: %d %v", status, out)
	}
	_, ownerNotifs := owner.do("GET", "/api/notifications", nil)
	if findNotif(ownerNotifs, "request_in_review") == nil {
		t.Fatalf("organizer should be notified of request_in_review")
	}

	// --- (11): repeated identical status update must not duplicate ---
	// in_review -> in_review is not itself a valid transition (self-loops
	// aren't in the state machine), so the API rejects the retry outright —
	// which is exactly what prevents the duplicate.
	if status, _ := admin.do("POST", adminReqPath, map[string]any{"status": "in_review"}); status != http.StatusConflict {
		t.Fatalf("repeating the same status should be rejected as an invalid transition, got %d", status)
	}
	_, ownerNotifsAfterRetry := owner.do("GET", "/api/notifications", nil)
	if got := countNotifs(ownerNotifsAfterRetry, "request_in_review"); got != 1 {
		t.Fatalf("rejected repeat status call must not create a second notification, got %d", got)
	}

	// --- (4) & (5): changes_requested notifies organizer with the comment ---
	status, crOut := admin.do("POST", adminReqPath, map[string]any{"status": "changes_requested", "manager_comment": "Уточните количество гостей"})
	if status != http.StatusOK {
		t.Fatalf("in_review -> changes_requested failed: %d %v", status, crOut)
	}
	_, ownerNotifs2 := owner.do("GET", "/api/notifications", nil)
	crNotif := findNotif(ownerNotifs2, "request_changes_requested")
	if crNotif == nil {
		t.Fatalf("organizer should be notified of request_changes_requested")
	}
	if crNotif["payload"].(map[string]any)["manager_comment"] != "Уточните количество гостей" {
		t.Fatalf("changes_requested notification should carry the manager's comment, got %v", crNotif["payload"])
	}
	// Spouse (a mere participant) is not part of this — it's the
	// organizer's action item, not the team's.
	_, spouseNotifs := spouse.do("GET", "/api/notifications", nil)
	if findNotif(spouseNotifs, "request_changes_requested") != nil {
		t.Fatalf("changes_requested should not be broadcast to participants")
	}

	// --- (9) & (14): resubmission notifies admin, referencing revision 2 ---
	owner.do("PUT", ep("/request"), map[string]any{"organizer_comment": "150 гостей"})
	status, resubmitOut := owner.do("POST", ep("/request/submit"), nil)
	if status != http.StatusOK {
		t.Fatalf("resubmit failed: %d %v", status, resubmitOut)
	}
	_, adminNotifs3 := admin.do("GET", "/api/notifications", nil)
	resubmitNotif := findNotif(adminNotifs3, "request_resubmitted")
	if resubmitNotif == nil {
		t.Fatalf("admin should be notified of request_resubmitted")
	}
	if resubmitNotif["payload"].(map[string]any)["revision"].(float64) != 2 {
		t.Fatalf("resubmission notification should reference revision 2, got %v", resubmitNotif["payload"])
	}
	// The original changes_requested notification must still say revision 1
	// — it must never be silently repointed at the new revision.
	_, ownerNotifs3 := owner.do("GET", "/api/notifications", nil)
	crNotifAfter := findNotif(ownerNotifs3, "request_changes_requested")
	if crNotifAfter["payload"].(map[string]any)["revision"].(float64) != 1 {
		t.Fatalf("the earlier changes_requested notification must keep pointing at revision 1, got %v", crNotifAfter["payload"])
	}

	// --- (6) & (7): approval notifies organizer AND the participant ---
	status, approveOut := admin.do("POST", adminReqPath, map[string]any{"status": "approved", "manager_comment": "Отлично, всё подтверждено!"})
	if status != http.StatusOK {
		t.Fatalf("approve failed: %d %v", status, approveOut)
	}
	_, ownerNotifs4 := owner.do("GET", "/api/notifications", nil)
	approvedForOwner := findNotif(ownerNotifs4, "request_approved")
	if approvedForOwner == nil {
		t.Fatalf("organizer should be notified of approval")
	}
	if approvedForOwner["payload"].(map[string]any)["revision"].(float64) != 2 {
		t.Fatalf("approval notification should reference the approved revision 2, got %v", approvedForOwner["payload"])
	}
	_, spouseNotifs2 := spouse.do("GET", "/api/notifications", nil)
	if findNotif(spouseNotifs2, "request_approved") == nil {
		t.Fatalf("participant (spouse) should also be notified of approval")
	}
	// The admin who approved it is the actor — never self-notified.
	_, adminNotifs4 := admin.do("GET", "/api/notifications", nil)
	if findNotif(adminNotifs4, "request_approved") != nil {
		t.Fatalf("the approving admin must not be notified about their own decision")
	}
}

// TestRequestRejectionNotifiesOrganizer covers point (8) in isolation with
// a fresh request.
func TestRequestRejectionNotifiesOrganizer(t *testing.T) {
	srv, db := setupTestServer(t)
	base := srv.URL

	owner := registerUser(t, base, "Ерлан", "req-reject-owner@example.com")
	admin := registerAdmin(t, base, db, "Manager", "req-reject-admin@example.com")

	_, out := owner.do("POST", "/api/events", map[string]any{"title": "Той", "type": "toi"})
	eventID := int(out["event"].(map[string]any)["id"].(float64))
	owner.do("POST", "/api/events/"+itoa(eventID)+"/request/submit", nil)

	_, adminList := admin.do("GET", "/api/admin/event-requests", nil)
	var reqID int
	for _, r := range adminList["requests"].([]any) {
		rm := r.(map[string]any)
		if int(rm["event_id"].(float64)) == eventID {
			reqID = int(rm["id"].(float64))
		}
	}

	status, _ := admin.do("POST", "/api/admin/event-requests/"+itoa(reqID)+"/status", map[string]any{"status": "rejected", "manager_comment": "Недостаточно данных"})
	if status != http.StatusOK {
		t.Fatalf("reject failed: %d", status)
	}

	_, ownerNotifs := owner.do("GET", "/api/notifications", nil)
	n := findNotif(ownerNotifs, "request_rejected")
	if n == nil {
		t.Fatalf("organizer should be notified of rejection")
	}
	if n["payload"].(map[string]any)["manager_comment"] != "Недостаточно данных" {
		t.Fatalf("rejection notification should carry the manager's reason, got %v", n["payload"])
	}
}

// TestRequestCancellationRecipients covers point (12): the organizer who
// cancels is never notified; other members always are; admins only hear
// about it if the request had actually reached them.
func TestRequestCancellationRecipients(t *testing.T) {
	srv, db := setupTestServer(t)
	base := srv.URL

	owner := registerUser(t, base, "Гульнара", "req-cancel-owner@example.com")
	spouse := registerUser(t, base, "Марат", "req-cancel-spouse@example.com")
	admin := registerAdmin(t, base, db, "Manager", "req-cancel-admin@example.com")

	_, out := owner.do("POST", "/api/events", map[string]any{"title": "Той", "type": "toi"})
	eventID := int(out["event"].(map[string]any)["id"].(float64))
	ep := func(p string) string { return "/api/events/" + itoa(eventID) + p }

	_, inv := owner.do("POST", ep("/invitations"), map[string]any{"role": "editor"})
	token := inv["invitation"].(map[string]any)["token"].(string)
	spouse.do("POST", "/api/invitations/"+token+"/accept", nil)

	// Cancel while still a pristine draft — admin never saw it, so admin
	// gets nothing; the spouse still does (they're on the team).
	if status, _ := owner.do("POST", ep("/request/cancel"), nil); status != http.StatusOK {
		t.Fatalf("cancel draft failed: %d", status)
	}
	_, ownerNotifs := owner.do("GET", "/api/notifications", nil)
	if findNotif(ownerNotifs, "request_cancelled") != nil {
		t.Fatalf("organizer must not be notified about their own cancellation")
	}
	_, spouseNotifs := spouse.do("GET", "/api/notifications", nil)
	if findNotif(spouseNotifs, "request_cancelled") == nil {
		t.Fatalf("spouse should be notified of the cancellation")
	}
	_, adminNotifs := admin.do("GET", "/api/notifications", nil)
	if findNotif(adminNotifs, "request_cancelled") != nil {
		t.Fatalf("admin should not be notified — this draft never reached them")
	}
}

// TestRequestCancellationAfterSubmitNotifiesAdmin is the other half of
// point (12): once a request has actually been submitted, cancelling it IS
// the manager's concern.
func TestRequestCancellationAfterSubmitNotifiesAdmin(t *testing.T) {
	srv, db := setupTestServer(t)
	base := srv.URL

	owner := registerUser(t, base, "Нурлан", "req-cancel2-owner@example.com")
	admin := registerAdmin(t, base, db, "Manager", "req-cancel2-admin@example.com")

	_, out := owner.do("POST", "/api/events", map[string]any{"title": "Той", "type": "toi"})
	eventID := int(out["event"].(map[string]any)["id"].(float64))
	ep := func(p string) string { return "/api/events/" + itoa(eventID) + p }

	owner.do("POST", ep("/request/submit"), nil)
	if status, _ := owner.do("POST", ep("/request/cancel"), nil); status != http.StatusOK {
		t.Fatalf("cancel after submit failed: %d", status)
	}

	_, adminNotifs := admin.do("GET", "/api/notifications", nil)
	if findNotif(adminNotifs, "request_cancelled") == nil {
		t.Fatalf("admin should be notified — this request had already reached them")
	}
}

// TestRequestNotificationForeignAccessDenied covers point (13): a request
// notification's deep-link target must still be gated by the real
// ownership/admin checks — a notification can never itself be a bypass.
func TestRequestNotificationForeignAccessDenied(t *testing.T) {
	srv, db := setupTestServer(t)
	base := srv.URL

	owner := registerUser(t, base, "Асель", "req-foreign-owner@example.com")
	admin := registerAdmin(t, base, db, "Manager", "req-foreign-admin@example.com")
	outsider := registerUser(t, base, "Чужой", "req-foreign-outsider@example.com")

	_, out := owner.do("POST", "/api/events", map[string]any{"title": "Той", "type": "toi"})
	eventID := int(out["event"].(map[string]any)["id"].(float64))
	owner.do("POST", "/api/events/"+itoa(eventID)+"/request/submit", nil)

	_, adminNotifs := admin.do("GET", "/api/notifications", nil)
	n := findNotif(adminNotifs, "request_submitted")
	if n == nil {
		t.Fatalf("admin should have a request_submitted notification")
	}
	notifID := int(n["id"].(float64))
	requestEntityID := int(n["entity_id"].(float64))

	// The outsider cannot read the admin's own notification row...
	if status, _ := outsider.do("POST", "/api/notifications/"+itoa(notifID)+"/read", nil); status != http.StatusNotFound {
		t.Fatalf("outsider should get 404 on the admin's notification, got %d", status)
	}
	// ...and cannot reach the admin request detail the notification points
	// at either — the notification is just a pointer, the endpoint itself
	// is still the real authority.
	if status, _ := outsider.do("GET", "/api/admin/event-requests/"+itoa(requestEntityID), nil); status != http.StatusForbidden {
		t.Fatalf("outsider should be forbidden from the admin request detail, got %d", status)
	}
	// A non-admin, non-member event owner-of-a-different-event also cannot.
	if status, _ := owner.do("GET", "/api/admin/event-requests/"+itoa(requestEntityID), nil); status != http.StatusForbidden {
		t.Fatalf("even the request's own organizer is not an admin and must be forbidden here, got %d", status)
	}
}
