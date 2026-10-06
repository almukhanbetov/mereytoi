package config

import (
	"reflect"
	"testing"
)

func TestTrustedProxiesDefaultIsPrivateOnly(t *testing.T) {
	t.Setenv("TRUSTED_PROXIES", "")
	got := Load().TrustedProxies
	want := []string{"127.0.0.1", "::1", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("default %v, want %v", got, want)
	}
	for _, p := range got {
		if p == "0.0.0.0/0" || p == "::/0" {
			t.Fatalf("default must never trust everyone: %v", got)
		}
	}
}

func TestTrustedProxiesFromEnv(t *testing.T) {
	t.Setenv("TRUSTED_PROXIES", " 172.18.0.1/32 , 127.0.0.1 ,, ")
	if got := Load().TrustedProxies; !reflect.DeepEqual(got, []string{"172.18.0.1/32", "127.0.0.1"}) {
		t.Fatalf("got %v", got)
	}
}

func TestPasswordResetDeliveryReady(t *testing.T) {
	ready := Config{
		PasswordResetDeliveryEnabled: true,
		WhatsAppAccessToken:          "t",
		WhatsAppPhoneNumberID:        "p",
		WhatsAppOTPTemplateName:      "otp",
		OTPHMACSecret:                "0123456789abcdef0123456789abcdef",
	}
	if !ready.PasswordResetDeliveryReady() {
		t.Fatal("complete config must be ready")
	}
	for name, mutate := range map[string]func(*Config){
		"disabled":     func(c *Config) { c.PasswordResetDeliveryEnabled = false },
		"no token":     func(c *Config) { c.WhatsAppAccessToken = "" },
		"no phone id":  func(c *Config) { c.WhatsAppPhoneNumberID = "" },
		"no template":  func(c *Config) { c.WhatsAppOTPTemplateName = "" },
		"short secret": func(c *Config) { c.OTPHMACSecret = "0123456789abcdef0123456789abcde" }, // 31 bytes
	} {
		c := ready
		mutate(&c)
		if c.PasswordResetDeliveryReady() {
			t.Errorf("%s: must not be ready", name)
		}
	}
}

func TestPasswordResetDeliveryOffByDefault(t *testing.T) {
	for _, k := range []string{"PASSWORD_RESET_DELIVERY_ENABLED", "WHATSAPP_OTP_TEMPLATE_NAME", "OTP_HMAC_SECRET"} {
		t.Setenv(k, "")
	}
	c := Load()
	if c.PasswordResetDeliveryEnabled || c.PasswordResetDeliveryReady() || c.WhatsAppOTPTemplateLanguage != "ru" {
		t.Fatalf("defaults: enabled=%v ready=%v lang=%q", c.PasswordResetDeliveryEnabled, c.PasswordResetDeliveryReady(), c.WhatsAppOTPTemplateLanguage)
	}
}
