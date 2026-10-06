package passwordreset

import (
	"log"
	"time"

	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

// RedactedDB returns db with a GORM logger that never prints query
// arguments. The app's default logger (Warn) prints the full SQL of any
// failed or slow query with its values filled in — for these queries that
// would be phone numbers, code HMACs and bcrypt hashes. Same level and
// slow-query threshold, values shown as placeholders only.
func RedactedDB(db *gorm.DB) *gorm.DB {
	return db.Session(&gorm.Session{Logger: logger.New(log.Default(), logger.Config{
		SlowThreshold:             200 * time.Millisecond,
		LogLevel:                  logger.Warn,
		IgnoreRecordNotFoundError: true,
		ParameterizedQueries:      true,
	})})
}
