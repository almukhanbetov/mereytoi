// Package passwordreset replaces a user's password after they prove they
// own their phone with a one-time code ("forgot password" while signed out,
// "I don't remember my current password" while signed in), and changes it
// for a signed-in user who does know the current one.
//
// Codes: 6 digits from crypto/rand, stored only as an HMAC (see code.go),
// valid for CodeTTL, at most MaxAttempts wrong guesses, single use, and a
// new code invalidates the previous one. Per phone: one code per
// ResendCooldown, at most MaxPerHour. Nothing here ever logs a code, a
// password, a hash or a phone number — only user ids and outcomes.
//
// Handlers keep the outward contract (identical answers whether or not an
// account exists); this package returns precise errors so they can.
package passwordreset

import (
	"context"
	"errors"
	"log"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

const (
	CodeTTL        = 10 * time.Minute
	MaxAttempts    = 5
	ResendCooldown = 60 * time.Second
	MaxPerHour     = 5
	MinPasswordLen = 8
	// maxPasswordBytes is bcrypt's own input limit.
	maxPasswordBytes = 72
	// retention — rows older than this no longer matter (the hourly cap
	// looks back one hour) and are deleted opportunistically.
	retention = 24 * time.Hour
	// deliveryBudget bounds one code's whole delivery (all attempts) on a
	// worker — never an HTTP request.
	deliveryBudget = 15 * time.Second
	// queueSize/workers bound background delivery: at most workers sends
	// in flight, at most queueSize waiting. A full queue drops the job
	// (and its code) rather than grow without limit.
	queueSize = 256
	workers   = 2
)

var (
	// ErrInvalidCode covers every way a code can fail: none issued, wrong,
	// expired, already used, superseded, out of attempts, or no single
	// matching account — deliberately indistinguishable.
	ErrInvalidCode         = errors.New("invalid or expired code")
	ErrWeakPassword        = errors.New("password too short")
	ErrPasswordTooLong     = errors.New("password too long")
	ErrWrongPassword       = errors.New("wrong current password")
	ErrPhoneMissing        = errors.New("no usable phone on the account")
	ErrRateLimited         = errors.New("too many codes requested")
	ErrDeliveryUnavailable = errors.New("code could not be delivered")
	// ErrNotAllowed — the account isn't active (e.g. a pending onboarding
	// account): its password can't be changed here at all.
	ErrNotAllowed = errors.New("password change not allowed for this account")
)

// Service is safe for concurrent use.
type Service struct {
	db        *gorm.DB
	sender    Sender
	available bool
	key       []byte
	now       func() time.Time
	log       *log.Logger
	locks     sync.Map // user id → *sync.Mutex: one code operation per user at a time

	jobs    chan func()
	pending sync.WaitGroup
}

// New builds the Service and starts its delivery workers. A nil sender, or
// NotConfiguredSender, means delivery is off: no code is ever created.
// otpSecret may be empty (see deriveKey).
func New(db *gorm.DB, sender Sender, otpSecret, jwtSecret string) *Service {
	_, notConfigured := sender.(NotConfiguredSender)
	if sender == nil {
		sender, notConfigured = NotConfiguredSender{}, true
	}
	s := &Service{
		db:        RedactedDB(db),
		sender:    sender,
		available: !notConfigured,
		key:       deriveKey(otpSecret, jwtSecret),
		now:       time.Now,
		log:       log.Default(),
		jobs:      make(chan func(), queueSize),
	}
	for i := 0; i < workers; i++ {
		go s.work()
	}
	return s
}

// Available reports whether codes can actually be delivered.
func (s *Service) Available() bool { return s.available }

// Flush waits until every queued delivery job has finished (tests).
func (s *Service) Flush() { s.pending.Wait() }

func (s *Service) work() {
	for job := range s.jobs {
		s.run(job)
	}
}

// run executes one job; a panic in it (or in a Sender) is contained here
// and never takes the backend down. The panic value isn't logged — it
// could carry whatever the job was holding.
func (s *Service) run(job func()) {
	defer s.pending.Done()
	defer func() {
		if r := recover(); r != nil {
			s.log.Printf("[password] delivery job panicked (recovered)")
		}
	}()
	job()
}

// enqueue hands job to the workers without ever blocking; false means the
// queue is full and the job was dropped.
func (s *Service) enqueue(job func()) bool {
	s.pending.Add(1)
	select {
	case s.jobs <- job:
		return true
	default:
		s.pending.Done()
		return false
	}
}

// WithClock replaces the clock (tests only).
func (s *Service) WithClock(now func() time.Time) *Service {
	s.now = now
	return s
}

func (s *Service) lock(userID uint) func() {
	m, _ := s.locks.LoadOrStore(userID, &sync.Mutex{})
	mu := m.(*sync.Mutex)
	mu.Lock()
	return mu.Unlock
}

// RequestReset sends a "reset" code if — and only if — phone (already
// strongly normalized, "" if it wasn't a valid number) belongs to exactly
// one active account with a real password. It returns at once, having
// done no lookup at all: finding the account, the per-phone limits,
// creating the code and sending it all happen on a delivery worker, so
// the caller's response takes the same time whatever the number is.
// Every outcome is silent.
func (s *Service) RequestReset(phone, lang string) {
	if !s.available || phone == "" {
		return
	}
	if !s.enqueue(func() {
		user, ok := s.uniqueActiveUser(phone)
		if !ok {
			return
		}
		row, code, err := s.createCode(user, phone, models.PasswordCodePurposeReset)
		if err != nil {
			return
		}
		s.deliver(row, CodeMessage{UserID: user.ID, Phone: phone, Code: code, Purpose: row.Purpose, Lang: lang})
	}) {
		s.log.Printf("[password] reset request dropped: delivery queue full")
	}
}

// ConfirmReset replaces the password of the account phone belongs to, if
// code is that account's live "reset" code.
func (s *Service) ConfirmReset(phone, code, newPassword string) error {
	if err := checkPassword(newPassword); err != nil {
		return err
	}
	user, ok := s.uniqueActiveUser(phone)
	if !ok {
		return ErrInvalidCode
	}
	return s.redeem(user, models.PasswordCodePurposeReset, code, newPassword)
}

// RequestChangeCode sends a "change" code to a signed-in user's own phone
// and returns a masked hint of it ("+7 ••• ••• 45 67").
// The code is created here (so limits can be reported) and sent in the
// background; this never waits for the provider.
func (s *Service) RequestChangeCode(userID uint, lang string) (string, error) {
	if !s.available {
		return "", ErrDeliveryUnavailable
	}
	user, err := s.activeUser(userID)
	if err != nil {
		return "", err
	}
	if user.PhoneNormalized == "" {
		return "", ErrPhoneMissing
	}
	row, code, err := s.createCode(user, user.PhoneNormalized, models.PasswordCodePurposeChange)
	if err != nil {
		return "", err
	}
	msg := CodeMessage{UserID: user.ID, Phone: user.PhoneNormalized, Code: code, Purpose: row.Purpose, Lang: lang}
	if !s.enqueue(func() { s.deliver(row, msg) }) {
		s.invalidate(row.ID)
		s.log.Printf("[password] change code for user #%d dropped: delivery queue full", user.ID)
		return "", ErrDeliveryUnavailable
	}
	return maskPhone(user.PhoneNormalized), nil
}

// ChangeWithCode replaces a signed-in user's password given their live
// "change" code, without the current password.
func (s *Service) ChangeWithCode(userID uint, code, newPassword string) error {
	if err := checkPassword(newPassword); err != nil {
		return err
	}
	user, err := s.activeUser(userID)
	if err != nil {
		return err
	}
	return s.redeem(user, models.PasswordCodePurposeChange, code, newPassword)
}

// ChangeWithCurrent replaces a signed-in user's password given the current
// one. Counting wrong guesses is the caller's job (it owns the limiter).
func (s *Service) ChangeWithCurrent(userID uint, current, newPassword string) error {
	if err := checkPassword(newPassword); err != nil {
		return err
	}
	user, err := s.activeUser(userID)
	if err != nil {
		return err
	}
	if bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(current)) != nil {
		s.log.Printf("[password] change rejected for user #%d: wrong current password", user.ID)
		return ErrWrongPassword
	}
	if err := s.db.Transaction(func(tx *gorm.DB) error {
		return s.setPassword(tx, user.ID, newPassword, false)
	}); err != nil {
		return err
	}
	s.log.Printf("[password] changed for user #%d (current password)", user.ID)
	return nil
}

