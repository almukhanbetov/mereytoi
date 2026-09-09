package handlers

import (
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/claimdelivery"
	"github.com/almukhanbetov/mereytoi/backend/internal/middleware"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

func normalizePhone(phone string) string {
	return strings.Join(strings.Fields(phone), "")
}

// strongNormalizePhone is a *separate*, stronger normalization used only
// by the new onboarding-matching pipeline (handlers/onboarding.go) — it
// collapses the "8.../+7..." Kazakhstani mobile prefix ambiguity that
// normalizePhone above deliberately doesn't touch (that one is left
// exactly as-is: it's still what phone-login lookup and every existing
// display use, unchanged). Returns "" for anything that isn't recognizably
// an 11-digit KZ mobile number, so it never falsely matches unrelated
// numbers.
func strongNormalizePhone(phone string) string {
	var digits strings.Builder
	for _, r := range phone {
		if r >= '0' && r <= '9' {
			digits.WriteRune(r)
		}
	}
	d := digits.String()
	if len(d) == 11 && d[0] == '8' {
		d = "7" + d[1:]
	}
	if len(d) != 11 || d[0] != '7' {
		return ""
	}
	return "+" + d
}

type AuthHandler struct {
	DB        *gorm.DB
	JWTSecret string
	Delivery  *claimdelivery.Service
}

func NewAuthHandler(db *gorm.DB, jwtSecret string, delivery *claimdelivery.Service) *AuthHandler {
	return &AuthHandler{DB: db, JWTSecret: jwtSecret, Delivery: delivery}
}

type registerInput struct {
	Name     string `json:"name" binding:"required"`
	Email    string `json:"email" binding:"required,email"`
	Phone    string `json:"phone"`
	Password string `json:"password" binding:"required,min=6"`
}

type loginInput struct {
	Email    string `json:"email"`
	Phone    string `json:"phone"`
	Password string `json:"password" binding:"required"`
}

func (h *AuthHandler) Register(c *gin.Context) {
	var in registerInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var existing models.User
	if err := h.DB.Where("email = ?", in.Email).First(&existing).Error; err == nil {
		c.JSON(http.StatusConflict, gin.H{"error": "email already registered"})
		return
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(in.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to hash password"})
		return
	}

	user := models.User{
		Name:            in.Name,
		Email:           in.Email,
		Phone:           normalizePhone(in.Phone),
		PhoneNormalized: strongNormalizePhone(in.Phone),
		PasswordHash:    string(hash),
		Role:            "user",
	}
	if err := h.DB.Create(&user).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create user"})
		return
	}

	token, err := h.issueToken(user)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to issue token"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"user": user, "token": token})
}

func (h *AuthHandler) Login(c *gin.Context) {
	var in loginInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	email := strings.TrimSpace(in.Email)
	phone := normalizePhone(in.Phone)
	if email == "" && phone == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "email or phone is required"})
		return
	}

	var user models.User
	var err error
	if email != "" {
		err = h.DB.Where("email = ?", email).First(&user).Error
	} else {
		err = h.DB.Where("phone = ?", phone).First(&user).Error
	}
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(in.Password)); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
		return
	}

	token, err := h.issueToken(user)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to issue token"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"user": user, "token": token})
}

func (h *AuthHandler) Me(c *gin.Context) {
	userID, _ := c.Get(middleware.ContextUserIDKey)

	var user models.User
	if err := h.DB.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	// telegram_linked/preferred_delivery_channel — additive, sibling to
	// "user" rather than fields on it, so User's own JSON shape (and every
	// other existing reader of it) stays exactly as it was. See
	// models.User's own doc comment on why TelegramChatID itself is never
	// serialized directly.
	c.JSON(http.StatusOK, gin.H{
		"user":                       user,
		"telegram_linked":            user.TelegramChatID != "",
		"preferred_delivery_channel": user.PreferredDeliveryChannel,
	})
}

type updateMeInput struct {
	Name  string `json:"name" binding:"required"`
	Phone string `json:"phone"`
}

func (h *AuthHandler) UpdateMe(c *gin.Context) {
	userID, _ := c.Get(middleware.ContextUserIDKey)

	var user models.User
	if err := h.DB.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	var in updateMeInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user.Name = in.Name
	user.Phone = normalizePhone(in.Phone)
	user.PhoneNormalized = strongNormalizePhone(in.Phone)
	if err := h.DB.Save(&user).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update profile"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"user": user})
}

