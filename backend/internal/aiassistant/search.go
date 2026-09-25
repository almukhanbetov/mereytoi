package aiassistant

import (
	"encoding/json"
	"fmt"

	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// VenueResult is one restaurant/venue match — every field is either
// straight off models.Listing or computed from ListingHall/ListingMenu
// rows actually in the database; nothing is estimated beyond a plain
// multiplication (EstimatedTotal), and a field the DB has no value for
// comes back with its *Known flag false rather than a guessed number —
// the model is instructed (see Service.systemPrompt) to say so rather than
// invent one.
type VenueResult struct {
	ID      uint   `json:"id"`
	NameRu  string `json:"name_ru"`
	NameKz  string `json:"name_kz"`
	City    string `json:"city,omitempty"`
	Address string `json:"address,omitempty"`

	// Capacity is the largest known capacity across this venue's active
	// halls (ListingHall.Capacity), falling back to the listing's own
	// nominal Capacity when it has no halls yet. See listing.go's own doc
	// comment on why this is deliberately not Listing.MinGuests/MaxGuests
	// (a pricing tier, not a physical capacity).
	Capacity      uint `json:"capacity,omitempty"`
	CapacityKnown bool `json:"capacity_known"`

	// PriceFrom is the cheapest starting price actually on file: the
	// lowest active menu's PricePerGuest if this venue has menus, else the
	// listing's own flat Price. PriceUnit says which, so the model never
	// has to guess what the number means.
	PriceFrom  uint   `json:"price_from,omitempty"`
	PriceUnit  string `json:"price_unit,omitempty"` // "per_guest" | "flat" | ""
	PriceKnown bool   `json:"price_known"`

	// EstimatedTotal is only set when both a guest count and a per-guest
	// price are known.
	EstimatedTotal uint    `json:"estimated_total,omitempty"`
	Rating         float32 `json:"rating"`

	// URL — matches the frontend's own `/services/:id` route, the same
	// link FloatingManagerWidget.jsx's ctxListing card already uses.
	URL string `json:"url"`
}

// SearchVenuesArgs is search_venues' input, mirrored 1:1 by
// SearchVenuesTool.InputSchema below.
type SearchVenuesArgs struct {
	City        string `json:"city"`
	GuestCount  int    `json:"guest_count"`
	BudgetTotal int    `json:"budget_total"`
	Keyword     string `json:"keyword"`
}

// SearchVenuesTool is the one function the model may call this stage —
// "получать подходящие варианты через существующий Go API и базу данных"
// (brief section 2). Deliberately the only tool for stage 1 — no
// get_listing_details/booking tool yet, so there's no way for the model to
// take any action beyond reading.
var SearchVenuesTool = ToolSpec{
	Name: "search_venues",
	Description: "Ищет реальные рестораны/залы MEREYTOI в базе данных по городу, числу гостей и бюджету. " +
		"Используй его для любого запроса о подборе места — никогда не называй ресторан, цену, вместимость " +
		"или адрес, если они не пришли из результата этого инструмента. Пустой список — это честный ответ " +
		"«ничего не найдено», а не повод предложить вариант самостоятельно.",
	InputSchema: map[string]any{
		"type": "object",
		"properties": map[string]any{
			"city":         map[string]any{"type": "string", "description": "Город на русском, например Алматы"},
			"guest_count":  map[string]any{"type": "integer", "description": "Ожидаемое число гостей"},
			"budget_total": map[string]any{"type": "integer", "description": "Общий бюджет клиента в тенге"},
			"keyword":      map[string]any{"type": "string", "description": "Название или ключевое слово, если клиент упомянул конкретное место"},
		},
	},
}

const venuesCategorySlug = "venues"
const maxSearchResults = 5

// SearchVenues runs the actual filter against the DB — plain GORM queries,
// no vector search/embeddings (brief section 3: "не добавляй векторную
// базу, если для первого сценария хватает существующих SQL-запросов").
func SearchVenues(db *gorm.DB, args SearchVenuesArgs) ([]VenueResult, error) {
	var category models.Category
	if err := db.Where("slug = ?", venuesCategorySlug).First(&category).Error; err != nil {
		return nil, fmt.Errorf("venues category: %w", err)
	}

	q := db.Model(&models.Listing{}).Where("is_active = ? AND category_id = ?", true, category.ID)
	// LOWER(...) LIKE rather than Postgres' own ILIKE (used elsewhere in
	// this codebase, e.g. listing_handler.go's List) — deliberately
	// portable so this package's own tests can run against sqlite without
	// a Postgres-only operator; behaves the same on the real Postgres DB.
	if args.City != "" {
		q = q.Where("LOWER(city) LIKE LOWER(?)", "%"+args.City+"%")
	}
	if args.Keyword != "" {
		like := "%" + args.Keyword + "%"
		q = q.Where("LOWER(name_ru) LIKE LOWER(?) OR LOWER(name_kz) LIKE LOWER(?)", like, like)
	}

	var listings []models.Listing
	if err := q.Order("rating desc").Find(&listings).Error; err != nil {
		return nil, fmt.Errorf("listings: %w", err)
	}
	if len(listings) == 0 {
		return []VenueResult{}, nil
	}

	listingIDs := make([]uint, len(listings))
	for i, l := range listings {
		listingIDs[i] = l.ID
	}

	// Two grouped aggregate queries total, same "no N+1" shape
	// listing_handler.go's attachListingCounts already established.
	type hallAgg struct {
		ListingID   uint
		MaxCapacity uint
	}
	var hallAggs []hallAgg
	db.Model(&models.ListingHall{}).
		Select("listing_id, max(capacity) as max_capacity").
		Where("listing_id IN ? AND is_active = ?", listingIDs, true).
		Group("listing_id").Scan(&hallAggs)
	hallByListing := map[uint]uint{}
	for _, row := range hallAggs {
		hallByListing[row.ListingID] = row.MaxCapacity
	}

	type menuAgg struct {
		ListingID uint
		MinPrice  uint
	}
	var menuAggs []menuAgg
	db.Model(&models.ListingMenu{}).
		Select("listing_id, min(price_per_guest) as min_price").
		Where("listing_id IN ? AND is_active = ? AND price_per_guest > 0", listingIDs, true).
		Group("listing_id").Scan(&menuAggs)
	menuByListing := map[uint]uint{}
	for _, row := range menuAggs {
		menuByListing[row.ListingID] = row.MinPrice
	}

	out := make([]VenueResult, 0, maxSearchResults)
	for _, l := range listings {
		capacity := hallByListing[l.ID]
		if capacity == 0 {
			capacity = l.Capacity
		}
		capacityKnown := capacity > 0

		var priceFrom uint
		var priceUnit string
		if p, ok := menuByListing[l.ID]; ok {
			priceFrom = p
			priceUnit = "per_guest"
		} else if l.Price > 0 {
			priceFrom = l.Price
			priceUnit = "flat"
		}

		// Honest exclusion only — a listing with unknown capacity/price
		// stays in the running rather than being silently dropped, so the
		// model still gets to say "уточните у менеджера" about it instead
		// of it just never showing up.
		if args.GuestCount > 0 && capacityKnown && capacity < uint(args.GuestCount) {
			continue
		}

		var estimatedTotal uint
		if args.GuestCount > 0 && priceUnit == "per_guest" {
			estimatedTotal = priceFrom * uint(args.GuestCount)
		}
		if args.BudgetTotal > 0 && estimatedTotal > 0 && estimatedTotal > uint(args.BudgetTotal) {
			continue
		}

		out = append(out, VenueResult{
			ID:             l.ID,
			NameRu:         l.NameRu,
			NameKz:         l.NameKz,
			City:           l.City,
			Address:        l.Address,
			Capacity:       capacity,
			CapacityKnown:  capacityKnown,
			PriceFrom:      priceFrom,
			PriceUnit:      priceUnit,
			PriceKnown:     priceUnit != "",
			EstimatedTotal: estimatedTotal,
			Rating:         l.Rating,
			URL:            fmt.Sprintf("/services/%d", l.ID),
		})
		if len(out) >= maxSearchResults {
			break
		}
	}
	return out, nil
}

func encodeSearchResults(results []VenueResult) string {
	b, err := json.Marshal(results)
	if err != nil {
		return "[]"
	}
	return string(b)
}
