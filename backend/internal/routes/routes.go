package routes

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/claimdelivery"
	"github.com/almukhanbetov/mereytoi/backend/internal/config"
	"github.com/almukhanbetov/mereytoi/backend/internal/handlers"
	"github.com/almukhanbetov/mereytoi/backend/internal/mail"
	"github.com/almukhanbetov/mereytoi/backend/internal/middleware"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
	"github.com/almukhanbetov/mereytoi/backend/internal/telegram"
)

// Register wires the full route tree. mailSvc is variadic purely so
// existing callers (production's main.go and every pre-11A test file's
// routes.Register(r, db, cfg)) keep compiling unchanged; when omitted, a
// real mail.Service is built from cfg exactly as main.go already did
// implicitly. Tests that need to observe email dispatch (mail_test.go)
// pass their own mail.NewServiceWithSender(mockSender, cfg) instead of
// wiring a second, parallel route tree just to reach the mail call sites.
func Register(r *gin.Engine, database *gorm.DB, cfg config.Config, mailSvc ...*mail.Service) {
	var mailer *mail.Service
	if len(mailSvc) > 0 && mailSvc[0] != nil {
		mailer = mailSvc[0]
	} else {
		mailer = mail.NewService(cfg)
	}
	// claimdelivery.Service has no test-injection seam through Register's
	// own signature (unlike mailSvc above) — a second variadic parameter
	// of a different type isn't legal Go, and every existing caller of
	// Register already passes cfg by value, so tests that need a fake
	// "WhatsApp/Telegram provider" instead point cfg.WhatsAppBaseURL /
	// cfg.TelegramBaseURL at a local httptest.Server and let this build
	// the real MetaCloudSender/BotSender around it (see
	// claim_delivery_test.go) — exercising the actual HTTP transport end
	// to end rather than a mock Sender.
	delivery := claimdelivery.NewService(cfg)

	// The Telegram bot's own Sender is also handed to TelegramHandler
	// directly (not through claimdelivery.Service, which is specifically
	// about *claim-link* delivery) — the webhook's post-link confirmation
	// message is a distinct, simpler concern. Rebuilding it here rather
	// than exposing an accessor on Service keeps that service's own
	// surface limited to what onboarding.go/ClaimResend actually need.
	var telegramSender telegram.Sender
	if cfg.TelegramBotToken != "" {
		telegramSender = &telegram.BotSender{BaseURL: cfg.TelegramBaseURL, Token: cfg.TelegramBotToken}
	}
	telegramHandler := handlers.NewTelegramHandler(database, telegramSender, cfg)

	authHandler := handlers.NewAuthHandler(database, cfg.JWTSecret, delivery)
	categoryHandler := handlers.NewCategoryHandler(database)
	listingHandler := handlers.NewListingHandler(database)
	listingHallHandler := handlers.NewListingHallHandler(database)
	listingMenuHandler := handlers.NewListingMenuHandler(database)
	uploadHandler := handlers.NewUploadHandler()
	bookingHandler := handlers.NewBookingHandler(database, cfg, delivery)
	commentHandler := handlers.NewCommentHandler(database)
	clientHandler := handlers.NewClientHandler(database)
	statisticsHandler := handlers.NewSiteStatisticsHandler(database)
	eventHandler := handlers.NewEventHandler(database)
	eventMemberHandler := handlers.NewEventMemberHandler(database, mailer)
	eventCandidateHandler := handlers.NewEventCandidateHandler(database)
	eventCommentHandler := handlers.NewEventCommentHandler(database)
	eventActivityHandler := handlers.NewEventActivityHandler(database)
	eventTaskHandler := handlers.NewEventTaskHandler(database)
	eventRequestHandler := handlers.NewEventRequestHandler(database, mailer)
	notificationHandler := handlers.NewNotificationHandler(database)
	managerChatHandler := handlers.NewManagerChatHandler(database)

	r.GET("/api/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	api := r.Group("/api")
	{
		auth := api.Group("/auth")
		{
			auth.POST("/register", authHandler.Register)
			auth.POST("/login", authHandler.Login)
			// Public — the only way a brand-new "pending" account (created
			// by the booking→onboarding pipeline, see handlers/onboarding.go)
			// can open a session; never reachable for/from an existing
			// password-protected account (see AccountClaim's own doc comment).
			auth.POST("/claim/:token", authHandler.Claim)
			// Public — never reveals whether a phone has a pending account
			// (see ClaimResend's own doc comment); rate-limited internally
			// via claimdelivery.Service, same as a fresh booking's own
			// delivery attempt.
			auth.POST("/claim/resend", authHandler.ClaimResend)
			auth.GET("/me", middleware.RequireAuth(cfg.JWTSecret), authHandler.Me)
			auth.PUT("/me", middleware.RequireAuth(cfg.JWTSecret), authHandler.UpdateMe)
		}

		// Public — Telegram's own servers are the only real caller (brief
		// section 5); see TelegramHandler.Webhook's own doc comment on why
		// it always answers 200 regardless of outcome.
		api.POST("/telegram/webhook", telegramHandler.Webhook)

		users := api.Group("/users")
		users.Use(middleware.RequireAuth(cfg.JWTSecret))
		{
			users.GET("/me/bookings", bookingHandler.MyBookings)
			users.DELETE("/me/bookings/:id", bookingHandler.DeleteMine)
			users.POST("/me/telegram/link-token", telegramHandler.MintLinkToken)
			users.PUT("/me/delivery-preference", authHandler.UpdateDeliveryPreference)
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
			// Restaurant/venue halls & menus — public read (brief section
			// 9's "отдельным endpoint menus"/halls; List above never loads
			// this tree, only aggregates — see listing_handler.go).
			listings.GET("/:id/halls", listingHandler.Halls)
			listings.GET("/:id/menus", listingHandler.Menus)

			admin := listings.Group("")
			admin.Use(middleware.RequireAuth(cfg.JWTSecret), middleware.RequireAdmin())
			{
				admin.POST("", listingHandler.Create)
				admin.PUT("/:id", listingHandler.Update)
				admin.DELETE("/:id", listingHandler.Delete)

				// Halls (brief section 10).
				admin.POST("/:id/halls", listingHallHandler.Create)
				admin.PUT("/:id/halls/:hallId", listingHallHandler.Update)
				admin.DELETE("/:id/halls/:hallId", listingHallHandler.Delete)

				// Menus + their sections/items/extras — nested under the
				// owning listing/menu the same way /api/events/:id/candidates/:cid
				// already nests candidate-scoped actions under their event.
				admin.POST("/:id/menus", listingMenuHandler.CreateMenu)
				admin.PUT("/:id/menus/:menuId", listingMenuHandler.UpdateMenu)
				admin.DELETE("/:id/menus/:menuId", listingMenuHandler.DeleteMenu)

				admin.POST("/:id/menus/:menuId/sections", listingMenuHandler.CreateSection)
				admin.PUT("/:id/menus/:menuId/sections/:sectionId", listingMenuHandler.UpdateSection)
				admin.DELETE("/:id/menus/:menuId/sections/:sectionId", listingMenuHandler.DeleteSection)

				admin.POST("/:id/menus/:menuId/sections/:sectionId/items", listingMenuHandler.CreateItem)
				admin.PUT("/:id/menus/:menuId/sections/:sectionId/items/:itemId", listingMenuHandler.UpdateItem)
				admin.DELETE("/:id/menus/:menuId/sections/:sectionId/items/:itemId", listingMenuHandler.DeleteItem)

				admin.POST("/:id/menus/:menuId/extras", listingMenuHandler.CreateExtra)
				admin.PUT("/:id/menus/:menuId/extras/:extraId", listingMenuHandler.UpdateExtra)
				admin.DELETE("/:id/menus/:menuId/extras/:extraId", listingMenuHandler.DeleteExtra)
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

		// In-app notification center — user-scoped, not event-scoped, so
		// this rides plain RequireAuth rather than RequireEventRole; every
		// handler method itself further filters by "user_id = caller".
		notifications := api.Group("/notifications")
		notifications.Use(middleware.RequireAuth(cfg.JWTSecret))
		{
			notifications.GET("", notificationHandler.List)
			notifications.GET("/unread-count", notificationHandler.UnreadCount)
			notifications.POST("/:id/read", notificationHandler.MarkRead)
			notifications.POST("/read-all", notificationHandler.MarkAllRead)
		}

		// Manager chat — real two-way conversation, auth-only (guests keep
		// using the pre-existing FloatingManagerWidget "leave a message"
		// form, which still creates a Booking via /api/bookings, untouched).
		// Get/AddMessage are the same handler methods mounted here AND under
		// /api/admin/manager-chat below — sender_type/ownership is resolved
		// from who's actually calling, not from the route it came in on.
		managerChat := api.Group("/manager-chat")
		managerChat.Use(middleware.RequireAuth(cfg.JWTSecret))
		{
			managerChat.POST("/start", managerChatHandler.Start)
			managerChat.GET("/:id", managerChatHandler.Get)
			managerChat.POST("/:id/messages", managerChatHandler.AddMessage)
		}

		adminManagerChat := api.Group("/admin/manager-chat")
		adminManagerChat.Use(middleware.RequireAuth(cfg.JWTSecret), middleware.RequireAdmin())
		{
			adminManagerChat.GET("", managerChatHandler.AdminList)
			adminManagerChat.GET("/:id", managerChatHandler.Get)
			adminManagerChat.POST("/:id/messages", managerChatHandler.AddMessage)
			adminManagerChat.POST("/:id/status", managerChatHandler.AdminUpdateStatus)
		}
	}
}
