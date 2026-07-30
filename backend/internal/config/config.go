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
