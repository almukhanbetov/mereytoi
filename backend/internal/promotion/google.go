package promotion

import (
	"context"
	"crypto/rsa"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const (
	googleAPIBase     = "https://androidpublisher.googleapis.com"
	googleTokenURL    = "https://oauth2.googleapis.com/token"
	androidPublisher  = "https://www.googleapis.com/auth/androidpublisher"
	googleHTTPTimeout = 15 * time.Second
)

// Google Play purchase states (purchases.products).
const (
	GooglePurchased = 0
	GoogleCanceled  = 1
	GooglePending   = 2
)

// GoogleClient talks to the Google Play Developer API as a service account.
type GoogleClient struct {
	PackageName string
	baseURL     string
	tokenURL    string
	email       string
	key         *rsa.PrivateKey
	http        *http.Client
	now         func() time.Time

	mu      sync.Mutex
	token   string
	expires time.Time
}

// LoadGoogleClient reads the service-account JSON key file.
func LoadGoogleClient(keyFile, packageName, baseURL, tokenURL string) (*GoogleClient, error) {
	data, err := os.ReadFile(keyFile)
	if err != nil {
		return nil, err
	}
	var sa struct {
		ClientEmail string `json:"client_email"`
		PrivateKey  string `json:"private_key"`
	}
	if err := json.Unmarshal(data, &sa); err != nil || sa.ClientEmail == "" || sa.PrivateKey == "" {
		return nil, fmt.Errorf("google service account file is not a service-account key")
	}
	key, err := jwt.ParseRSAPrivateKeyFromPEM([]byte(sa.PrivateKey))
	if err != nil {
		return nil, fmt.Errorf("google service account key: %w", err)
	}
	if baseURL == "" {
		baseURL = googleAPIBase
	}
	if tokenURL == "" {
		tokenURL = googleTokenURL
	}
	return &GoogleClient{
		PackageName: packageName,
		baseURL:     strings.TrimRight(baseURL, "/"),
		tokenURL:    tokenURL,
		email:       sa.ClientEmail,
		key:         key,
		http:        &http.Client{Timeout: googleHTTPTimeout},
		now:         time.Now,
	}, nil
}

// GooglePurchase is the part of a ProductPurchase we use.
type GooglePurchase struct {
	PurchaseState               int    `json:"purchaseState"`
	ConsumptionState            int    `json:"consumptionState"`
	AcknowledgementState        int    `json:"acknowledgementState"`
	OrderID                     string `json:"orderId"`
	ObfuscatedExternalAccountID string `json:"obfuscatedExternalAccountId"`
	PurchaseTimeMillis          string `json:"purchaseTimeMillis"`
}

// GetPurchase fetches the purchase state of a one-time product.
func (g *GoogleClient) GetPurchase(ctx context.Context, productID, token string) (GooglePurchase, error) {
	var p GooglePurchase
	err := g.call(ctx, http.MethodGet, g.productURL(productID, token, ""), &p)
	return p, err
}

// Acknowledge confirms delivery (Google refunds unacknowledged purchases
// after three days).
func (g *GoogleClient) Acknowledge(ctx context.Context, productID, token string) error {
	return g.call(ctx, http.MethodPost, g.productURL(productID, token, ":acknowledge"), nil)
}

// Consume lets the same consumable product be bought again later.
func (g *GoogleClient) Consume(ctx context.Context, productID, token string) error {
	return g.call(ctx, http.MethodPost, g.productURL(productID, token, ":consume"), nil)
}

func (g *GoogleClient) productURL(productID, token, action string) string {
	return fmt.Sprintf("%s/androidpublisher/v3/applications/%s/purchases/products/%s/tokens/%s%s",
		g.baseURL, url.PathEscape(g.PackageName), url.PathEscape(productID), url.PathEscape(token), action)
}

// GoogleAPIError is a non-2xx answer of the Play Developer API.
type GoogleAPIError struct{ Status int }

func (e GoogleAPIError) Error() string { return fmt.Sprintf("google play api: status %d", e.Status) }

func (g *GoogleClient) call(ctx context.Context, method, endpoint string, out any) error {
	tok, err := g.accessToken(ctx)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, method, endpoint, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+tok)
	res, err := g.http.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(res.Body, 1<<20))
	if res.StatusCode < 200 || res.StatusCode > 299 {
		return GoogleAPIError{Status: res.StatusCode}
	}
	if out != nil {
		return json.Unmarshal(body, out)
	}
	return nil
}

func (g *GoogleClient) accessToken(ctx context.Context) (string, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	now := g.now()
	if g.token != "" && now.Before(g.expires.Add(-time.Minute)) {
		return g.token, nil
	}
	assertion, err := jwt.NewWithClaims(jwt.SigningMethodRS256, jwt.MapClaims{
		"iss":   g.email,
		"scope": androidPublisher,
		"aud":   g.tokenURL,
		"iat":   now.Unix(),
		"exp":   now.Add(time.Hour).Unix(),
	}).SignedString(g.key)
	if err != nil {
		return "", err
	}
	form := url.Values{
		"grant_type": {"urn:ietf:params:oauth:grant-type:jwt-bearer"},
		"assertion":  {assertion},
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, g.tokenURL, strings.NewReader(form.Encode()))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	res, err := g.http.Do(req)
	if err != nil {
		return "", err
	}
	defer res.Body.Close()
	var out struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
	}
	if res.StatusCode != http.StatusOK || json.NewDecoder(io.LimitReader(res.Body, 1<<20)).Decode(&out) != nil || out.AccessToken == "" {
		return "", fmt.Errorf("google oauth: status %d", res.StatusCode)
	}
	g.token = out.AccessToken
	g.expires = now.Add(time.Duration(out.ExpiresIn) * time.Second)
	return g.token, nil
}

// GoogleNotification is a decoded Real-time developer notification.
type GoogleNotification struct {
	PackageName                string `json:"packageName"`
	OneTimeProductNotification *struct {
		NotificationType int    `json:"notificationType"`
		PurchaseToken    string `json:"purchaseToken"`
		SKU              string `json:"sku"`
	} `json:"oneTimeProductNotification"`
	VoidedPurchaseNotification *struct {
		PurchaseToken string `json:"purchaseToken"`
		OrderID       string `json:"orderId"`
		ProductType   int    `json:"productType"`
	} `json:"voidedPurchaseNotification"`
	TestNotification *struct {
		Version string `json:"version"`
	} `json:"testNotification"`
}

// One-time product notification types.
const (
	GoogleOneTimePurchased = 1
	GoogleOneTimeCanceled  = 2
)
