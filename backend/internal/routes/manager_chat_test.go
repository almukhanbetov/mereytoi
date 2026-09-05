package routes_test

import (
	"net/http"
	"testing"
)

// TestManagerChatServiceContext covers brief sections 17/20: a logged-in
// customer starts a chat from a service's detail page (listing_id set, no
// event_id — a public catalog visit), the admin sees that context on the
// conversation, and can reply.
func TestManagerChatServiceContext(t *testing.T) {
	srv, db := setupTestServer(t)
	base := srv.URL

	customer := registerUser(t, base, "Madina", "chat-service-customer@example.com")
	admin := registerAdmin(t, base, db, "Manager", "chat-service-admin@example.com")
	listing := seedListing(t, db, "Aurora Quintet", 80000)

	status, out := customer.do("POST", "/api/manager-chat/start", map[string]any{
		"listing_id": listing.ID, "message": "Свободны ли они 20 июня?",
	})
	if status != http.StatusOK {
		t.Fatalf("start chat: %d %v", status, out)
	}
	conv := out["conversation"].(map[string]any)
	if conv["event_id"] != nil {
		t.Fatalf("a catalog-page chat must not carry an event_id, got %v", conv["event_id"])
	}
	listingOut := conv["listing"].(map[string]any)
	if listingOut["name_ru"] != "Aurora Quintet" || listingOut["price"].(float64) != 80000 {
		t.Fatalf("conversation should carry the service context (name+price), got %v", listingOut)
	}
	convID := int(conv["id"].(float64))
	messages := out["messages"].([]any)
	if len(messages) != 1 || messages[0].(map[string]any)["sender_type"] != "user" {
		t.Fatalf("expected exactly 1 user message, got %v", messages)
	}

	// Admin sees it in the dialog list with the right context + unread count.
	status, list := admin.do("GET", "/api/admin/manager-chat", nil)
	if status != http.StatusOK {
		t.Fatalf("admin list: %d %v", status, list)
	}
	var found map[string]any
	for _, c := range list["conversations"].([]any) {
		cm := c.(map[string]any)
		if int(cm["id"].(float64)) == convID {
			found = cm
		}
	}
	if found == nil {
		t.Fatalf("admin should see the new conversation")
	}
	if found["unread_count"].(float64) != 1 {
		t.Fatalf("expected unread_count=1 before admin opens it, got %v", found["unread_count"])
	}
	lastMsg := found["last_message"].(map[string]any)
	if lastMsg["body"] != "Свободны ли они 20 июня?" {
		t.Fatalf("last_message preview should be the customer's message, got %v", lastMsg)
	}

	// Admin opens it -> unread flips to 0, and admin can reply.
	status, detail := admin.do("GET", "/api/admin/manager-chat/"+itoa(convID), nil)
	if status != http.StatusOK {
		t.Fatalf("admin get: %d %v", status, detail)
	}
	status, list2 := admin.do("GET", "/api/admin/manager-chat", nil)
	for _, c := range list2["conversations"].([]any) {
		cm := c.(map[string]any)
		if int(cm["id"].(float64)) == convID && cm["unread_count"].(float64) != 0 {
			t.Fatalf("opening the conversation should mark the customer's message read, unread_count=%v", cm["unread_count"])
		}
	}

	status, replyOut := admin.do("POST", "/api/admin/manager-chat/"+itoa(convID)+"/messages", map[string]any{"body": "Да, свободны!"})
	if status != http.StatusOK {
		t.Fatalf("admin reply: %d %v", status, replyOut)
	}
	replyMsgs := replyOut["messages"].([]any)
	last := replyMsgs[len(replyMsgs)-1].(map[string]any)
	if last["sender_type"] != "manager" || last["body"] != "Да, свободны!" {
		t.Fatalf("expected the reply to be recorded as sender_type=manager, got %v", last)
	}

	// Customer polls -> sees the reply, and opening it marks it read on
	// their side.
	status, custView := customer.do("GET", "/api/manager-chat/"+itoa(convID), nil)
	if status != http.StatusOK {
		t.Fatalf("customer get: %d %v", status, custView)
	}
	custMsgs := custView["messages"].([]any)
	if len(custMsgs) != 2 {
		t.Fatalf("customer should see both messages, got %v", custMsgs)
	}
}

