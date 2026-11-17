package handlers

import (
	"time"

	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/middleware"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// AccountSessionValidator re-reads the account behind every authenticated
// request, so a token is only as good as the account is right now:
//   - the account must still exist (a token of a deleted user is refused);
//   - a token issued before the last password change is retired (iat
//     compared in whole seconds, so the token ChangePassword itself returns
//     in that same second still works);
//   - an administrator's block in force refuses every token, old or new;
//   - the role comes from the database, not the token, so granting or
//     revoking admin applies from the next request.
//
// A database error fails closed. now is injectable for tests.
func AccountSessionValidator(db *gorm.DB, now func() time.Time) middleware.SessionValidator {
	if now == nil {
		now = time.Now
	}
	return func(userID uint, issuedAt int64) middleware.Session {
		var row struct {
			Role              string
			PasswordChangedAt *time.Time
			BlockedAt         *time.Time
			BlockedUntil      *time.Time
		}
		err := db.Model(&models.User{}).
			Select("role", "password_changed_at", "blocked_at", "blocked_until").
			Where("id = ?", userID).Take(&row).Error
		if err != nil {
			return middleware.Session{Error: "session_expired"}
		}
		if row.PasswordChangedAt != nil && issuedAt < row.PasswordChangedAt.Unix() {
			return middleware.Session{Error: "session_expired"}
		}
		if models.BlockActive(row.BlockedAt, row.BlockedUntil, now().UTC()) {
			return middleware.Session{Error: "account_blocked", BlockedUntil: row.BlockedUntil}
		}
		return middleware.Session{Valid: true, Role: row.Role}
	}
}
