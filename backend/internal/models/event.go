package models

import "time"

// Event is a user's "Мой той" workspace — one wedding/той/anniversary/
// corporate event being planned collaboratively. OwnerID is denormalized
// alongside the owner's own EventMember row (role=owner) so "is this the
// creator" checks never require a join.
type Event struct {
	ID      uint `gorm:"primaryKey" json:"id"`
	OwnerID uint `gorm:"not null;index" json:"owner_id"`

	Title string `gorm:"size:200;not null" json:"title"`
	// Type: wedding | toi | anniversary | corporate | other — free-form
	// string rather than a DB enum, matching how Booking.Status/Listing
	// fields are modeled elsewhere in this codebase.
	Type string `gorm:"size:30;not null;default:other" json:"type"`

	EventDate *time.Time `json:"event_date,omitempty"`
	City      string     `gorm:"size:100" json:"city"`
	Guests    uint       `gorm:"default:0" json:"guests"`
	// BudgetTotal is the only budget figure actually stored — "spent" is
	// always computed live from selected candidates, never persisted, so it
	// can never drift out of sync with the shortlist.
	BudgetTotal uint   `gorm:"default:0" json:"budget_total"`
	Comment     string `gorm:"type:text" json:"comment"`

	// Status: planning (default) | submitted — flips once a final заявка is
	// generated (Phase 4). Kept here now so the column exists and defaults
	// safely even before Phase 4 ships.
	Status string `gorm:"size:20;not null;default:planning" json:"status"`

	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// Event roles, ranked low→high so a single integer comparison expresses
// "at least editor", "owner only", etc. — see RoleRank.
const (
	EventRoleViewer = "viewer"
	EventRoleEditor = "editor"
	EventRoleOwner  = "owner"
)

// RoleRank turns a role string into a comparable rank. Unknown values rank
// below viewer (i.e. "no access") rather than panicking or granting access.
func RoleRank(role string) int {
	switch role {
	case EventRoleOwner:
		return 3
	case EventRoleEditor:
		return 2
	case EventRoleViewer:
		return 1
	default:
		return 0
	}
}

// EventMember links a user to an event with a role. The owner is also a
// row here (role=owner) so every "who can see/do X" query is a single
// table, never a special case for the creator.
type EventMember struct {
	ID       uint      `gorm:"primaryKey" json:"id"`
	EventID  uint      `gorm:"not null;index:idx_event_member,unique" json:"event_id"`
	UserID   uint      `gorm:"not null;index:idx_event_member,unique" json:"user_id"`
	Role     string    `gorm:"size:20;not null" json:"role"`
	User     *User     `gorm:"foreignKey:UserID" json:"user,omitempty"`
	JoinedAt time.Time `json:"joined_at"`
}

// EventInvitation is a single-use-until-revoked join link — the same token
// works whether it's shared as a raw URL, wrapped in a WhatsApp message, or
// pasted into an email/mailto: link (this project has no outbound email
// infrastructure to reuse, so "invite by email" is the same link, not a
// server-sent email).
type EventInvitation struct {
	ID      uint   `gorm:"primaryKey" json:"id"`
	EventID uint   `gorm:"not null;index" json:"event_id"`
	Token   string `gorm:"size:64;uniqueIndex;not null" json:"token"`
	// Role granted to whoever accepts this invitation.
	Role        string     `gorm:"size:20;not null" json:"role"`
	CreatedByID uint       `gorm:"not null" json:"created_by_id"`
	Revoked     bool       `gorm:"not null;default:false" json:"revoked"`
	UsedByID    *uint      `json:"used_by_id,omitempty"`
	UsedAt      *time.Time `json:"used_at,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
}

// EventCandidate is one listing shortlisted for an event. "candidate" and
// "shortlisted" from the brief's state list collapse into one thing here —
// anything added to an event IS shortlisted; the meaningful states past
// that are only whether it's been decided on.
type EventCandidate struct {
	ID        uint     `gorm:"primaryKey" json:"id"`
	EventID   uint     `gorm:"not null;index" json:"event_id"`
	ListingID uint     `gorm:"not null;index" json:"listing_id"`
	Listing   *Listing `gorm:"foreignKey:ListingID" json:"listing,omitempty"`
	// Status: shortlisted (default) | selected | rejected.
	Status    string    `gorm:"size:20;not null;default:shortlisted" json:"status"`
	AddedByID uint      `gorm:"not null" json:"added_by_id"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

const (
	CandidateShortlisted = "shortlisted"
	CandidateSelected    = "selected"
	CandidateRejected    = "rejected"
)

// EventVote is one member's vote on one candidate — unique on
// (candidate_id, user_id) so a member can change their mind but never vote
// twice.
type EventVote struct {
	ID          uint  `gorm:"primaryKey" json:"id"`
	CandidateID uint  `gorm:"not null;index:idx_candidate_vote,unique" json:"candidate_id"`
	UserID      uint  `gorm:"not null;index:idx_candidate_vote,unique" json:"user_id"`
	User        *User `gorm:"foreignKey:UserID" json:"user,omitempty"`
	// Value: up | maybe | down.
	Value     string    `gorm:"size:10;not null" json:"value"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

const (
	VoteUp    = "up"
	VoteMaybe = "maybe"
	VoteDown  = "down"
)

// EventComment covers both the per-service discussion thread and the
// event-wide "Обсуждение" tab — CandidateID nil means it's a general
// message, non-nil scopes it to one shortlisted service. One table instead
// of two: the shape (author, body, timestamp) is identical either way.
type EventComment struct {
	ID          uint      `gorm:"primaryKey" json:"id"`
	EventID     uint      `gorm:"not null;index" json:"event_id"`
	CandidateID *uint     `gorm:"index" json:"candidate_id,omitempty"`
	UserID      uint      `gorm:"not null" json:"user_id"`
	User        *User     `gorm:"foreignKey:UserID" json:"user,omitempty"`
	Body        string    `gorm:"type:text;not null" json:"body"`
	CreatedAt   time.Time `json:"created_at"`
}

// EventActivity is an append-only log entry for the workspace's shared
// activity feed. Payload carries a small denormalized snapshot (e.g. a
// listing's name/price at the time) so the feed still reads correctly even
// if the underlying row is later edited or removed.
type EventActivity struct {
	ID          uint           `gorm:"primaryKey" json:"id"`
	EventID     uint           `gorm:"not null;index" json:"event_id"`
	ActorID     *uint          `json:"actor_id,omitempty"` // nil = system-generated
	Actor       *User          `gorm:"foreignKey:ActorID" json:"actor,omitempty"`
	Verb        string         `gorm:"size:40;not null" json:"verb"`
	Payload     string         `gorm:"type:text" json:"-"`
	PayloadJSON map[string]any `gorm:"-" json:"payload,omitempty"`
	CreatedAt   time.Time      `json:"created_at"`
}

// EventTask is one checklist item — deliberately flat (no sub-tasks, no
// priority, no labels) per the brief's "не превращать в Jira".
type EventTask struct {
	ID         uint       `gorm:"primaryKey" json:"id"`
	EventID    uint       `gorm:"not null;index" json:"event_id"`
	Title      string     `gorm:"size:300;not null" json:"title"`
	AssigneeID *uint      `json:"assignee_id,omitempty"`
	Assignee   *User      `gorm:"foreignKey:AssigneeID" json:"assignee,omitempty"`
	DueDate    *time.Time `json:"due_date,omitempty"`
	// Status: todo | doing | done.
	Status      string    `gorm:"size:10;not null;default:todo" json:"status"`
	CreatedByID uint      `gorm:"not null" json:"created_by_id"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

const (
	TaskTodo  = "todo"
	TaskDoing = "doing"
	TaskDone  = "done"
)
