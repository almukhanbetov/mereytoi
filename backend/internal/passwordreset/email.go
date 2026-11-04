package passwordreset

import (
	"context"
	"errors"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// EmailSender delivers a code to an email address (mail.Service in
// production). An error means it didn't go out.
type EmailSender interface {
	SendPasswordResetOTP(ctx context.Context, lang, to, code string) error
}

// EnableEmail turns on recovery by email. Call before serving requests.
func (s *Service) EnableEmail(sender EmailSender) { s.email = sender }

// EmailAvailable reports whether codes can be sent by email.
func (s *Service) EmailAvailable() bool { return s.email != nil }

// RequestEmailReset sends a code to email if it belongs to exactly one active
// account with a real password. It returns at once, before any lookup: finding
// the account, the limits, the code and the send all happen on a delivery
// worker, so neither the answer nor its timing depends on the account or on
// whether the mail server is up.
func (s *Service) RequestEmailReset(email, lang, clientIP string) {
	if s.email == nil {
		return
	}
	if !s.enqueue(func() { s.requestEmailReset(email, lang, clientIP) }) {
		s.log.Printf("[password] email code dropped: delivery queue full")
	}
}

func (s *Service) requestEmailReset(email, lang, clientIP string) {
	user, ok := s.uniqueActiveUserByEmail(email)
	if !ok {
		return
	}
	row, code, err := s.issueCode(user, "", models.PasswordCodePurposeEmail, func(now time.Time) (bool, error) {
		return s.emailLimited(user.ID, now)
	})
	if err != nil {
		if !errors.Is(err, ErrRateLimited) {
			s.log.Printf("[password] email code for user #%d not issued", user.ID)
		}
		return
	}
	s.audit(s.db, models.RecoveryAuditEmailRequested, user.ID, clientIP, s.now())
	s.deliverEmail(row, user, lang, code)
}

// ConfirmEmailReset sets newPassword if code is the account's live email code.
// An unknown email and a wrong, expired or used code all fail the same way
// (ErrInvalidCode). A bad guess counts against the code (MaxAttempts).
func (s *Service) ConfirmEmailReset(email, code, newPassword, clientIP string) error {
	if err := checkPassword(newPassword); err != nil {
		return err
	}
	user, ok := s.uniqueActiveUserByEmail(email)
	if !ok {
		return ErrInvalidCode
	}
	return s.redeem(user, models.PasswordCodePurposeEmail, strings.TrimSpace(code), newPassword, clientIP)
}

// finishEmailReset is the tail of a redeemed email code, in its transaction:
// the new password, which also revokes every session; no other reset code of
// the account stays usable; the audit record. The phone stays unverified: an
// email code says nothing about it.
func (s *Service) finishEmailReset(tx *gorm.DB, userID uint, newPassword, clientIP string, now time.Time) error {
	if err := s.setPassword(tx, userID, newPassword, false); err != nil {
		return err
	}
	if err := tx.Model(&models.PasswordResetCode{}).
		Where("user_id = ? AND used_at IS NULL AND invalidated_at IS NULL", userID).
		Update("invalidated_at", now).Error; err != nil {
		return err
	}
	return s.audit(tx, models.RecoveryAuditEmailUsed, userID, clientIP, now)
}

func (s *Service) audit(db *gorm.DB, action string, userID uint, clientIP string, at time.Time) error {
	err := db.Create(&models.RecoveryAuditEvent{UserID: &userID, Action: action, IP: clientIP, CreatedAt: at}).Error
	if err != nil {
		s.log.Printf("[password] audit %s failed for user #%d", action, userID)
	}
	return err
}

func (s *Service) uniqueActiveUserByEmail(email string) (models.User, bool) {
	email = strings.ToLower(strings.TrimSpace(email))
	if email == "" {
		return models.User{}, false
	}
	var users []models.User
	if err := s.db.Where("LOWER(email) = ? AND status = ?", email, models.UserStatusActive).
		Limit(2).Find(&users).Error; err != nil || len(users) != 1 {
		return models.User{}, false
	}
	if _, err := bcrypt.Cost([]byte(users[0].PasswordHash)); err != nil {
		return models.User{}, false
	}
	return users[0], true
}

// emailLimited applies the cooldown and hourly cap per account, counting every
// email code issued (whatever happened to it).
func (s *Service) emailLimited(userID uint, now time.Time) (bool, error) {
	q := func(since time.Time) (int64, error) {
		var n int64
		err := s.db.Model(&models.PasswordResetCode{}).
			Where("user_id = ? AND purpose = ? AND created_at > ?", userID, models.PasswordCodePurposeEmail, since).
			Count(&n).Error
		return n, err
	}
	recent, err := q(now.Add(-ResendCooldown))
	if err != nil {
		return false, err
	}
	if recent > 0 {
		return true, nil
	}
	hourly, err := q(now.Add(-time.Hour))
	if err != nil {
		return false, err
	}
	return hourly >= MaxPerHour, nil
}

// deliverEmail sends the code; unless the send definitely succeeded the code
// is invalidated. Only the failing stage of the transport is logged, as its
// full error can hold the address.
func (s *Service) deliverEmail(row models.PasswordResetCode, user models.User, lang, code string) {
	delivered := false
	defer func() {
		if !delivered {
			s.invalidate(row.ID)
		}
	}()
	ctx, cancel := context.WithTimeout(context.Background(), deliveryBudget)
	defer cancel()
	if err := s.email.SendPasswordResetOTP(ctx, lang, user.Email, code); err != nil {
		stage, _, _ := strings.Cut(err.Error(), ":")
		s.log.Printf("[password] email code for user #%d not delivered: %s", user.ID, stage)
		return
	}
	delivered = true
	s.log.Printf("[password] email code sent to user #%d", user.ID)
}
