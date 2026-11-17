package handlers

import (
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// ReportHandler — users' complaints (POST /api/reports, GET
// /api/reports/mine). A report only queues the matter for an administrator;
// it never blocks, hides or notifies anyone by itself, and the reporter's
// identity is never shown to whoever the report is about.
type ReportHandler struct {
	DB  *gorm.DB
	Now func() time.Time
}

func NewReportHandler(db *gorm.DB) *ReportHandler {
	return &ReportHandler{DB: db, Now: time.Now}
}

func (h *ReportHandler) now() time.Time { return h.Now().UTC() }

// Rate limits per reporter, counted in the database so they survive
// restarts and hold across instances.
const (
	reportsPerHour     = 10
	reportsPerDay      = 30
	reportDetailsMax   = 2000
	reportOtherMinChar = 5
)

var reportTargets = map[string]bool{
	models.ReportTargetListing: true, models.ReportTargetProvider: true,
	models.ReportTargetComment: true, models.ReportTargetUser: true,
}

var reportReasons = map[string]bool{
	models.ReportReasonSpam: true, models.ReportReasonFraud: true, models.ReportReasonAbuse: true,
	models.ReportReasonInappropriate: true, models.ReportReasonRights: true, models.ReportReasonOther: true,
}

type reportInput struct {
	TargetType string `json:"target_type"`
	TargetID   uint   `json:"target_id"`
	Reason     string `json:"reason"`
	Details    string `json:"details"`
}

// reportOut is what the reporter sees of their own report: no decision
// text, no administrator ids.
type reportOut struct {
	ID         uint       `json:"id"`
	TargetType string     `json:"target_type"`
	TargetID   uint       `json:"target_id"`
	Reason     string     `json:"reason"`
	Status     string     `json:"status"`
	CreatedAt  time.Time  `json:"created_at"`
	ResolvedAt *time.Time `json:"resolved_at"`
}

func reportOutFrom(r models.Report) reportOut {
	return reportOut{ID: r.ID, TargetType: r.TargetType, TargetID: r.TargetID, Reason: r.Reason,
		Status: r.Status, CreatedAt: r.CreatedAt, ResolvedAt: r.ResolvedAt}
}

func reportOpenKey(reporter uint, targetType string, targetID uint) *string {
	k := fmt.Sprintf("%d:%s:%d", reporter, targetType, targetID)
	return &k
}

// resolveReportTarget checks that the target exists and that the reporter
// can see it (so a report can't probe hidden content), and returns the
// account answerable for it. status != 0 means answer with it.
func resolveReportTarget(c *gin.Context, db *gorm.DB, targetType string, id, reporter uint) (answerable *uint, status int, code string) {
	notFound := func() (*uint, int, string) { return nil, http.StatusNotFound, "target_not_found" }
	switch targetType {
	case models.ReportTargetListing:
		var l models.Listing
		if err := db.First(&l, id).Error; err != nil || listingHiddenFromRequester(c, db, l.ID) {
			return notFound()
		}
		if owner, ok := listingOwner(db, l.ID); ok {
			answerable = &owner
		}
	case models.ReportTargetProvider:
		var p models.Provider
		if err := db.Where("status = ?", models.ProviderStatusActive).First(&p, id).Error; err != nil || userBlockedNow(db, p.UserID) {
			return notFound()
		}
		answerable = &p.UserID
	case models.ReportTargetComment:
		var cm models.Comment
		if err := db.First(&cm, id).Error; err != nil {
			return notFound()
		}
		// Only reviews the reporter can actually see: approved ones on a
		// listing visible to them.
		if (!cm.Approved && cm.UserID != reporter) || listingHiddenFromRequester(c, db, cm.ListingID) {
			return notFound()
		}
		answerable = &cm.UserID
	case models.ReportTargetUser:
		var u models.User
		if err := db.Select("id").First(&u, id).Error; err != nil {
			return notFound()
		}
		answerable = &u.ID
	}
	if answerable != nil && *answerable == reporter {
		return nil, http.StatusBadRequest, "cannot_report_self"
	}
	return answerable, 0, ""
}

// Create — POST /api/reports (authenticated).
func (h *ReportHandler) Create(c *gin.Context) {
	var in reportInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_input"})
		return
	}
	if !reportTargets[in.TargetType] || in.TargetID == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_target"})
		return
	}
	if !reportReasons[in.Reason] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_reason"})
		return
	}
	details := strings.TrimSpace(in.Details)
	if utf8.RuneCountInString(details) > reportDetailsMax {
		c.JSON(http.StatusBadRequest, gin.H{"error": "details_too_long"})
		return
	}
	if in.Reason == models.ReportReasonOther && utf8.RuneCountInString(details) < reportOtherMinChar {
		c.JSON(http.StatusBadRequest, gin.H{"error": "details_required"})
		return
	}
	reporter := currentUserID(c)
	now := h.now()

	var lastHour, lastDay int64
	h.DB.Model(&models.Report{}).Where("reporter_id = ? AND created_at > ?", reporter, now.Add(-time.Hour)).Count(&lastHour)
	h.DB.Model(&models.Report{}).Where("reporter_id = ? AND created_at > ?", reporter, now.Add(-24*time.Hour)).Count(&lastDay)
	if lastHour >= reportsPerHour || lastDay >= reportsPerDay {
		c.JSON(http.StatusTooManyRequests, gin.H{"error": "too_many_reports"})
		return
	}

	answerable, status, code := resolveReportTarget(c, h.DB, in.TargetType, in.TargetID, reporter)
	if status != 0 {
		c.JSON(status, gin.H{"error": code})
		return
	}

	key := reportOpenKey(reporter, in.TargetType, in.TargetID)
	var open int64
	h.DB.Model(&models.Report{}).Where("open_key = ?", *key).Count(&open)
	if open > 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "duplicate_report"})
		return
	}
	r := models.Report{
		ReporterID: reporter, TargetType: in.TargetType, TargetID: in.TargetID, TargetUserID: answerable,
		Reason: in.Reason, Details: details, Status: models.ReportStatusNew, OpenKey: key,
		CreatedAt: now, UpdatedAt: now,
	}
	if err := h.DB.Create(&r).Error; err != nil {
		// Two identical reports at once: the unique open_key lets one in.
		if isUniqueViolation(err) {
			c.JSON(http.StatusConflict, gin.H{"error": "duplicate_report"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create report"})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"report": reportOutFrom(r)})
}

// Mine — GET /api/reports/mine: the caller's own reports and their status.
func (h *ReportHandler) Mine(c *gin.Context) {
	var rs []models.Report
	if err := h.DB.Where("reporter_id = ?", currentUserID(c)).Order("created_at desc, id desc").Limit(100).Find(&rs).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch reports"})
		return
	}
	out := make([]reportOut, len(rs))
	for i, r := range rs {
		out[i] = reportOutFrom(r)
	}
	c.JSON(http.StatusOK, gin.H{"reports": out})
}

func isUniqueViolation(err error) bool {
	if errors.Is(err, gorm.ErrDuplicatedKey) {
		return true
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "unique") || strings.Contains(msg, "duplicate key")
}
