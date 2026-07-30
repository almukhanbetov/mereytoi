package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

const ContextUserIDKey = "userID"
const ContextUserRoleKey = "userRole"

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
		if err == nil && token.Valid {
			userID, _ := claims["sub"].(float64)
			role, _ := claims["role"].(string)
			c.Set(ContextUserIDKey, uint(userID))
			c.Set(ContextUserRoleKey, role)
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
