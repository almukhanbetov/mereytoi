package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// AdminHandler — the administrator API for people and their listings
// (/api/admin/users, /api/admin/listings/:id/hide|restore,
// /api/admin/audit-events). Every route sits behind RequireAuth +
// RequireAdmin, and the role there is the one in the database at this
// request (AccountSessionValidator). Every change is written together with
// its admin_audit_events row in one transaction.
type AdminHandler struct {
	DB  *gorm.DB
	Now func() time.Time
}

func NewAdminHandler(db *gorm.DB) *AdminHandler {
	return &AdminHandler{DB: db, Now: time.Now}
}

func (h *AdminHandler) now() time.Time { return h.Now().UTC() }

const (
	adminPageDefault  = 20
	adminPageMax      = 100
	adminReasonMinLen = 3
	adminReasonMaxLen = 1000
)

// blockTerms — the agreed block lengths; "permanent" has no end date.
var blockTerms = map[string]time.Duration{
	"1d":        24 * time.Hour,
	"7d":        7 * 24 * time.Hour,
	"30d":       30 * 24 * time.Hour,
	"permanent": 0,
}

// ---- DTOs (explicit, so no secret column can leak through a model) ----

type adminProviderOut struct {
	ID          uint   `json:"id"`
	DisplayName string `json:"display_name"`
	City        string `json:"city"`
	Phone       string `json:"phone"`
	WhatsApp    string `json:"whatsapp"`
	Status      string `json:"status"`
}

type adminBlockOut struct {
	Active    bool       `json:"active"`
	BlockedAt *time.Time `json:"blocked_at"`
	Until     *time.Time `json:"until"`
	Reason    string     `json:"reason"`
	BlockedBy *uint      `json:"blocked_by"`
}

type adminUserOut struct {
	ID            uint              `json:"id"`
	Name          string            `json:"name"`
	Email         string            `json:"email"`
	Phone         string            `json:"phone"`
	Role          string            `json:"role"`
	Status        string            `json:"status"`
	CreatedAt     time.Time         `json:"created_at"`
	Block         *adminBlockOut    `json:"block"`
	Provider      *adminProviderOut `json:"provider"`
	ListingsCount int64             `json:"listings_count"`
}

type adminListingOut struct {
	ID                 uint       `json:"id"`
	NameRu             string     `json:"name_ru"`
	NameKz             string     `json:"name_kz"`
	CategoryID         uint       `json:"category_id"`
	City               string     `json:"city"`
	Role               string     `json:"role"`
	IsActive           bool       `json:"is_active"`
	ModerationHiddenAt *time.Time `json:"moderation_hidden_at"`
	ModerationReason   string     `json:"moderation_reason"`
	PubliclyVisible    bool       `json:"publicly_visible"`
}

func (h *AdminHandler) userOut(u models.User, provider *models.Provider, listings int64) adminUserOut {
	out := adminUserOut{
		ID: u.ID, Name: u.Name, Email: u.Email, Phone: u.Phone, Role: u.Role,
		Status: u.Status, CreatedAt: u.CreatedAt, ListingsCount: listings,
	}
	if u.BlockedAt != nil {
		out.Block = &adminBlockOut{
			Active: u.IsBlocked(h.now()), BlockedAt: u.BlockedAt, Until: u.BlockedUntil,
			Reason: u.BlockReason, BlockedBy: u.BlockedBy,
		}
	}
	if provider != nil {
		out.Provider = &adminProviderOut{
			ID: provider.ID, DisplayName: provider.DisplayName, City: provider.City,
			Phone: provider.Phone, WhatsApp: provider.WhatsApp, Status: provider.Status,
		}
	}
	return out
}

// ---- helpers ----

func adminPage(c *gin.Context) (page, perPage int, ok bool) {
	page, perPage = 1, adminPageDefault
	if raw := c.Query("page"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 1 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_page"})
			return 0, 0, false
		}
		page = n
	}
	if raw := c.Query("per_page"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 1 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_per_page"})
			return 0, 0, false
		}
		if n > adminPageMax {
			n = adminPageMax
		}
		perPage = n
	}
	return page, perPage, true
}

