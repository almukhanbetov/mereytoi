package recoverycode

import (
	"errors"
	"time"

	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
	"github.com/almukhanbetov/mereytoi/backend/internal/passwordreset"
)

// Support-assisted recovery, for a person without a usable backup code: they
// file a request, an admin checks who they are outside the system and
// approves it, and the temporary code the admin passes on sets a new password.

var (
	// ErrRequestNotFound — no recovery request with this id.
	ErrRequestNotFound = errors.New("recovery request not found")
	// ErrRequestState — the request can't take this action any more.
	ErrRequestState = errors.New("recovery request is in the wrong state")
	// ErrSelfApproval — an admin may not issue a code for their own account.
	ErrSelfApproval = errors.New("cannot approve own recovery request")
)

const (
	// TempCodeTTL — how long an issued temporary code works.
	TempCodeTTL = 15 * time.Minute
	// pendingRequestTTL — an unanswered request stops being approvable:
	// the person asking may no longer be waiting for it.
	pendingRequestTTL = 7 * 24 * time.Hour

	maxSupportRequestsPerIP      = 10
	maxSupportRequestsPerAccount = 3
	maxSupportResetsPerIP        = 20
	maxSupportResetsPerAccount   = 5

	scopeSupportRequestIP      = "sup_req_ip"
	scopeSupportRequestAccount = "sup_req_acct"
	scopeSupportResetIP        = "sup_reset_ip"
	scopeSupportResetAccount   = "sup_reset_acct"
)

// Actor is the admin behind an action, for the audit log.
type Actor struct {
	ID uint
	IP string
}

func audit(tx *gorm.DB, at time.Time, action string, requestID, userID, actorID *uint, ip string) error {
	return tx.Create(&models.RecoveryAuditEvent{
		RequestID: requestID, UserID: userID, ActorID: actorID,
		Action: action, IP: ip, CreatedAt: at,
	}).Error
}

// expireStale retires what ran out of time. Requests expire lazily: an
// expired code is refused by its own timestamp whether or not this has run.
func (s *Service) expireStale(tx *gorm.DB) error {
	now := s.now()
	if err := tx.Model(&models.PasswordRecoveryRequest{}).
		Where("status = ? AND temp_code_expires_at <= ?", models.RecoveryRequestApproved, now).
		Updates(map[string]any{"status": models.RecoveryRequestExpired, "temp_code_hash": ""}).Error; err != nil {
		return err
	}
	return tx.Model(&models.PasswordRecoveryRequest{}).
		Where("status = ? AND requested_at <= ?", models.RecoveryRequestPending, now.Add(-pendingRequestTTL)).
		Update("status", models.RecoveryRequestExpired).Error
}

// RequestSupport files a request for the account behind id, if there is
// exactly one active account and it has no open request yet. Only the IP
// limit surfaces (ErrRateLimited), since it doesn't depend on the account;
// everything else, an unknown account and an internal error included, looks
// the same to the caller. The per-account limit stays silent too: its key is
// shared by an account's email and phone, so a visible refusal would tell
// whether the two belong together.
func (s *Service) RequestSupport(id Identifier, clientIP string) error {
	if _, allowed := s.reserve(slot{scopeSupportRequestIP, clientIP, maxSupportRequestsPerIP}); !allowed {
		return ErrRateLimited
	}
	if _, allowed := s.reserve(slot{scopeSupportRequestAccount, s.accountKey(id), maxSupportRequestsPerAccount}); !allowed {
		return nil
	}
	if id.empty() {
		return nil
	}
	var found []models.User
	err := byIdentifier(s.db.Where("status = ?", models.UserStatusActive), id).Limit(2).Find(&found).Error
	if err != nil {
		s.log.Printf("[recovery] support request lookup failed: %v", err)
		return nil
	}
	if len(found) != 1 {
		return nil
	}
	user := found[0]
	err = s.db.Transaction(func(tx *gorm.DB) error {
		if err := s.expireStale(tx); err != nil {
			return err
		}
		now := s.now()
		req := models.PasswordRecoveryRequest{UserID: user.ID, Status: models.RecoveryRequestPending, RequestedAt: now}
		// A conflict on the one-pending index: already waiting for support.
		res := tx.Clauses(clause.OnConflict{DoNothing: true}).Create(&req)
		if res.Error != nil {
			return res.Error
		}
		if res.RowsAffected == 0 {
			return nil
		}
		return audit(tx, now, models.RecoveryAuditRequested, &req.ID, &user.ID, nil, clientIP)
	})
	if err != nil {
		s.log.Printf("[recovery] support request failed for user #%d: %v", user.ID, err)
		return nil
	}
	s.log.Printf("[recovery] support request recorded for user #%d", user.ID)
	return nil
}

