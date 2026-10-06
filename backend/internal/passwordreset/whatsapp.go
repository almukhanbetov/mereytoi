package passwordreset

import (
	"context"
	"errors"
	"fmt"
	"net"
	"time"

	"github.com/almukhanbetov/mereytoi/backend/internal/whatsapp"
)

// WhatsAppSender delivers codes through the approved WhatsApp
// AUTHENTICATION template (whatsapp.OTPSender). It runs on the delivery
// workers, never inside an HTTP request.
//
// Retry: at most one more attempt, and only for failures that may pass —
// 429, 5xx, timeouts and network errors. A 4xx (bad template, bad number,
// bad credentials) won't get better by repeating it.
type WhatsAppSender struct {
	OTP            *whatsapp.OTPSender
	AttemptTimeout time.Duration
	RetryDelay     time.Duration
}

func NewWhatsAppSender(otp *whatsapp.OTPSender) *WhatsAppSender {
	return &WhatsAppSender{OTP: otp, AttemptTimeout: 5 * time.Second, RetryDelay: 500 * time.Millisecond}
}

// DeliveryError says why a code wasn't delivered, as a short class
// ("provider_400", "provider_5xx", "timeout", …) — never the provider's
// response, the request URL (which a transport error's text contains) or
// anything from the message itself.
type DeliveryError struct{ Class string }

func (e *DeliveryError) Error() string { return "password code not delivered: " + e.Class }

func (s *WhatsAppSender) SendPasswordResetCode(ctx context.Context, msg CodeMessage) error {
	const attempts = 2
	for attempt := 1; ; attempt++ {
		attemptCtx, cancel := context.WithTimeout(ctx, s.AttemptTimeout)
		err := s.OTP.SendCode(attemptCtx, msg.Phone, msg.Code)
		cancel()
		if err == nil {
			return nil
		}
		class, transient := classifySendError(err)
		if !transient || attempt == attempts || ctx.Err() != nil {
			return &DeliveryError{Class: class}
		}
		select {
		case <-time.After(s.RetryDelay):
		case <-ctx.Done():
			return &DeliveryError{Class: class}
		}
	}
}

// classifySendError never calls err.Error() on a transport error: a
// *url.Error's text embeds the full request URL.
func classifySendError(err error) (class string, transient bool) {
	var status *whatsapp.StatusError
	if errors.As(err, &status) {
		switch {
		case status.Code == 429:
			return "provider_429", true
		case status.Code >= 500:
			return "provider_5xx", true
		default:
			return fmt.Sprintf("provider_%d", status.Code), false
		}
	}
	if errors.Is(err, context.DeadlineExceeded) {
		return "timeout", true
	}
	var netErr net.Error
	if errors.As(err, &netErr) && netErr.Timeout() {
		return "timeout", true
	}
	return "network", true
}
