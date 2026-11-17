package handlers

import (
	"errors"
	"net/http"
	"strconv"
	"time"
	"unicode/utf8"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// Administrators' report queue: /api/admin/reports, /:id, /:id/take,
// /:id/decide and /api/admin/summary. A decision only closes the report —
// blocking a user or hiding a listing is a separate admin action of its own
// (admin_users.go), so a report can never sanction anyone by itself.

var reportStatuses = map[string]bool{
	models.ReportStatusNew: true, models.ReportStatusInReview: true,
	models.ReportStatusResolved: true, models.ReportStatusRejected: true,
}

var openReportStatuses = []string{models.ReportStatusNew, models.ReportStatusInReview}

type adminPersonOut struct {
	ID    uint   `json:"id"`
	Name  string `json:"name"`
	Email string `json:"email,omitempty"`
}

// adminReportTargetOut — a short, admin-only description of the target.
// Exists=false when it has been deleted since.
type adminReportTargetOut struct {
	Exists bool   `json:"exists"`
	Title  string `json:"title"`
	// Detail — e.g. the review text, or the listing/provider state.
	Detail map[string]any `json:"detail,omitempty"`
}

type adminReportOut struct {
	models.Report
	Reporter       *adminPersonOut      `json:"reporter"`
	TargetUser     *adminPersonOut      `json:"target_user"`
	Target         adminReportTargetOut `json:"target"`
	OpenOnSameItem int64                `json:"open_on_same_target"`
}

// reportTargets loads a summary of each report's target in one query per
// type.
func (h *AdminHandler) reportTargets(rs []models.Report, full bool) map[string]adminReportTargetOut {
	ids := map[string][]uint{}
	for _, r := range rs {
		ids[r.TargetType] = append(ids[r.TargetType], r.TargetID)
	}
	out := map[string]adminReportTargetOut{}
	key := func(t string, id uint) string { return t + ":" + strconv.FormatUint(uint64(id), 10) }
	now := h.now()
	if v := ids[models.ReportTargetListing]; len(v) > 0 {
		var ls []models.Listing
		h.DB.Where("id IN ?", v).Find(&ls)
		var visible []uint
		h.DB.Model(&models.Listing{}).Where("id IN ?", v).Scopes(publicListingScope(now)).Pluck("id", &visible)
		vis := map[uint]bool{}
		for _, id := range visible {
			vis[id] = true
		}
		for _, l := range ls {
			t := adminReportTargetOut{Exists: true, Title: l.NameRu}
			if full {
				t.Detail = map[string]any{"is_active": l.IsActive, "moderation_hidden_at": l.ModerationHiddenAt,
					"moderation_reason": l.ModerationReason, "publicly_visible": vis[l.ID], "city": l.City}
			}
			out[key(models.ReportTargetListing, l.ID)] = t
		}
	}
	if v := ids[models.ReportTargetProvider]; len(v) > 0 {
		var ps []models.Provider
		h.DB.Where("id IN ?", v).Find(&ps)
		for _, p := range ps {
			t := adminReportTargetOut{Exists: true, Title: p.DisplayName}
			if full {
				t.Detail = map[string]any{"status": p.Status, "city": p.City, "user_id": p.UserID}
			}
			out[key(models.ReportTargetProvider, p.ID)] = t
		}
	}
	if v := ids[models.ReportTargetComment]; len(v) > 0 {
		var cs []models.Comment
		h.DB.Where("id IN ?", v).Find(&cs)
		for _, cm := range cs {
			preview := cm.Text
			if !full && utf8.RuneCountInString(preview) > 120 {
				preview = string([]rune(preview)[:120]) + "…"
			}
			out[key(models.ReportTargetComment, cm.ID)] = adminReportTargetOut{Exists: true, Title: preview,
				Detail: map[string]any{"listing_id": cm.ListingID, "rating": cm.Rating, "approved": cm.Approved}}
		}
	}
	if v := ids[models.ReportTargetUser]; len(v) > 0 {
		var us []models.User
		h.DB.Where("id IN ?", v).Find(&us)
		for _, u := range us {
			t := adminReportTargetOut{Exists: true, Title: u.Name}
			if full {
				t.Detail = map[string]any{"role": u.Role, "blocked": u.IsBlocked(now)}
			}
			out[key(models.ReportTargetUser, u.ID)] = t
		}
	}
	for _, r := range rs {
		if _, ok := out[key(r.TargetType, r.TargetID)]; !ok {
			out[key(r.TargetType, r.TargetID)] = adminReportTargetOut{Exists: false}
		}
	}
	return out
}

func (h *AdminHandler) people(ids []uint, withEmail bool) map[uint]*adminPersonOut {
	out := map[uint]*adminPersonOut{}
	if len(ids) == 0 {
		return out
	}
	var us []models.User
	h.DB.Select("id", "name", "email").Where("id IN ?", ids).Find(&us)
	for _, u := range us {
		p := &adminPersonOut{ID: u.ID, Name: u.Name}
		if withEmail {
			p.Email = u.Email
		}
		out[u.ID] = p
	}
	return out
}

func (h *AdminHandler) reportsOut(rs []models.Report, full bool) []adminReportOut {
	targets := h.reportTargets(rs, full)
	var personIDs []uint
	for _, r := range rs {
		personIDs = append(personIDs, r.ReporterID)
		if r.TargetUserID != nil {
			personIDs = append(personIDs, *r.TargetUserID)
		}
	}
	people := h.people(personIDs, full)
	out := make([]adminReportOut, len(rs))
	for i, r := range rs {
		o := adminReportOut{Report: r, Reporter: people[r.ReporterID],
			Target: targets[r.TargetType+":"+strconv.FormatUint(uint64(r.TargetID), 10)]}
		if r.TargetUserID != nil {
			o.TargetUser = people[*r.TargetUserID]
		}
		h.DB.Model(&models.Report{}).Where("target_type = ? AND target_id = ? AND status IN ?",
			r.TargetType, r.TargetID, openReportStatuses).Count(&o.OpenOnSameItem)
		out[i] = o
	}
	return out
}

// ListReports — GET /api/admin/reports?status=&target_type=&reason=&
// target_id=&target_user_id=&reporter_id=&assignee=me&page=&per_page=.
// status=open means new + in_review. Newest first.
func (h *AdminHandler) ListReports(c *gin.Context) {
	page, perPage, ok := adminPage(c)
	if !ok {
		return
	}
	q := h.DB.Model(&models.Report{})
	switch st := c.Query("status"); {
	case st == "open":
		q = q.Where("status IN ?", openReportStatuses)
	case st != "":
		if !reportStatuses[st] {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_status"})
			return
		}
		q = q.Where("status = ?", st)
	}
	if v := c.Query("target_type"); v != "" {
		if !reportTargets[v] {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_target"})
			return
		}
		q = q.Where("target_type = ?", v)
	}
	if v := c.Query("reason"); v != "" {
		if !reportReasons[v] {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_reason"})
			return
		}
		q = q.Where("reason = ?", v)
	}
	for _, f := range []string{"target_id", "target_user_id", "reporter_id"} {
		if v := c.Query(f); v != "" {
			n, err := strconv.Atoi(v)
			if err != nil || n < 1 {
				c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_" + f})
				return
			}
			q = q.Where(f+" = ?", n)
		}
	}
	if c.Query("assignee") == "me" {
		q = q.Where("assignee_id = ?", currentUserID(c))
	}
	var total int64
	if err := q.Count(&total).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch reports"})
		return
	}
	var rs []models.Report
	if err := q.Order("created_at desc, id desc").Offset((page - 1) * perPage).Limit(perPage).Find(&rs).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch reports"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"reports": h.reportsOut(rs, false), "total": total, "page": page, "per_page": perPage})
}

