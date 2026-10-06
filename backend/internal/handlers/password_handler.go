package handlers

import (
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/middleware"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
	"github.com/almukhanbetov/mereytoi/backend/internal/passwordreset"
	"github.com/almukhanbetov/mereytoi/backend/internal/ratelimit"
)

// passwordForgotNeutralMessage is the only answer ForgotPassword ever gives
// a well-formed request, whatever the number turned out to be — the same
// no-enumeration rule as ClaimResend.
const passwordForgotNeutralMessage = "Если номер зарегистрирован, мы отправили код."

// PasswordHandler serves password reset (signed out) and change (signed
// in). The rules themselves live in internal/passwordreset; this layer maps
// them onto HTTP and applies the per-IP / per-user limits.
type PasswordHandler struct {
	DB        *gorm.DB
	JWTSecret string
	Reset     *passwordreset.Service

	// ForgotPerIP / ResetPerIP throttle the two public endpoints by client
	// IP (gin's ClientIP — only trusted proxies may set it, see
	// routes.Register); WrongPasswordPerUser counts wrong current-password
	// guesses.
	ForgotPerIP          ratelimit.Limiter
	ResetPerIP           ratelimit.Limiter
	WrongPasswordPerUser ratelimit.Limiter
}

func NewPasswordHandler(db *gorm.DB, jwtSecret string, svc *passwordreset.Service) *PasswordHandler {
	return &PasswordHandler{
		DB:                   db,
		JWTSecret:            jwtSecret,
		Reset:                svc,
		ForgotPerIP:          ratelimit.NewMemory(10, 15*time.Minute),
		ResetPerIP:           ratelimit.NewMemory(20, 15*time.Minute),
		WrongPasswordPerUser: ratelimit.NewMemory(5, 15*time.Minute),
	}
}

func tooManyRequests(c *gin.Context) {
	c.JSON(http.StatusTooManyRequests, gin.H{"error": "too_many_requests"})
}

type forgotPasswordInput struct {
	Phone string `json:"phone" binding:"required"`
	Lang  string `json:"lang"`
}

// ForgotPassword — POST /api/auth/password/forgot (public). Sends a reset
// code if the number belongs to exactly one active account; the response is
// the same in every case (unknown, ambiguous, pending, malformed number,
// per-phone rate limit, delivery unavailable). Only the per-IP limit
// answers differently, and that says nothing about the number.
func (h *PasswordHandler) ForgotPassword(c *gin.Context) {
	var in forgotPasswordInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "phone is required"})
		return
	}
	if !h.ForgotPerIP.Allow(c.ClientIP()) {
		tooManyRequests(c)
		return
	}
	// Returns immediately: the account lookup and the send happen in the
	// background, so this answer takes the same time for every number.
	h.Reset.RequestReset(strongNormalizePhone(in.Phone), in.Lang)
	c.JSON(http.StatusOK, gin.H{
		"message":      passwordForgotNeutralMessage,
		"resend_after": int(passwordreset.ResendCooldown.Seconds()),
	})
}

// PasswordConfig — GET /api/auth/password/config (public). Tells the app
// whether codes can actually be delivered, so it can hide "Forgot
// password?" until they can. Exactly one boolean, nothing else.
func (h *PasswordHandler) PasswordConfig(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"reset_available": h.Reset.Available()})
}

type resetPasswordInput struct {
	Phone       string `json:"phone" binding:"required"`
	Code        string `json:"code" binding:"required"`
	NewPassword string `json:"new_password" binding:"required"`
}

// ResetPassword — POST /api/auth/password/reset (public). One answer for
// every code failure ("invalid_code"), so it can't be used to probe numbers
// either. No session is issued: the user signs in with the new password.
func (h *PasswordHandler) ResetPassword(c *gin.Context) {
	var in resetPasswordInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "phone, code and new_password are required"})
		return
	}
	if !h.ResetPerIP.Allow(c.ClientIP()) {
		tooManyRequests(c)
		return
	}
	if err := h.Reset.ConfirmReset(strongNormalizePhone(in.Phone), in.Code, in.NewPassword); err != nil {
		passwordError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "password_changed"})
}

type changeCodeInput struct {
	Lang string `json:"lang"`
}