// ApproveResult is an approved request and the temporary code in canonical
// form. This is the only time the code exists outside its hash.
type ApproveResult struct {
	Request models.PasswordRecoveryRequest
	Code    string
}

// Approve issues a temporary code for a pending request, or a replacement
// for an approved one. Any code issued earlier for the account stops working
// in the same transaction, which also writes the audit record: no code exists
// without one.
func (s *Service) Approve(requestID uint, note string, actor Actor) (ApproveResult, error) {
	code, err := generate(TempLength)
	if err != nil {
		return ApproveResult{}, err
	}
	var req models.PasswordRecoveryRequest
	err = s.db.Transaction(func(tx *gorm.DB) error {
		if err := s.expireStale(tx); err != nil {
			return err
		}
		if err := tx.First(&req, requestID).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return ErrRequestNotFound
			}
			return err
		}
		if req.Status != models.RecoveryRequestPending && req.Status != models.RecoveryRequestApproved {
			return ErrRequestState
		}
		if req.UserID == actor.ID {
			return ErrSelfApproval
		}
		var user models.User
		if err := tx.First(&user, req.UserID).Error; err != nil {
			return err
		}
		if user.Status != models.UserStatusActive {
			return ErrNotAllowed
		}

		now := s.now()
		var others []models.PasswordRecoveryRequest
		if err := tx.Where("user_id = ? AND status = ? AND id <> ?", req.UserID, models.RecoveryRequestApproved, req.ID).
			Find(&others).Error; err != nil {
			return err
		}
		for i := range others {
			if err := tx.Model(&models.PasswordRecoveryRequest{}).
				Where("id = ? AND status = ?", others[i].ID, models.RecoveryRequestApproved).
				Updates(map[string]any{"status": models.RecoveryRequestExpired, "temp_code_hash": ""}).Error; err != nil {
				return err
			}
			if err := audit(tx, now, models.RecoveryAuditSuperseded, &others[i].ID, &req.UserID, &actor.ID, actor.IP); err != nil {
				return err
			}
		}

		action := models.RecoveryAuditApproved
		if req.Status == models.RecoveryRequestApproved {
			action = models.RecoveryAuditReissued
		}
		expires := now.Add(TempCodeTTL)
		updates := map[string]any{
			"status":               models.RecoveryRequestApproved,
			"temp_code_hash":       Hash(code),
			"temp_code_expires_at": expires,
			"approved_at":          now,
			"approved_by":          actor.ID,
		}
		if note != "" {
			updates["admin_note"] = note
		}
		// Conditional on the status read above, so of two admins approving
		// one pending request only one gets a code.
		res := tx.Model(&models.PasswordRecoveryRequest{}).Where("id = ? AND status = ?", req.ID, req.Status).Updates(updates)
		if res.Error != nil {
			return res.Error
		}
		if res.RowsAffected != 1 {
			return ErrRequestState
		}
		if err := audit(tx, now, action, &req.ID, &req.UserID, &actor.ID, actor.IP); err != nil {
			return err
		}
		return tx.First(&req, req.ID).Error
	})
	if err != nil {
		return ApproveResult{}, err
	}
	// Guesses made before this code existed shouldn't hold it back.
	_ = s.db.Where("scope = ? AND key_hash = ?", scopeSupportResetAccount, keyHash(userAccountKey(req.UserID))).
		Delete(&models.RecoveryAttempt{}).Error
	s.log.Printf("[recovery] temporary code issued for user #%d by admin #%d", req.UserID, actor.ID)
	return ApproveResult{Request: req, Code: code}, nil
}

