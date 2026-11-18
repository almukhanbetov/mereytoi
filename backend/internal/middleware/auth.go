package middleware

import (
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

const ContextUserIDKey = "userID"
const ContextUserRoleKey = "userRole"

const contextSessionValidatorKey = "sessionValidator"

// Session is a SessionValidator's verdict on one signature-valid token.
// Valid=false rejects it with Error ("session_expired" — retired by a
// password change, or the account is gone; "account_blocked" — an
// administrator's block is in force, BlockedUntil nil meaning indefinite).
// Role is the account's role read from the database at this request, which
// replaces the JWT's "role" claim: granting or revoking admin takes effect
// on the very next request, not when the token expires.
type Session struct {
	Valid        bool
	Role         string
	Error        string
	BlockedUntil *time.Time
	// BlockReason — the administrator's stated reason, shown to the blocked
	// user themselves (the same one the login refusal carries).
	BlockReason string
}

// SessionValidator decides whether a signature-valid token for userID,
// issued at issuedAt (Unix seconds, the JWT "iat"), may still be used (see
// handlers.AccountSessionValidator).
type SessionValidator func(userID uint, issuedAt int64) Session

// WithSessionValidator makes v available to RequireAuth/OptionalAuth for
// every route below it. Installed once on the /api group, so none of the
// individual RequireAuth call sites need to know about it; without it
// (e.g. a test building a bare route), tokens are only signature-checked
// and the role comes from the token, exactly as before.
func WithSessionValidator(v SessionValidator) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Set(contextSessionValidatorKey, v)
		c.Next()
	}
}

// checkSession applies the installed SessionValidator, if any. Without one
// the token's own role claim stands.
func checkSession(c *gin.Context, userID uint, claims jwt.MapClaims) Session {
	role, _ := claims["role"].(string)
	v, ok := c.Get(contextSessionValidatorKey)
	if !ok {
		return Session{Valid: true, Role: role}
	}
	validate, ok := v.(SessionValidator)
	if !ok || validate == nil {
		return Session{Valid: true, Role: role}
	}
	iat, _ := claims["iat"].(float64)
	return validate(userID, int64(iat))
}

// rejection is the 401 body for an invalid session.
func rejection(s Session) gin.H {
	code := s.Error
	if code == "" {
		code = "session_expired"
	}
	body := gin.H{"error": code}
	if code == "account_blocked" {
		body["blocked_until"] = s.BlockedUntil
		body["reason"] = s.BlockReason
	}
	return body
}

// RequireAuth validates the Bearer JWT and stores the user id/role in the
// request context for downstream handlers.
func RequireAuth(secret string) gin.HandlerFunc {
	return func(c *gin.Context) {
		header := c.GetHeader("Authorization")
		if header == "" || !strings.HasPrefix(header, "Bearer ") {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing or invalid authorization header"})
			return
		}

		tokenString := strings.TrimPrefix(header, "Bearer ")
		claims := jwt.MapClaims{}
		token, err := jwt.ParseWithClaims(tokenString, claims, func(t *jwt.Token) (interface{}, error) {
			return []byte(secret), nil
		})
		if err != nil || !token.Valid {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired token"})
			return
		}

		userID, _ := claims["sub"].(float64)
		session := checkSession(c, uint(userID), claims)
		if !session.Valid {
			c.AbortWithStatusJSON(http.StatusUnauthorized, rejection(session))
			return
		}
		c.Set(ContextUserIDKey, uint(userID))
		c.Set(ContextUserRoleKey, session.Role)
		c.Next()
	}
}

// OptionalAuth attaches the user id/role to the context when a valid Bearer
// JWT is present, but never rejects the request — used for endpoints (like
// creating a booking) that work for both guests and logged-in customers.
func OptionalAuth(secret string) gin.HandlerFunc {
	return func(c *gin.Context) {
		header := c.GetHeader("Authorization")
		if header == "" || !strings.HasPrefix(header, "Bearer ") {
			c.Next()
			return
		}

		tokenString := strings.TrimPrefix(header, "Bearer ")
		claims := jwt.MapClaims{}
		token, err := jwt.ParseWithClaims(tokenString, claims, func(t *jwt.Token) (interface{}, error) {
			return []byte(secret), nil
		})
		// A token retired by a password change, of a deleted or blocked
		// account, is treated like no token at all: the request carries on
		// as a guest.
		if err == nil && token.Valid {
			userID, _ := claims["sub"].(float64)
			if session := checkSession(c, uint(userID), claims); session.Valid {
				c.Set(ContextUserIDKey, uint(userID))
				c.Set(ContextUserRoleKey, session.Role)
			}
		}
		c.Next()
	}
}

// RequireAdmin must run after RequireAuth; it rejects non-admin users.
func RequireAdmin() gin.HandlerFunc {
	return func(c *gin.Context) {
		role, _ := c.Get(ContextUserRoleKey)
		if role != "admin" {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "admin access required"})
			return
		}
		c.Next()
	}
}
