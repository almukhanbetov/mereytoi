package handlers

import (
	"crypto/rand"
	"fmt"
	"log"
	"time"

	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/claimdelivery"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// claimTTL is generous on purpose — a "pending" account has nothing at
// stake but the one draft event it was created with, so there's no
// security reason to expire it fast, and every reason not to lock someone
// out just because they didn't click the success-screen link the same day.
const claimTTL = 30 * 24 * time.Hour

// onboardingResult is what BookingHandler.Create adds to its response as
// "onboarding" when the pipeline actually did something — nil (omitted
// entirely) whenever there's nothing for the success screen to show,
// including every case where the flag is off or this booking already had
// a user/event attached.
type onboardingResult struct {
	Status     string `json:"status"` // "created_pending" | "pending_claim" | "existing_account"
	EventID    uint   `json:"event_id,omitempty"`
	ClaimToken string `json:"claim_token,omitempty"`

	// DeliveryStatus/DeliveryChannel — claim-link delivery over messengers
	// (internal/claimdelivery). DeliveryStatus is omitted entirely (not
	// just empty) whenever nothing was actually attempted —
	// CLAIM_DELIVERY_ENABLED=false, no channel usable for this user, or
	// this result never had a claim token to begin with
	// (existing_account) — so the frontend's "если внешняя доставка
	// отсутствует: не писать, что сообщение отправлено" (brief section 8)
	// falls out of "the field just isn't there", not a branch it has to
	// get right. DeliveryChannel ("whatsapp" | "telegram") is only ever
	// set alongside a non-empty DeliveryStatus, and is what picks the
	// exact success-screen sentence (brief section 8).
	DeliveryStatus  string `json:"delivery_status,omitempty"`
	DeliveryChannel string `json:"delivery_channel,omitempty"`
}

// reconcileBookingAccount is the secondary, best-effort half of the
// booking→account pipeline (brief section 2): booking creation has
// already fully succeeded by the time this runs, and nothing here is
// allowed to change that. Every DB error is logged and swallowed — the
// caller gets nil, the booking response is unaffected either way.
//
// Only ever called for a genuine anonymous booking (booking.UserID and
// booking.EventID both nil going in) — a booking placed while logged in,
// or one that arrived already linked to an event (e.g. the "Мой той"
// request-submit flow), is left completely alone; see BookingHandler.Create's
// own guard before calling this. delivery may be nil (tests that don't
// care about delivery at all); Deliver itself already treats a disabled
// Service as a no-op, so nil is just one step earlier on the same path.
func reconcileBookingAccount(db *gorm.DB, booking *models.Booking, delivery *claimdelivery.Service) *onboardingResult {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("[onboarding] recovered panic for booking #%d: %v", booking.ID, r)
		}
	}()

	phone := strongNormalizePhone(booking.Phone)
	if phone == "" {
		// Not a recognizable KZ mobile number — nothing safe to match on.
		return nil
	}

	var existing models.User
	err := db.Where("phone_normalized = ?", phone).First(&existing).Error
	switch {
	case err == nil:
		return reconcileExistingUser(db, booking, &existing, delivery)
	case err == gorm.ErrRecordNotFound:
		return createPendingAccount(db, booking, phone, delivery)
	default:
		log.Printf("[onboarding] lookup failed for booking #%d: %v", booking.ID, err)
		return nil
	}
}

// reconcileExistingUser handles the phone-already-belongs-to-someone case.
func reconcileExistingUser(db *gorm.DB, booking *models.Booking, user *models.User, delivery *claimdelivery.Service) *onboardingResult {
	if err := db.Model(booking).Update("user_id", user.ID).Error; err != nil {
		log.Printf("[onboarding] failed to link booking #%d to user #%d: %v", booking.ID, user.ID, err)
		return nil
	}
	booking.UserID = &user.ID

	if user.Status != models.UserStatusPending {
		// A real, password-protected account. A phone number typed into a
		// public, unauthenticated form is not proof of identity — never
		// mint a session for somebody else's real account off the back of
		// it. The booking is still correctly linked (that part is safe:
		// worst case, an admin sees one extra booking attributed to the
		// wrong account, exactly the same exposure the site already has
		// today whenever OptionalAuth attaches a UserID). The success
		// screen just invites them to log in normally.
		return &onboardingResult{Status: "existing_account"}
	}

	// A previously auto-created pending account (e.g. an earlier guest
	// booking from the same phone) — still just an empty shell, so it's
	// safe to hand out a fresh claim link the same way a new one would get.
	eventID, err := ensureDraftEvent(db, user.ID, booking)
	if err != nil {
		log.Printf("[onboarding] failed to ensure event for pending user #%d: %v", user.ID, err)
		return nil
	}
	claim, err := mintClaim(db, user.ID)
	if err != nil {
		log.Printf("[onboarding] failed to mint claim for pending user #%d: %v", user.ID, err)
		return &onboardingResult{Status: "pending_claim", EventID: eventID}
	}
	result := &onboardingResult{Status: "pending_claim", EventID: eventID, ClaimToken: claim.Token}
	attemptDelivery(db, delivery, claim, user, result)
	return result
}

