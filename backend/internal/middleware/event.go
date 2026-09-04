package middleware

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

const ContextEventIDKey = "eventID"
const ContextEventRoleKey = "eventRole"

// RequireEventRole must run after RequireAuth, on a route with an :id param
// naming the event. It loads the caller's EventMember row and rejects the
// request unless their role ranks at least minRole (see models.RoleRank).
//
// A non-member gets 404, not 403 — this is the guard against the "subbing
// in another event's ID" attack the brief calls out: someone who isn't a
// member can't even tell the event exists, let alone that they lack
// permission on it.
func RequireEventRole(db *gorm.DB, minRole string) gin.HandlerFunc {
	minRank := models.RoleRank(minRole)
	return func(c *gin.Context) {
		eventID, err := strconv.Atoi(c.Param("id"))
		if err != nil {
			c.AbortWithStatusJSON(http.StatusBadRequest, gin.H{"error": "invalid event id"})
			return
		}

		userIDVal, _ := c.Get(ContextUserIDKey)
		userID, _ := userIDVal.(uint)

		var member models.EventMember
		if err := db.Where("event_id = ? AND user_id = ?", eventID, userID).First(&member).Error; err != nil {
			c.AbortWithStatusJSON(http.StatusNotFound, gin.H{"error": "event not found"})
			return
		}
		if models.RoleRank(member.Role) < minRank {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "insufficient role"})
			return
		}

		c.Set(ContextEventIDKey, uint(eventID))
		c.Set(ContextEventRoleKey, member.Role)
		c.Next()
	}
}
