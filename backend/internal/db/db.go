package db

import (
	"log"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	"github.com/almukhanbetov/mereytoi/backend/internal/config"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

func Connect(cfg config.Config) *gorm.DB {
	database, err := gorm.Open(postgres.Open(cfg.DSN()), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Warn),
	})
	if err != nil {
		log.Fatalf("failed to connect to database: %v", err)
	}

	if err := database.AutoMigrate(
		&models.User{}, &models.Category{}, &models.Listing{}, &models.Booking{}, &models.Comment{}, &models.Client{}, &models.SiteStatistics{},
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
	); err != nil {
		log.Fatalf("failed to run migrations: %v", err)
	}

	return database
}