// Claim — POST /api/auth/claim/:token (public). The one bridge a brand-new
// pending account (see handlers/onboarding.go) has into an actual session —
// issues the exact same shape of response Register/Login already do, via
// the same issueToken, plus one additive "event_id" field so a standalone
// /claim/:token page (reached fresh, with no prior booking-response state
// in hand) still knows where to send the user next. Never client-supplied
// or otherwise chosen — always "whatever event this exact account owns",
// so there is no way to claim your way into someone else's event.
// Single-use (see AccountClaim's own doc comment on why, and on what would
// need to change here first if that's ever revisited).
func (h *AuthHandler) Claim(c *gin.Context) {
	token := c.Param("token")

	var claim models.AccountClaim
	if err := h.DB.Where("token = ?", token).First(&claim).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "claim link not found"})
		return
	}
	if claim.UsedAt != nil {
		c.JSON(http.StatusGone, gin.H{"error": "claim link already used"})
		return
	}
	if time.Now().After(claim.ExpiresAt) {
		c.JSON(http.StatusGone, gin.H{"error": "claim link expired"})
		return
	}

	var user models.User
	if err := h.DB.First(&user, claim.UserID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "account not found"})
		return
	}

	jwtToken, err := h.issueToken(user)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to issue token"})
		return
	}

	// Marked used only after the token is successfully issued — a DB
	// failure above must not silently burn the claim.
	now := time.Now()
	h.DB.Model(&claim).Update("used_at", now)

	resp := gin.H{"user": user, "token": jwtToken}
	var event models.Event
	if h.DB.Where("owner_id = ?", user.ID).Order("created_at desc").First(&event).Error == nil {
		resp["event_id"] = event.ID
	}
	c.JSON(http.StatusOK, resp)
}

type claimResendInput struct {
	Phone string `json:"phone" binding:"required"`
}

// claimResendNeutralMessage is the one response body ClaimResend ever
// sends, regardless of what actually happened — brief section 12/13: this
// endpoint must never reveal whether a given phone number has a pending
// account (no enumeration), so "not found", "rate-limited" and "sent" are
// all indistinguishable from the outside.
const claimResendNeutralMessage = "Если кабинет связан с этим номером, ссылка будет отправлена."

// ClaimResend — POST /api/auth/claim/resend (public). Lets someone who
// lost their claim link (never delivered, or delivery failed) ask for a
// fresh one. Reuses mintClaim/onboarding.go's own pending-account lookup
// rather than introducing a second account-matching path; rate limiting
// happens entirely inside claimdelivery.Service.Deliver (the same
// cooldown/hourly-cap a fresh booking's own delivery attempt already goes
// through — see onboarding.go's attemptDelivery), so hammering this
// endpoint cannot turn into a message flood any more than repeatedly
// submitting the booking form could. Uses the exact same channel-priority
// logic as the original send (brief section 9 — "должен использовать тот
// же канал"): whichever of WhatsApp/Telegram is actually usable for this
// user right now, decided by Service.Deliver itself, not chosen here.
func (h *AuthHandler) ClaimResend(c *gin.Context) {
	var in claimResendInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	phone := strongNormalizePhone(in.Phone)
	if phone == "" {
		c.JSON(http.StatusOK, gin.H{"message": claimResendNeutralMessage})
		return
	}

	var user models.User
	if err := h.DB.Where("phone_normalized = ? AND status = ?", phone, models.UserStatusPending).First(&user).Error; err != nil {
		c.JSON(http.StatusOK, gin.H{"message": claimResendNeutralMessage})
		return
	}

	claim, err := mintClaim(h.DB, user.ID)
	if err == nil && h.Delivery != nil {
		h.Delivery.Deliver(h.DB, claim, &user)
	}

	c.JSON(http.StatusOK, gin.H{"message": claimResendNeutralMessage})
}

type deliveryPreferenceInput struct {
	Channel string `json:"channel" binding:"required,oneof=whatsapp telegram"`
}

// UpdateDeliveryPreference — PUT /api/users/me/delivery-preference
// (authenticated). Brief section 7's optional per-user override of the
// default WhatsApp-first priority (claimdelivery.Service.pickChannel);
// deliberately a standalone endpoint rather than folded into UpdateMe, so
// this stage never touches that existing profile-update path at all.
func (h *AuthHandler) UpdateDeliveryPreference(c *gin.Context) {
	userID, _ := c.Get(middleware.ContextUserIDKey)

	var in deliveryPreferenceInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.DB.Model(&models.User{}).Where("id = ?", userID).Update("preferred_delivery_channel", in.Channel).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save preference"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"preferred_delivery_channel": in.Channel})
}

func (h *AuthHandler) issueToken(user models.User) (string, error) {
	claims := jwt.MapClaims{
		"sub":  user.ID,
		"role": user.Role,
		"exp":  time.Now().Add(7 * 24 * time.Hour).Unix(),
		"iat":  time.Now().Unix(),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(h.JWTSecret))
}
