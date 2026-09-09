package handlers

import (
	"crypto/rand"
	"encoding/hex"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/claimdelivery"
	"github.com/almukhanbetov/mereytoi/backend/internal/config"
	"github.com/almukhanbetov/mereytoi/backend/internal/middleware"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

type BookingHandler struct {
	DB       *gorm.DB
	Cfg      config.Config
	Delivery *claimdelivery.Service
}

func NewBookingHandler(db *gorm.DB, cfg config.Config, delivery *claimdelivery.Service) *BookingHandler {
	return &BookingHandler{DB: db, Cfg: cfg, Delivery: delivery}
}

// generateRef creates an unguessable token used so a customer's browser can
// look up their own booking(s) without a full account/login system.
func generateRef() string {
	buf := make([]byte, 8)
	if _, err := rand.Read(buf); err != nil {
		return ""
	}
	return hex.EncodeToString(buf)
}

type bookingItemInput struct {
	ListingID  uint   `json:"listing_id"`
	Name       string `json:"name"`
	Category   string `json:"category"`
	Guests     uint   `json:"guests"`
	UnitPrice  uint   `json:"unit_price"`
	TotalPrice uint   `json:"total_price"`

	// HallID/HallName/MenuID/MenuName/MenuPricePerGuest — restaurant/venue
	// snapshot (brief section 8). Nothing sends these yet (Cart stays
	// frontend-only/localStorage this stage, untouched — brief section 7),
	// so every existing caller keeps omitting them and gets exactly the
	// old behavior. Trusted as-supplied, same as Name/UnitPrice/TotalPrice
	// already are — this endpoint has never re-verified a booking item
	// against the live Listing, so hall/menu follow that same established
	// model rather than introducing server-side re-verification nothing
	// else here does either.
	HallID            *uint  `json:"hall_id"`
	HallName          string `json:"hall_name"`
	MenuID            *uint  `json:"menu_id"`
	MenuName          string `json:"menu_name"`
	MenuPricePerGuest uint   `json:"menu_price_per_guest"`

	// SelectedExtras/EstimatedTotal — this stage's own addition (brief
	// section 5 — "только если аналогичных полей ещё нет"; they didn't).
	// Now that Cart does carry them (see CartContext.addItem's own doc
	// comment), they flow straight through, same trust model as
	// everything else in this struct.
	SelectedExtras []bookingItemExtraInput `json:"selected_extras"`
	EstimatedTotal uint                    `json:"estimated_total"`
}

type bookingItemExtraInput struct {
	Title string `json:"title"`
	Price uint   `json:"price"`
	Unit  string `json:"unit"`
}

type bookingInput struct {
	Name    string `json:"name" binding:"required"`
	Phone   string `json:"phone" binding:"required"`
	Message string `json:"message"`
	// General contact-form inquiries (no specific listing selected) submit
	// an empty items array — only cart checkouts require at least one.
	Items []bookingItemInput `json:"items"`
}

func (h *BookingHandler) Create(c *gin.Context) {
	var in bookingInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	items := make([]models.BookingItem, 0, len(in.Items))
	var total uint
	for _, it := range in.Items {
		extras := make([]models.BookingItemExtra, 0, len(it.SelectedExtras))
		for _, e := range it.SelectedExtras {
			extras = append(extras, models.BookingItemExtra{Title: e.Title, Price: e.Price, Unit: e.Unit})
		}
		items = append(items, models.BookingItem{
			ListingID:  it.ListingID,
			Name:       it.Name,
			Category:   it.Category,
			Guests:     it.Guests,
			UnitPrice:  it.UnitPrice,
			TotalPrice: it.TotalPrice,

			HallID:            it.HallID,
			HallName:          it.HallName,
			MenuID:            it.MenuID,
			MenuName:          it.MenuName,
			MenuPricePerGuest: it.MenuPricePerGuest,

			SelectedExtras: extras,
			EstimatedTotal: it.EstimatedTotal,
		})
		total += it.TotalPrice
	}

	booking := models.Booking{
		PublicRef: generateRef(),
		Name:      in.Name,
		Phone:     in.Phone,
		Message:   in.Message,
		Items:     items,
		Total:     total,
		Status:    "new",
	}
	if userID, ok := c.Get(middleware.ContextUserIDKey); ok {
		if id, ok := userID.(uint); ok {
			booking.UserID = &id
		}
	}
	if err := h.DB.Create(&booking).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create booking"})
		return
	}

	// The booking above is the primary operation and has already fully
	// succeeded — everything from here is secondary/best-effort (brief
	// section 2). Only ever runs for a genuine anonymous booking with no
	// event context yet; a booking placed while logged in, or one that
	// already arrived linked to an event (e.g. the "Мой той" request-submit
	// flow), is left completely alone regardless of the flag.
	resp := gin.H{"booking": booking}
	if h.Cfg.AutoAccountFromBooking && booking.UserID == nil && booking.EventID == nil {
		if onboarding := reconcileBookingAccount(h.DB, &booking, h.Delivery); onboarding != nil {
			resp["booking"] = booking // re-attach: UserID/EventID may have just been set
			resp["onboarding"] = onboarding
		}
	}

	c.JSON(http.StatusCreated, resp)
}

