package models

import "time"

// RecoveryAttempt is one failed backup-code check (internal/recoverycode),
// counted to throttle guessing. It lives in the database rather than in
// process memory so every backend instance sees the same counts. KeyHash
// is a SHA-256 of the throttled key (client IP, normalized email/phone or
// user id) — the raw value is never stored. Rows older than a day are
// deleted as new ones are written.
type RecoveryAttempt struct {
	ID        uint      `gorm:"primaryKey"`
	Scope     string    `gorm:"size:16;not null;index:idx_recovery_attempt_lookup,priority:1"`
	KeyHash   string    `gorm:"size:64;not null;index:idx_recovery_attempt_lookup,priority:2"`
	CreatedAt time.Time `gorm:"not null;index:idx_recovery_attempt_lookup,priority:3"`
}
