package models

import "time"

// EventRequest is the collaborative-workspace side of "send this to
// MEREYTOI" — one per event, living in `draft` until the organizer submits
// it. It deliberately does NOT duplicate Booking: Booking already models
// "an order MEREYTOI received" (used by both anonymous cart checkouts and
// this flow) with its own new/contacted/confirmed/cancelled pipeline: that
// stays untouched. EventRequest adds the richer review workflow a
// collaborative event needs on top — draft state, revision history,
// manager back-and-forth — that Booking was never designed for, and links
// to a real Booking row once first submitted (BookingID) so the submitted
// order still shows up in the existing admin Bookings list.
type EventRequest struct {
	ID          uint   `gorm:"primaryKey" json:"id"`
	EventID     uint   `gorm:"not null;uniqueIndex" json:"event_id"`
	CreatedByID uint   `gorm:"not null" json:"created_by_id"`
	Status      string `gorm:"size:20;not null;default:draft" json:"status"`

	// OrganizerComment is editable while the request is draft or the manager
	// has asked for changes; it's frozen into each EventRequestRevision's
	// snapshot at submit time, not just kept live.
	OrganizerComment string `gorm:"type:text" json:"organizer_comment"`
	// ManagerComment is always the *latest* manager note — shown prominently
	// to the organizer. Full history lives implicitly via the activity feed.
	ManagerComment string `gorm:"type:text" json:"manager_comment"`

	BookingID *uint `json:"booking_id,omitempty"`

	LatestRevision int        `gorm:"not null;default:0" json:"latest_revision"`
	SubmittedAt    *time.Time `json:"submitted_at,omitempty"`

	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

const (
	RequestDraft            = "draft"
	RequestSubmitted        = "submitted"
	RequestInReview         = "in_review"
	RequestChangesRequested = "changes_requested"
	RequestApproved         = "approved"
	RequestRejected         = "rejected"
	RequestCancelled        = "cancelled"
)

// Editable reports whether the organizer's comment (and, by extension, the
// event's own selections) can still be changed before/for the next
// revision — true only pre-submission or once the manager has asked for
// changes.
func RequestEditable(status string) bool {
	return status == RequestDraft || status == RequestChangesRequested
}

// requestTransitions is the admin-side status state machine — every key is
// a status manager review can move *from*, mapped to the statuses it may
// move *to*. Anything not listed here (including every transition out of
// approved/rejected/cancelled) is rejected.
var requestTransitions = map[string][]string{
	RequestSubmitted: {RequestInReview, RequestChangesRequested, RequestApproved, RequestRejected},
	RequestInReview:  {RequestChangesRequested, RequestApproved, RequestRejected},
}

// CanTransition reports whether an admin may move a request from `from` to
// `to` directly.
func CanTransition(from, to string) bool {
	for _, allowed := range requestTransitions[from] {
		if allowed == to {
			return true
		}
	}
	return false
}

// EventRequestRevision is one frozen snapshot of an EventRequest at the
// moment it was (re)submitted — selections may keep changing in the event
// workspace afterward, but a revision, once created, never does.
type EventRequestRevision struct {
	ID             uint  `gorm:"primaryKey" json:"id"`
	EventRequestID uint  `gorm:"not null;index" json:"event_request_id"`
	RevisionNumber int   `gorm:"not null" json:"revision_number"`
	SubmittedByID  uint  `gorm:"not null" json:"submitted_by_id"`
	SubmittedBy    *User `gorm:"foreignKey:SubmittedByID" json:"submitted_by,omitempty"`
	// SnapshotJSON is the frozen picture (event details + selected
	// services/prices/votes at the time) — see handlers/event_request_handler.go
	// for the shape. Never mutated once written.
	SnapshotJSON string         `gorm:"type:text;not null" json:"-"`
	Snapshot     map[string]any `gorm:"-" json:"snapshot,omitempty"`
	Total        uint           `gorm:"not null;default:0" json:"total"`
	SubmittedAt  time.Time      `json:"submitted_at"`
	CreatedAt    time.Time      `json:"created_at"`
}
