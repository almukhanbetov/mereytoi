package routes_test

import (
	"net/http"
	"testing"
)

// TestManagerChatNotifications covers Этап 12A: a customer's message
// notifies every admin (manager_chat_user_message), a manager's reply
// notifies the conversation's customer (manager_message_received), both
// deep-linking to the conversation itself, and nobody is notified about
// their own message.
func TestManagerChatNotifications(t *testing.T) {
	srv, db := setupTestServer(t)
	base := srv.URL

	customer := registerUser(t, base, "Madina", "mchat-notif-customer@example.com")
	admin := registerAdmin(t, base, db, "Manager", "mchat-notif-admin@example.com")
	listing := seedListing(t, db, "Notif Aurora Quintet", 80000)

	status, out := customer.do("POST", "/api/manager-chat/start", map[string]any{
		"listing_id": listing.ID, "message": "Свободны ли они 20 июня?",
	})
	if status != http.StatusOK {
		t.Fatalf("start chat: %d %v", status, out)
	}
	convID := int(out["conversation"].(map[string]any)["id"].(float64))

	// A bare peek (no message) must never notify anyone.
	customer.do("POST", "/api/manager-chat/start", map[string]any{"listing_id": listing.ID})

	_, adminNotifs := admin.do("GET", "/api/notifications", nil)
	if n := countNotifs(adminNotifs, "manager_chat_user_message"); n != 1 {
		t.Fatalf("admin should get exactly 1 notification for the customer's message, got %d: %v", n, adminNotifs)
	}
	n := findNotif(adminNotifs, "manager_chat_user_message")
	if n["entity_type"] != "manager_conversation" || int(n["entity_id"].(float64)) != convID {
		t.Fatalf("admin notification should deep-link to the conversation, got %v", n)
	}
	if n["event_id"] != nil {
		t.Fatalf("manager chat notifications must not be event-scoped, got event_id=%v", n["event_id"])
	}
	payload := n["payload"].(map[string]any)
	if payload["body"] != "Свободны ли они 20 июня?" || int(payload["listing_id"].(float64)) != int(listing.ID) {
		t.Fatalf("admin notification payload should carry body+listing_id, got %v", payload)
	}

	_, custNotifs := customer.do("GET", "/api/notifications", nil)
	if countNotifs(custNotifs, "manager_chat_user_message")+countNotifs(custNotifs, "manager_message_received") != 0 {
		t.Fatalf("the customer must not be notified about their own message, got %v", custNotifs)
	}

	// Admin replies -> customer is notified, admin is not.
	status, replyOut := admin.do("POST", "/api/admin/manager-chat/"+itoa(convID)+"/messages", map[string]any{"body": "Да, свободны!"})
	if status != http.StatusOK {
		t.Fatalf("admin reply: %d %v", status, replyOut)
	}
	_, custNotifs = customer.do("GET", "/api/notifications", nil)
	reply := findNotif(custNotifs, "manager_message_received")
	if reply == nil {
		t.Fatalf("customer should be notified about the manager's reply, got %v", custNotifs)
	}
	if reply["entity_type"] != "manager_conversation" || int(reply["entity_id"].(float64)) != convID {
		t.Fatalf("reply notification should deep-link to the conversation, got %v", reply)
	}
	replyPayload := reply["payload"].(map[string]any)
	if replyPayload["body"] != "Да, свободны!" || int(replyPayload["listing_id"].(float64)) != int(listing.ID) {
		t.Fatalf("reply payload should carry body+listing_id, got %v", replyPayload)
	}
	_, adminNotifs = admin.do("GET", "/api/notifications", nil)
	if countNotifs(adminNotifs, "manager_message_received") != 0 {
		t.Fatalf("the admin must not be notified about their own reply, got %v", adminNotifs)
	}

	// The notification id opens exactly that conversation on the customer's side.
	status, detail := customer.do("GET", "/api/manager-chat/"+itoa(convID), nil)
	if status != http.StatusOK || len(detail["messages"].([]any)) != 2 {
		t.Fatalf("customer should open the notified conversation by id: %d %v", status, detail)
	}

	// Mark-as-read on the notification still works and drops the badge.
	_, unread := customer.do("GET", "/api/notifications/unread-count", nil)
	before := unread["count"].(float64)
	status, _ = customer.do("POST", "/api/notifications/"+itoa(int(reply["id"].(float64)))+"/read", nil)
	if status != http.StatusOK {
		t.Fatalf("mark read: %d", status)
	}
	_, unread = customer.do("GET", "/api/notifications/unread-count", nil)
	if unread["count"].(float64) != before-1 {
		t.Fatalf("unread count should drop by 1 after mark-read: before=%v after=%v", before, unread["count"])
	}

	// Customer follow-up via AddMessage also notifies admins.
	customer.do("POST", "/api/manager-chat/"+itoa(convID)+"/messages", map[string]any{"body": "Спасибо!"})
	_, adminNotifs = admin.do("GET", "/api/notifications", nil)
	if n := countNotifs(adminNotifs, "manager_chat_user_message"); n != 2 {
		t.Fatalf("admin should now have 2 customer-message notifications, got %d", n)
	}
}

// TestProviderChatNotificationPayload covers Этап 12B's backend half: the
// provider_message_received payload carries provider_id/listing_id and the
// sender's name as the recipient knows them, so the client can open the
// exact ProviderChatScreen without any extra lookup.
func TestProviderChatNotificationPayload(t *testing.T) {
	srv, db := setupTestServer(t)
	base := srv.URL

	customer := registerUser(t, base, "Madina", "pchat-notif-customer@example.com")
	providerClient, provider := registerProvider(t, base, "Ерлан", "pchat-notif-provider@example.com", "Ерлан Events")
	listing := seedListing(t, db, "Notif Ерлан Show", 50000)
	linkListingToProvider(t, db, listing.ID, provider.UserID)

	status, out := customer.do("POST", "/api/provider-chat/start", map[string]any{
		"provider_id": provider.ID, "listing_id": listing.ID, "message": "Свободны на 20 июня?",
	})
	if status != http.StatusOK {
		t.Fatalf("start chat: %d %v", status, out)
	}
	convID := int(out["conversation"].(map[string]any)["id"].(float64))

	_, provNotifs := providerClient.do("GET", "/api/notifications", nil)
	n := findNotif(provNotifs, "provider_message_received")
	if n == nil || int(n["entity_id"].(float64)) != convID {
		t.Fatalf("provider should be notified with the conversation id, got %v", provNotifs)
	}
	p := n["payload"].(map[string]any)
	if int(p["provider_id"].(float64)) != int(provider.ID) || int(p["listing_id"].(float64)) != int(listing.ID) || p["sender_name"] != "Madina" {
		t.Fatalf("provider-side payload should carry provider_id/listing_id/customer name, got %v", p)
	}

	providerClient.do("POST", "/api/provider-chat/"+itoa(convID)+"/messages", map[string]any{"body": "Да!"})
	_, custNotifs := customer.do("GET", "/api/notifications", nil)
	n = findNotif(custNotifs, "provider_message_received")
	if n == nil || int(n["entity_id"].(float64)) != convID {
		t.Fatalf("customer should be notified with the conversation id, got %v", custNotifs)
	}
	p = n["payload"].(map[string]any)
	if int(p["provider_id"].(float64)) != int(provider.ID) || p["sender_name"] != "Ерлан Events" {
		t.Fatalf("customer-side payload should name the provider by display_name, got %v", p)
	}
}
