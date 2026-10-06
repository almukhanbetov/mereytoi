package passwordreset

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/almukhanbetov/mereytoi/backend/internal/whatsapp"
)

// graph answers each request with the next status in statuses (repeating
// the last), optionally after a delay, and counts requests.
func graph(t *testing.T, delay time.Duration, statuses ...int) (*httptest.Server, *atomic.Int32) {
	t.Helper()
	var n atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		i := int(n.Add(1)) - 1
		if delay > 0 {
			select {
			case <-time.After(delay):
			case <-r.Context().Done():
				return
			}
		}
		if i >= len(statuses) {
			i = len(statuses) - 1
		}
		w.WriteHeader(statuses[i])
	}))
	t.Cleanup(srv.Close)
	return srv, &n
}

func waSender(url string) *WhatsAppSender {
	s := NewWhatsAppSender(&whatsapp.OTPSender{BaseURL: url, Token: "tok", PhoneID: "P", Template: "otp"})
	s.AttemptTimeout = 200 * time.Millisecond
	s.RetryDelay = time.Millisecond
	return s
}

var msg = CodeMessage{UserID: 1, Phone: "+77071234567", Code: "123456", Purpose: "reset"}

func class(err error) string {
	var de *DeliveryError
	if errors.As(err, &de) {
		return de.Class
	}
	return ""
}

func TestWhatsAppSenderSuccess(t *testing.T) { // 7
	srv, n := graph(t, 0, 200)
	if err := waSender(srv.URL).SendPasswordResetCode(context.Background(), msg); err != nil {
		t.Fatal(err)
	}
	if n.Load() != 1 {
		t.Fatalf("%d requests, want 1", n.Load())
	}
}

func TestWhatsAppSenderRetriesOnceOnTransient(t *testing.T) { // 8, 9
	for status, want := range map[int]string{429: "provider_429", 500: "provider_5xx", 503: "provider_5xx"} {
		srv, n := graph(t, 0, status)
		err := waSender(srv.URL).SendPasswordResetCode(context.Background(), msg)
		if class(err) != want {
			t.Errorf("%d: got %v, want class %s", status, err, want)
		}
		if n.Load() != 2 {
			t.Errorf("%d: %d requests, want exactly 2 (one retry)", status, n.Load())
		}
	}
	// A transient failure followed by success is a success.
	srv, n := graph(t, 0, 429, 200)
	if err := waSender(srv.URL).SendPasswordResetCode(context.Background(), msg); err != nil || n.Load() != 2 {
		t.Fatalf("retry then success: err=%v requests=%d", err, n.Load())
	}
}

func TestWhatsAppSenderNoRetryOn4xx(t *testing.T) { // 10
	for _, status := range []int{400, 401, 403, 404} {
		srv, n := graph(t, 0, status)
		err := waSender(srv.URL).SendPasswordResetCode(context.Background(), msg)
		if n.Load() != 1 {
			t.Errorf("%d: %d requests, want 1 (no retry)", status, n.Load())
		}
		if class(err) == "" {
			t.Errorf("%d: want a DeliveryError, got %v", status, err)
		}
	}
}

func TestWhatsAppSenderTimeoutIsBounded(t *testing.T) { // 11
	srv, n := graph(t, time.Second, 200)
	start := time.Now()
	err := waSender(srv.URL).SendPasswordResetCode(context.Background(), msg)
	if class(err) != "timeout" {
		t.Fatalf("got %v, want timeout", err)
	}
	if n.Load() != 2 {
		t.Fatalf("%d attempts, want 2", n.Load())
	}
	if el := time.Since(start); el > 2*time.Second {
		t.Fatalf("took %v — attempt timeout not applied", el)
	}
}

func TestDeliveryErrorNeverCarriesSecrets(t *testing.T) {
	// A refused connection: the transport error text contains the URL.
	srv, _ := graph(t, 0, 200)
	url := srv.URL
	srv.Close()
	err := waSender(url+"/secret-path").SendPasswordResetCode(context.Background(), msg)
	if err == nil {
		t.Fatal("expected a failure")
	}
	for _, s := range []string{"secret-path", "127.0.0.1", msg.Code, msg.Phone, "tok"} {
		if strings.Contains(err.Error(), s) {
			t.Errorf("error text %q leaks %q", err.Error(), s)
		}
	}
}
