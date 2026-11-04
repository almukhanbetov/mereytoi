package handlers

import (
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/middleware"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
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
	// OTP sends and redeems the codes of email recovery.
	OTP *passwordreset.Service
}

func NewRecoveryHandler(db *gorm.DB, jwtSecret string, svc *recoverycode.Service, otp *passwordreset.Service) *RecoveryHandler {
	return &RecoveryHandler{DB: db, JWTSecret: jwtSecret, Svc: svc, OTP: otp}
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
	case errors.Is(err, recoverycode.ErrInvalid), errors.Is(err, passwordreset.ErrInvalidCode):
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

type supportRequestInput struct {
	Login string `json:"login" binding:"required"`
}

// SupportRequest — POST /api/auth/recovery/support-request (public). Asks
// support for a temporary code. The answer is the same whether or not the
// account exists; only the per-address limit shows (429).
func (h *RecoveryHandler) SupportRequest(c *gin.Context) {
	noStore(c)
	var in supportRequestInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request"})
		return
	}
	if err := h.Svc.RequestSupport(recoveryIdentifier(in.Login), c.ClientIP()); err != nil {
		recoveryError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

type supportResetInput struct {
	Login       string `json:"login" binding:"required"`
	TempCode    string `json:"temp_code" binding:"required"`
	NewPassword string `json:"new_password" binding:"required"`
}

// SupportReset — POST /api/auth/recovery/support-reset (public). Sets a new
// password with the temporary code. On success every earlier session is
// revoked and the response carries a fresh token and a new backup code. An
// unknown account and a wrong, expired or used code get the same 400.
func (h *RecoveryHandler) SupportReset(c *gin.Context) {
	noStore(c)
	var in supportResetInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request"})
		return
	}
	res, err := h.Svc.ResetWithTempCode(recoveryIdentifier(in.Login), in.TempCode, in.NewPassword, c.ClientIP())
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

// recoveryRequestView is what an admin sees: never a hash. The fields are
// listed one by one so a new column can't leak by default.
func recoveryRequestView(r models.PasswordRecoveryRequest, u *models.User) gin.H {
	view := gin.H{
		"id":                   r.ID,
		"user_id":              r.UserID,
		"status":               r.Status,
		"requested_at":         r.RequestedAt,
		"approved_at":          r.ApprovedAt,
		"approved_by":          r.ApprovedBy,
		"temp_code_expires_at": r.TempCodeExpiresAt,
		"used_at":              r.UsedAt,
		"admin_note":           r.AdminNote,
	}
	if u != nil {
		view["user"] = gin.H{"id": u.ID, "name": u.Name, "email": u.Email, "phone": u.Phone, "role": u.Role, "status": u.Status}
	}
	return view
}

func recoveryActor(c *gin.Context) recoverycode.Actor {
	userID, _ := c.Get(middleware.ContextUserIDKey)
	return recoverycode.Actor{ID: userID.(uint), IP: c.ClientIP()}
}

func recoveryRequestID(c *gin.Context) (uint, bool) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil || id == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request"})
		return 0, false
	}
	return uint(id), true
}

func adminRecoveryError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, recoverycode.ErrRequestNotFound):
		c.JSON(http.StatusNotFound, gin.H{"error": "not_found"})
	case errors.Is(err, recoverycode.ErrRequestState):
		c.JSON(http.StatusConflict, gin.H{"error": "invalid_status"})
	case errors.Is(err, recoverycode.ErrSelfApproval):
		c.JSON(http.StatusForbidden, gin.H{"error": "self_approval_forbidden"})
	default:
		recoveryError(c, err)
	}
}

// AdminListRequests — GET /api/admin/recovery-requests?status=pending.
func (h *RecoveryHandler) AdminListRequests(c *gin.Context) {
	noStore(c)
	status := c.Query("status")
	switch status {
	case "", models.RecoveryRequestPending, models.RecoveryRequestApproved, models.RecoveryRequestRejected,
		models.RecoveryRequestUsed, models.RecoveryRequestExpired:
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_status"})
		return
	}
	page, err := h.Svc.ListRequests(status, recoveryActor(c))
	if err != nil {
		adminRecoveryError(c, err)
		return
	}
	requests := make([]gin.H, 0, len(page.Requests))
	for _, r := range page.Requests {
		var user *models.User
		if u, ok := page.Users[r.UserID]; ok {
			user = &u
		}
		requests = append(requests, recoveryRequestView(r, user))
	}
	c.JSON(http.StatusOK, gin.H{"requests": requests})
}