// adminReason validates the required reason; on failure it has already
// answered 400.
func adminReason(c *gin.Context, raw string) (string, bool) {
	reason := strings.TrimSpace(raw)
	switch n := utf8.RuneCountInString(reason); {
	case n < adminReasonMinLen:
		c.JSON(http.StatusBadRequest, gin.H{"error": "reason_required"})
		return "", false
	case n > adminReasonMaxLen:
		c.JSON(http.StatusBadRequest, gin.H{"error": "reason_too_long"})
		return "", false
	}
	return reason, true
}

func (h *AdminHandler) likeOp() string {
	if h.DB.Dialector.Name() == "postgres" {
		return "ILIKE"
	}
	return "LIKE"
}

// recordAdminAudit writes the audit row inside the action's transaction.
// changes must hold plain, non-secret values only.
func recordAdminAudit(tx *gorm.DB, c *gin.Context, now time.Time, action, targetType string, targetID uint, reason string, changes map[string]any) error {
	data, err := json.Marshal(changes)
	if err != nil {
		return err
	}
	return tx.Create(&models.AdminAuditEvent{
		ActorID: currentUserID(c), Action: action, TargetType: targetType, TargetID: targetID,
		Reason: reason, Changes: string(data), IP: c.ClientIP(), CreatedAt: now,
	}).Error
}

// notifyInTx creates the user's in-app notification inside the
// transaction (no actor: the user isn't told which administrator acted).
func notifyInTx(tx *gorm.DB, userID uint, notifType string, payload map[string]any) error {
	data, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	return tx.Create(&models.Notification{
		UserID: userID, Type: notifType, EntityType: "account", Payload: string(data),
	}).Error
}

// loadTargetUser — 404s for an unknown id; on failure it has answered.
func (h *AdminHandler) loadTargetUser(c *gin.Context) (models.User, bool) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil || id < 1 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return models.User{}, false
	}
	var u models.User
	if err := h.DB.First(&u, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return models.User{}, false
	}
	return u, true
}

// ---- GET /api/admin/users ----

// SearchUsers — users and providers, searched by name, e-mail, phone or
// provider name (q), filtered by role, by provider=1 (has a provider
// profile) and by blocked=1|0 (block in force now). Paged, newest first.
func (h *AdminHandler) SearchUsers(c *gin.Context) {
	page, perPage, ok := adminPage(c)
	if !ok {
		return
	}
	now := h.now()
	q := h.DB.Model(&models.User{}).Joins("LEFT JOIN providers ON providers.user_id = users.id")

	if term := strings.TrimSpace(c.Query("q")); term != "" {
		like := "%" + term + "%"
		op := h.likeOp()
		cond := "users.name " + op + " ? OR users.email " + op + " ? OR users.phone LIKE ? OR providers.display_name " + op + " ?"
		args := []any{like, like, like, like}
		if digits := onlyDigits(term); len(digits) >= 4 {
			cond += " OR users.phone_normalized LIKE ? OR providers.phone LIKE ? OR providers.whats_app LIKE ?"
			d := "%" + digits + "%"
			args = append(args, d, d, d)
		}
		q = q.Where("("+cond+")", args...)
	}
	if role := c.Query("role"); role != "" {
		q = q.Where("users.role = ?", role)
	}
	switch c.Query("provider") {
	case "1":
		q = q.Where("providers.id IS NOT NULL")
	case "0":
		q = q.Where("providers.id IS NULL")
	}
	const blockedNow = "users.blocked_at IS NOT NULL AND (users.blocked_until IS NULL OR users.blocked_until > ?)"
	switch c.Query("blocked") {
	case "1":
		q = q.Where(blockedNow, now)
	case "0":
		q = q.Where("NOT ("+blockedNow+")", now)
	}

	var total int64
	if err := q.Count(&total).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to search users"})
		return
	}
	var users []models.User
	if err := q.Select("users.*").Order("users.created_at desc, users.id desc").
		Offset((page - 1) * perPage).Limit(perPage).Find(&users).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to search users"})
		return
	}

	ids := make([]uint, len(users))
	for i, u := range users {
		ids[i] = u.ID
	}
	providers := map[uint]*models.Provider{}
	counts := map[uint]int64{}
	if len(ids) > 0 {
		var ps []models.Provider
		h.DB.Where("user_id IN ?", ids).Find(&ps)
		for i := range ps {
			providers[ps[i].UserID] = &ps[i]
		}
		var rows []struct {
			UserID uint
			N      int64
		}
		h.DB.Model(&models.ListingManager{}).Select("user_id, count(*) as n").
			Where("user_id IN ?", ids).Group("user_id").Scan(&rows)
		for _, r := range rows {
			counts[r.UserID] = r.N
		}
	}
	out := make([]adminUserOut, len(users))
	for i, u := range users {
		out[i] = h.userOut(u, providers[u.ID], counts[u.ID])
	}
	c.JSON(http.StatusOK, gin.H{"users": out, "total": total, "page": page, "per_page": perPage})
}

