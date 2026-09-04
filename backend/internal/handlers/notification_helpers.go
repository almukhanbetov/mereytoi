package handlers

import (
	"encoding/json"

	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// createNotification is the one place a Notification row gets written —
// every call site below goes through this, so "never notify the actor
// about their own action" (brief section 19) is enforced exactly once,
// not re-checked at every call site.
func createNotification(db *gorm.DB, userID uint, actorID uint, eventID uint, notifType, entityType string, entityID uint, payload map[string]any) {
	if userID == 0 || userID == actorID {
		return
	}
	data, _ := json.Marshal(payload)

	n := models.Notification{
		UserID:  userID,
		Type:    notifType,
		Payload: string(data),
	}
	if actorID != 0 {
		a := actorID
		n.ActorID = &a
	}
	if eventID != 0 {
		e := eventID
		n.EventID = &e
	}
	if entityType != "" {
		n.EntityType = entityType
	}
	if entityID != 0 {
		i := entityID
		n.EntityID = &i
	}
	db.Create(&n)
}

// notifyMany fans the same notification out to several recipients — used
// wherever "the team" or "everyone but the actor" needs telling, deduping
// so a user who'd otherwise be counted twice (e.g. both an assignee and a
// generic member match) only gets one row.
func notifyMany(db *gorm.DB, userIDs []uint, actorID, eventID uint, notifType, entityType string, entityID uint, payload map[string]any) {
	seen := make(map[uint]bool, len(userIDs))
	for _, uid := range userIDs {
		if uid == 0 || seen[uid] {
			continue
		}
		seen[uid] = true
		createNotification(db, uid, actorID, eventID, notifType, entityType, entityID, payload)
	}
}

// memberUserIDs returns the user IDs of every event member at or above
// minRole — e.g. models.EventRoleViewer for "everyone", or
// models.EventRoleEditor to exclude viewers (budget updates only concern
// people actually deciding, per the brief's explicit "organizer +
// participants" rule).
func memberUserIDs(db *gorm.DB, eventID uint, minRole string) []uint {
	var members []models.EventMember
	db.Where("event_id = ?", eventID).Find(&members)
	minRank := models.RoleRank(minRole)
	ids := make([]uint, 0, len(members))
	for _, m := range members {
		if models.RoleRank(m.Role) >= minRank {
			ids = append(ids, m.UserID)
		}
	}
	return ids
}

func eventOwnerID(db *gorm.DB, eventID uint) uint {
	var event models.Event
	if db.First(&event, eventID).Error != nil {
		return 0
	}
	return event.OwnerID
}
