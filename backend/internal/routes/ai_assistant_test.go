package routes_test

import (
	"net/http"
	"testing"
)

// Scenario 5 (stage brief section 4): with no ANTHROPIC_API_KEY configured
// — setupTestServer's cfg never sets one — the assistant endpoint must fail
// predictably and the rest of the site (catalog, Manager Chat) must keep
// working entirely unaffected.
func TestAIAssistantUnavailableWithoutAPIKeyDoesNotBreakSite(t *testing.T) {
	srv, db := setupTestServer(t)
	base := srv.URL

	anon := apiClient{t: t, base: base}
	status, out := anon.do("POST", "/api/ai-assistant/chat", map[string]any{
		"locale":   "ru",
		"messages": []map[string]any{{"role": "user", "content": "Нужен зал в Алматы на 120 гостей"}},
	})
	if status != http.StatusServiceUnavailable {
		t.Fatalf("expected 503 with no API key configured, got %d %v", status, out)
	}
	if out["unavailable"] != true {
		t.Fatalf("expected unavailable:true, got %v", out)
	}

	// The catalog and Manager Chat are on entirely separate handlers — a
	// failing/unconfigured assistant must not affect them.
	customer := registerUser(t, base, "Aigerim", "ai-assistant-sanity-customer@example.com")
	listing := seedListing(t, db, "Sanity Venue", 50000)
	status, catalogOut := anon.do("GET", "/api/listings", nil)
	if status != http.StatusOK {
		t.Fatalf("catalog should still work: %d %v", status, catalogOut)
	}
	status, chatOut := customer.do("POST", "/api/manager-chat/start", map[string]any{
		"listing_id": listing.ID, "message": "Здравствуйте",
	})
	if status != http.StatusOK {
		t.Fatalf("manager chat should still work: %d %v", status, chatOut)
	}
}