// Reject closes a pending request, or revokes the code of an approved one.
func (s *Service) Reject(requestID uint, note string, actor Actor) (models.PasswordRecoveryRequest, error) {
	var req models.PasswordRecoveryRequest
	err := s.db.Transaction(func(tx *gorm.DB) error {
		if err := s.expireStale(tx); err != nil {
			return err
		}
		if err := tx.First(&req, requestID).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return ErrRequestNotFound
			}
			return err
		}
		updates := map[string]any{"status": models.RecoveryRequestRejected, "temp_code_hash": ""}
		if note != "" {
			updates["admin_note"] = note
		}
		res := tx.Model(&models.PasswordRecoveryRequest{}).
			Where("id = ? AND status IN ?", req.ID, []string{models.RecoveryRequestPending, models.RecoveryRequestApproved}).
			Updates(updates)
		if res.Error != nil {
			return res.Error
		}
		if res.RowsAffected != 1 {
			return ErrRequestState
		}
		if err := audit(tx, s.now(), models.RecoveryAuditRejected, &req.ID, &req.UserID, &actor.ID, actor.IP); err != nil {
			return err
		}
		return tx.First(&req, req.ID).Error
	})
	if err != nil {
		return models.PasswordRecoveryRequest{}, err
	}
	s.log.Printf("[recovery] support request #%d rejected by admin #%d", req.ID, actor.ID)
	return req, nil
}

// RequestWithAudit is one request with its account (nil if it no longer
// exists) and audit trail, for the admin view.
type RequestWithAudit struct {
	Request models.PasswordRecoveryRequest
	User    *models.User
	Audit   []models.RecoveryAuditEvent
}

// RequestPage is a list of requests with their accounts.
type RequestPage struct {
	Requests []models.PasswordRecoveryRequest
	Users    map[uint]models.User
}

// requestPageSize caps a listing; the newest requests come first.
const requestPageSize = 100

// ListRequests returns requests, narrowed to status unless it is empty. The
// listing exposes contact details, so it is audited like any admin action.
func (s *Service) ListRequests(status string, actor Actor) (RequestPage, error) {
	var page RequestPage
	err := s.db.Transaction(func(tx *gorm.DB) error {
		if err := s.expireStale(tx); err != nil {
			return err
		}
		q := tx.Order("requested_at DESC, id DESC").Limit(requestPageSize)
		if status != "" {
			q = q.Where("status = ?", status)
		}
		if err := q.Find(&page.Requests).Error; err != nil {
			return err
		}
		userIDs := make([]uint, 0, len(page.Requests))
		for _, r := range page.Requests {
			userIDs = append(userIDs, r.UserID)
		}
		page.Users = map[uint]models.User{}
		if len(userIDs) > 0 {
			var users []models.User
			if err := tx.Where("id IN ?", userIDs).Find(&users).Error; err != nil {
				return err
			}
			for _, u := range users {
				page.Users[u.ID] = u
			}
		}
		return audit(tx, s.now(), models.RecoveryAuditListed, nil, nil, &actor.ID, actor.IP)
	})
	return page, err
}

// GetRequest returns one request with its account and audit trail.
func (s *Service) GetRequest(requestID uint, actor Actor) (RequestWithAudit, error) {
	var out RequestWithAudit
	err := s.db.Transaction(func(tx *gorm.DB) error {
		if err := s.expireStale(tx); err != nil {
			return err
		}
		if err := tx.First(&out.Request, requestID).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return ErrRequestNotFound
			}
			return err
		}
		var user models.User
		err := tx.First(&user, out.Request.UserID).Error
		switch {
		case err == nil:
			out.User = &user
		case !errors.Is(err, gorm.ErrRecordNotFound):
			return err
		}
		if err := audit(tx, s.now(), models.RecoveryAuditViewed, &out.Request.ID, &out.Request.UserID, &actor.ID, actor.IP); err != nil {
			return err
		}
		return tx.Where("request_id = ?", out.Request.ID).Order("created_at DESC, id DESC").Find(&out.Audit).Error
	})
	return out, err
}

