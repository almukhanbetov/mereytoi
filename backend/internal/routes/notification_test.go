package routes_test

import (
	"net/http"
	"testing"
)

// findNotif returns the first notification of the given type in a
// GET /api/notifications response, or nil if there isn't one.
func findNotif(out map[string]any, notifType string) map[string]any {
	list, _ := out["notifications"].([]any)
	for _, n := range list {
		m := n.(map[string]any)
		if m["type"] == notifType {
			return m
		}
	}
	return nil
}

func countNotifs(out map[string]any, notifType string) int {
	list, _ := out["notifications"].([]any)
	n := 0
	for _, item := range list {
		if item.(map[string]any)["type"] == notifType {
			n++
		}
	}
	return n
}

// TestNotificationsRealDomainActions is the E2E scenario from the brief's
// section 28: every notification here is produced by a real action through
// the real API, never seeded directly.
func TestNotificationsRealDomainActions(t *testing.T) {
	srv, db := setupTestServer(t)
	base := srv.URL

	owner := registerUser(t, base, "Мухтар", "notif-owner@example.com")
	spouse := registerUser(t, base, "Айжан", "notif-spouse@example.com")

	status, out := owner.do("POST", "/api/events", map[string]any{"title": "Той", "type": "toi", "budget_total": 1000000})
	if status != http.StatusCreated {
		t.Fatalf("create event: %d %v", status, out)
	}
	eventID := int(out["event"].(map[string]any)["id"].(float64))
	ep := func(p string) string { return "/api/events/" + itoa(eventID) + p }

	// --- invite + accept: organizer should get invitation_accepted ---
	_, inv := owner.do("POST", ep("/invitations"), map[string]any{"role": "editor"})
	token := inv["invitation"].(map[string]any)["token"].(string)

	// Owner has 0 unread before anything happens.
	status, unread := owner.do("GET", "/api/notifications/unread-count", nil)
	if status != http.StatusOK || unread["count"].(float64) != 0 {
		t.Fatalf("expected 0 unread initially, got %d %v", status, unread)
	}

	if status, _ := spouse.do("POST", "/api/invitations/"+token+"/accept", nil); status != http.StatusOK {
		t.Fatalf("spouse accept failed: %d", status)
	}

	status, ownerNotifs := owner.do("GET", "/api/notifications", nil)
	if status != http.StatusOK {
		t.Fatalf("owner list notifications: %d", status)
	}
	if n := findNotif(ownerNotifs, "invitation_accepted"); n == nil {
		t.Fatalf("owner should have an invitation_accepted notification, got %v", ownerNotifs["notifications"])
	}
	// The spouse (the actor here) must not be notified about their own acceptance.
	status, spouseNotifs := spouse.do("GET", "/api/notifications", nil)
	if status != http.StatusOK {
		t.Fatalf("spouse list notifications: %d", status)
	}
	if n := findNotif(spouseNotifs, "invitation_accepted"); n != nil {
		t.Fatalf("actor should never be notified about their own action, got %v", n)
	}
	if n := findNotif(spouseNotifs, "member_joined"); n != nil {
		t.Fatalf("actor should not get member_joined about themselves either, got %v", n)
	}

	status, unread = owner.do("GET", "/api/notifications/unread-count", nil)
	if status != http.StatusOK || unread["count"].(float64) != 1 {
		t.Fatalf("owner should have exactly 1 unread now, got %v", unread)
	}

	// --- candidate added: both members should be notified except the actor ---
	listing := seedListing(t, db, "Ресторан Grand", 500000)
	_, candOut := owner.do("POST", ep("/candidates"), map[string]any{"listing_id": listing.ID})
	candID := int(candOut["candidate"].(map[string]any)["id"].(float64))

	_, spouseNotifs2 := spouse.do("GET", "/api/notifications", nil)
	if findNotif(spouseNotifs2, "candidate_added") == nil {
		t.Fatalf("spouse should be notified of candidate_added")
	}
	_, ownerNotifs2 := owner.do("GET", "/api/notifications", nil)
	if findNotif(ownerNotifs2, "candidate_added") != nil {
		t.Fatalf("owner added the candidate — they must not be notified about their own action")
	}

	// --- vote: owner (who added it) should get vote_added; re-voting the
	// same value must NOT create a duplicate notification ---
	if status, _ := spouse.do("POST", ep("/candidates/"+itoa(candID)+"/vote"), map[string]any{"value": "up"}); status != http.StatusOK {
		t.Fatalf("vote failed: %d", status)
	}
	_, ownerNotifs3 := owner.do("GET", "/api/notifications", nil)
	if findNotif(ownerNotifs3, "vote_added") == nil {
		t.Fatalf("owner should get a vote_added notification")
	}
	firstCount := countNotifs(ownerNotifs3, "vote_added")

	// Idempotent retry — same value again.
	spouse.do("POST", ep("/candidates/"+itoa(candID)+"/vote"), map[string]any{"value": "up"})
	_, ownerNotifs4 := owner.do("GET", "/api/notifications", nil)
	if got := countNotifs(ownerNotifs4, "vote_added"); got != firstCount {
		t.Fatalf("re-voting the same value must not create a duplicate notification: had %d, now %d", firstCount, got)
	}

	// Changing the vote should produce a vote_changed, not another vote_added.
	spouse.do("POST", ep("/candidates/"+itoa(candID)+"/vote"), map[string]any{"value": "down"})
	_, ownerNotifs5 := owner.do("GET", "/api/notifications", nil)
	if findNotif(ownerNotifs5, "vote_changed") == nil {
		t.Fatalf("changing a vote should produce a vote_changed notification")
	}

	// --- comment: all members except the author ---
	if status, _ := spouse.do("POST", ep("/comments"), map[string]any{"body": "Мне нравится!", "candidate_id": candID}); status != http.StatusCreated {
		t.Fatalf("comment failed: %d", status)
	}
	_, ownerNotifs6 := owner.do("GET", "/api/notifications", nil)
	commentNotif := findNotif(ownerNotifs6, "comment_added")
	if commentNotif == nil {
		t.Fatalf("owner should be notified of the comment")
	}
	if commentNotif["entity_type"] != "candidate" || int(commentNotif["entity_id"].(float64)) != candID {
		t.Fatalf("comment notification should deep-link to the candidate, got %v", commentNotif)
	}

	// --- task: assignee gets task_created, creator gets task_completed ---
	_, membersOut := owner.do("GET", ep("/members"), nil)
	var spouseUserID int
	for _, m := range membersOut["members"].([]any) {
		mm := m.(map[string]any)
		if mm["user"].(map[string]any)["email"] == "notif-spouse@example.com" {
			spouseUserID = int(mm["user_id"].(float64))
		}
	}
	if spouseUserID == 0 {
		t.Fatalf("spouse membership not found in %v", membersOut["members"])
	}

	status, taskOut := owner.do("POST", ep("/tasks"), map[string]any{"title": "Забронировать зал", "assignee_id": spouseUserID})
	if status != http.StatusCreated {
		t.Fatalf("create task: %d %v", status, taskOut)
	}
	taskID := int(taskOut["task"].(map[string]any)["id"].(float64))

	_, spouseNotifs3 := spouse.do("GET", "/api/notifications", nil)
	if findNotif(spouseNotifs3, "task_created") == nil {
		t.Fatalf("assignee (spouse) should be notified of task_created")
	}

	if status, _ := spouse.do("PUT", ep("/tasks/"+itoa(taskID)), map[string]any{"status": "done"}); status != http.StatusOK {
		t.Fatalf("complete task: %d", status)
	}
	_, ownerNotifs7 := owner.do("GET", "/api/notifications", nil)
	if findNotif(ownerNotifs7, "task_completed") == nil {
		t.Fatalf("task creator (owner) should be notified of task_completed")
	}

	// --- unread count, mark one read, mark all read ---
	status, unreadBefore := owner.do("GET", "/api/notifications/unread-count", nil)
	if status != http.StatusOK {
		t.Fatalf("unread count: %d", status)
	}
	countBefore := unreadBefore["count"].(float64)
	if countBefore < 4 {
		t.Fatalf("owner should have several unread notifications by now, got %v", countBefore)
	}

	oneID := int(commentNotif["id"].(float64))
	if status, _ := owner.do("POST", "/api/notifications/"+itoa(oneID)+"/read", nil); status != http.StatusOK {
		t.Fatalf("mark one read failed: %d", status)
	}
	// Idempotent — reading it again must still succeed.
	if status, _ := owner.do("POST", "/api/notifications/"+itoa(oneID)+"/read", nil); status != http.StatusOK {
		t.Fatalf("marking an already-read notification read again should still succeed, got %d", status)
	}
	_, unreadAfterOne := owner.do("GET", "/api/notifications/unread-count", nil)
	if unreadAfterOne["count"].(float64) != countBefore-1 {
		t.Fatalf("unread count should drop by exactly 1, got %v (was %v)", unreadAfterOne["count"], countBefore)
	}

	if status, _ := owner.do("POST", "/api/notifications/read-all", nil); status != http.StatusOK {
		t.Fatalf("mark all read failed: %d", status)
	}
	_, unreadFinal := owner.do("GET", "/api/notifications/unread-count", nil)
	if unreadFinal["count"].(float64) != 0 {
		t.Fatalf("unread count should be 0 after mark-all-read, got %v", unreadFinal["count"])
	}

	// Mark-all-read must never touch the spouse's own notifications.
	status, spouseUnread := spouse.do("GET", "/api/notifications/unread-count", nil)
	if status != http.StatusOK || spouseUnread["count"].(float64) == 0 {
		t.Fatalf("spouse's unread notifications must be unaffected by owner's mark-all-read, got %v", spouseUnread)
	}
}

