package whatsapp

import (
	"context"
	"net/http"
	"strings"
)

// OTPSender sends one-time codes with an approved AUTHENTICATION template
// (password reset) — separate from MetaCloudSender, whose template and
// copy belong to claim links. Authentication templates have Meta's own
// fixed copy ("<code> is your verification code…") plus a copy-code
// button; per Meta's "Copy code authentication templates" send example
// the code goes in twice — the body's {{1}} and the button's parameter
// (sub_type "url", index "0") — and may be at most 15 characters.
// There's deliberately no plain-text fallback: a code only ever goes out
// through the approved template.
type OTPSender struct {
	Client   *http.Client
	BaseURL  string // defaults to https://graph.facebook.com (tests only override it)
	Version  string // defaults to the same Graph API version as MetaCloudSender
	Token    string // WHATSAPP_ACCESS_TOKEN
	PhoneID  string // WHATSAPP_PHONE_NUMBER_ID
	Template string // WHATSAPP_OTP_TEMPLATE_NAME
	Language string // WHATSAPP_OTP_TEMPLATE_LANGUAGE, defaults to "ru"
}

// SendCode delivers code to to (E.164, e.g. "+77051112233").
func (s *OTPSender) SendCode(ctx context.Context, to, code string) error {
	client := s.Client
	if client == nil {
		client = &http.Client{}
	}
	base := s.BaseURL
	if base == "" {
		base = defaultBaseURL
	}
	version := s.Version
	if version == "" {
		version = defaultAPIVersion
	}
	lang := s.Language
	if lang == "" {
		lang = defaultLanguage
	}
	return postMessage(ctx, client, base+"/"+version+"/"+s.PhoneID+"/messages", s.Token, otpPayload(strings.TrimPrefix(to, "+"), s.Template, lang, code))
}

func otpPayload(to, template, lang, code string) map[string]any {
	return map[string]any{
		"messaging_product": "whatsapp",
		"recipient_type":    "individual",
		"to":                to,
		"type":              "template",
		"template": map[string]any{
			"name":     template,
			"language": map[string]string{"code": lang},
			"components": []map[string]any{
				{
					"type":       "body",
					"parameters": []map[string]any{{"type": "text", "text": code}},
				},
				{
					"type":       "button",
					"sub_type":   "url",
					"index":      "0",
					"parameters": []map[string]any{{"type": "text", "text": code}},
				},
			},
		},
	}
}
