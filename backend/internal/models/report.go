package models

import "time"

// Report is a user's complaint about a listing, a provider profile, a review
// (comment) or another user. It never acts by itself: nothing is blocked or
// hidden because of a report — an administrator decides and, if needed,
// acts separately through the admin API (both recorded in
// admin_audit_events). Private conversations are not reportable yet.
//
// The reporter's identity is admin-only: no endpoint shows a report to the
// person or content it is about.
type Report struct {
	ID         uint `gorm:"primaryKey" json:"id"`
	ReporterID uint `gorm:"not null;index" json:"reporter_id"`
	// TargetType/TargetID — what is reported (ReportTarget* below).
	TargetType string `gorm:"size:20;not null;index:idx_report_target" json:"target_type"`
	TargetID   uint   `gorm:"not null;index:idx_report_target" json:"target_id"`
	// TargetUserID — the account answerable for the target at report time
	// (listing owner, provider's user, review author, the user), so an
	// administrator can see every complaint about one person. NULL when a
	// listing has no owner (an admin-made catalog card).
	TargetUserID *uint  `gorm:"index" json:"target_user_id"`
	Reason       string `gorm:"size:20;not null;index" json:"reason"`
	Details      string `gorm:"type:text" json:"details"`
	Status       string `gorm:"size:20;not null;index" json:"status"`
	// OpenKey is "reporter:type:id" while the report is open (new or
	// in_review) and NULL once decided: the unique index makes a second open
	// report by the same person on the same thing impossible even under a
	// race, while decided ones never block a new report.
	OpenKey *string `gorm:"size:80;uniqueIndex" json:"-"`
	// AssigneeID — the administrator who took it into work.
	AssigneeID *uint      `json:"assignee_id"`
	ResolvedBy *uint      `json:"resolved_by"`
	ResolvedAt *time.Time `json:"resolved_at"`
	// Resolution — the administrator's required explanation of the decision.
	Resolution string    `gorm:"type:text" json:"resolution"`
	CreatedAt  time.Time `gorm:"index" json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

// Report targets.
const (
	ReportTargetListing  = "listing"
	ReportTargetProvider = "provider"
	ReportTargetComment  = "comment"
	ReportTargetUser     = "user"
)

// Report reasons.
const (
	ReportReasonSpam          = "spam"
	ReportReasonFraud         = "fraud"
	ReportReasonAbuse         = "abuse"
	ReportReasonInappropriate = "inappropriate"
	ReportReasonRights        = "rights"
	ReportReasonOther         = "other"
)

// Report statuses.
const (
	ReportStatusNew      = "new"
	ReportStatusInReview = "in_review"
	ReportStatusResolved = "resolved"
	ReportStatusRejected = "rejected"
)
