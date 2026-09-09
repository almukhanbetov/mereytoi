// Package telegram is MEREYTOI's Telegram transport layer — both for claim
// delivery (driven by internal/claimdelivery, once a specific user has
// linked their chat) and for the link-confirmation message sent right
// after linking (handlers/telegram_handler.go's Webhook). The delivery
// audit for this stage found no Telegram Bot API integration anywhere in
// this codebase; BotSender (bot_sender.go) is real, working code against
// Telegram's actual Bot API — not a mock — it just has no bot token
// configured out of the box.
//
// Unlike WhatsApp, Telegram addressing is a numeric chat_id, not a phone
// number, and a bot's own messages to a chat that has already /start'd it
// need no pre-approved template — so Sender here takes a chat_id + plain
// text directly rather than a Message struct shaped around a phone number.
package telegram

import (
	"context"
	"fmt"
	"log"
)

// Sender is the one seam a real provider adapter implements.
type Sender interface {
	Send(ctx context.Context, chatID, text string) error
}

// StatusError is returned when Telegram's API actually responded, just not
// with 2xx. Carries only the status code — never the response body (which
// could echo back the message text, including a claim link).
type StatusError struct{ Code int }

func (e *StatusError) Error() string { return fmt.Sprintf("telegram api returned status %d", e.Code) }

// LogSender never touches the network. As with whatsapp.LogSender,
// claimdelivery.Service treats "no bot token configured" as "channel
// unavailable" rather than routing production sends through this, so it
// only matters for local dev visibility.
type LogSender struct{}

func (LogSender) Send(_ context.Context, chatID, text string) error {
	log.Printf("[telegram:log-driver] chat_id=%s text_len=%d (no bot token configured — nothing actually sent)", chatID, len(text))
	return nil
}
