package routes_test

import (
	"encoding/json"
	"net/http"
	"testing"

	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// registerProvider registers a fresh user via the real /api/auth/register
// endpoint (so its password/login work exactly like any real account, no
// fabricated password hashes needed) and creates their Provider profile via
// the real POST /api/provider endpoint — returning both the authenticated
// client and the created Provider so tests can address it by id.
func registerProvider(t *testing.T, base, name, email, displayName string) (apiClient, models.Provider) {
	t.Helper()
	c := registerUser(t, base, name, email)
	status, out := c.do("POST", "/api/provider", map[string]any{"display_name": displayName})
	if status != http.StatusCreated {
		t.Fatalf("create provider profile for %s: %d %v", email, status, out)
	}
	raw, _ := json.Marshal(out["provider"])
	var p models.Provider
	if err := json.Unmarshal(raw, &p); err != nil {
		t.Fatalf("decode created provider: %v", err)
	}
	return c, p
}

// linkListingToProvider assigns listingID's ListingManager(role=owner) row
// to providerUserID, mirroring what ListingHandler.CreateOwn does for a
// self-serve listing.
func linkListingToProvider(t *testing.T, db *gorm.DB, listingID, providerUserID uint) {
	t.Helper()
	m := models.ListingManager{ListingID: listingID, UserID: providerUserID, Role: models.ListingManagerRoleOwner}
	if err := db.Create(&m).Error; err != nil {
		t.Fatalf("link listing to provider: %v", err)
	}
}

// TestProviderChatStartReplyAndPublicProfile covers the end-to-end happy
// path: a customer looks up the provider's public profile, starts a chat
// from the service page, the provider replies, and the customer sees the
// reply — brief section 9's device-QA scenario, exercised over HTTP.
func TestProviderChatStartReplyAndPublicProfile(t *testing.T) {
	srv, db := setupTestServer(t)
	base := srv.URL

	customer := registerUser(t, base, "Madina", "pchat-customer@example.com")
	providerClient, provider := registerProvider(t, base, "Ерлан", "pchat-provider@example.com", "Ерлан Events")
	listing := seedListing(t, db, "Ерлан's Show", 50000)
	linkListingToProvider(t, db, listing.ID, provider.UserID)

	// Public provider profile — no auth, no internal ids leaked.
	status, profile := apiClient{t: t, base: base}.do("GET", "/api/providers/"+itoa(int(provider.ID)), nil)
	if status != http.StatusOK {
		t.Fatalf("public provider profile: %d %v", status, profile)
	}
	providerOut := profile["provider"].(map[string]any)
	if providerOut["display_name"] != "Ерлан Events" {
		t.Fatalf("expected display_name, got %v", providerOut)
	}
	if _, leaked := providerOut["user_id"]; leaked {
		t.Fatalf("public provider profile must never include user_id, got %v", providerOut)
	}
	if profile["listing_count"].(float64) != 1 {
		t.Fatalf("expected listing_count=1, got %v", profile["listing_count"])
	}
	listings := profile["listings"].([]any)
	if len(listings) != 1 || listings[0].(map[string]any)["name_ru"] != "Ерлан's Show" {
		t.Fatalf("expected the provider's published listing, got %v", listings)
	}

	// Customer starts the chat from the service page.
	status, out := customer.do("POST", "/api/provider-chat/start", map[string]any{
		"provider_id": provider.ID, "listing_id": listing.ID, "message": "Свободны на 20 июня?",
	})
	if status != http.StatusOK {
		t.Fatalf("start chat: %d %v", status, out)
	}
	conv := out["conversation"].(map[string]any)
	if _, leaked := conv["provider"].(map[string]any)["user_id"]; leaked {
		t.Fatalf("conversation.provider must never include user_id, got %v", conv["provider"])
	}
	convID := int(conv["id"].(float64))
	messages := out["messages"].([]any)
	if len(messages) != 1 || messages[0].(map[string]any)["body"] != "Свободны на 20 июня?" {
		t.Fatalf("expected exactly 1 customer message, got %v", messages)
	}

	// Provider sees it in their own conversation list, with the right preview.
	status, list := providerClient.do("GET", "/api/provider-chat", nil)
	if status != http.StatusOK {
		t.Fatalf("provider list: %d %v", status, list)
	}
	convs := list["conversations"].([]any)
	if len(convs) != 1 {
		t.Fatalf("expected the provider to see exactly 1 conversation, got %v", convs)
	}
	row := convs[0].(map[string]any)
	if row["unread_count"].(float64) != 1 {
		t.Fatalf("expected unread_count=1 before the provider opens it, got %v", row["unread_count"])
	}

	// Provider opens it -> unread flips to 0 -> replies.
	status, detail := providerClient.do("GET", "/api/provider-chat/"+itoa(convID), nil)
	if status != http.StatusOK {
		t.Fatalf("provider get: %d %v", status, detail)
	}
	status, list2 := providerClient.do("GET", "/api/provider-chat", nil)
	if status != http.StatusOK || list2["conversations"].([]any)[0].(map[string]any)["unread_count"].(float64) != 0 {
		t.Fatalf("opening the conversation should mark the customer's message read: %d %v", status, list2)
	}

	status, replyOut := providerClient.do("POST", "/api/provider-chat/"+itoa(convID)+"/messages", map[string]any{"body": "Да, свободны!"})
	if status != http.StatusOK {
		t.Fatalf("provider reply: %d %v", status, replyOut)
	}
	replyMsgs := replyOut["messages"].([]any)
	last := replyMsgs[len(replyMsgs)-1].(map[string]any)
	if last["body"] != "Да, свободны!" || int(last["sender_user_id"].(float64)) == 0 {
		t.Fatalf("expected the reply recorded with a sender_user_id, got %v", last)
	}

	// Customer polls -> sees the reply.
	status, custView := customer.do("GET", "/api/provider-chat/"+itoa(convID), nil)
	if status != http.StatusOK {
		t.Fatalf("customer get: %d %v", status, custView)
	}
	custMsgs := custView["messages"].([]any)
	if len(custMsgs) != 2 {
		t.Fatalf("customer should see both messages, got %v", custMsgs)
	}
}

// TestProviderChatDedup covers "a repeated /start for the same
// customer/provider/listing tuple reuses one conversation, never spawns
// duplicates" — brief section 3's explicit requirement.
func TestProviderChatDedup(t *testing.T) {
	srv, db := setupTestServer(t)
	base := srv.URL

	customer := registerUser(t, base, "Rustem", "pchat-dedup-customer@example.com")
	_, provider := registerProvider(t, base, "Айгуль", "pchat-dedup-provider@example.com", "Айгуль Decor")
	listing := seedListing(t, db, "Decor Hall", 30000)
	linkListingToProvider(t, db, listing.ID, provider.UserID)

	_, out1 := customer.do("POST", "/api/provider-chat/start", map[string]any{
		"provider_id": provider.ID, "listing_id": listing.ID, "message": "Вопрос 1",
	})
	conv1 := int(out1["conversation"].(map[string]any)["id"].(float64))

	_, out2 := customer.do("POST", "/api/provider-chat/start", map[string]any{
		"provider_id": provider.ID, "listing_id": listing.ID, "message": "Вопрос 2",
	})
	conv2 := int(out2["conversation"].(map[string]any)["id"].(float64))

	if conv1 != conv2 {
		t.Fatalf("repeated /start for the same (customer, provider, listing) must reuse one conversation, got %d and %d", conv1, conv2)
	}
	msgs := out2["messages"].([]any)
	if len(msgs) != 2 {
		t.Fatalf("expected both messages in the one reused conversation, got %d", len(msgs))
	}

	// A different listing from the SAME provider gets its own conversation.
	listing2 := seedListing(t, db, "Decor Garden", 20000)
	linkListingToProvider(t, db, listing2.ID, provider.UserID)
	_, out3 := customer.do("POST", "/api/provider-chat/start", map[string]any{
		"provider_id": provider.ID, "listing_id": listing2.ID, "message": "Про другой зал",
	})
	conv3 := int(out3["conversation"].(map[string]any)["id"].(float64))
	if conv3 == conv1 {
		t.Fatalf("a different listing from the same provider must start a separate conversation")
	}
}

// TestProviderChatPeekWithoutMessage mirrors
// TestManagerChatPeekWithoutMessage: an empty message never creates a
// conversation, and once one exists, peeking again doesn't duplicate it.
func TestProviderChatPeekWithoutMessage(t *testing.T) {
	srv, _ := setupTestServer(t)
	base := srv.URL

	customer := registerUser(t, base, "Peek", "pchat-peek-customer@example.com")
	_, provider := registerProvider(t, base, "Peek Provider", "pchat-peek-provider@example.com", "Peek Co")

	status, out := customer.do("POST", "/api/provider-chat/start", map[string]any{"provider_id": provider.ID, "message": ""})
	if status != http.StatusOK {
		t.Fatalf("peek with no prior conversation: %d %v", status, out)
	}
	if out["conversation"] != nil {
		t.Fatalf("peeking with no message and no prior conversation must not create one, got %v", out["conversation"])
	}

	_, real := customer.do("POST", "/api/provider-chat/start", map[string]any{"provider_id": provider.ID, "message": "Реальный вопрос"})
	convID := int(real["conversation"].(map[string]any)["id"].(float64))

	status, peek2 := customer.do("POST", "/api/provider-chat/start", map[string]any{"provider_id": provider.ID, "message": ""})
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

// TestProviderChatSecurity is the brief's own section 8 checklist, each
// bullet as one sub-assertion: anonymous can't open a chat; customer A
// can't see customer B's chat; provider A can't see provider B's chat;
// can't message someone else's conversation; can't spoof provider_id/
// listing_id.
func TestProviderChatSecurity(t *testing.T) {
	srv, db := setupTestServer(t)
	base := srv.URL

	customerA := registerUser(t, base, "Customer A", "pchat-sec-customerA@example.com")
	customerB := registerUser(t, base, "Customer B", "pchat-sec-customerB@example.com")
	providerAClient, providerA := registerProvider(t, base, "Provider A", "pchat-sec-providerA@example.com", "Provider A Co")
	providerBClient, providerB := registerProvider(t, base, "Provider B", "pchat-sec-providerB@example.com", "Provider B Co")
	listingA := seedListing(t, db, "Listing A", 10000)
	linkListingToProvider(t, db, listingA.ID, providerA.UserID)
	listingB := seedListing(t, db, "Listing B", 10000)
	linkListingToProvider(t, db, listingB.ID, providerB.UserID)

	// --- anonymous cannot open a chat ---
	anon := apiClient{t: t, base: base}
	status, _ := anon.do("POST", "/api/provider-chat/start", map[string]any{"provider_id": providerA.ID, "message": "hi"})
	if status != http.StatusUnauthorized {
		t.Fatalf("anonymous start must be 401, got %d", status)
	}
	status, _ = anon.do("GET", "/api/provider-chat", nil)
	if status != http.StatusUnauthorized {
		t.Fatalf("anonymous list must be 401, got %d", status)
	}

	// --- customer A starts a chat with provider A ---
	_, out := customerA.do("POST", "/api/provider-chat/start", map[string]any{
		"provider_id": providerA.ID, "listing_id": listingA.ID, "message": "Вопрос от A",
	})
	convID := int(out["conversation"].(map[string]any)["id"].(float64))

	// --- customer B cannot see customer A's conversation ---
	status, _ = customerB.do("GET", "/api/provider-chat/"+itoa(convID), nil)
	if status != http.StatusNotFound {
		t.Fatalf("customer B opening customer A's conversation must be 404, got %d", status)
	}
	// --- customer B cannot post into it either ---
	status, _ = customerB.do("POST", "/api/provider-chat/"+itoa(convID)+"/messages", map[string]any{"body": "подслушиваю"})
	if status != http.StatusNotFound {
		t.Fatalf("customer B posting into customer A's conversation must be 404, got %d", status)
	}

	// --- provider B cannot see provider A's conversation ---
	status, _ = providerBClient.do("GET", "/api/provider-chat/"+itoa(convID), nil)
	if status != http.StatusNotFound {
		t.Fatalf("provider B opening provider A's conversation must be 404, got %d", status)
	}
	status, _ = providerBClient.do("POST", "/api/provider-chat/"+itoa(convID)+"/messages", map[string]any{"body": "подслушиваю"})
	if status != http.StatusNotFound {
		t.Fatalf("provider B posting into provider A's conversation must be 404, got %d", status)
	}

	// --- provider B doesn't even see it in their own list ---
	status, listB := providerBClient.do("GET", "/api/provider-chat", nil)
	if status != http.StatusOK {
		t.Fatalf("provider B list: %d %v", status, listB)
	}
	if convs, _ := listB["conversations"].([]any); len(convs) != 0 {
		t.Fatalf("provider B's conversation list must not include provider A's conversation, got %v", convs)
	}

	// --- provider A (the real participant) CAN see and reply ---
	status, detail := providerAClient.do("GET", "/api/provider-chat/"+itoa(convID), nil)
	if status != http.StatusOK {
		t.Fatalf("the actual provider participant must be able to open the conversation, got %d %v", status, detail)
	}
	status, reply := providerAClient.do("POST", "/api/provider-chat/"+itoa(convID)+"/messages", map[string]any{"body": "Да, свободны!"})
	if status != http.StatusOK {
		t.Fatalf("the actual provider participant must be able to reply, got %d %v", status, reply)
	}

	// --- cannot spoof provider_id: listing_id belongs to a different
	// provider than the one named in provider_id ---
	status, spoof := customerA.do("POST", "/api/provider-chat/start", map[string]any{
		"provider_id": providerA.ID, "listing_id": listingB.ID, "message": "подделка",
	})
	if status != http.StatusBadRequest {
		t.Fatalf("mismatched provider_id/listing_id must be rejected with 400, got %d %v", status, spoof)
	}

	// --- a provider cannot message their own profile (degenerate case,
	// not itself a security hole but must not silently create a self-chat) ---
	status, selfChat := providerAClient.do("POST", "/api/provider-chat/start", map[string]any{
		"provider_id": providerA.ID, "message": "себе",
	})
	if status != http.StatusBadRequest {
		t.Fatalf("a provider messaging their own profile must be rejected, got %d %v", status, selfChat)
	}
}