func onlyDigits(s string) string {
	var b strings.Builder
	for _, r := range s {
		if r >= '0' && r <= '9' {
			b.WriteRune(r)
		}
	}
	return b.String()
}

// ---- GET /api/admin/users/:id ----

// GetUser — profile, provider profile with contacts, every listing the user
// is assigned to (with its own switch, administrative hiding and whether
// visitors see it now) and the sanctions history from the audit log.
func (h *AdminHandler) GetUser(c *gin.Context) {
	u, ok := h.loadTargetUser(c)
	if !ok {
		return
	}
	var provider *models.Provider
	var p models.Provider
	if err := h.DB.Where("user_id = ?", u.ID).First(&p).Error; err == nil {
		provider = &p
	}

	var managers []models.ListingManager
	h.DB.Where("user_id = ?", u.ID).Order("listing_id").Find(&managers)
	roleOf := map[uint]string{}
	ids := make([]uint, 0, len(managers))
	for _, m := range managers {
		roleOf[m.ListingID] = m.Role
		ids = append(ids, m.ListingID)
	}
	listings := []adminListingOut{}
	if len(ids) > 0 {
		var ls []models.Listing
		h.DB.Where("id IN ?", ids).Order("id").Find(&ls)
		var visible []uint
		h.DB.Model(&models.Listing{}).Where("id IN ?", ids).Scopes(publicListingScope(h.now())).Pluck("id", &visible)
		isVisible := map[uint]bool{}
		for _, id := range visible {
			isVisible[id] = true
		}
		for _, l := range ls {
			listings = append(listings, adminListingOut{
				ID: l.ID, NameRu: l.NameRu, NameKz: l.NameKz, CategoryID: l.CategoryID, City: l.City,
				Role: roleOf[l.ID], IsActive: l.IsActive, ModerationHiddenAt: l.ModerationHiddenAt,
				ModerationReason: l.ModerationReason, PubliclyVisible: isVisible[l.ID],
			})
		}
	}

	var history []models.AdminAuditEvent
	h.DB.Where("target_type = ? AND target_id = ?", models.AdminTargetUser, u.ID).
		Order("created_at desc, id desc").Limit(50).Find(&history)
	decodeAuditChanges(history)

	c.JSON(http.StatusOK, gin.H{
		"user":     h.userOut(u, provider, int64(len(managers))),
		"listings": listings,
		"history":  history,
	})
}

// ---- POST /api/admin/users/:id/warn ----

type adminReasonInput struct {
	Reason string `json:"reason"`
}

