package main

import (
	"log"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"

	"github.com/almukhanbetov/mereytoi/backend/internal/config"
	"github.com/almukhanbetov/mereytoi/backend/internal/db"
	"github.com/almukhanbetov/mereytoi/backend/internal/routes"
	"github.com/almukhanbetov/mereytoi/backend/internal/seed"
)

func main() {
	cfg := config.Load()
	database := db.Connect(cfg)
	seed.Run(database)

	r := gin.Default()
	r.MaxMultipartMemory = 8 << 20 // 8MB

	r.Use(cors.New(cors.Config{
		AllowOrigins:     cfg.CORSOrigins,
		AllowMethods:     []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Authorization"},
		AllowCredentials: true,
		MaxAge:           12 * time.Hour,
	}))

	r.Static("/uploads", "./uploads")

	routes.Register(r, database, cfg)

	log.Printf("mereytoi backend listening on :%s", cfg.Port)
	if err := r.Run(":" + cfg.Port); err != nil {
		log.Fatalf("server failed: %v", err)
	}
}
