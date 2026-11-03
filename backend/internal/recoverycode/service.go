package recoverycode

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"log"
	"strconv"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
	"github.com/almukhanbetov/mereytoi/backend/internal/passwordreset"
)

var (
	// ErrInvalid — the one answer for an unknown email/phone, a wrong,
	// malformed or already used code, or an inactive account, so a caller
	// can't tell which.
	ErrInvalid = errors.New("invalid recovery code")
	// ErrRateLimited — too many failed attempts for this client or account.
	ErrRateLimited = errors.New("too many recovery attempts")
	// ErrWrongPassword — the current password given to replace the code
	// didn't match.
	ErrWrongPassword = errors.New("wrong current password")
	// ErrNotAllowed — the account isn't active (e.g. a pending booking
	// account that hasn't been claimed yet).
	ErrNotAllowed = errors.New("account not allowed")
)

// Throttles. Failures are stored in the database (models.RecoveryAttempt),
// so the limits hold across backend instances.
const (
	attemptWindow = 15 * time.Minute
	// maxFailuresPerAccount — attempts that didn't succeed for one
	// email/phone (known or not, so the limit itself reveals nothing).
	maxFailuresPerAccount = 5
	// maxFailuresPerIP — wrong codes from one client address, across
	// accounts.
	maxFailuresPerIP = 20
	// maxWrongPasswordsPerUser — wrong current passwords when replacing
	// the code from settings.
	maxWrongPasswordsPerUser = 5
	attemptRetention         = 24 * time.Hour
)

const (
	scopeIP       = "recover_ip"
	scopeAccount  = "recover_acct"
	scopeRegenPwd = "regen_pwd"
)

// Identifier is who is recovering: an email, or a phone in the two forms
// login matches on (see handlers.findLoginUserByPhone). Exactly one of
// Email / phone is expected.
type Identifier struct {
	Email           string
	PhoneNormalized string // +7XXXXXXXXXX, or "" when the number isn't Kazakhstani
	PhoneRaw        string // as typed, spaces removed — legacy rows only
}

func (id Identifier) key() string {
	if id.Email != "" {
		return "e:" + strings.ToLower(strings.TrimSpace(id.Email))
	}
	if id.PhoneNormalized != "" {
		return "p:" + id.PhoneNormalized
	}
	return "r:" + id.PhoneRaw
}

func (id Identifier) empty() bool {
	return strings.TrimSpace(id.Email) == "" && id.PhoneNormalized == "" && id.PhoneRaw == ""
}

// Service issues, replaces and redeems backup codes.
type Service struct {
	db  *gorm.DB
	now func() time.Time
	log *log.Logger
	// afterLookup, when set (tests only), runs between finding the account
	// and the conditional UPDATE — lets a test line two requests up there.
	afterLookup func()
}

func New(db *gorm.DB) *Service {
	return &Service{db: db, now: time.Now, log: log.Default()}
}

// NewCode generates a code and returns it with the hash to store. Callers
// that create a user store the hash in the same insert (see Register).
func NewCode() (code, hash string, err error) {
	code, err = Generate()
	if err != nil {
		return "", "", err
	}
	return code, Hash(code), nil
}

// RecoverResult is a successful recovery: the account and the new code
// (canonical form) that replaced the redeemed one.
type RecoverResult struct {
	User models.User
	Code string
}

// Recover checks code for the account behind id and, only if it matches,
// in one UPDATE: sets newPassword, stamps password_changed_at (which
// revokes every existing session) and swaps the code for a fresh one. The
// UPDATE is conditional on the old hash, so of two concurrent requests
// with the same code only one can succeed. clientIP is the address Gin
// resolved through its trusted proxies.
func (s *Service) Recover(id Identifier, code, newPassword, clientIP string) (RecoverResult, error) {
	if err := passwordreset.CheckNewPassword(newPassword); err != nil {
		return RecoverResult{}, err
	}
	// The attempt is counted before the code is even looked at; only a
	// successful recovery takes it back (see reserve).
	res, allowed := s.reserve(
		slot{scopeIP, clientIP, maxFailuresPerIP},
		slot{scopeAccount, s.accountKey(id), maxFailuresPerAccount},
	)
	if !allowed {
		return RecoverResult{}, ErrRateLimited
	}

	canonical, ok := Normalize(code)
	if !ok || id.empty() {
		return RecoverResult{}, ErrInvalid
	}
	oldHash := Hash(canonical)

	passwordHash, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
	if err != nil {
		s.release(res)
		return RecoverResult{}, err
	}
	newCode, newHash, err := NewCode()
	if err != nil {
		s.release(res)
		return RecoverResult{}, err
	}

	var user models.User
	err = s.db.Transaction(func(tx *gorm.DB) error {
		q := byIdentifier(tx.Where("status = ? AND recovery_code_hash = ?", models.UserStatusActive, oldHash), id)
		var found []models.User
		if err := q.Limit(2).Find(&found).Error; err != nil {
			return err
		}
		if len(found) != 1 {
			return ErrInvalid
		}
		user = found[0]
		if s.afterLookup != nil {
			s.afterLookup()
		}

		now := s.now()
		res := tx.Model(&models.User{}).
			Where("id = ? AND recovery_code_hash = ?", user.ID, oldHash).
			Updates(map[string]any{
				"password_hash":            string(passwordHash),
				"password_changed_at":      now,
				"recovery_code_hash":       newHash,
				"recovery_code_created_at": now,
			})
		if res.Error != nil {
			return res.Error
		}
		if res.RowsAffected != 1 {
			return ErrInvalid // redeemed or replaced by a concurrent request
		}
		return nil
	})
	if errors.Is(err, ErrInvalid) {
		return RecoverResult{}, ErrInvalid // the attempt stays counted
	}
	if err != nil {
		s.release(res)
		return RecoverResult{}, err
	}
	s.release(res)
	if err := s.db.First(&user, user.ID).Error; err != nil {
		return RecoverResult{}, err
	}
	s.log.Printf("[recovery] password recovered with backup code for user #%d", user.ID)
	return RecoverResult{User: user, Code: newCode}, nil
}