// RequestChangeCode — POST /api/users/me/password/code (signed in). The
// "I don't remember my current password" path: a code to the account's own
// phone. Being the user's own account, it can say plainly what went wrong.
func (h *PasswordHandler) RequestChangeCode(c *gin.Context) {
	var in changeCodeInput
	_ = c.ShouldBindJSON(&in) // body is optional
	hint, err := h.Reset.RequestChangeCode(currentUserID(c), in.Lang)
	switch {
	case errors.Is(err, passwordreset.ErrNotAllowed):
		c.JSON(http.StatusForbidden, gin.H{"error": "not_allowed"})
	case errors.Is(err, passwordreset.ErrPhoneMissing):
		c.JSON(http.StatusConflict, gin.H{"error": "phone_missing"})
	case errors.Is(err, passwordreset.ErrRateLimited):
		tooManyRequests(c)
	case errors.Is(err, passwordreset.ErrDeliveryUnavailable):
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "delivery_unavailable"})
	case err != nil:
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to send code"})
	default:
		c.JSON(http.StatusOK, gin.H{
			"message":      "code_sent",
			"resend_after": int(passwordreset.ResendCooldown.Seconds()),
			"phone_hint":   hint,
		})
	}
}

type changePasswordInput struct {
	CurrentPassword string `json:"current_password"`
	Code            string `json:"code"`
	NewPassword     string `json:"new_password" binding:"required"`
}

// ChangePassword — PUT /api/users/me/password (signed in), with either the
// current password or a "change" code. Every session issued before this
// moment stops working — including the caller's — so a fresh token comes
// back with the success.
func (h *PasswordHandler) ChangePassword(c *gin.Context) {
	var in changePasswordInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "new_password is required"})
		return
	}
	if (in.CurrentPassword == "") == (in.Code == "") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "current_password_or_code_required"})
		return
	}
	userID := currentUserID(c)

	var err error
	if in.CurrentPassword != "" {
		limitKey := fmt.Sprintf("user:%d", userID)
		if h.WrongPasswordPerUser.Blocked(limitKey) {
			tooManyRequests(c)
			return
		}
		err = h.Reset.ChangeWithCurrent(userID, in.CurrentPassword, in.NewPassword)
		if errors.Is(err, passwordreset.ErrWrongPassword) {
			h.WrongPasswordPerUser.Allow(limitKey)
		}
	} else {
		err = h.Reset.ChangeWithCode(userID, in.Code, in.NewPassword)
	}
	if err != nil {
		passwordError(c, err)
		return
	}

	var user models.User
	if err := h.DB.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load user"})
		return
	}
	token, err := issueJWT(h.JWTSecret, user)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to issue token"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "password_changed", "token": token})
}

func passwordError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, passwordreset.ErrWeakPassword):
		c.JSON(http.StatusBadRequest, gin.H{"error": "weak_password", "min_length": passwordreset.MinPasswordLen})
	case errors.Is(err, passwordreset.ErrPasswordTooLong):
		c.JSON(http.StatusBadRequest, gin.H{"error": "password_too_long"})
	case errors.Is(err, passwordreset.ErrInvalidCode):
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_code"})
	case errors.Is(err, passwordreset.ErrWrongPassword):
		c.JSON(http.StatusBadRequest, gin.H{"error": "wrong_current_password"})
	case errors.Is(err, passwordreset.ErrNotAllowed):
		c.JSON(http.StatusForbidden, gin.H{"error": "not_allowed"})
	default:
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to change password"})
	}
}

// PasswordSessionValidator retires every token issued before the user's
// last password change: valid iff iat >= password_changed_at in whole
// seconds, so a token minted in the same second as the change (the one
// ChangePassword returns) still works. Users who never changed their
// password, and ids with no row (unchanged behaviour), pass; a database
// error fails closed.
func PasswordSessionValidator(db *gorm.DB) middleware.SessionValidator {
	return func(userID uint, issuedAt int64) bool {
		var row struct{ PasswordChangedAt *time.Time }
		err := db.Model(&models.User{}).Select("password_changed_at").Where("id = ?", userID).Take(&row).Error
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return true
		}
		if err != nil {
			return false
		}
		return row.PasswordChangedAt == nil || issuedAt >= row.PasswordChangedAt.Unix()
	}
}