func (h *AdminHandler) WarnUser(c *gin.Context) {
	var in adminReasonInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_input"})
		return
	}
	reason, ok := adminReason(c, in.Reason)
	if !ok {
		return
	}
	u, ok := h.loadTargetUser(c)
	if !ok {
		return
	}
	if u.ID == currentUserID(c) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "cannot_target_self"})
		return
	}
	now := h.now()
	err := h.DB.Transaction(func(tx *gorm.DB) error {
		if err := notifyInTx(tx, u.ID, models.NotifAdminWarning, map[string]any{"reason": reason}); err != nil {
			return err
		}
		return recordAdminAudit(tx, c, now, models.AdminActionUserWarn, models.AdminTargetUser, u.ID, reason, nil)
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to warn user"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "warned"})
}

// ---- POST /api/admin/users/:id/block ----

type adminBlockInput struct {
	Reason   string `json:"reason"`
	Duration string `json:"duration"`
}

// BlockUser — 1d/7d/30d/permanent. Takes effect on the user's next request
// (AccountSessionValidator) and refuses new tokens (issueJWT). Never the
// caller themselves nor another administrator. Re-blocking a blocked user
// replaces the term. Listings, bookings, chats and reviews stay stored; the
// owner's listings simply aren't shown while it lasts (visibility.go).
func (h *AdminHandler) BlockUser(c *gin.Context) {
	var in adminBlockInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_input"})
		return
	}
	reason, ok := adminReason(c, in.Reason)
	if !ok {
		return
	}
	term, ok := blockTerms[in.Duration]
	if !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_duration"})
		return
	}
	u, ok := h.loadTargetUser(c)
	if !ok {
		return
	}
	actor := currentUserID(c)
	if u.ID == actor {
		c.JSON(http.StatusBadRequest, gin.H{"error": "cannot_target_self"})
		return
	}
	if u.Role == "admin" {
		c.JSON(http.StatusForbidden, gin.H{"error": "cannot_block_admin"})
		return
	}

	now := h.now()
	var until *time.Time
	if term > 0 {
		t := now.Add(term)
		until = &t
	}
	was := u.IsBlocked(now)
	err := h.DB.Transaction(func(tx *gorm.DB) error {
		// The role is re-checked in the same statement, so a user promoted
		// to admin meanwhile can't be blocked by a stale read.
		res := tx.Model(&models.User{}).Where("id = ? AND role <> ?", u.ID, "admin").Updates(map[string]any{
			"blocked_at": now, "blocked_until": until, "block_reason": reason, "blocked_by": actor,
		})
		if res.Error != nil {
			return res.Error
		}
		if res.RowsAffected != 1 {
			return errAdminTargetChanged
		}
		payload := map[string]any{"reason": reason, "blocked_until": until}
		if err := notifyInTx(tx, u.ID, models.NotifAccountBlocked, payload); err != nil {
			return err
		}
		return recordAdminAudit(tx, c, now, models.AdminActionUserBlock, models.AdminTargetUser, u.ID, reason, map[string]any{
			"duration": in.Duration, "blocked_until": until,
			"was_blocked": was, "previous_until": u.BlockedUntil,
		})
	})
	if errors.Is(err, errAdminTargetChanged) {
		c.JSON(http.StatusConflict, gin.H{"error": "target_changed"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to block user"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "blocked", "blocked_until": until})
}

var errAdminTargetChanged = errors.New("admin target changed")

// ---- POST /api/admin/users/:id/unblock ----

// UnblockUser lifts a block in force. Nothing is republished by hand: the
// listings that were visible before come back by themselves, and those the
// owner unpublished or an administrator hid stay out (visibility.go).
func (h *AdminHandler) UnblockUser(c *gin.Context) {
	var in adminReasonInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_input"})
		return
	}
	reason, ok := adminReason(c, in.Reason)
	if !ok {
		return
	}
	u, ok := h.loadTargetUser(c)
	if !ok {
		return
	}
	now := h.now()
	if !u.IsBlocked(now) {
		c.JSON(http.StatusConflict, gin.H{"error": "not_blocked"})
		return
	}
	err := h.DB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&models.User{}).Where("id = ?", u.ID).Updates(map[string]any{
			"blocked_at": nil, "blocked_until": nil, "block_reason": "", "blocked_by": nil,
		}).Error; err != nil {
			return err
		}
		if err := notifyInTx(tx, u.ID, models.NotifAccountUnblocked, map[string]any{"reason": reason}); err != nil {
			return err
		}
		return recordAdminAudit(tx, c, now, models.AdminActionUserUnblock, models.AdminTargetUser, u.ID, reason, map[string]any{
			"previous_until": u.BlockedUntil, "previous_reason": u.BlockReason,
		})
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to unblock user"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "unblocked"})
}

// ---- POST /api/admin/listings/:id/hide | restore ----

// HideListing hides a listing from visitors with a required reason. Kept
// apart from is_active, which stays exactly as the owner set it.
func (h *AdminHandler) HideListing(c *gin.Context) { h.setListingHidden(c, true) }

