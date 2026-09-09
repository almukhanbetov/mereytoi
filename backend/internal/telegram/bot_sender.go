package telegram

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
)

const defaultBaseURL = "https://api.telegram.org"

// BotSender talks to Telegram's real Bot API
// (POST /bot{token}/sendMessage). BaseURL is only ever overridden by tests
// (a local httptest.Server standing in for api.telegram.org) — not a
// top-level env var, so production config can't accidentally point this
// at the wrong host.
type BotSender struct {
	Client  *http.Client
	BaseURL string // defaults to https://api.telegram.org
	Token   string // TELEGRAM_BOT_TOKEN
}

func (s *BotSender) Send(ctx context.Context, chatID, text string) error {
	client := s.Client
	if client == nil {
		client = &http.Client{}
	}
	base := s.BaseURL
	if base == "" {
		base = defaultBaseURL
	}

	body, err := json.Marshal(map[string]string{"chat_id": chatID, "text": text})
	if err != nil {
		return err
	}

	url := base + "/bot" + s.Token + "/sendMessage"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		// *url.Error — its Error() string embeds the full request URL
		// (which itself embeds the bot token). Callers must classify this
		// without calling .Error() on it (see claimdelivery's classifyError).
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return &StatusError{Code: resp.StatusCode}
	}
	return nil
}
