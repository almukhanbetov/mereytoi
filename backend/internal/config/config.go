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
