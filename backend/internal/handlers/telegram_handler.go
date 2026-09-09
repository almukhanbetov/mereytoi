package handlers

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/config"
	"github.com/almukhanbetov/mereytoi/backend/internal/middleware"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
	"github.com/almukhanbetov/mereytoi/backend/internal/telegram"
)

// telegramLinkTTL is short (unlike claimTTL's 30 days) — a linking token
// only needs to survive one app-switch from the browser tab that minted it
// to the Telegram app opening moments later, not an unattended wait of
// days (brief section 5 — "short-lived linking token").
const telegramLinkTTL = 15 * time.Minute

type TelegramHandler struct {
	DB            *gorm.DB
	Sender        telegram.Sender // nil when TELEGRAM_BOT_TOKEN isn't configured
	BotUsername   string
	WebhookSecret string
}

func NewTelegramHandler(db *gorm.DB, sender telegram.Sender, cfg config.Config) *TelegramHandler {
	return &TelegramHandler{DB: db, Sender: sender, BotUsername: cfg.TelegramBotUsername, WebhookSecret: cfg.TelegramWebhookSecret}
}

// MintLinkToken — POST /api/users/me/telegram/link-token (authenticated).
// Brief section 5's flow, step 1: mints a fresh, single-use,
// short-lived token scoped to the *authenticated caller's own* UserID —
// never anything the client supplies — so nothing downstream (Webhook) can
// ever attach a Telegram chat to somebody else's account (brief section
// 11 — "нельзя связать Telegram с чужим User").
func (h *TelegramHandler) MintLinkToken(c *gin.Context) {
	userIDVal, _ := c.Get(middleware.ContextUserIDKey)
	userID, _ := userIDVal.(uint)

	if h.BotUsername == "" {
		// Nothing to build a t.me link with — report honestly rather than
		// handing back a broken link (brief: "не создавать fake delivery").
		c.JSON(http.StatusOK, gin.H{"configured": false})
		return
	}

	link := models.TelegramLinkToken{
		UserID:    userID,
		Token:     generateRef() + generateRef(),
		ExpiresAt: time.Now().Add(telegramLinkTTL),
	}
	if err := h.DB.Create(&link).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create link token"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"configured": true,
		"link_url":   "https://t.me/" + h.BotUsername + "?start=" + link.Token,
	})
}

type telegramUpdate struct {
	Message *struct {
		Chat struct {
			ID int64 `json:"id"`
		} `json:"chat"`
		Text string `json:"text"`
	} `json:"message"`
}

// Webhook — POST /api/telegram/webhook (public; Telegram itself is the
// only real caller). Brief section 5's flow, steps 2-4: parses a
// `/start <token>` update, resolves it to the UserID that minted it via
// MintLinkToken above, and stores the resulting chat_id on that user —
// never on any UserID the incoming message itself might claim (there is
// no such field in Telegram's own update payload to begin with).
//
// Always responds 200 regardless of outcome — this matches Telegram's own
// webhook contract (a non-2xx makes Telegram retry the same update
// repeatedly), not an attempt to hide anything from a caller, since the
// only real caller is Telegram's own servers, not an end user.
func (h *TelegramHandler) Webhook(c *gin.Context) {
	if h.WebhookSecret != "" && c.GetHeader("X-Telegram-Bot-Api-Secret-Token") != h.WebhookSecret {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid secret"})
		return
	}

	var upd telegramUpdate
	if err := c.ShouldBindJSON(&upd); err != nil || upd.Message == nil {
		c.JSON(http.StatusOK, gin.H{})
		return
	}

	text := strings.TrimSpace(upd.Message.Text)
	if !strings.HasPrefix(text, "/start ") {
		c.JSON(http.StatusOK, gin.H{})
		return
	}
	token := strings.TrimSpace(strings.TrimPrefix(text, "/start "))

	var link models.TelegramLinkToken
	if err := h.DB.Where("token = ?", token).First(&link).Error; err != nil {
		c.JSON(http.StatusOK, gin.H{})
		return
	}
	if link.UsedAt != nil || time.Now().After(link.ExpiresAt) {
		c.JSON(http.StatusOK, gin.H{})
		return
	}

	chatID := strconv.FormatInt(upd.Message.Chat.ID, 10)
	if err := h.DB.Model(&models.User{}).Where("id = ?", link.UserID).Update("telegram_chat_id", chatID).Error; err != nil {
		c.JSON(http.StatusOK, gin.H{})
		return
	}
	now := time.Now()
	h.DB.Model(&link).Update("used_at", now)

	if h.Sender != nil {
		h.Sender.Send(c.Request.Context(), chatID,
			"MEREYTOI: Telegram подключён. Здесь будут появляться ссылки на ваше пространство «Мой той».")
	}

	c.JSON(http.StatusOK, gin.H{})
}