// uniqueActiveUser finds the one active account with a real password hash
// for phone. Zero, several, pending or passwordless all mean "no".
func (s *Service) uniqueActiveUser(phone string) (models.User, bool) {
	if phone == "" {
		return models.User{}, false
	}
	var users []models.User
	if err := s.db.Where("phone_normalized = ? AND status = ?", phone, models.UserStatusActive).
		Limit(2).Find(&users).Error; err != nil || len(users) != 1 {
		return models.User{}, false
	}
	if _, err := bcrypt.Cost([]byte(users[0].PasswordHash)); err != nil {
		return models.User{}, false
	}
	return users[0], true
}

// activeUser loads a signed-in user for a password change, which only an
// active account may make — a pending (onboarding) account has no password
// of its own, and this must not become a back door to one.
func (s *Service) activeUser(userID uint) (models.User, error) {
	var user models.User
	if err := s.db.First(&user, userID).Error; err != nil {
		return models.User{}, err
	}
	if user.Status != models.UserStatusActive {
		s.log.Printf("[password] change refused for user #%d: account not active", user.ID)
		return models.User{}, ErrNotAllowed
	}
	return user, nil
}

// createCode makes a fresh code for user/purpose — after the per-phone
// limits, invalidating the previous live one — and returns its row and the
// plaintext, which only the delivery step ever sees.
func (s *Service) createCode(user models.User, phone, purpose string) (models.PasswordResetCode, string, error) {
	unlock := s.lock(user.ID)
	defer unlock()

	now := s.now()
	s.db.Where("created_at < ?", now.Add(-retention)).Delete(&models.PasswordResetCode{})

	if limited, err := s.phoneLimited(phone, now); err != nil {
		return models.PasswordResetCode{}, "", err
	} else if limited {
		s.log.Printf("[password] %s code for user #%d not issued: rate limited", purpose, user.ID)
		return models.PasswordResetCode{}, "", ErrRateLimited
	}

	code, err := generateCode()
	if err != nil {
		return models.PasswordResetCode{}, "", err
	}
	row := models.PasswordResetCode{
		UserID:          user.ID,
		PhoneNormalized: phone,
		Purpose:         purpose,
		CodeHash:        hashCode(s.key, user.ID, purpose, code),
		ExpiresAt:       now.Add(CodeTTL),
		CreatedAt:       now,
	}
	if err := s.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&models.PasswordResetCode{}).
			Where("user_id = ? AND purpose = ? AND used_at IS NULL AND invalidated_at IS NULL", user.ID, purpose).
			Update("invalidated_at", now).Error; err != nil {
			return err
		}
		return tx.Create(&row).Error
	}); err != nil {
		return models.PasswordResetCode{}, "", err
	}
	return row, code, nil
}

