package whatsapp

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"strings"
)

const (
	defaultBaseURL    = "https://graph.facebook.com"
	defaultAPIVersion = "v21.0"
	defaultLanguage   = "ru"
)

// MetaCloudSender talks to Meta's real WhatsApp Cloud API
// (POST /{version}/{phone_number_id}/messages, Bearer auth). This is the
// only "WhatsApp Business Platform" implementation this codebase has —
// Twilio/Infobip-as-BSP were not found configured anywhere, so nothing
// else was built to guess at their contracts.
//
// BaseURL is only ever overridden by tests (a local httptest.Server
// standing in for graph.facebook.com); it is not exposed as a top-level
// env var precisely so production config can't accidentally point this at
// the wrong host.
type MetaCloudSender struct {
	Client   *http.Client
	BaseURL  string // defaults to https://graph.facebook.com
	Version  string // defaults to v21.0
	Token    string // WHATSAPP_ACCESS_TOKEN
	PhoneID  string // WHATSAPP_PHONE_NUMBER_ID
	Template string // WHATSAPP_TEMPLATE_NAME — empty means "send plain text"
	Language string // WHATSAPP_TEMPLATE_LANGUAGE, defaults to "ru"
}

func (s *MetaCloudSender) Send(ctx context.Context, msg Message) error {
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

	to := strings.TrimPrefix(msg.To, "+")

	var payload map[string]any
	if s.Template != "" {
		// Business-initiated messages outside a 24h customer-service
		// window require a pre-approved template on Meta's side (brief
		// section 3's "template-based sending"). This code only ever
		// supplies the single {{1}} body variable — the template's own
		// static copy (which should match brief section 3's message) is
		// whatever was approved in Meta Business Manager under this name.
		lang := s.Language
		if lang == "" {
			lang = defaultLanguage
		}
		payload = map[string]any{
			"messaging_product": "whatsapp",
			"to":                to,
			"type":              "template",
			"template": map[string]any{
				"name":     s.Template,
				"language": map[string]string{"code": lang},
				"components": []map[string]any{
					{
						"type": "body",
						"parameters": []map[string]any{
							{"type": "text", "text": msg.TemplateParam},
						},
					},
				},
			},
		}
	} else {
		payload = map[string]any{
			"messaging_product": "whatsapp",
			"to":                to,
			"type":              "text",
			"text":              map[string]any{"body": msg.Body},
		}
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return err
	}

	url := base + "/" + version + "/" + s.PhoneID + "/messages"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+s.Token)
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		// *url.Error — its Error() string embeds the full request URL.
		// Callers must classify this without calling .Error() on it (see
		// claimdelivery's classifyError).
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return &StatusError{Code: resp.StatusCode}
	}
	return nil
}
