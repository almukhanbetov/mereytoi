package models

import "time"

// Password recovery request statuses (internal/recoverycode, support.go).
const (
	RecoveryRequestPending  = "pending"
	RecoveryRequestApproved = "approved"
	RecoveryRequestRejected = "rejected"
	RecoveryRequestUsed     = "used"
	RecoveryRequestExpired  = "expired"
)

// PasswordRecoveryRequest is a person's request to support for a temporary
// recovery code, for when the backup code is lost or was never created. An
// admin checks who they are outside the system and approves it, which
// issues a short-lived one-time code. Only its hash is stored, and it is
// cleared as soon as the request leaves "approved".
//
// The two partial unique indexes are what bound the table and keep one live
// code per account: at most one pending and one approved request per user.
type PasswordRecoveryRequest struct {
	ID     uint   `gorm:"primaryKey" json:"id"`
	UserID uint   `gorm:"not null;index:idx_recovery_request_one_pending,unique,where:status = 'pending';index:idx_recovery_request_one_approved,unique,where:status = 'approved'" json:"user_id"`
	Status string `gorm:"size:16;not null;index" json:"status"`

	RequestedAt time.Time  `gorm:"not null;index" json:"requested_at"`
	ApprovedAt  *time.Time `json:"approved_at"`
	ApprovedBy  *uint      `json:"approved_by"`

	TempCodeHash      string     `gorm:"size:80" json:"-"`
	TempCodeExpiresAt *time.Time `json:"temp_code_expires_at"`
	UsedAt            *time.Time `json:"used_at"`
	AdminNote         string     `gorm:"size:500" json:"admin_note"`
	UpdatedAt         time.Time  `json:"updated_at"`
}

// Audit actions on a password recovery request.
const (
	RecoveryAuditRequested  = "requested"
	RecoveryAuditListed     = "listed"
	RecoveryAuditViewed     = "viewed"
	RecoveryAuditApproved   = "approved"
	RecoveryAuditReissued   = "reissued"
	RecoveryAuditSuperseded = "superseded"
	RecoveryAuditRejected   = "rejected"
	RecoveryAuditUsed       = "used"
)

// RecoveryAuditEvent is one append-only record of what happened to a recovery
// request. ActorID is the admin, or NULL for the public steps. Nothing here
// can hold a code: it records who, what, when and from which address.
// RequestID/UserID are NULL for an action on the list as a whole.
type RecoveryAuditEvent struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	RequestID *uint     `gorm:"index" json:"request_id"`
	UserID    *uint     `gorm:"index" json:"user_id"`
	ActorID   *uint     `gorm:"index" json:"actor_id"`
	Action    string    `gorm:"size:16;not null" json:"action"`
	IP        string    `gorm:"size:45" json:"ip"`
	CreatedAt time.Time `gorm:"not null;index" json:"created_at"`
}
