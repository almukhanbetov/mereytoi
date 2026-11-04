package recoverycode

import "strings"

// Limits on email OTP recovery, in the same attempt table and window as the
// other recovery flows. Keys are stored hashed.
const (
	maxEmailOTPRequestsPerIP    = 10
	maxEmailOTPRequestsPerEmail = 5
	maxEmailOTPResetsPerIP      = 20
	maxEmailOTPResetsPerEmail   = 10

	scopeEmailOTPRequestIP    = "otp_req_ip"
	scopeEmailOTPRequestEmail = "otp_req_email"
	scopeEmailOTPResetIP      = "otp_rst_ip"
	scopeEmailOTPResetEmail   = "otp_rst_email"
)

func emailKey(email string) string { return "e:" + strings.ToLower(strings.TrimSpace(email)) }

// AllowEmailOTPRequest counts a request for a code. Over the address limit it
// returns ErrRateLimited, which says nothing about the email. Over the per-email
// limit it just reports not to send: the answer must look the same.
func (s *Service) AllowEmailOTPRequest(clientIP, email string) (send bool, err error) {
	if _, ok := s.reserve(slot{scopeEmailOTPRequestIP, clientIP, maxEmailOTPRequestsPerIP}); !ok {
		return false, ErrRateLimited
	}
	_, send = s.reserve(slot{scopeEmailOTPRequestEmail, emailKey(email), maxEmailOTPRequestsPerEmail})
	return send, nil
}

// AllowEmailOTPReset counts an attempt to redeem a code, whether or not the
// email is known, so the limit reveals nothing either.
func (s *Service) AllowEmailOTPReset(clientIP, email string) bool {
	_, ok := s.reserve(
		slot{scopeEmailOTPResetIP, clientIP, maxEmailOTPResetsPerIP},
		slot{scopeEmailOTPResetEmail, emailKey(email), maxEmailOTPResetsPerEmail},
	)
	return ok
}