// TestManagerChatEventContext covers section 19/21: a chat started from
// inside an event workspace carries both event_id and listing_id, and a
// non-member cannot spoof someone else's event_id into their own chat.
func TestManagerChatEventContext(t *testing.T) {
	srv, db := setupTestServer(t)
	base := srv.URL

	owner := registerUser(t, base, "Aigerim", "chat-event-owner@example.com")
	outsider := registerUser(t, base, "Outsider", "chat-event-outsider@example.com")
	listing := seedListing(t, db, "Grand Hall Chat", 500000)

	_, evOut := owner.do("POST", "/api/events", map[string]any{"title": "Свадьба сына", "type": "wedding", "city": "Алматы", "guests": 150, "budget_total": 3000000})
	eventID := int(evOut["event"].(map[string]any)["id"].(float64))

	status, out := owner.do("POST", "/api/manager-chat/start", map[string]any{
		"event_id": eventID, "listing_id": listing.ID, "message": "Спросить MEREYTOI про этот зал",
	})
	if status != http.StatusOK {
		t.Fatalf("start chat with event context: %d %v", status, out)
	}
	conv := out["conversation"].(map[string]any)
	if int(conv["event_id"].(float64)) != eventID {
		t.Fatalf("expected event_id=%d, got %v", eventID, conv["event_id"])
	}
	eventOut := conv["event"].(map[string]any)
	if eventOut["title"] != "Свадьба сына" || eventOut["city"] != "Алматы" {
		t.Fatalf("conversation should carry the event context, got %v", eventOut)
	}

	// An outsider cannot attach someone else's event to their own chat.
	status, forbidden := outsider.do("POST", "/api/manager-chat/start", map[string]any{
		"event_id": eventID, "message": "пробую подделать событие",
	})
	if status != http.StatusForbidden {
		t.Fatalf("a non-member must be rejected when spoofing event_id, got %d %v", status, forbidden)
	}

	// The outsider cannot open the owner's conversation directly either.
	convID := int(conv["id"].(float64))
	status, _ = outsider.do("GET", "/api/manager-chat/"+itoa(convID), nil)
	if status != http.StatusNotFound {
		t.Fatalf("a stranger must get 404 (not 403) opening someone else's conversation, got %d", status)
	}
}

// TestManagerChatReuseSameContext covers the "same context reopens the
// same thread" behavior the widget relies on (brief sections 17/21 — the
// widget calls /start every time it opens, not just once).
func TestManagerChatReuseSameContext(t *testing.T) {
	srv, _ := setupTestServer(t)
	base := srv.URL

	customer := registerUser(t, base, "Rustem", "chat-reuse-customer@example.com")

	_, out1 := customer.do("POST", "/api/manager-chat/start", map[string]any{"message": "Общий вопрос"})
	conv1 := int(out1["conversation"].(map[string]any)["id"].(float64))

	_, out2 := customer.do("POST", "/api/manager-chat/start", map[string]any{"message": "Ещё один общий вопрос"})
	conv2 := int(out2["conversation"].(map[string]any)["id"].(float64))

	if conv1 != conv2 {
		t.Fatalf("two general (no context) chats from the same user should reuse one open conversation, got %d and %d", conv1, conv2)
	}
	msgs := out2["messages"].([]any)
	if len(msgs) != 2 {
		t.Fatalf("expected both messages in the one reused conversation, got %d", len(msgs))
	}
}

// TestManagerChatPeekWithoutMessage covers the "open the chat and see
// context before typing anything" requirement (brief section 17/20): an
// empty message neither creates a conversation nor errors, and once a real
// one exists, an empty-message peek just returns its current state.
func TestManagerChatPeekWithoutMessage(t *testing.T) {
	srv, db := setupTestServer(t)
	base := srv.URL

	customer := registerUser(t, base, "Peek", "chat-peek-customer@example.com")
	listing := seedListing(t, db, "Peek Hall", 100000)

	status, out := customer.do("POST", "/api/manager-chat/start", map[string]any{"listing_id": listing.ID, "message": ""})
	if status != http.StatusOK {
		t.Fatalf("peek with no prior conversation: %d %v", status, out)
	}
	if out["conversation"] != nil {
		t.Fatalf("peeking with no message and no prior conversation must not create one, got %v", out["conversation"])
	}
	if msgs, ok := out["messages"].([]any); !ok || len(msgs) != 0 {
		t.Fatalf("expected an empty messages list, got %v", out["messages"])
	}

	// Now send a real message, creating the conversation...
	_, real := customer.do("POST", "/api/manager-chat/start", map[string]any{"listing_id": listing.ID, "message": "Реальный вопрос"})
	convID := int(real["conversation"].(map[string]any)["id"].(float64))

	// ...and peek again: same conversation, no duplicate message added.
	status, peek2 := customer.do("POST", "/api/manager-chat/start", map[string]any{"listing_id": listing.ID, "message": ""})
	if status != http.StatusOK {
		t.Fatalf("peek after a real conversation exists: %d %v", status, peek2)
	}
	if int(peek2["conversation"].(map[string]any)["id"].(float64)) != convID {
		t.Fatalf("peek should return the same existing conversation")
	}
	if msgs := peek2["messages"].([]any); len(msgs) != 1 {
		t.Fatalf("peek with an empty message must not add a new message, got %d", len(msgs))
	}
}

// TestManagerChatStatusUpdate covers the admin-only close/reopen action.
func TestManagerChatStatusUpdate(t *testing.T) {
	srv, db := setupTestServer(t)
	base := srv.URL

	customer := registerUser(t, base, "Bota", "chat-status-customer@example.com")
	admin := registerAdmin(t, base, db, "Manager", "chat-status-admin@example.com")

	_, out := customer.do("POST", "/api/manager-chat/start", map[string]any{"message": "Вопрос"})
	convID := int(out["conversation"].(map[string]any)["id"].(float64))

	status, _ := admin.do("POST", "/api/admin/manager-chat/"+itoa(convID)+"/status", map[string]any{"status": "closed"})
	if status != http.StatusOK {
		t.Fatalf("admin should be able to close a conversation, got %d", status)
	}

	// A non-admin cannot change status.
	status, _ = customer.do("POST", "/api/admin/manager-chat/"+itoa(convID)+"/status", map[string]any{"status": "open"})
	if status != http.StatusForbidden {
		t.Fatalf("a customer must not reach the admin status endpoint, got %d", status)
	}
}
