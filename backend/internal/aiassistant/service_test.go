package aiassistant_test

import (
	"context"
	"encoding/json"
	"errors"
	"testing"

	"github.com/almukhanbetov/mereytoi/backend/internal/aiassistant"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// stubProvider is a fake Provider — it calls req.Execute itself (as a real
// model would, via a tool_use turn) and returns a canned reply, so
// Service.Ask's own wiring (tool dispatch -> DB search -> Listings on the
// response) is testable without ever reaching a real LLM API.
type stubProvider struct {
	toolInput json.RawMessage
	reply     string
	err       error
}

func (s stubProvider) Chat(ctx context.Context, req aiassistant.ChatRequest) (string, error) {
	if s.err != nil {
		return "", s.err
	}
	if s.toolInput != nil {
		result, isErr := req.Execute(ctx, aiassistant.ToolCall{Name: aiassistant.SearchVenuesTool.Name, Input: s.toolInput})
		if isErr {
			return "", errors.New("tool call failed: " + result)
		}
	}
	return s.reply, nil
}

func TestServiceAskReturnsSearchResultsAlongsideReply(t *testing.T) {
	db := setupDB(t)
	cat := venuesCategory(t, db)
	listing := models.Listing{CategoryID: cat.ID, NameRu: "Panorama", NameKz: "Panorama", City: "Алматы", IsActive: true}
	db.Create(&listing)
	db.Create(&models.ListingHall{ListingID: listing.ID, NameRu: "Зал", NameKz: "Зал", Capacity: 150, IsActive: true})

	provider := stubProvider{
		toolInput: json.RawMessage(`{"city":"Алматы","guest_count":120}`),
		reply:     "Нашёл вариант в Алматы на 150 гостей — Panorama.",
	}
	svc := aiassistant.NewService(provider, db)

	resp, err := svc.Ask(context.Background(), aiassistant.AskRequest{
		Locale:   "ru",
		Messages: []aiassistant.ChatMessage{{Role: aiassistant.RoleUser, Content: "Нужен зал в Алматы на 120 гостей"}},
	})
	if err != nil {
		t.Fatalf("ask: %v", err)
	}
	if resp.Reply != provider.reply {
		t.Fatalf("expected the provider's reply verbatim, got %q", resp.Reply)
	}
	if len(resp.Listings) != 1 || resp.Listings[0].NameRu != "Panorama" {
		t.Fatalf("expected the real search result on the response, got %+v", resp.Listings)
	}
}

// Scenario 5 (stage brief section 4): no provider configured (no API key)
// must fail predictably with ErrNotConfigured — the handler maps this to a
// clear "unavailable" response rather than the assistant silently
// misbehaving or the request hanging.
func TestServiceAskWithoutProviderIsNotConfigured(t *testing.T) {
	db := setupDB(t)
	svc := aiassistant.NewService(nil, db)

	_, err := svc.Ask(context.Background(), aiassistant.AskRequest{
		Messages: []aiassistant.ChatMessage{{Role: aiassistant.RoleUser, Content: "Привет"}},
	})
	if !errors.Is(err, aiassistant.ErrNotConfigured) {
		t.Fatalf("expected ErrNotConfigured, got %v", err)
	}
}