// ResetWithTempCode checks a temporary code and, only if it is the live one
// for this account: marks the request used, sets newPassword, revokes every
// session through password_changed_at and replaces the backup code, since the
// lost one may turn up in someone else's hands. It fails the same way
// (ErrInvalid) for an unknown account and a wrong, expired or used code. The
// UPDATE on the request is conditional on the code, so of two concurrent
// requests only one can succeed.
func (s *Service) ResetWithTempCode(id Identifier, code, newPassword, clientIP string) (RecoverResult, error) {
	if err := passwordreset.CheckNewPassword(newPassword); err != nil {
		return RecoverResult{}, err
	}
	res, allowed := s.reserve(
		slot{scopeSupportResetIP, clientIP, maxSupportResetsPerIP},
		slot{scopeSupportResetAccount, s.accountKey(id), maxSupportResetsPerAccount},
	)
	if !allowed {
		return RecoverResult{}, ErrRateLimited
	}

	canonical, ok := normalize(code, TempLength)
	if !ok || id.empty() {
		return RecoverResult{}, ErrInvalid
	}
	codeHash := Hash(canonical)

	passwordHash, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
	if err != nil {
		s.release(res)
		return RecoverResult{}, err
	}
	newCode, newHash, err := NewCode()
	if err != nil {
		s.release(res)
		return RecoverResult{}, err
	}

	var user models.User
	err = s.db.Transaction(func(tx *gorm.DB) error {
		var found []models.User
		if err := byIdentifier(tx.Where("status = ?", models.UserStatusActive), id).Limit(2).Find(&found).Error; err != nil {
			return err
		}
		if len(found) != 1 {
			return ErrInvalid
		}
		user = found[0]

		now := s.now()
		var req models.PasswordRecoveryRequest
		err := tx.Where("user_id = ? AND status = ? AND temp_code_hash = ? AND temp_code_expires_at > ?",
			user.ID, models.RecoveryRequestApproved, codeHash, now).First(&req).Error
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrInvalid
		}
		if err != nil {
			return err
		}
		if s.afterLookup != nil {
			s.afterLookup()
		}

		spent := tx.Model(&models.PasswordRecoveryRequest{}).
			Where("id = ? AND status = ? AND temp_code_hash = ? AND temp_code_expires_at > ?",
				req.ID, models.RecoveryRequestApproved, codeHash, now).
			Updates(map[string]any{
				"status":         models.RecoveryRequestUsed,
				"temp_code_hash": "",
				"used_at":        now,
			})
		if spent.Error != nil {
			return spent.Error
		}
		if spent.RowsAffected != 1 {
			return ErrInvalid // used or replaced by a concurrent request
		}
		// A request still waiting could otherwise issue another code later.
		if err := tx.Model(&models.PasswordRecoveryRequest{}).
			Where("user_id = ? AND status = ?", user.ID, models.RecoveryRequestPending).
			Update("status", models.RecoveryRequestExpired).Error; err != nil {
			return err
		}
		if err := tx.Model(&models.User{}).Where("id = ?", user.ID).Updates(map[string]any{
			"password_hash":            string(passwordHash),
			"password_changed_at":      now,
			"recovery_code_hash":       newHash,
			"recovery_code_created_at": now,
		}).Error; err != nil {
			return err
		}
		return audit(tx, now, models.RecoveryAuditUsed, &req.ID, &user.ID, nil, clientIP)
	})
	if errors.Is(err, ErrInvalid) {
		return RecoverResult{}, ErrInvalid // the attempt stays counted
	}
	s.release(res)
	if err != nil {
		return RecoverResult{}, err
	}
	if err := s.db.First(&user, user.ID).Error; err != nil {
		return RecoverResult{}, err
	}
	s.log.Printf("[recovery] password recovered with temporary code for user #%d", user.ID)
	return RecoverResult{User: user, Code: newCode}, nil
}