// Replace issues a new code for an active user after checking their
// current password; the previous code stops working at once. Wrong
// passwords are throttled per user.
func (s *Service) Replace(userID uint, currentPassword string) (string, error) {
	res, allowed := s.reserve(slot{scopeRegenPwd, userKeyFor(userID), maxWrongPasswordsPerUser})
	if !allowed {
		return "", ErrRateLimited
	}
	var user models.User
	if err := s.db.First(&user, userID).Error; err != nil {
		s.release(res)
		return "", err
	}
	if user.Status != models.UserStatusActive {
		s.release(res)
		return "", ErrNotAllowed
	}
	if bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(currentPassword)) != nil {
		return "", ErrWrongPassword // the attempt stays counted
	}
	s.release(res)
	code, hash, err := NewCode()
	if err != nil {
		return "", err
	}
	if err := s.db.Model(&models.User{}).Where("id = ?", userID).Updates(map[string]any{
		"recovery_code_hash":       hash,
		"recovery_code_created_at": s.now(),
	}).Error; err != nil {
		return "", err
	}
	s.log.Printf("[recovery] backup code replaced for user #%d", userID)
	return code, nil
}

// byIdentifier narrows q to the users id names — matched the way login
// matches (see handlers.findLoginUserByPhone), email case-insensitively.
func byIdentifier(q *gorm.DB, id Identifier) *gorm.DB {
	switch {
	case strings.TrimSpace(id.Email) != "":
		return q.Where("LOWER(email) = ?", strings.ToLower(strings.TrimSpace(id.Email)))
	case id.PhoneNormalized != "":
		return q.Where("(phone_normalized = ? OR (phone_normalized = '' AND phone = ?))", id.PhoneNormalized, id.PhoneRaw)
	default:
		return q.Where("phone_normalized = '' AND phone = ?", id.PhoneRaw)
	}
}

// accountKey is what the per-account limit counts: the user, when the
// email/phone names exactly one active account — so guesses by email and
// by phone share one budget — otherwise the typed identifier itself. The
// response never depends on which, so this reveals nothing.
func (s *Service) accountKey(id Identifier) string {
	if !id.empty() {
		var ids []uint
		err := byIdentifier(s.db.Model(&models.User{}).Where("status = ?", models.UserStatusActive), id).
			Limit(2).Pluck("id", &ids).Error
		if err == nil && len(ids) == 1 {
			return "a:" + strconv.FormatUint(uint64(ids[0]), 10)
		}
	}
	return id.key()
}

func userKeyFor(id uint) string { return "u:" + strconv.FormatUint(uint64(id), 10) }

func keyHash(key string) string {
	sum := sha256.Sum256([]byte(key))
	return hex.EncodeToString(sum[:])
}

// slot is one throttle a request must pass: at most max attempts per key
// within attemptWindow.
type slot struct {
	scope, key string
	max        int
}

// reservation is the attempt rows a request wrote in reserve.
type reservation []uint

// reserve counts an attempt atomically with its check: it first writes the
// attempt (committed on its own), then counts the key's attempts in the
// window including that row, and refuses if any count exceeds its max.
// Whatever the interleaving, at most max requests per key get through:
// the last of them to count sees every other one's row, all written before
// their own counts. Refused attempts keep their rows, so a flood can't free
// up room; callers release only on success (and on internal errors). Any
// database error refuses.
func (s *Service) reserve(slots ...slot) (reservation, bool) {
	now := s.now()
	var res reservation
	allowed := true
	for _, sl := range slots {
		row := models.RecoveryAttempt{Scope: sl.scope, KeyHash: keyHash(sl.key), CreatedAt: now}
		if err := s.db.Create(&row).Error; err != nil {
			allowed = false
			continue
		}
		res = append(res, row.ID)
		var n int64
		err := s.db.Model(&models.RecoveryAttempt{}).
			Where("scope = ? AND key_hash = ? AND created_at > ?", sl.scope, row.KeyHash, now.Add(-attemptWindow)).
			Count(&n).Error
		if err != nil || n > int64(sl.max) {
			allowed = false
		}
	}
	_ = s.db.Where("created_at < ?", now.Add(-attemptRetention)).Delete(&models.RecoveryAttempt{}).Error
	return res, allowed
}

// release takes back a reservation's attempts (the request succeeded).
func (s *Service) release(res reservation) {
	if len(res) > 0 {
		_ = s.db.Delete(&models.RecoveryAttempt{}, []uint(res)).Error
	}
}
