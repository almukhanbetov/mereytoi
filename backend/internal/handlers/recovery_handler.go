package handlers

import (
	"errors"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/middleware"
	"github.com/almukhanbetov/mereytoi/backend/internal/passwordreset"
	"github.com/almukhanbetov/mereytoi/backend/internal/recoverycode"
)

// RecoveryHandler — password recovery with the one-time backup code
// (internal/recoverycode). Works whatever PASSWORD_RESET_DELIVERY_ENABLED
// says: nothing is delivered anywhere.
type RecoveryHandler struct {
	DB        *gorm.DB
	JWTSecret string
	Svc       *recoverycode.Service
}

func NewRecoveryHandler(db *gorm.DB, jwtSecret string, svc *recoverycode.Service) *RecoveryHandler {
	return &RecoveryHandler{DB: db, JWTSecret: jwtSecret, Svc: svc}
}

// noStore keeps a response carrying a secret (a backup code, a token) out
// of every cache along the way.
func noStore(c *gin.Context) {
	c.Header("Cache-Control", "no-store")
	c.Header("Pragma", "no-cache")
}

type recoverInput struct {
	// Login is an email or a phone number, the same as at sign-in.
	Login       string `json:"login" binding:"required"`
	Code        string `json:"code" binding:"required"`
	NewPassword string `json:"new_password" binding:"required"`
}

// Recover — POST /api/auth/recovery/reset (public). On success the new
// password is set, every earlier session is revoked, the used code is
// replaced and the response carries a fresh session token plus the new
// code. An unknown email/phone and a wrong code get the same 400.
func (h *RecoveryHandler) Recover(c *gin.Context) {
	noStore(c)
	var in recoverInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request"})
		return
	}
	res, err := h.Svc.Recover(recoveryIdentifier(in.Login), in.Code, in.NewPassword, c.ClientIP())
	if err != nil {
		recoveryError(c, err)
		return
	}
	token, err := issueJWT(h.JWTSecret, res.User)
	if err != nil {
		// The password did change; the client can still sign in with it.
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to issue token"})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"user":          res.User,
		"token":         token,
		"recovery_code": recoverycode.Format(res.Code),
	})
}

type replaceCodeInput struct {
	CurrentPassword string `json:"current_password" binding:"required"`
}

// ReplaceCode — POST /api/users/me/recovery-code (auth). Creates a new
// backup code after checking the current password; the previous one stops
// working immediately. The old code can never be shown again.
func (h *RecoveryHandler) ReplaceCode(c *gin.Context) {
	noStore(c)
	var in replaceCodeInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request"})
		return
	}
	userID, _ := c.Get(middleware.ContextUserIDKey)
	code, err := h.Svc.Replace(userID.(uint), in.CurrentPassword)
	if err != nil {
		recoveryError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"recovery_code": recoverycode.Format(code)})
}

func recoveryIdentifier(login string) recoverycode.Identifier {
	login = strings.TrimSpace(login)
	if strings.Contains(login, "@") {
		return recoverycode.Identifier{Email: login}
	}
	return recoverycode.Identifier{
		PhoneNormalized: strongNormalizePhone(login),
		PhoneRaw:        normalizePhone(login),
	}
}

func recoveryError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, passwordreset.ErrWeakPassword):
		c.JSON(http.StatusBadRequest, gin.H{"error": "weak_password", "min_length": passwordreset.MinPasswordLen})
	case errors.Is(err, passwordreset.ErrPasswordTooLong):
		c.JSON(http.StatusBadRequest, gin.H{"error": "password_too_long"})
	case errors.Is(err, recoverycode.ErrInvalid):
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_recovery_code"})
	case errors.Is(err, recoverycode.ErrRateLimited):
		c.JSON(http.StatusTooManyRequests, gin.H{"error": "too_many_attempts"})
	case errors.Is(err, recoverycode.ErrWrongPassword):
		c.JSON(http.StatusBadRequest, gin.H{"error": "wrong_current_password"})
	case errors.Is(err, recoverycode.ErrNotAllowed):
		c.JSON(http.StatusForbidden, gin.H{"error": "not_allowed"})
	default:
		c.JSON(http.StatusInternalServerError, gin.H{"error": "recovery_failed"})
	}
}
