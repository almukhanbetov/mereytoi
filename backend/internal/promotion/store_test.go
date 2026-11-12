package promotion_test

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/almukhanbetov/mereytoi/backend/internal/promotion"
	"github.com/almukhanbetov/mereytoi/backend/internal/promotion/promotiontest"
)

func appleTx(overrides map[string]any) map[string]any {
	tx := map[string]any{
		"transactionId": "2000000001", "originalTransactionId": "2000000001",
		"bundleId": "kz.mereytoi.mereytoiApp", "productId": "promo_7d", "type": "Consumable",
		"appAccountToken": "6f1c5a43-2a0b-4b8e-9c9e-0a1b2c3d4e5f", "environment": "Sandbox",
		"purchaseDate": 1700000000000,
	}
	for k, v := range overrides {
		tx[k] = v
	}
	return tx
}

func TestAppleTransactionVerified(t *testing.T) {
	chain := promotiontest.NewAppleChain(promotiontest.Options{})
	v := promotion.NewAppleVerifier(chain.Roots, "kz.mereytoi.mereytoiApp", "Sandbox")
	tx, err := v.VerifyTransaction(chain.Sign(appleTx(nil)))
	if err != nil {
		t.Fatalf("valid transaction rejected: %v", err)
	}
	if tx.TransactionID != "2000000001" || tx.ProductID != "promo_7d" || tx.AppAccountToken == "" {
		t.Fatalf("decoded %+v", tx)
	}
}

func TestAppleTransactionRejected(t *testing.T) {
	chain := promotiontest.NewAppleChain(promotiontest.Options{})
	v := promotion.NewAppleVerifier(chain.Roots, "kz.mereytoi.mereytoiApp", "Sandbox")

	other := promotiontest.NewAppleChain(promotiontest.Options{})
	if _, err := v.VerifyTransaction(other.Sign(appleTx(nil))); err == nil {
		t.Fatal("a chain from another root must be rejected")
	}
	unmarked := promotiontest.NewAppleChain(promotiontest.Options{SkipLeafMarker: true})
	vu := promotion.NewAppleVerifier(unmarked.Roots, "kz.mereytoi.mereytoiApp", "Sandbox")
	if _, err := vu.VerifyTransaction(unmarked.Sign(appleTx(nil))); err == nil {
		t.Fatal("a leaf without Apple's marker must be rejected")
	}
	if _, err := v.VerifyTransaction(chain.Sign(appleTx(map[string]any{"bundleId": "com.other"}))); err == nil {
		t.Fatal("another app's transaction must be rejected")
	}
	if _, err := v.VerifyTransaction(chain.Sign(appleTx(map[string]any{"environment": "Production"}))); err == nil {
		t.Fatal("a production transaction must be rejected by a sandbox server")
	}
	// Payload changed after signing.
	jws := chain.Sign(appleTx(nil))
	parts := strings.Split(jws, ".")
	forged, _ := json.Marshal(appleTx(map[string]any{"productId": "free"}))
	parts[1] = base64.RawURLEncoding.EncodeToString(forged)
	if _, err := v.VerifyTransaction(strings.Join(parts, ".")); err == nil {
		t.Fatal("a tampered payload must be rejected")
	}
	if _, err := v.VerifyTransaction("not.a.jws"); err == nil {
		t.Fatal("garbage must be rejected")
	}
}

func TestAppleNotificationVerified(t *testing.T) {
	chain := promotiontest.NewAppleChain(promotiontest.Options{})
	v := promotion.NewAppleVerifier(chain.Roots, "kz.mereytoi.mereytoiApp", "Sandbox")
	payload := map[string]any{
		"notificationType": "REFUND", "notificationUUID": "n-1",
		"data": map[string]any{
			"bundleId": "kz.mereytoi.mereytoiApp", "environment": "Sandbox",
			"signedTransactionInfo": chain.Sign(appleTx(map[string]any{"revocationDate": 1700000100000})),
		},
	}
	n, tx, err := v.VerifyNotification(chain.Sign(payload))
	if err != nil || n.NotificationType != "REFUND" || tx.RevocationDate == 0 {
		t.Fatalf("notification: %+v %+v %v", n, tx, err)
	}
}

func writeServiceAccount(t *testing.T) string {
	key, _ := rsa.GenerateKey(rand.Reader, 2048)
	pemKey := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(key)})
	data, _ := json.Marshal(map[string]string{"client_email": "svc@test.iam.gserviceaccount.com", "private_key": string(pemKey)})
	p := filepath.Join(t.TempDir(), "sa.json")
	if err := os.WriteFile(p, data, 0o600); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestGoogleClientFetchesPurchaseWithServiceAccountToken(t *testing.T) {
	var tokenCalls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/token":
			tokenCalls.Add(1)
			if r.FormValue("grant_type") != "urn:ietf:params:oauth:grant-type:jwt-bearer" || r.FormValue("assertion") == "" {
				w.WriteHeader(http.StatusBadRequest)
				return
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "at-1", "expires_in": 3600})
		case r.Header.Get("Authorization") != "Bearer at-1":
			w.WriteHeader(http.StatusUnauthorized)
		case r.Method == http.MethodGet && strings.HasSuffix(r.URL.Path, "/purchases/products/promo_7d/tokens/tok-1"):
			_ = json.NewEncoder(w).Encode(map[string]any{
				"purchaseState": 0, "orderId": "GPA.1", "obfuscatedExternalAccountId": "order-token",
			})
		case r.Method == http.MethodPost && strings.HasSuffix(r.URL.Path, "/tokens/tok-1:acknowledge"):
			w.WriteHeader(http.StatusNoContent)
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer srv.Close()

	g, err := promotion.LoadGoogleClient(writeServiceAccount(t), "kz.mereytoi.mereytoi_app", srv.URL, srv.URL+"/token")
	if err != nil {
		t.Fatal(err)
	}
	p, err := g.GetPurchase(context.Background(), "promo_7d", "tok-1")
	if err != nil || p.PurchaseState != promotion.GooglePurchased || p.OrderID != "GPA.1" || p.ObfuscatedExternalAccountID != "order-token" {
		t.Fatalf("purchase %+v %v", p, err)
	}
	if err := g.Acknowledge(context.Background(), "promo_7d", "tok-1"); err != nil {
		t.Fatal(err)
	}
	if tokenCalls.Load() != 1 {
		t.Fatalf("access token must be cached, fetched %d times", tokenCalls.Load())
	}
	if _, err := g.GetPurchase(context.Background(), "promo_7d", "unknown"); err == nil {
		t.Fatal("an unknown purchase token must be an error")
	}
}

func TestGoogleClientRejectsBadKeyFile(t *testing.T) {
	p := filepath.Join(t.TempDir(), "bad.json")
	_ = os.WriteFile(p, []byte(`{"type":"authorized_user"}`), 0o600)
	if _, err := promotion.LoadGoogleClient(p, "pkg", "", ""); err == nil {
		t.Fatal("a file without a service-account key must be rejected")
	}
}