func (h *AdminHandler) loadReport(c *gin.Context) (models.Report, bool) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil || id < 1 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return models.Report{}, false
	}
	var r models.Report
	if err := h.DB.First(&r, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "report not found"})
		return models.Report{}, false
	}
	return r, true
}

// GetReport — GET /api/admin/reports/:id: the report with its target in
// full, the other reports about the same target and the report's own
// action history.
func (h *AdminHandler) GetReport(c *gin.Context) {
	r, ok := h.loadReport(c)
	if !ok {
		return
	}
	var related []models.Report
	h.DB.Where("target_type = ? AND target_id = ? AND id <> ?", r.TargetType, r.TargetID, r.ID).
		Order("created_at desc").Limit(50).Find(&related)
	type relatedOut struct {
		ID        uint      `json:"id"`
		Reason    string    `json:"reason"`
		Status    string    `json:"status"`
		CreatedAt time.Time `json:"created_at"`
	}
	rel := make([]relatedOut, len(related))
	for i, x := range related {
		rel[i] = relatedOut{ID: x.ID, Reason: x.Reason, Status: x.Status, CreatedAt: x.CreatedAt}
	}
	var history []models.AdminAuditEvent
	h.DB.Where("target_type = ? AND target_id = ?", models.AdminTargetReport, r.ID).Order("created_at, id").Find(&history)
	decodeAuditChanges(history)
	c.JSON(http.StatusOK, gin.H{"report": h.reportsOut([]models.Report{r}, true)[0], "related": rel, "history": history})
}

var errReportStateChanged = errors.New("report state changed")