// deliver sends msg for row on a delivery worker. Unless the send
// definitely succeeded — error, timeout or panic — the code is invalidated:
// a code the user never received must never stay redeemable.
func (s *Service) deliver(row models.PasswordResetCode, msg CodeMessage) {
	delivered := false
	defer func() {
		if !delivered {
			s.invalidate(row.ID)
		}
	}()
	ctx, cancel := context.WithTimeout(context.Background(), deliveryBudget)
	defer cancel()
	if err := s.sender.SendPasswordResetCode(ctx, msg); err != nil {
		reason := "send_failed"
		var de *DeliveryError
		switch {
		case errors.Is(err, ErrNotConfigured):
			reason = "not_configured"
		case errors.As(err, &de):
			reason = de.Class
		}
		s.log.Printf("[password] %s code for user #%d not delivered: %s", msg.Purpose, msg.UserID, reason)
		return
	}
	delivered = true
	s.log.Printf("[password] %s code sent to user #%d", msg.Purpose, msg.UserID)
}

// invalidate retires a code unless it has already been used or retired.
func (s *Service) invalidate(id uint) {
	s.db.Model(&models.PasswordResetCode{}).
		Where("id = ? AND used_at IS NULL AND invalidated_at IS NULL", id).
		Update("invalidated_at", s.now())
}