// Lookup returns bookings matching the given public refs, e.g.
// GET /api/bookings/lookup?ref=abc123,def456 — used by the cart drawer to
// show a customer their own past bookings without requiring a login.
func (h *BookingHandler) Lookup(c *gin.Context) {
	raw := c.Query("ref")
	if raw == "" {
		c.JSON(http.StatusOK, gin.H{"bookings": []models.Booking{}})
		return
	}

	refs := make([]string, 0)
	for _, r := range strings.Split(raw, ",") {
		r = strings.TrimSpace(r)
		if r != "" {
			refs = append(refs, r)
		}
	}
	if len(refs) == 0 {
		c.JSON(http.StatusOK, gin.H{"bookings": []models.Booking{}})
		return
	}

	var bookings []models.Booking
	if err := h.DB.Where("public_ref IN ?", refs).Order("created_at desc").Find(&bookings).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch bookings"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"bookings": bookings})
}

// MyBookings returns bookings belonging to the authenticated customer
// account — GET /api/users/me/bookings.
func (h *BookingHandler) MyBookings(c *gin.Context) {
	userID, _ := c.Get(middleware.ContextUserIDKey)

	var bookings []models.Booking
	if err := h.DB.Where("user_id = ?", userID).Order("created_at desc").Find(&bookings).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch bookings"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"bookings": bookings})
}

func (h *BookingHandler) List(c *gin.Context) {
	var bookings []models.Booking
	if err := h.DB.Order("created_at desc").Find(&bookings).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch bookings"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"bookings": bookings})
}

type bookingStatusInput struct {
	Status *string `json:"status" binding:"omitempty,oneof=new contacted confirmed cancelled"`
	Paid   *bool   `json:"paid"`
}

func (h *BookingHandler) UpdateStatus(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}

	var booking models.Booking
	if err := h.DB.First(&booking, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "booking not found"})
		return
	}

	var in bookingStatusInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if in.Status != nil {
		booking.Status = *in.Status
	}
	if in.Paid != nil {
		booking.Paid = *in.Paid
	}
	if err := h.DB.Save(&booking).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update booking"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"booking": booking})
}

func (h *BookingHandler) Delete(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}

	if err := h.DB.Delete(&models.Booking{}, id).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete booking"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "booking deleted"})
}

// DeleteMine lets an authenticated customer delete one of their own
// bookings — DELETE /api/users/me/bookings/:id.
func (h *BookingHandler) DeleteMine(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	userIDVal, _ := c.Get(middleware.ContextUserIDKey)
	userID, _ := userIDVal.(uint)

	var booking models.Booking
	if err := h.DB.First(&booking, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "booking not found"})
		return
	}
	if booking.UserID == nil || *booking.UserID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "not your booking"})
		return
	}

	if err := h.DB.Delete(&booking).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete booking"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "booking deleted"})
}
