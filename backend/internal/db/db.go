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

	if err := database.AutoMigrate(&models.User{}, &models.Category{}, &models.Listing{}, &models.Booking{}, &models.Comment{}, &models.Client{}); err != nil {
		log.Fatalf("failed to run migrations: %v", err)
	}

	return database
}
