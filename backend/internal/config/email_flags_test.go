package config

import "testing"

func TestEmailFlagsAreReadSeparatelyAndOffByDefault(t *testing.T) {
	for _, tc := range []struct {
		mail, otp         string
		wantMail, wantOTP bool
	}{
		{"", "", false, false},
		{"false", "true", false, true},
		{"true", "false", true, false},
		{"true", "true", true, true},
	} {
		t.Setenv("MAIL_ENABLED", tc.mail)
		t.Setenv("PASSWORD_EMAIL_OTP_ENABLED", tc.otp)
		cfg := Load()
		if cfg.MailEnabled != tc.wantMail || cfg.PasswordEmailOTPEnabled != tc.wantOTP {
			t.Fatalf("%+v: mail %v, otp %v", tc, cfg.MailEnabled, cfg.PasswordEmailOTPEnabled)
		}
	}
}
