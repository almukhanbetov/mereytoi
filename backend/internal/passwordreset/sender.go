package passwordreset

import (
	"context"
	"errors"
)

// CodeMessage is what a Sender delivers. Code is the plaintext one-time
// code — it exists only in memory, for the duration of this one call.
// Senders must never log it (nor Phone).
type CodeMessage struct {
	UserID  uint
	Phone   string // +7XXXXXXXXXX
	Code    string
	Purpose string // models.PasswordCodePurpose*
	Lang    string // "ru" | "kz" | "en" — template language hint, may be empty
}

// Sender delivers a password code to the user's phone.
type Sender interface {
	SendPasswordResetCode(ctx context.Context, msg CodeMessage) error
}

// ErrNotConfigured is what NotConfiguredSender returns: no delivery channel
// exists, so no code ever leaves the server.
var ErrNotConfigured = errors.New("password reset delivery not configured")

// NotConfiguredSender is the default Sender until a real channel (WhatsApp
// Cloud API) is wired in: it sends nothing and says so.
type NotConfiguredSender struct{}

func (NotConfiguredSender) SendPasswordResetCode(context.Context, CodeMessage) error {
	return ErrNotConfigured
}