// phoneLimited applies the per-phone cooldown and hourly cap, counting
// every code ever issued to the number (whatever happened to it).
func (s *Service) phoneLimited(phone string, now time.Time) (bool, error) {
	var recent int64
	if err := s.db.Model(&models.PasswordResetCode{}).
		Where("phone_normalized = ? AND created_at > ?", phone, now.Add(-ResendCooldown)).
		Count(&recent).Error; err != nil {
		return false, err
	}
	if recent > 0 {
		return true, nil
	}
	var hourly int64
	if err := s.db.Model(&models.PasswordResetCode{}).
		Where("phone_normalized = ? AND created_at > ?", phone, now.Add(-time.Hour)).
		Count(&hourly).Error; err != nil {
		return false, err
	}
	return hourly >= MaxPerHour, nil
}

// redeem checks code against user's live code for purpose and, if it
// matches, uses it up and sets the new password — both or neither. A wrong
// guess is counted (and kills the code at MaxAttempts) even though the
// caller only ever sees ErrInvalidCode.
func (s *Service) redeem(user models.User, purpose, code, newPassword string) error {
	unlock := s.lock(user.ID)
	defer unlock()

	now := s.now()
	var live models.PasswordResetCode
	err := s.db.Where("user_id = ? AND purpose = ? AND used_at IS NULL AND invalidated_at IS NULL", user.ID, purpose).
		Order("created_at desc").First(&live).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		s.log.Printf("[password] %s rejected for user #%d: no live code", purpose, user.ID)
		return ErrInvalidCode
	}
	if err != nil {
		return err
	}
	if !now.Before(live.ExpiresAt) || live.Attempts >= MaxAttempts {
		s.db.Model(&live).Update("invalidated_at", now)
		s.log.Printf("[password] %s rejected for user #%d: code expired or out of attempts", purpose, user.ID)
		return ErrInvalidCode
	}
	if !wellFormed(code) || !codeMatches(s.key, user.ID, purpose, code, live.CodeHash) {
		updates := map[string]any{"attempts": gorm.Expr("attempts + 1")}
		if live.Attempts+1 >= MaxAttempts {
			updates["invalidated_at"] = now
		}
		s.db.Model(&models.PasswordResetCode{}).Where("id = ? AND used_at IS NULL", live.ID).Updates(updates)
		s.log.Printf("[password] %s rejected for user #%d: wrong code", purpose, user.ID)
		return ErrInvalidCode
	}

	err = s.db.Transaction(func(tx *gorm.DB) error {
		res := tx.Model(&models.PasswordResetCode{}).
			Where("id = ? AND used_at IS NULL AND invalidated_at IS NULL", live.ID).
			Update("used_at", now)
		if res.Error != nil {
			return res.Error
		}
		if res.RowsAffected != 1 {
			return ErrInvalidCode // someone else redeemed or replaced it first
		}
		return s.setPassword(tx, user.ID, newPassword, true)
	})
	if err != nil {
		return err
	}
	s.log.Printf("[password] %s completed for user #%d", purpose, user.ID)
	return nil
}

// setPassword stores newPassword's bcrypt hash and stamps
// password_changed_at, which retires every session issued before now.
// A code redeemed via the phone also proves the phone is the user's.
func (s *Service) setPassword(tx *gorm.DB, userID uint, newPassword string, phoneProven bool) error {
	hash, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	now := s.now()
	updates := map[string]any{"password_hash": string(hash), "password_changed_at": now}
	if phoneProven {
		updates["phone_verified_at"] = now
	}
	return tx.Model(&models.User{}).Where("id = ?", userID).Updates(updates).Error
}

func checkPassword(p string) error {
	if utf8.RuneCountInString(p) < MinPasswordLen {
		return ErrWeakPassword
	}
	if len(p) > maxPasswordBytes {
		return ErrPasswordTooLong
	}
	return nil
}

// maskPhone keeps the country code and last four digits:
// "+77071234567" → "+7 ••• ••• 45 67".
func maskPhone(phone string) string {
	if len(phone) < 6 {
		return strings.Repeat("•", len(phone))
	}
	last := phone[len(phone)-4:]
	return phone[:2] + " ••• ••• " + last[:2] + " " + last[2:]
}
