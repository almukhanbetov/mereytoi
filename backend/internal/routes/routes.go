package routes

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/config"
	"github.com/almukhanbetov/mereytoi/backend/internal/handlers"
	"github.com/almukhanbetov/mereytoi/backend/internal/middleware"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

func Register(r *gin.Engine, database *gorm.DB, cfg config.Config) {
	authHandler := handlers.NewAuthHandler(database, cfg.JWTSecret)
	categoryHandler := handlers.NewCategoryHandler(database)
	listingHandler := handlers.NewListingHandler(database)
	uploadHandler := handlers.NewUploadHandler()
	bookingHandler := handlers.NewBookingHandler(database)
	commentHandler := handlers.NewCommentHandler(database)
	clientHandler := handlers.NewClientHandler(database)
	statisticsHandler := handlers.NewSiteStatisticsHandler(database)
	eventHandler := handlers.NewEventHandler(database)
	eventMemberHandler := handlers.NewEventMemberHandler(database)
	eventCandidateHandler := handlers.NewEventCandidateHandler(database)
	eventCommentHandler := handlers.NewEventCommentHandler(database)
	eventActivityHandler := handlers.NewEventActivityHandler(database)
	eventTaskHandler := handlers.NewEventTaskHandler(database)
	eventRequestHandler := handlers.NewEventRequestHandler(database)

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

		statistics := api.Group("/site-statistics")
		{
			statistics.GET("", statisticsHandler.Get)

			admin := statistics.Group("")
			admin.Use(middleware.RequireAuth(cfg.JWTSecret), middleware.RequireAdmin())
			{
				admin.PUT("", statisticsHandler.Update)
			}
		}

		// "Мой той" collaborative event workspaces — see models/event.go for
		// the domain model and middleware/event.go for the membership/role
		// guard every :id-scoped route below runs through.
		events := api.Group("/events")
		events.Use(middleware.RequireAuth(cfg.JWTSecret))
		{
			events.POST("", eventHandler.Create)
			events.GET("", eventHandler.List)

			// Read-only + "anyone who belongs here" actions (viewers included —
			// they can still see everything and vote).
			viewer := events.Group("/:id")
			viewer.Use(middleware.RequireEventRole(database, models.EventRoleViewer))
			{
				viewer.GET("", eventHandler.Get)
				viewer.GET("/summary", eventHandler.Summary)
				viewer.GET("/members", eventMemberHandler.Members)
				viewer.GET("/candidates", eventCandidateHandler.List)
				viewer.POST("/candidates/:cid/vote", eventCandidateHandler.Vote)
				viewer.GET("/comments", eventCommentHandler.List)
				viewer.GET("/activity", eventActivityHandler.List)
				viewer.GET("/tasks", eventTaskHandler.List)
				// Marking a task done/undone is viewer-allowed too; the
				// handler itself re-checks role for any other field change.
				viewer.PUT("/tasks/:taskId", eventTaskHandler.Update)
				// Any member can see the final request/status — only the
				// organizer can actually change it (below).
				viewer.GET("/request", eventRequestHandler.Get)
			}

			// Collaborative-selection actions — "Участник" (editor) and above.
			editor := events.Group("/:id")
			editor.Use(middleware.RequireEventRole(database, models.EventRoleEditor))
			{
				editor.PUT("", eventHandler.Update)
				editor.POST("/candidates", eventCandidateHandler.AddCandidate)
				editor.PUT("/candidates/:cid", eventCandidateHandler.UpdateStatus)
				editor.DELETE("/candidates/:cid", eventCandidateHandler.RemoveCandidate)
				editor.POST("/comments", eventCommentHandler.AddComment)
				editor.DELETE("/comments/:commentId", eventCommentHandler.Delete)
				editor.POST("/tasks", eventTaskHandler.Create)
				editor.DELETE("/tasks/:taskId", eventTaskHandler.Delete)
			}

			// Ownership-only: membership management and the event itself.
			owner := events.Group("/:id")
			owner.Use(middleware.RequireEventRole(database, models.EventRoleOwner))
			{
				owner.DELETE("", eventHandler.Delete)
				owner.POST("/invitations", eventMemberHandler.CreateInvitation)
				owner.GET("/invitations", eventMemberHandler.ListInvitations)
				owner.DELETE("/invitations/:invId", eventMemberHandler.RevokeInvitation)
				owner.PUT("/members/:userId", eventMemberHandler.ChangeRole)
				owner.DELETE("/members/:userId", eventMemberHandler.RemoveMember)
				// Final request to MEREYTOI — only the organizer prepares,
				// submits, resubmits, or cancels it (section 9 of the brief).
				owner.PUT("/request", eventRequestHandler.Update)
				owner.POST("/request/submit", eventRequestHandler.Submit)
				owner.POST("/request/cancel", eventRequestHandler.Cancel)
			}
		}

		// Invitation acceptance lives outside /events/:id — the whole point is
		// that the person opening the link isn't a member yet, so it can't be
		// guarded by RequireEventRole. The preview is public (no auth) so a
		// freshly-shared link renders "X invites you to..." before anyone logs
		// in; accepting requires being logged in as *someone*.
		invitations := api.Group("/invitations")
		{
			invitations.GET("/:token", eventMemberHandler.PreviewInvitation)
			invitations.POST("/:token/accept", middleware.RequireAuth(cfg.JWTSecret), eventMemberHandler.AcceptInvitation)
		}

		// Manager/admin review of submitted event requests — deliberately
		// separate from /events/:id (an admin reviewing a request is not,
		// and should not need to be, a member of that event).
		adminEventRequests := api.Group("/admin/event-requests")
		adminEventRequests.Use(middleware.RequireAuth(cfg.JWTSecret), middleware.RequireAdmin())
		{
			adminEventRequests.GET("", eventRequestHandler.AdminList)
			adminEventRequests.GET("/:id", eventRequestHandler.AdminGet)
			adminEventRequests.POST("/:id/status", eventRequestHandler.AdminUpdateStatus)
		}
	}
}