// AdminGetRequest — GET /api/admin/recovery-requests/:id, with the audit trail.
func (h *RecoveryHandler) AdminGetRequest(c *gin.Context) {
	noStore(c)
	id, ok := recoveryRequestID(c)
	if !ok {
		return
	}
	out, err := h.Svc.GetRequest(id, recoveryActor(c))
	if err != nil {
		adminRecoveryError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"request": recoveryRequestView(out.Request, out.User), "audit": out.Audit})
}

type recoveryDecisionInput struct {
	Note string `json:"note" binding:"max=500"`
}

// recoveryDecision reads the optional note; an empty body is fine.
func recoveryDecision(c *gin.Context) (string, bool) {
	var in recoveryDecisionInput
	if err := c.ShouldBindJSON(&in); err != nil && !errors.Is(err, io.EOF) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request"})
		return "", false
	}
	return strings.TrimSpace(in.Note), true
}

// AdminApproveRequest — POST /api/admin/recovery-requests/:id/approve. The
// response is the only place the temporary code ever appears.
func (h *RecoveryHandler) AdminApproveRequest(c *gin.Context) {
	noStore(c)
	id, ok := recoveryRequestID(c)
	if !ok {
		return
	}
	note, ok := recoveryDecision(c)
	if !ok {
		return
	}
	res, err := h.Svc.Approve(id, note, recoveryActor(c))
	if err != nil {
		adminRecoveryError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"request":    recoveryRequestView(res.Request, nil),
		"temp_code":  recoverycode.Format(res.Code),
		"expires_at": res.Request.TempCodeExpiresAt,
	})
}

// AdminRejectRequest — POST /api/admin/recovery-requests/:id/reject. Also
// revokes the code of an already approved request.
func (h *RecoveryHandler) AdminRejectRequest(c *gin.Context) {
	noStore(c)
	id, ok := recoveryRequestID(c)
	if !ok {
		return
	}
	note, ok := recoveryDecision(c)
	if !ok {
		return
	}
	req, err := h.Svc.Reject(id, note, recoveryActor(c))
	if err != nil {
		adminRecoveryError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"request": recoveryRequestView(req, nil)})
}

type emailOTPRequestInput struct {
	Email string `json:"email" binding:"required"`
	Lang  string `json:"lang"`
}

// EmailOTPRequest — POST /api/auth/recovery/email/request (public). Sends a
// code if the address belongs to an active account. The answer is the same in
// every case and comes before any lookup or send; only the per-address limit
// shows (429), which says nothing about the email.
func (h *RecoveryHandler) EmailOTPRequest(c *gin.Context) {
	noStore(c)
	var in emailOTPRequestInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request"})
		return
	}
	send, err := h.Svc.AllowEmailOTPRequest(c.ClientIP(), in.Email)
	if err != nil {
		recoveryError(c, err)
		return
	}
	if send {
		h.OTP.RequestEmailReset(in.Email, in.Lang, c.ClientIP())
	}
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

type emailOTPResetInput struct {
	Email       string `json:"email" binding:"required"`
	OTP         string `json:"otp" binding:"required"`
	NewPassword string `json:"new_password" binding:"required"`
}

// EmailOTPReset — POST /api/auth/recovery/email/reset (public). Sets a new
// password with the code; every earlier session is revoked. An unknown email
// and a wrong, expired or used code get the same 400.
func (h *RecoveryHandler) EmailOTPReset(c *gin.Context) {
	noStore(c)
	var in emailOTPResetInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request"})
		return
	}
	if err := passwordreset.CheckNewPassword(in.NewPassword); err != nil {
		recoveryError(c, err)
		return
	}
	if !h.Svc.AllowEmailOTPReset(c.ClientIP(), in.Email) {
		recoveryError(c, recoverycode.ErrRateLimited)
		return
	}
	if err := h.OTP.ConfirmEmailReset(in.Email, in.OTP, in.NewPassword, c.ClientIP()); err != nil {
		recoveryError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}
