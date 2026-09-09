package config

import (
	"fmt"
	"os"
	"strings"

	"github.com/joho/godotenv"
)

type Config struct {
	Port        string
	DBHost      string
	DBPort      string
	DBUser      string
	DBPassword  string
	DBName      string
	DBSSLMode   string
	JWTSecret   string
	CORSOrigins []string

	// FrontendURL builds the deep links inside transactional emails
	// (invite links, request-tab links, admin review links) — there was no
	// existing "what's the frontend's origin" config value anywhere in this
	// backend before 11A (CORSOrigins is a list for a different purpose,
	// access control, not link-building), so this is a genuinely new var.
	FrontendURL string

	// Mail* — stage 11A transactional email (see internal/mail). Every
	// value here is read once at startup by mail.NewService; nothing in
	// internal/mail reads os.Getenv directly.
	MailEnabled     bool
	MailDriver      string // "smtp" (default) | "log"
	MailHost        string
	MailPort        string
	MailUsername    string
	MailPassword    string
	MailFromAddress string
	MailFromName    string
	MailUseTLS      bool

	// AutoAccountFromBooking gates the entire booking→pending-account
	// onboarding pipeline (handlers/onboarding.go). Off by default — a
	// guest booking behaves exactly as it always has until this is
	// explicitly turned on; flipping it back to false is a full,
	// instant rollback with no database changes needed (the new columns/
	// table just sit unused).
	AutoAccountFromBooking bool

	// ClaimDelivery* / WhatsApp* / Telegram* — claim-link delivery over
	// messengers (see internal/claimdelivery, internal/whatsapp,
	// internal/telegram). SMS was this pipeline's first iteration and has
	// been fully removed per this stage's brief — no SMS_* env var is read
	// anywhere in this codebase any more.
	//
	// ClaimDeliveryEnabled is a separate on/off switch from
	// AutoAccountFromBooking on purpose: an operator can turn onboarding on
	// before WhatsApp/Telegram are configured (claim links still work via
	// the in-page button — nothing here is load-bearing for the flow
	// itself), and turning delivery off again is a full, instant rollback
	// (no data changes needed; the delivery_* columns just sit empty).
	//
	// WhatsApp only supports Meta's own WhatsApp Cloud API today (the
	// delivery audit for this stage found no Business Solution Provider —
	// Twilio/Infobip/etc. — actually connected in this codebase either).
	// WhatsAppAccessToken/PhoneNumberID empty means claimdelivery.Service
	// treats WhatsApp as unavailable (falls through to Telegram, or to no
	// external delivery at all) rather than silently no-op-sending.
	// WhatsAppTemplateName empty means plain-text messages, which Meta
	// only actually delivers within an existing 24h customer-service
	// window — for real cold-start delivery you need an approved template
	// (brief section 3) and must set this.
	//
	// TelegramBotToken empty likewise means Telegram is treated as
	// unavailable for everyone, regardless of any User.TelegramChatID
	// already on file. TelegramBotUsername is only used to build the
	// `https://t.me/<username>?start=<token>` link
	// (handlers/telegram_handler.go's MintLinkToken) — it can be set even
	// before TelegramBotToken is, though linking obviously can't complete
	// (the webhook has nothing to reply through) until both are.
	ClaimDeliveryEnabled bool
	ClaimDeliveryPrimary string // "whatsapp" (default) | "telegram" — global default priority when a user has no PreferredDeliveryChannel of their own

	WhatsAppAccessToken      string
	WhatsAppPhoneNumberID    string
	WhatsAppTemplateName     string
	WhatsAppTemplateLanguage string
	// WhatsAppBaseURL/TelegramBaseURL override the real
	// graph.facebook.com/api.telegram.org host — leave unset in every real
	// environment (whatsapp.MetaCloudSender/telegram.BotSender fall back
	// to the real host themselves whenever this is empty). Exists purely
	// as a testing/staging hook: Go tests set it directly via a
	// config.Config struct literal, and a local end-to-end run can point
	// it at a throwaway HTTP server via WHATSAPP_API_BASE_URL /
	// TELEGRAM_API_BASE_URL — routes.Register has no other injection seam
	// for this service (see its own comment on why a second variadic
	// parameter isn't legal Go). Deliberately excluded from
	// .env.example's own template so it's never mistaken for a normal
	// piece of production config.
	WhatsAppBaseURL string
	TelegramBaseURL string

	TelegramBotToken      string
	TelegramBotUsername   string
	TelegramWebhookSecret string // optional; if set, Webhook rejects requests missing the matching X-Telegram-Bot-Api-Secret-Token header
}

