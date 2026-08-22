package routes

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/config"
	"github.com/almukhanbetov/mereytoi/backend/internal/handlers"
	"github.com/almukhanbetov/mereytoi/backend/internal/middleware"
)

func Register(r *gin.Engine, database *gorm.DB, cfg config.Config) {
	authHandler := handlers.NewAuthHandler(database, cfg.JWTSecret)
	categoryHandler := handlers.NewCategoryHandler(database)
	listingHandler := handlers.NewListingHandler(database)
	uploadHandler := handlers.NewUploadHandler()
	bookingHandler := handlers.NewBookingHandler(database)
	commentHandler := handlers.NewCommentHandler(database)
	clientHandler := handlers.NewClientHandler(database)

	r.GET("/api/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	api := r.Group("/api")
	{
		auth := api.Group("/auth")
		{
			auth.POST("/register", authHandler.Register)
			auth.POST("/login", authHandler.Login)
			auth.GET("/me", middleware.RequireAuth(cfg.JWTSecret), authHandler.Me)
			auth.PUT("/me", middleware.RequireAuth(cfg.JWTSecret), authHandler.UpdateMe)
		}

		users := api.Group("/users")
		users.Use(middleware.RequireAuth(cfg.JWTSecret))
		{
			users.GET("/me/bookings", bookingHandler.MyBookings)
			users.DELETE("/me/bookings/:id", bookingHandler.DeleteMine)
		}

		categories := api.Group("/categories")
		{
			categories.GET("", categoryHandler.List)
			categories.GET("/:slug", categoryHandler.GetBySlug)

			admin := categories.Group("")
			admin.Use(middleware.RequireAuth(cfg.JWTSecret), middleware.RequireAdmin())
			{
				admin.POST("", categoryHandler.Create)
				admin.PUT("/:id", categoryHandler.Update)
				admin.DELETE("/:id", categoryHandler.Delete)
			}
		}

		listings := api.Group("/listings")
		{
			listings.GET("", listingHandler.List)
			listings.GET("/:id", listingHandler.Get)
			listings.GET("/:id/comments", commentHandler.ListApproved)
			listings.POST("/:id/comments", middleware.RequireAuth(cfg.JWTSecret), commentHandler.Create)

			admin := listings.Group("")
			admin.Use(middleware.RequireAuth(cfg.JWTSecret), middleware.RequireAdmin())
			{
				admin.POST("", listingHandler.Create)
				admin.PUT("/:id", listingHandler.Update)
				admin.DELETE("/:id", listingHandler.Delete)
			}
		}

		comments := api.Group("/comments")
		comments.Use(middleware.RequireAuth(cfg.JWTSecret), middleware.RequireAdmin())
		{
			comments.GET("", commentHandler.ListAll)
			comments.PUT("/:id", commentHandler.UpdateApproval)
			comments.DELETE("/:id", commentHandler.Delete)
		}

		uploads := api.Group("/uploads")
		uploads.Use(middleware.RequireAuth(cfg.JWTSecret), middleware.RequireAdmin())
		{
			uploads.POST("", uploadHandler.Upload)
			uploads.POST("/video", uploadHandler.UploadVideo)
		}

		bookings := api.Group("/bookings")
		{
			bookings.POST("", middleware.OptionalAuth(cfg.JWTSecret), bookingHandler.Create)
			bookings.GET("/lookup", bookingHandler.Lookup)

			admin := bookings.Group("")
			admin.Use(middleware.RequireAuth(cfg.JWTSecret), middleware.RequireAdmin())
			{
				admin.GET("", bookingHandler.List)
				admin.PUT("/:id", bookingHandler.UpdateStatus)
				admin.DELETE("/:id", bookingHandler.Delete)
			}
		}

		clients := api.Group("/clients")
		{
			clients.GET("", clientHandler.List)

			admin := clients.Group("")
			admin.Use(middleware.RequireAuth(cfg.JWTSecret), middleware.RequireAdmin())
			{
				admin.POST("", clientHandler.Create)
				admin.PUT("/:id", clientHandler.Update)
				admin.DELETE("/:id", clientHandler.Delete)
			}
		}
	}
}
