package db

import (
	"log"
	"os"
	"time"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	"github.com/almukhanbetov/mereytoi/backend/internal/config"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

func Connect(cfg config.Config) *gorm.DB {
	database, err := gorm.Open(postgres.Open(cfg.DSN()), &gorm.Config{
		// Same output as logger.Default at Warn, but SQL is logged without
		// its parameter values and "record not found" isn't logged at all:
		// otherwise a failed sign-in wrote whatever was typed as the login
		// (an email, a phone — or a password pasted into the wrong field)
		// to the server log. passwordreset.RedactedDB did this for its own
		// queries only.
		Logger: logger.New(log.New(os.Stdout, "\r\n", log.LstdFlags), logger.Config{
			SlowThreshold:             200 * time.Millisecond,
			LogLevel:                  logger.Warn,
			IgnoreRecordNotFoundError: true,
			ParameterizedQueries:      true,
			Colorful:                  true,
		}),
	})
	if err != nil {
		log.Fatalf("failed to connect to database: %v", err)
	}

	if err := database.AutoMigrate(
		&models.User{}, &models.Category{}, &models.Listing{}, &models.Booking{}, &models.Comment{}, &models.Client{}, &models.SiteStatistics{},
		// Password reset/change one-time codes — see models/password_reset_code.go.
		&models.PasswordResetCode{},
		// Backup-code recovery throttle — see models/recovery_attempt.go
		// (the code's hash itself is a column on users).
		&models.RecoveryAttempt{},
		// "Мой той" collaborative workspace — see models/event.go.
		&models.Event{}, &models.EventMember{}, &models.EventInvitation{},
		&models.EventCandidate{}, &models.EventVote{}, &models.EventComment{},
		&models.EventActivity{}, &models.EventTask{},
		// Final event request / booking flow — see models/event_request.go.
		&models.EventRequest{}, &models.EventRequestRevision{},
		// In-app notification center — see models/notification.go.
		&models.Notification{},
		// Manager chat — see models/manager_chat.go.
		&models.ManagerConversation{}, &models.ManagerMessage{},
		// Booking->account onboarding — see models/account_claim.go. User's
		// own new columns (Status/PhoneNormalized/PhoneVerifiedAt, and later
		// TelegramChatID/PreferredDeliveryChannel) are additive fields on
		// the already-registered &models.User{} above, not separate
		// migration entries.
		&models.AccountClaim{},
		// WhatsApp/Telegram claim delivery — see internal/claimdelivery and
		// models/telegram_link_token.go.
		&models.TelegramLinkToken{},
		// Restaurant/venue halls & menus — see models/listing_hall.go and
		// models/listing_menu.go. Listing itself (registered above) only
		// grew scalar columns (Address/Latitude/Longitude/PlaceID/Capacity),
		// no association back-reference, so it has no ordering dependency
		// on these; EventCandidate (also registered above) does reference
		// ListingHall/ListingMenu via HallID/MenuID, so these must be
		// migrated before or alongside it — AutoMigrate handles this
		// correctly regardless of list order, but the columns simply don't
		// exist as FK targets until these run at least once.
		&models.ListingHall{}, &models.ListingMenu{}, &models.ListingMenuSection{}, &models.ListingMenuItem{}, &models.ListingMenuExtra{},
		// Restaurant/venue ownership — see models/listing_manager.go. Links a
		// user to a listing they may manage (role owner|manager); a global
		// admin needs no row here.
		&models.ListingManager{},
		// Provider marketplace — see models/provider.go. A user's optional
		// "услугодатель" profile; ownership of their actual listings still
		// goes through ListingManager above, not a new FK here.
		&models.Provider{},
		// Direct customer<->provider chat — see models/provider_chat.go,
		// deliberately separate from ManagerConversation/ManagerMessage above.
		&models.ProviderConversation{}, &models.ProviderMessage{},
	); err != nil {
		log.Fatalf("failed to run migrations: %v", err)
	}

	return database
}
