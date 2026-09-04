package mail

import (
	"context"
	"log"
)

// LogSender is the "no extra container" dev transport (brief section 3's
// second option) — selected via MAIL_DRIVER=log. It never touches the
// network; it just logs what would have been sent, at INFO-ish verbosity,
// so a developer without Mailpit running can still see invitation/request
// emails "arrive" in the backend's own stdout during local development.
//
// Never logs full bodies (they may embed the invitation link/token) —
// only recipient, subject and body lengths, matching the masking rule in
// brief section 26.
type LogSender struct{}

func (LogSender) Send(_ context.Context, msg Message) error {
	log.Printf("[mail:log-driver] to=%s subject=%q text_len=%d html_len=%d (MAIL_DRIVER=log — no network send)",
		msg.To, msg.Subject, len(msg.TextBody), len(msg.HTMLBody))
	return nil
}