// RestoreListing lifts an administrator's hiding; the owner's own is_active
// still decides whether it's published.
func (h *AdminHandler) RestoreListing(c *gin.Context) { h.setListingHidden(c, false) }

func (h *AdminHandler) setListingHidden(c *gin.Context, hide bool) {
	var in adminReasonInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_input"})
		return
	}
	reason, ok := adminReason(c, in.Reason)
	if !ok {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil || id < 1 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	var l models.Listing
	if err := h.DB.First(&l, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "listing not found"})
		return
	}
	isHidden := l.ModerationHiddenAt != nil
	if hide && isHidden {
		c.JSON(http.StatusConflict, gin.H{"error": "already_hidden"})
		return
	}
	if !hide && !isHidden {
		c.JSON(http.StatusConflict, gin.H{"error": "not_hidden"})
		return
	}
	now := h.now()
	actor := currentUserID(c)
	err = h.DB.Transaction(func(tx *gorm.DB) error {
		var updates map[string]any
		action := models.AdminActionListingHide
		if hide {
			updates = map[string]any{"moderation_hidden_at": now, "moderation_reason": reason, "moderated_by": actor}
		} else {
			action = models.AdminActionListingRestore
			updates = map[string]any{"moderation_hidden_at": nil, "moderation_reason": "", "moderated_by": nil}
		}
		// UpdateColumns: leaves updated_at alone, and never touches is_active.
		if err := tx.Model(&models.Listing{}).Where("id = ?", l.ID).UpdateColumns(updates).Error; err != nil {
			return err
		}
		changes := map[string]any{"hidden": hide, "is_active": l.IsActive}
		if !hide {
			changes["previous_reason"] = l.ModerationReason
		}
		return recordAdminAudit(tx, c, now, action, models.AdminTargetListing, l.ID, reason, changes)
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update listing"})
		return
	}
	status := "hidden"
	if !hide {
		status = "restored"
	}
	c.JSON(http.StatusOK, gin.H{"status": status})
}

// ---- GET /api/admin/audit-events ----

// AuditEvents — the administrators' action log, newest first, filtered by
// target_type+target_id, actor_id or action. Read-only.
func (h *AdminHandler) AuditEvents(c *gin.Context) {
	page, perPage, ok := adminPage(c)
	if !ok {
		return
	}
	q := h.DB.Model(&models.AdminAuditEvent{})
	if v := c.Query("target_type"); v != "" {
		q = q.Where("target_type = ?", v)
	}
	if v := c.Query("target_id"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_target_id"})
			return
		}
		q = q.Where("target_id = ?", n)
	}
	if v := c.Query("actor_id"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_actor_id"})
			return
		}
		q = q.Where("actor_id = ?", n)
	}
	if v := c.Query("action"); v != "" {
		q = q.Where("action = ?", v)
	}
	var total int64
	if err := q.Count(&total).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch audit events"})
		return
	}
	var events []models.AdminAuditEvent
	if err := q.Order("created_at desc, id desc").Offset((page - 1) * perPage).Limit(perPage).Find(&events).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch audit events"})
		return
	}
	decodeAuditChanges(events)

	actorIDs := make([]uint, 0, len(events))
	for _, e := range events {
		actorIDs = append(actorIDs, e.ActorID)
	}
	actors := map[uint]string{}
	if len(actorIDs) > 0 {
		var us []models.User
		h.DB.Select("id", "name").Where("id IN ?", actorIDs).Find(&us)
		for _, u := range us {
			actors[u.ID] = u.Name
		}
	}
	type eventOut struct {
		models.AdminAuditEvent
		ActorName string `json:"actor_name"`
	}
	out := make([]eventOut, len(events))
	for i, e := range events {
		out[i] = eventOut{AdminAuditEvent: e, ActorName: actors[e.ActorID]}
	}
	c.JSON(http.StatusOK, gin.H{"events": out, "total": total, "page": page, "per_page": perPage})
}

func decodeAuditChanges(events []models.AdminAuditEvent) {
	for i := range events {
		if events[i].Changes == "" || events[i].Changes == "null" {
			continue
		}
		var m map[string]any
		if json.Unmarshal([]byte(events[i].Changes), &m) == nil {
			events[i].ChangesJSON = m
		}
	}
}