// createPendingAccount handles the no-match case: a genuinely new person.
func createPendingAccount(db *gorm.DB, booking *models.Booking, phoneNormalized string, delivery *claimdelivery.Service) *onboardingResult {
	randomPassword := make([]byte, 24)
	if _, err := rand.Read(randomPassword); err != nil {
		log.Printf("[onboarding] failed to generate random password for booking #%d: %v", booking.ID, err)
		return nil
	}
	hash, err := bcrypt.GenerateFromPassword(randomPassword, bcrypt.DefaultCost)
	if err != nil {
		log.Printf("[onboarding] failed to hash random password for booking #%d: %v", booking.ID, err)
		return nil
	}

	user := models.User{
		Name: booking.Name,
		// Synthesized, deterministic per phone — Email stays NOT NULL +
		// UNIQUE exactly as it already is; this never touches that
		// constraint's meaning, it just satisfies it for an account that
		// has no real email yet. Obviously not a real address if it's
		// ever shown anywhere (it isn't, today).
		Email:           fmt.Sprintf("pending+%s@onboarding.mereytoi.local", phoneNormalized[1:]),
		Phone:           normalizePhone(booking.Phone),
		PhoneNormalized: phoneNormalized,
		PasswordHash:    string(hash),
		Role:            "user",
		Status:          models.UserStatusPending,
	}
	if err := db.Create(&user).Error; err != nil {
		log.Printf("[onboarding] failed to create pending user for booking #%d: %v", booking.ID, err)
		return nil
	}

	eventID, err := ensureDraftEvent(db, user.ID, booking)
	if err != nil {
		log.Printf("[onboarding] failed to create draft event for new pending user #%d: %v", user.ID, err)
		return nil
	}

	if err := db.Model(booking).Update("user_id", user.ID).Error; err != nil {
		log.Printf("[onboarding] failed to link booking #%d to new user #%d: %v", booking.ID, user.ID, err)
	} else {
		booking.UserID = &user.ID
	}

	createNotification(db, user.ID, 0, eventID, models.NotifWorkspaceCreated, "event", eventID, map[string]any{})

	claim, err := mintClaim(db, user.ID)
	if err != nil {
		log.Printf("[onboarding] failed to mint claim for new pending user #%d: %v", user.ID, err)
		return &onboardingResult{Status: "created_pending", EventID: eventID}
	}
	result := &onboardingResult{Status: "created_pending", EventID: eventID, ClaimToken: claim.Token}
	attemptDelivery(db, delivery, claim, &user, result)
	return result
}

// attemptDelivery is the one place both mint-claim call sites above funnel
// through to actually send the link — never called for existing_account
// (that branch never reaches mintClaim at all). delivery may be nil (some
// tests construct the pipeline without one); Deliver on a nil *Service
// would panic, so this checks first rather than pushing a nil-guard into
// claimdelivery itself, keeping that package's own nil-handling story
// simple (a disabled Service, not a nil one, is its "off" state).
//
// user is passed whole (not just a phone string) because
// claimdelivery.Service needs both PhoneNormalized (for WhatsApp) and
// TelegramChatID/PreferredDeliveryChannel (for channel selection) — see
// its own pickChannel.
func attemptDelivery(db *gorm.DB, delivery *claimdelivery.Service, claim *models.AccountClaim, user *models.User, result *onboardingResult) {
	if delivery == nil {
		return
	}
	status := delivery.Deliver(db, claim, user)
	if status == "" {
		return
	}
	result.DeliveryStatus = status
	if status == "sent" {
		result.DeliveryChannel = claim.DeliveryChannel
	}
}

// ensureDraftEvent reuses the user's existing event if they already own
// one (brief section 4 — "не создавать новый Event на каждый callback"),
// otherwise creates exactly one, mirroring EventHandler.Create's own
// Event+EventMember(owner) transaction so this new event is
// indistinguishable from one created the normal way.
func ensureDraftEvent(db *gorm.DB, userID uint, booking *models.Booking) (uint, error) {
	var owned models.Event
	err := db.Where("owner_id = ?", userID).Order("created_at desc").First(&owned).Error
	if err == nil {
		if booking.EventID == nil {
			db.Model(booking).Update("event_id", owned.ID)
			booking.EventID = &owned.ID
		}
		return owned.ID, nil
	}
	if err != gorm.ErrRecordNotFound {
		return 0, err
	}

	event := models.Event{
		OwnerID: userID,
		Title:   "Новое мероприятие",
		Type:    "other",
		Status:  "planning",
	}
	txErr := db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(&event).Error; err != nil {
			return err
		}
		member := models.EventMember{EventID: event.ID, UserID: userID, Role: models.EventRoleOwner, JoinedAt: time.Now()}
		return tx.Create(&member).Error
	})
	if txErr != nil {
		return 0, txErr
	}
	logActivity(db, event.ID, userID, "event.created", map[string]any{"title": event.Title, "source": "booking_onboarding"})

	db.Model(booking).Update("event_id", event.ID)
	booking.EventID = &event.ID

	return event.ID, nil
}

// mintClaim returns the created row (not just its token) so callers can
// hand it straight to claimdelivery.Service.Deliver, which updates the
// same row's delivery_* columns once it knows the outcome.
func mintClaim(db *gorm.DB, userID uint) (*models.AccountClaim, error) {
	claim := models.AccountClaim{
		UserID:    userID,
		Token:     generateRef() + generateRef(),
		ExpiresAt: time.Now().Add(claimTTL),
	}
	if err := db.Create(&claim).Error; err != nil {
		return nil, err
	}
	return &claim, nil
}
