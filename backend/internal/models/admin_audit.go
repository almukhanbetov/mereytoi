package models

import "time"

// AdminAuditEvent is one append-only record of an administrator's action:
// who (ActorID), what (Action), on which object (TargetType/TargetID), why
// (Reason, required for every sanction) and a small safe summary of what
// changed (Changes — JSON of plain before/after values; never a password,
// token, code or hash). It is written in the same transaction as the action
// itself (handlers.recordAdminAudit), so an action without its record — or a
// record of an action that didn't happen — can't exist. No API updates or
// deletes these rows.
type AdminAuditEvent struct {
	ID          uint           `gorm:"primaryKey" json:"id"`
	ActorID     uint           `gorm:"not null;index" json:"actor_id"`
	Action      string         `gorm:"size:40;not null;index" json:"action"`
	TargetType  string         `gorm:"size:20;not null;index:idx_admin_audit_target" json:"target_type"`
	TargetID    uint           `gorm:"not null;index:idx_admin_audit_target" json:"target_id"`
	Reason      string         `gorm:"type:text" json:"reason"`
	Changes     string         `gorm:"type:text" json:"-"`
	ChangesJSON map[string]any `gorm:"-" json:"changes,omitempty"`
	IP          string         `gorm:"size:45" json:"ip"`
	CreatedAt   time.Time      `gorm:"not null;index" json:"created_at"`
}

// Admin audit actions.
const (
	AdminActionUserWarn       = "user.warn"
	AdminActionUserBlock      = "user.block"
	AdminActionUserUnblock    = "user.unblock"
	AdminActionListingHide    = "listing.hide"
	AdminActionListingRestore = "listing.restore"
	AdminActionReportTake     = "report.take"
	AdminActionReportResolve  = "report.resolve"
	AdminActionReportReject   = "report.reject"
)

// Admin audit target types.
const (
	AdminTargetUser    = "user"
	AdminTargetListing = "listing"
	AdminTargetReport  = "report"
)
