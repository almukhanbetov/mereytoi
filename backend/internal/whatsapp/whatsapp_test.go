package whatsapp

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
)

// captured is one request the fake Graph API received.
type captured struct {
	path, auth string
	body       map[string]any
}

func fakeGraph(t *testing.T, status int) (*httptest.Server, *[]captured) {
	t.Helper()
	var got []captured
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		raw, _ := io.ReadAll(r.Body)
		var body map[string]any
		_ = json.Unmarshal(raw, &body)
		got = append(got, captured{path: r.URL.Path, auth: r.Header.Get("Authorization"), body: body})
		w.WriteHeader(status)
	}))
	t.Cleanup(srv.Close)
	return srv, &got
}

func asJSON(t *testing.T, v any) string {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

// Matches Meta's "Copy code authentication templates" send example: the
// code in the body parameter and again as the url button's parameter.
func TestOTPSenderPayloadIsAuthenticationTemplate(t *testing.T) {
	srv, got := fakeGraph(t, http.StatusOK)
	s := &OTPSender{BaseURL: srv.URL, Token: "tok", PhoneID: "PHONEID", Template: "mereytoi_password_code", Language: "ru"}
	if err := s.SendCode(context.Background(), "+77071234567", "048213"); err != nil {
		t.Fatal(err)
	}
	if len(*got) != 1 {
		t.Fatalf("%d requests", len(*got))
	}
	req := (*got)[0]
	if req.path != "/v21.0/PHONEID/messages" || req.auth != "Bearer tok" {
		t.Fatalf("path %q auth %q", req.path, req.auth)
	}
	want := `{"messaging_product":"whatsapp","recipient_type":"individual","template":{"components":[{"parameters":[{"text":"048213","type":"text"}],"type":"body"},{"index":"0","parameters":[{"text":"048213","type":"text"}],"sub_type":"url","type":"button"}],"language":{"code":"ru"},"name":"mereytoi_password_code"},"to":"77071234567","type":"template"}`
	if g := asJSON(t, req.body); g != want {
		t.Fatalf("payload\n got %s\nwant %s", g, want)
	}
}

func TestOTPSenderDefaultsLanguageAndReportsStatus(t *testing.T) {
	srv, got := fakeGraph(t, http.StatusBadRequest)
	s := &OTPSender{BaseURL: srv.URL, Token: "tok", PhoneID: "P", Template: "t"}
	err := s.SendCode(context.Background(), "+77071234567", "123456")
	var se *StatusError
	if !errors.As(err, &se) || se.Code != http.StatusBadRequest {
		t.Fatalf("got %v, want StatusError 400", err)
	}
	if lang := (*got)[0].body["template"].(map[string]any)["language"].(map[string]any)["code"]; lang != "ru" {
		t.Fatalf("default language %v", lang)
	}
}

// The claim-link sender's two payloads are unchanged by the shared POST
// refactor (exact JSON snapshots).
func TestClaimSenderPayloadsUnchanged(t *testing.T) {
	srv, got := fakeGraph(t, http.StatusOK)
	tpl := &MetaCloudSender{BaseURL: srv.URL, Token: "tok", PhoneID: "P", Template: "claim_tpl", Language: "ru"}
	if err := tpl.Send(context.Background(), Message{To: "+77051112233", Body: "b", TemplateParam: "https://x/claim/abc"}); err != nil {
		t.Fatal(err)
	}
	text := &MetaCloudSender{BaseURL: srv.URL, Token: "tok", PhoneID: "P"}
	if err := text.Send(context.Background(), Message{To: "+77051112233", Body: "Откройте https://x/claim/abc"}); err != nil {
		t.Fatal(err)
	}
	wantTpl := `{"messaging_product":"whatsapp","template":{"components":[{"parameters":[{"text":"https://x/claim/abc","type":"text"}],"type":"body"}],"language":{"code":"ru"},"name":"claim_tpl"},"to":"77051112233","type":"template"}`
	wantText := `{"messaging_product":"whatsapp","text":{"body":"Откройте https://x/claim/abc"},"to":"77051112233","type":"text"}`
	if g := asJSON(t, (*got)[0].body); g != wantTpl {
		t.Fatalf("claim template payload changed:\n got %s\nwant %s", g, wantTpl)
	}
	if g := asJSON(t, (*got)[1].body); g != wantText {
		t.Fatalf("claim text payload changed:\n got %s\nwant %s", g, wantText)
	}
	if (*got)[0].path != "/v21.0/P/messages" || (*got)[0].auth != "Bearer tok" {
		t.Fatal("claim request target changed")
	}
}