// TestNotificationCrossUserIsolation is the security-critical case: one
// user must never be able to read or modify another user's notifications,
// even by guessing an ID.
func TestNotificationCrossUserIsolation(t *testing.T) {
	srv, db := setupTestServer(t)
	base := srv.URL

	owner := registerUser(t, base, "Ерлан", "notif-iso-owner@example.com")
	spouse := registerUser(t, base, "Гульнара", "notif-iso-spouse@example.com")
	outsider := registerUser(t, base, "Чужой", "notif-iso-outsider@example.com")

	_, out := owner.do("POST", "/api/events", map[string]any{"title": "Той", "type": "toi"})
	eventID := int(out["event"].(map[string]any)["id"].(float64))
	_, inv := owner.do("POST", "/api/events/"+itoa(eventID)+"/invitations", map[string]any{"role": "editor"})
	token := inv["invitation"].(map[string]any)["token"].(string)
	spouse.do("POST", "/api/invitations/"+token+"/accept", nil)

	// A candidate add triggers a notification to the spouse.
	listing := seedListing(t, db, "Декор X", 100000)
	owner.do("POST", "/api/events/"+itoa(eventID)+"/candidates", map[string]any{"listing_id": listing.ID})

	_, spouseNotifs := spouse.do("GET", "/api/notifications", nil)
	n := findNotif(spouseNotifs, "candidate_added")
	if n == nil {
		t.Fatalf("spouse should have a candidate_added notification to test isolation against")
	}
	notifID := int(n["id"].(float64))

	// The outsider (unrelated to this event and this notification) cannot
	// mark the spouse's notification read.
	if status, _ := outsider.do("POST", "/api/notifications/"+itoa(notifID)+"/read", nil); status != http.StatusNotFound {
		t.Fatalf("outsider should get 404 marking someone else's notification read, got %d", status)
	}
	// Nor can the owner, even though they belong to the same event.
	if status, _ := owner.do("POST", "/api/notifications/"+itoa(notifID)+"/read", nil); status != http.StatusNotFound {
		t.Fatalf("the event owner should still get 404 for another member's notification, got %d", status)
	}

	// Confirm it's genuinely still unread — the failed attempts had no effect.
	_, spouseNotifsAfter := spouse.do("GET", "/api/notifications", nil)
	if findNotif(spouseNotifsAfter, "candidate_added")["is_read"].(bool) {
		t.Fatalf("notification should remain unread after other users' failed attempts")
	}

	// Each user's list only ever contains their own notifications — a stray
	// GET never leaks another user's rows even implicitly.
	status, outsiderNotifs := outsider.do("GET", "/api/notifications", nil)
	if status != http.StatusOK {
		t.Fatalf("outsider list: %d", status)
	}
	if len(outsiderNotifs["notifications"].([]any)) != 0 {
		t.Fatalf("outsider (not a member of this event) should have zero notifications, got %v", outsiderNotifs["notifications"])
	}
}