func Load() Config {
	_ = godotenv.Load()

	// Local dev frontends can end up on 3000 or 3001 depending on what else
	// is running on the machine, so allow both out of the box.
	rawOrigins := getEnv("CORS_ORIGIN", "http://localhost:3000,http://localhost:3001")
	origins := make([]string, 0)
	for _, o := range strings.Split(rawOrigins, ",") {
		if o = strings.TrimSpace(o); o != "" {
			origins = append(origins, o)
		}
	}

	return Config{
		Port:        getEnv("PORT", "8090"),
		DBHost:      getEnv("DB_HOST", "localhost"),
		DBPort:      getEnv("DB_PORT", "5433"),
		DBUser:      getEnv("DB_USER", "mereytoi"),
		DBPassword:  getEnv("DB_PASSWORD", "mereytoi_password"),
		DBName:      getEnv("DB_NAME", "mereytoi_db"),
		DBSSLMode:   getEnv("DB_SSLMODE", "disable"),
		JWTSecret:   getEnv("JWT_SECRET", "dev-secret-change-me"),
		CORSOrigins: origins,
		FrontendURL: getEnv("FRONTEND_URL", "http://localhost:3000"),

		// Off by default (brief section 21): a fresh clone/CI run must not
		// start attempting SMTP connections nobody configured. A developer
		// who wants to see real emails opts in with MAIL_ENABLED=true (and,
		// normally, `docker compose up -d mailpit` — see docker-compose.yml).
		MailEnabled:     getEnv("MAIL_ENABLED", "false") == "true",
		MailDriver:      getEnv("MAIL_DRIVER", "smtp"),
		MailHost:        getEnv("MAIL_HOST", "localhost"),
		MailPort:        getEnv("MAIL_PORT", "1025"),
		MailUsername:    getEnv("MAIL_USERNAME", ""),
		MailPassword:    getEnv("MAIL_PASSWORD", ""),
		MailFromAddress: getEnv("MAIL_FROM_ADDRESS", "no-reply@mereytoi.kz"),
		MailFromName:    getEnv("MAIL_FROM_NAME", "MEREYTOI"),
		MailUseTLS:      getEnv("MAIL_USE_TLS", "false") == "true",

		AutoAccountFromBooking: getEnv("AUTO_ACCOUNT_FROM_BOOKING", "false") == "true",

		// Off by default, same reasoning as AutoAccountFromBooking above: a
		// fresh clone/CI run must not start attempting real HTTP sends
		// nobody configured.
		ClaimDeliveryEnabled: getEnv("CLAIM_DELIVERY_ENABLED", "false") == "true",
		ClaimDeliveryPrimary: getEnv("CLAIM_DELIVERY_PRIMARY", "whatsapp"),

		WhatsAppAccessToken:      getEnv("WHATSAPP_ACCESS_TOKEN", ""),
		WhatsAppPhoneNumberID:    getEnv("WHATSAPP_PHONE_NUMBER_ID", ""),
		WhatsAppTemplateName:     getEnv("WHATSAPP_TEMPLATE_NAME", ""),
		WhatsAppTemplateLanguage: getEnv("WHATSAPP_TEMPLATE_LANGUAGE", "ru"),
		// Testing/staging hook only — see the struct field's own doc
		// comment. Empty (the only value any real environment should ever
		// use) means MetaCloudSender/BotSender fall back to the real host.
		WhatsAppBaseURL: getEnv("WHATSAPP_API_BASE_URL", ""),
		TelegramBaseURL: getEnv("TELEGRAM_API_BASE_URL", ""),

		TelegramBotToken:      getEnv("TELEGRAM_BOT_TOKEN", ""),
		TelegramBotUsername:   getEnv("TELEGRAM_BOT_USERNAME", ""),
		TelegramWebhookSecret: getEnv("TELEGRAM_WEBHOOK_SECRET", ""),
	}
}

func (c Config) DSN() string {
	return fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
		c.DBHost, c.DBPort, c.DBUser, c.DBPassword, c.DBName, c.DBSSLMode,
	)
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
