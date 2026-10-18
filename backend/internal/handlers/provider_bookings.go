package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// providerBookingsLimit caps GET /api/provider/me/bookings to the most
// recent matching bookings.
const providerBookingsLimit = 100

// providerBookingsBatch is how many bookings are read per scan page.
const providerBookingsBatch = 200

type providerBookingItemOut struct {
	ListingID  uint   `json:"listing_id"`
	Title      string `json:"title"`
	Category   string `json:"category,omitempty"`
	Guests     uint   `json:"guests,omitempty"`
	UnitPrice  uint   `json:"unit_price"`
	TotalPrice uint   `json:"total_price"`
	HallName   string `json:"hall_name,omitempty"`
	MenuName   string `json:"menu_name,omitempty"`
}

type providerBookingOut struct {
	ID        uint       `json:"id"`
	PublicRef string     `json:"public_ref"`
	Status    string     `json:"status"`
	CreatedAt time.Time  `json:"created_at"`
	EventID   *uint      `json:"event_id,omitempty"`
	EventDate *time.Time `json:"event_date,omitempty"`
	// Client contact exactly as the customer submitted it with the booking.
	ClientName  string `json:"client_name"`
	ClientPhone string `json:"client_phone"`
	Message     string `json:"message,omitempty"`
	// Only this provider's own items, and their subtotal — never another
	// provider's items or the booking's overall total.
	Items []providerBookingItemOut `json:"items"`
	Total uint                     `json:"total"`
}

// MyBookings — GET /api/provider/me/bookings. The booking requests that
// include at least one of the caller's own services, newest first (up to
// providerBookingsLimit).
//
// Scoped purely by the JWT: "own services" are the listings the caller
// manages through ListingManager (the same rows that authorize editing
// them), so no id or query parameter can widen it to someone else's
// bookings. Each booking carries only the caller's items — a mixed cart
// never leaks another provider's lines or prices.
//
// A Booking stores its items as a JSON column, so the match runs in Go
// over id-descending pages rather than in SQL; that stays cheap at the
// current volume and needs no new table.
func (h *ProviderHandler) MyBookings(c *gin.Context) {
	userID := currentUserID(c)

	var provider models.Provider
	if err := h.DB.Where("user_id = ?", userID).First(&provider).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "provider_not_found"})
		return
	}

	var listingIDs []uint
	if err := h.DB.Model(&models.ListingManager{}).Where("user_id = ?", userID).
		Pluck("listing_id", &listingIDs).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch bookings"})
		return
	}
	out := []providerBookingOut{}
	if len(listingIDs) == 0 {
		c.JSON(http.StatusOK, gin.H{"bookings": out})
		return
	}
	own := make(map[uint]bool, len(listingIDs))
	for _, id := range listingIDs {
		own[id] = true
	}

	var eventIDs []uint
	var cursor uint
	for len(out) < providerBookingsLimit {
		var page []models.Booking
		q := h.DB.Order("id desc").Limit(providerBookingsBatch)
		if cursor > 0 {
			q = q.Where("id < ?", cursor)
		}
		if err := q.Find(&page).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch bookings"})
			return
		}
		for _, b := range page {
			var items []providerBookingItemOut
			var total uint
			for _, it := range b.Items {
				if !own[it.ListingID] {
					continue
				}
				items = append(items, providerBookingItemOut{
					ListingID:  it.ListingID,
					Title:      it.Name,
					Category:   it.Category,
					Guests:     it.Guests,
					UnitPrice:  it.UnitPrice,
					TotalPrice: it.TotalPrice,
					HallName:   it.HallName,
					MenuName:   it.MenuName,
				})
				total += it.TotalPrice
			}
			if len(items) == 0 {
				continue
			}
			out = append(out, providerBookingOut{
				ID:          b.ID,
				PublicRef:   b.PublicRef,
				Status:      b.Status,
				CreatedAt:   b.CreatedAt,
				EventID:     b.EventID,
				ClientName:  b.Name,
				ClientPhone: b.Phone,
				Message:     b.Message,
				Items:       items,
				Total:       total,
			})
			if b.EventID != nil {
				eventIDs = append(eventIDs, *b.EventID)
			}
			if len(out) == providerBookingsLimit {
				break
			}
		}
		if len(page) < providerBookingsBatch {
			break
		}
		cursor = page[len(page)-1].ID
	}

	if len(eventIDs) > 0 {
		var events []models.Event
		if err := h.DB.Select("id", "event_date").Where("id IN ?", eventIDs).Find(&events).Error; err == nil {
			dates := make(map[uint]*time.Time, len(events))
			for _, e := range events {
				dates[e.ID] = e.EventDate
			}
			for i := range out {
				if out[i].EventID != nil {
					out[i].EventDate = dates[*out[i].EventID]
				}
			}
		}
	}

	c.JSON(http.StatusOK, gin.H{"bookings": out})
}
