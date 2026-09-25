package aiassistant

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"gorm.io/gorm"
)

// ErrNotConfigured is returned by Ask when no Provider is wired up (no API
// key configured) — the handler maps this to a clear "assistant
// unavailable" response rather than a generic 500, and nothing else on the
// site (Manager Chat, bookings, catalog) is affected either way, since
// this package is never on any of those call paths.
var ErrNotConfigured = errors.New("aiassistant: provider not configured")

// Service ties a Provider to this project's own DB-backed search tool —
// the "получать подходящие варианты через существующий Go API и базу
// данных" half of the brief. DB is used directly (plain GORM queries via
// SearchVenues), not through an HTTP call to /api/listings, because that
// endpoint has no city/guest/budget filters (see the stage report).
type Service struct {
	Provider Provider
	DB       *gorm.DB
}

func NewService(provider Provider, db *gorm.DB) *Service {
	return &Service{Provider: provider, DB: db}
}

type AskRequest struct {
	// Locale is a *hint* for which language to answer in (matches the
	// site's own ru/kz/en toggle) — the assistant still follows the
	// customer's own message language when it's unambiguous, since brief
	// section 2 requires understanding all three regardless of this value.
	Locale   string
	Messages []ChatMessage
}

type AskResponse struct {
	Reply string
	// Listings is exactly the last search_venues result the model saw —
	// returned separately from Reply so the frontend can render real,
	// clickable cards deterministically, instead of relying on the model
	// to format links correctly inside its prose every time.
	Listings []VenueResult
}

// Ask runs one full turn: the model may call search_venues zero or more
// times against the real database before producing its final reply.
func (s *Service) Ask(ctx context.Context, req AskRequest) (AskResponse, error) {
	if s.Provider == nil {
		return AskResponse{}, ErrNotConfigured
	}

	var lastResults []VenueResult
	execute := func(ctx context.Context, call ToolCall) (string, bool) {
		if call.Name != SearchVenuesTool.Name {
			return fmt.Sprintf("unknown tool %q", call.Name), true
		}
		var args SearchVenuesArgs
		if err := json.Unmarshal(call.Input, &args); err != nil {
			return "invalid search arguments", true
		}
		results, err := SearchVenues(s.DB, args)
		if err != nil {
			return "поиск временно недоступен (ошибка базы данных)", true
		}
		lastResults = results
		return encodeSearchResults(results), false
	}

	reply, err := s.Provider.Chat(ctx, ChatRequest{
		System:   systemPrompt(req.Locale),
		Messages: req.Messages,
		Tools:    []ToolSpec{SearchVenuesTool},
		Execute:  execute,
	})
	if err != nil {
		return AskResponse{}, err
	}

	return AskResponse{Reply: reply, Listings: lastResults}, nil
}

func systemPrompt(locale string) string {
	lang := "русском"
	switch locale {
	case "kz":
		lang = "казахском"
	case "en":
		lang = "английском"
	}

	return "Ты — ИИ-помощник MEREYTOI, сайта организации той/мероприятий в Казахстане. " +
		"Твоя единственная задача на этом этапе — помочь клиенту подобрать ресторан/зал для мероприятия.\n\n" +
		"Правила, которые нельзя нарушать:\n" +
		"1. Для любого конкретного варианта (название, цена, вместимость, адрес) вызывай инструмент search_venues " +
		"и используй только то, что он вернул. Никогда не придумывай и не досочиняй такие данные, даже приблизительно.\n" +
		"2. В базе данных MEREYTOI нет календаря занятости залов — ты физически не можешь знать, свободна ли " +
		"конкретная дата. На любой вопрос о доступности даты отвечай честно: точно сказать нельзя, это нужно " +
		"уточнить у менеджера MEREYTOI (предложи написать в чат менеджеру на сайте).\n" +
		"3. Если search_venues вернул пустой список — прямо скажи, что подходящих вариантов не нашлось, и " +
		"предложи связаться с менеджером, а не предлагай что-то от себя.\n" +
		"4. Если для поиска не хватает города, числа гостей или бюджета — можешь один раз коротко уточнить у " +
		"клиента, но если часть данных уже есть, всё равно сделай поиск с тем, что известно, и покажи результат, " +
		"а не жди все ответы подряд.\n" +
		"5. Если у найденного варианта неизвестна вместимость или цена (capacity_known/price_known = false в " +
		"результате инструмента) — так и скажи клиенту, что эту цифру нужно уточнить, не оценивай её сама.\n" +
		"6. Коротко объясняй, почему предложен именно этот вариант (город/вместимость/бюджет совпали).\n" +
		"7. Никогда не подтверждай бронирование, оплату или точную стоимость — только предварительный ориентир.\n\n" +
		fmt.Sprintf("Отвечай на %s языке, если из сообщения клиента явно не следует другой язык — тогда отвечай на его языке. ", lang) +
		"Пиши кратко и по-человечески, без списков на каждую мелочь."
}
