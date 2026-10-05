package routes_test

import (
	"net/http"
	"testing"
)

// TestManagerChatListOwnConversationsOnly covers the customer-side
// GET /api/manager-chat: each user sees exactly their own conversations
// (never another customer's), anonymous callers get 401, another user's
// conversation stays unreachable by id, and unread_count counts only the
// manager's unread replies — dropping to 0 once the customer opens the
// thread.
func TestManagerChatListOwnConversationsOnly(t *testing.T) {
	srv, db := setupTestServer(t)
	base := srv.URL

	alice := registerUser(t, base, "Alice", "mlist-alice@example.com")
	bob := registerUser(t, base, "Bob", "mlist-bob@example.com")
	admin := registerAdmin(t, base, db, "Manager", "mlist-admin@example.com")
	listing := seedListing(t, db, "MList Aurora Quintet", 80000)

	// Alice: a general thread and a service-context thread.
	_, general := alice.do("POST", "/api/manager-chat/start", map[string]any{"message": "Общий вопрос"})
	aliceGeneralID := int(general["conversation"].(map[string]any)["id"].(float64))
	aliceUserID := int(general["conversation"].(map[string]any)["user_id"].(float64))
	_, svc := alice.do("POST", "/api/manager-chat/start", map[string]any{"listing_id": listing.ID, "message": "Свободны 20 июня?"})
	aliceSvcID := int(svc["conversation"].(map[string]any)["id"].(float64))
	// Bob: one thread of his own.
	_, bobConv := bob.do("POST", "/api/manager-chat/start", map[string]any{"message": "Вопрос Боба"})
	bobID := int(bobConv["conversation"].(map[string]any)["id"].(float64))

	// Manager replies twice in Alice's service thread, once in Bob's.
	admin.do("POST", "/api/admin/manager-chat/"+itoa(aliceSvcID)+"/messages", map[string]any{"body": "Да, свободны"})
	admin.do("POST", "/api/admin/manager-chat/"+itoa(aliceSvcID)+"/messages", map[string]any{"body": "Отправить смету?"})
	admin.do("POST", "/api/admin/manager-chat/"+itoa(bobID)+"/messages", map[string]any{"body": "Ответ Бобу"})

	// Anonymous -> 401.
	status, _ := apiClient{t: t, base: base}.do("GET", "/api/manager-chat", nil)
	if status != http.StatusUnauthorized {
		t.Fatalf("anonymous list should be 401, got %d", status)
	}

	// Alice sees exactly her two conversations, newest activity first.
	status, out := alice.do("GET", "/api/manager-chat", nil)
	if status != http.StatusOK {
		t.Fatalf("alice list: %d %v", status, out)
	}
	convs := out["conversations"].([]any)
	if len(convs) != 2 {
		t.Fatalf("alice should see exactly her 2 conversations, got %d: %v", len(convs), convs)
	}
	byID := map[int]map[string]any{}
	for _, c := range convs {
		cm := c.(map[string]any)
		id := int(cm["id"].(float64))
		if id == bobID {
			t.Fatalf("alice must never see bob's conversation")
		}
		if int(cm["user_id"].(float64)) != aliceUserID {
			t.Fatalf("every listed conversation must belong to alice, got %v", cm["user_id"])
		}
		byID[id] = cm
	}
	if int(convs[0].(map[string]any)["id"].(float64)) != aliceSvcID {
		t.Fatalf("the thread with the latest activity should come first")
	}

	svcRow := byID[aliceSvcID]
	if svcRow["unread_count"].(float64) != 2 {
		t.Fatalf("service thread should have 2 unread manager replies, got %v", svcRow["unread_count"])
	}
	if svcRow["last_message"].(map[string]any)["body"] != "Отправить смету?" {
		t.Fatalf("last_message should be the newest reply, got %v", svcRow["last_message"])
	}
	if svcRow["listing"].(map[string]any)["name_ru"] != "MList Aurora Quintet" {
		t.Fatalf("service context should be included, got %v", svcRow["listing"])
	}
	if byID[aliceGeneralID]["unread_count"].(float64) != 0 {
		t.Fatalf("alice's own message must not count as unread for her, got %v", byID[aliceGeneralID]["unread_count"])
	}

	// Opening the thread marks the manager's replies read -> unread 0.
	alice.do("GET", "/api/manager-chat/"+itoa(aliceSvcID), nil)
	_, out = alice.do("GET", "/api/manager-chat", nil)
	for _, c := range out["conversations"].([]any) {
		cm := c.(map[string]any)
		if int(cm["id"].(float64)) == aliceSvcID && cm["unread_count"].(float64) != 0 {
			t.Fatalf("unread_count should be 0 after opening, got %v", cm["unread_count"])
		}
	}

	// Bob sees only his own, with his 1 unread reply.
	_, bobOut := bob.do("GET", "/api/manager-chat", nil)
	bobConvs := bobOut["conversations"].([]any)
	if len(bobConvs) != 1 || int(bobConvs[0].(map[string]any)["id"].(float64)) != bobID {
		t.Fatalf("bob should see exactly his own conversation, got %v", bobConvs)
	}
	if bobConvs[0].(map[string]any)["unread_count"].(float64) != 1 {
		t.Fatalf("bob should have 1 unread reply, got %v", bobConvs[0].(map[string]any)["unread_count"])
	}

	// Another user's conversation stays unreachable by id (read or write).
	if status, _ := alice.do("GET", "/api/manager-chat/"+itoa(bobID), nil); status != http.StatusNotFound {
		t.Fatalf("alice opening bob's conversation should be 404, got %d", status)
	}
	if status, _ := alice.do("POST", "/api/manager-chat/"+itoa(bobID)+"/messages", map[string]any{"body": "hi"}); status != http.StatusNotFound {
		t.Fatalf("alice posting into bob's conversation should be 404, got %d", status)
	}
}