// TakeReport — POST /api/admin/reports/:id/take: new → in_review, assigned
// to the caller. Conditional on the status still being new, so two
// administrators can't both take it.
func (h *AdminHandler) TakeReport(c *gin.Context) {
	r, ok := h.loadReport(c)
	if !ok {
		return
	}
	now := h.now()
	actor := currentUserID(c)
	err := h.DB.Transaction(func(tx *gorm.DB) error {
		res := tx.Model(&models.Report{}).Where("id = ? AND status = ?", r.ID, models.ReportStatusNew).
			Updates(map[string]any{"status": models.ReportStatusInReview, "assignee_id": actor, "updated_at": now})
		if res.Error != nil {
			return res.Error
		}
		if res.RowsAffected != 1 {
			return errReportStateChanged
		}
		return recordAdminAudit(tx, c, now, models.AdminActionReportTake, models.AdminTargetReport, r.ID, "",
			map[string]any{"from": models.ReportStatusNew, "to": models.ReportStatusInReview})
	})
	if errors.Is(err, errReportStateChanged) {
		c.JSON(http.StatusConflict, gin.H{"error": "not_new"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update report"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": models.ReportStatusInReview})
}

type reportDecisionInput struct {
	Decision string `json:"decision"`
	Reason   string `json:"reason"`
}

// DecideReport — POST /api/admin/reports/:id/decide {decision:
// resolved|rejected, reason}. The reason is required. The update is
// conditional on the report still being open, so of two administrators
// deciding at once exactly one wins and the other gets 409; the audit row is
// written in the same transaction. Nothing is blocked or hidden here.
func (h *AdminHandler) DecideReport(c *gin.Context) {
	var in reportDecisionInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_input"})
		return
	}
	action := ""
	switch in.Decision {
	case models.ReportStatusResolved:
		action = models.AdminActionReportResolve
	case models.ReportStatusRejected:
		action = models.AdminActionReportReject
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_decision"})
		return
	}
	reason, ok := adminReason(c, in.Reason)
	if !ok {
		return
	}
	r, ok := h.loadReport(c)
	if !ok {
		return
	}
	now := h.now()
	actor := currentUserID(c)
	err := h.DB.Transaction(func(tx *gorm.DB) error {
		res := tx.Model(&models.Report{}).Where("id = ? AND status IN ?", r.ID, openReportStatuses).
			Updates(map[string]any{
				"status": in.Decision, "resolved_by": actor, "resolved_at": now,
				"resolution": reason, "open_key": nil, "updated_at": now,
			})
		if res.Error != nil {
			return res.Error
		}
		if res.RowsAffected != 1 {
			return errReportStateChanged
		}
		return recordAdminAudit(tx, c, now, action, models.AdminTargetReport, r.ID, reason, map[string]any{
			"from": r.Status, "to": in.Decision, "target_type": r.TargetType, "target_id": r.TargetID,
		})
	})
	if errors.Is(err, errReportStateChanged) {
		c.JSON(http.StatusConflict, gin.H{"error": "already_decided"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update report"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": in.Decision})
}

// Summary — GET /api/admin/summary: counters for the mobile admin home.
func (h *AdminHandler) Summary(c *gin.Context) {
	now := h.now()
	count := func(q *gorm.DB) int64 {
		var n int64
		q.Count(&n)
		return n
	}
	out := gin.H{
		"reports_new":       count(h.DB.Model(&models.Report{}).Where("status = ?", models.ReportStatusNew)),
		"reports_in_review": count(h.DB.Model(&models.Report{}).Where("status = ?", models.ReportStatusInReview)),
		"reports_mine":      count(h.DB.Model(&models.Report{}).Where("status = ? AND assignee_id = ?", models.ReportStatusInReview, currentUserID(c))),
		"reviews_pending":   count(h.DB.Model(&models.Comment{}).Where("approved = ?", false)),
		"recovery_requests_pending": count(h.DB.Model(&models.PasswordRecoveryRequest{}).
			Where("status = ?", models.RecoveryRequestPending)),
		"support_chats_open": count(h.DB.Model(&models.ManagerConversation{}).Where("status = ?", models.ConversationOpen)),
		"event_requests_waiting": count(h.DB.Model(&models.EventRequest{}).
			Where("status IN ?", []string{models.RequestSubmitted, models.RequestInReview})),
		"blocked_users": count(h.DB.Model(&models.User{}).
			Where("blocked_at IS NOT NULL AND (blocked_until IS NULL OR blocked_until > ?)", now)),
		"hidden_listings": count(h.DB.Model(&models.Listing{}).Where("moderation_hidden_at IS NOT NULL")),
	}
	c.JSON(http.StatusOK, out)
}
