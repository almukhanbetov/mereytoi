// Package whatsapp is MEREYTOI's WhatsApp transport layer, driven by
// internal/claimdelivery the same way internal/mail's own Sender/Service
// split works for email. The delivery audit for this stage's brief found
// no WhatsApp Business Platform integration anywhere in this codebase —
// only manual wa.me links in the UI, which are not automated delivery.
// MetaCloudSender (meta_sender.go) is real, working code against Meta's
// actual WhatsApp Cloud API — not a mock — it just has no credentials
// configured out of the box (WHATSAPP_ACCESS_TOKEN / _PHONE_NUMBER_ID
// empty means claimdelivery.Service never constructs one at all — see its
// own NewService).
package whatsapp

import (
	"context"
	"fmt"
	"log"
)

// Message is one outbound claim-link notification. Body is used when no
// approved template is configured (plain "session" message — only
// deliverable within WhatsApp's 24h customer-service window in real
// production use); TemplateParam is the single {{1}} body variable Meta's
// Cloud API substitutes into a pre-approved template when one is
// configured (WHATSAPP_TEMPLATE_NAME) — see MetaCloudSender.Send.
type Message struct {
	To            string // E.164, e.g. "+77051112233"
	Body          string
	TemplateParam string
}

// Sender is the one seam a real provider adapter implements.
type Sender interface {
	Send(ctx context.Context, msg Message) error
}

// StatusError is returned when Meta's API actually responded, just not
// with 2xx. Carries only the status code — never the response body or the
// request payload, either of which could echo back the claim link.
type StatusError struct{ Code int }

func (e *StatusError) Error() string { return fmt.Sprintf("whatsapp api returned status %d", e.Code) }

// LogSender never touches the network — used only for local dev visibility
// when explicitly wanted; claimdelivery.Service normally treats "no
// credentials configured" as "channel unavailable" (see its pickChannel),
// not as "send via LogSender", so production traffic never silently
// no-ops here. Never logs the body (it contains the claim link/token).
type LogSender struct{}

func (LogSender) Send(_ context.Context, msg Message) error {
	log.Printf("[whatsapp:log-driver] to=%s body_len=%d (no provider configured — nothing actually sent)", msg.To, len(msg.Body))
	return nil
}
