package models

import "time"

// Notification is a per-user alert, distinct from EventActivity:
// EventActivity records *what happened in the event* (a shared, public
// feed everyone in the event sees the same way); Notification records
// *which user should be told about it* — one action can fan out into zero,
// one, or several Notification rows for different recipients, and each
// recipient reads/dismisses their own independently.
//
// Deliberately no Title/Message text columns: storing pre-rendered strings
// would freeze a notification in whatever language it was created in, so a
// user switching RU→KZ would see stale-language history. Instead this
// stores structured references (Type + Payload + Actor/Event/Entity) and
// the frontend renders localized copy from Type at read time — the same
// approach already used for EventActivity.Payload/PayloadJSON.
type Notification struct {
	ID uint `gorm:"primaryKey" json:"id"`
	// UserID is the recipient — every query in the handler is scoped to
	// "user_id = current user", so one user can never see or touch another's row.
	UserID  uint   `gorm:"not null;index:idx_notif_user_read" json:"user_id"`
	ActorID *uint  `json:"actor_id,omitempty"` // nil = system-generated
	Actor   *User  `gorm:"foreignKey:ActorID" json:"actor,omitempty"`
	EventID *uint  `gorm:"index" json:"event_id,omitempty"`
	Event   *Event `gorm:"foreignKey:EventID" json:"event,omitempty"`

	// Type: one of the NotificationType* constants below.
	Type string `gorm:"size:40;not null" json:"type"`
	// EntityType + EntityID are the deep-link target (e.g. "candidate"/12,
	// "task"/3) — kept as structured refs rather than a stored frontend URL,
	// so a later route rename can't leave old notifications pointing at a
	// dead link (brief section 15).
	EntityType string `gorm:"size:20" json:"entity_type,omitempty"`
	EntityID   *uint  `json:"entity_id,omitempty"`

	// Payload is the same small-denormalized-snapshot idea as
	// EventActivity.Payload (a name/price/value/title at the time) — just
	// enough for the notification text to read correctly even if the
	// underlying row later changes.
	Payload     string         `gorm:"type:text" json:"-"`
	PayloadJSON map[string]any `gorm:"-" json:"payload,omitempty"`

	IsRead    bool       `gorm:"not null;default:false;index:idx_notif_user_read" json:"is_read"`
	ReadAt    *time.Time `json:"read_at,omitempty"`
	CreatedAt time.Time  `gorm:"index" json:"created_at"`
}

// 10A types — invitation_received is intentionally NOT included: this
// project's invitations are shareable links with a role, not a message
// addressed to a specific known user (there's no "invitee user_id" to
// notify until they actually accept) — see the stage report for the full
// explanation. Manager/request-decision types belong to 10B.
const (
	NotifInvitationAccepted = "invitation_accepted"
	NotifCandidateAdded     = "candidate_added"
	NotifVoteAdded          = "vote_added"
	NotifVoteChanged        = "vote_changed"
	NotifCommentAdded       = "comment_added"
	NotifBudgetUpdated      = "budget_updated"
	NotifTaskCreated        = "task_created"
	NotifTaskUpdated        = "task_updated"
	NotifTaskCompleted      = "task_completed"
	NotifMemberJoined       = "member_joined"
	NotifMemberRoleChanged  = "member_role_changed"
)
