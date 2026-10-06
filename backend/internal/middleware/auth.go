package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

const ContextUserIDKey = "userID"
const ContextUserRoleKey = "userRole"

const contextSessionValidatorKey = "sessionValidator"

// SessionValidator reports whether a signature-valid token for userID,
// issued at issuedAt (Unix seconds, the JWT "iat"), may still be used —
// false once the user's password has changed since (see
// handlers.PasswordSessionValidator).
type SessionValidator func(userID uint, issuedAt int64) bool

// WithSessionValidator makes v available to RequireAuth/OptionalAuth for
// every route below it. Installed once on the /api group, so none of the
// individual RequireAuth call sites need to know about it; without it
// (e.g. a test building a bare route), tokens are only signature-checked,
// exactly as before.
func WithSessionValidator(v SessionValidator) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Set(contextSessionValidatorKey, v)
		c.Next()
	}
}

// sessionStillValid applies the installed SessionValidator, if any.
func sessionStillValid(c *gin.Context, userID uint, claims jwt.MapClaims) bool {
	v, ok := c.Get(contextSessionValidatorKey)
	if !ok {
		return true
	}
	validate, ok := v.(SessionValidator)
	if !ok || validate == nil {
		return true
	}
	iat, _ := claims["iat"].(float64)
	return validate(userID, int64(iat))
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
		role, _ := claims["role"].(string)
		if !sessionStillValid(c, uint(userID), claims) {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "session_expired"})
			return
		}
		c.Set(ContextUserIDKey, uint(userID))
		c.Set(ContextUserRoleKey, role)
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
		// A token retired by a password change is treated like no token
		// at all: the request carries on as a guest.
		if err == nil && token.Valid {
			userID, _ := claims["sub"].(float64)
			role, _ := claims["role"].(string)
			if sessionStillValid(c, uint(userID), claims) {
				c.Set(ContextUserIDKey, uint(userID))
				c.Set(ContextUserRoleKey, role)
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
