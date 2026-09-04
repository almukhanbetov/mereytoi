// Package mail is MEREYTOI's transactional email layer (stage 11A).
//
// Shape, top to bottom:
//
//	domain handler (event_request_handler.go / event_member_handler.go)
//	  -> mail.Service (typed Send* methods + copy/template rendering)
//	    -> mail.Sender (provider-agnostic transport: SMTPSender or LogSender)
//
// No business handler ever imports net/smtp or knows a provider exists —
// it calls a typed method like Service.SendInvitation with plain domain
// data, exactly the same shape as how notification_helpers.go's
// createNotification/notifyMany already keep provider-specific concerns
// (there, "how a Notification row is stored") out of the handlers.
package mail

import "context"

// Message is one already-composed email, independent of how it's
// eventually transported.
type Message struct {
	To       string
	Subject  string
	HTMLBody string
	TextBody string
	// ReplyTo is optional; empty means "use the From address" (every
	// current call site leaves this empty — MEREYTOI has no support inbox
	// distinct from its From address yet).
	ReplyTo string
}

// Sender is the one seam a provider adapter implements. Send must not
// panic; returning an error is how transport failures are reported back to
// Service, which is responsible for making sure that never fails the
// business action that triggered it (brief section 14).
type Sender interface {
	Send(ctx context.Context, msg Message) error
}
