package routes_test

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/config"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
	"github.com/almukhanbetov/mereytoi/backend/internal/promotion"
	"github.com/almukhanbetov/mereytoi/backend/internal/promotion/promotiontest"
	"github.com/almukhanbetov/mereytoi/backend/internal/routes"
)

// fakeGoogle stands in for the Play Developer API. Tests set the state of
// each purchase token; nothing is ever charged.
type fakeGoogle struct {
	mu        sync.Mutex
	purchases map[string]promotion.GooglePurchase
	acks      map[string]int
	consumes  map[string]int
	down      bool
}

func newFakeGoogle() *fakeGoogle {
	return &fakeGoogle{purchases: map[string]promotion.GooglePurchase{}, acks: map[string]int{}, consumes: map[string]int{}}
}

func (f *fakeGoogle) set(token string, p promotion.GooglePurchase) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.purchases[token] = p
}

func (f *fakeGoogle) GetPurchase(_ context.Context, _ string, token string) (promotion.GooglePurchase, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.down {
		return promotion.GooglePurchase{}, promotion.GoogleAPIError{Status: 503}
	}
	p, ok := f.purchases[token]
	if !ok {
		return p, promotion.GoogleAPIError{Status: 404}
	}
	return p, nil
}

func (f *fakeGoogle) Acknowledge(_ context.Context, _ string, token string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.acks[token]++
	p := f.purchases[token]
	p.AcknowledgementState = 1
	f.purchases[token] = p
	return nil
}

func (f *fakeGoogle) Consume(_ context.Context, _ string, token string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.consumes[token]++
	p := f.purchases[token]
	p.ConsumptionState = 1
	f.purchases[token] = p
	return nil
}

// clock is a settable test clock.
type clock struct {
	mu sync.Mutex
	t  time.Time
}

func (c *clock) now() time.Time { c.mu.Lock(); defer c.mu.Unlock(); return c.t }
func (c *clock) add(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.t = c.t.Add(d)
}

type promoEnv struct {
	t      *testing.T
	base   string
	db     *gorm.DB
	google *fakeGoogle
	apple  *promotiontest.AppleChain
	clock  *clock
	admin  apiClient
	cat    models.Category
	cat2   models.Category
}

const rtdnToken = "rtdn-test-token"

func setupPromotions(t *testing.T, mutate func(*config.Config), withStores bool) *promoEnv {
	t.Helper()
	gin.SetMode(gin.TestMode)
	name := strings.NewReplacer("/", "_", " ", "_").Replace(t.Name())
	db, err := gorm.Open(sqlite.Open("file:"+name+"?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(
		&models.User{}, &models.Category{}, &models.Listing{}, &models.ListingManager{}, &models.Provider{},
		&models.ListingHall{}, &models.ListingMenu{}, &models.ListingMenuSection{}, &models.ListingMenuItem{}, &models.ListingMenuExtra{},
		&models.PromotionSettings{}, &models.PromotionOrder{}, &models.Promotion{},
		&models.PromotionStat{}, &models.PromotionEventSeen{}, &models.PromotionStoreNotification{},
	); err != nil {
		t.Fatal(err)
	}
	cfg := config.Config{
		JWTSecret: "test-secret-only", PromotionsEnabled: true, PromotionFirstPosition: 2, PromotionEvery: 6,
		GooglePlayPackageName: "kz.mereytoi.mereytoi_app", GooglePlayRTDNToken: rtdnToken,
		AppleBundleID: "kz.mereytoi.mereytoiApp", AppleEnvironment: "Sandbox",
	}
	if mutate != nil {
		mutate(&cfg)
	}
	env := &promoEnv{t: t, db: db, clock: &clock{t: time.Date(2026, 11, 1, 10, 0, 0, 0, time.UTC)}}
	opts := routes.Options{Now: env.clock.now}
	if withStores {
		env.google = newFakeGoogle()
		env.apple = promotiontest.NewAppleChain(promotiontest.Options{})
		opts.PromotionGoogle = env.google
		opts.PromotionApple = promotion.NewAppleVerifier(env.apple.Roots, cfg.AppleBundleID, cfg.AppleEnvironment)
	}
	r := gin.New()
	routes.RegisterWithOptions(r, db, cfg, opts)
	srv := httptest.NewServer(r)
	t.Cleanup(func() {
		srv.Close()
		sqlDB, _ := db.DB()
		_ = sqlDB.Close()
	})
	env.base = srv.URL
	env.admin = registerAdmin(t, env.base, db, "Admin", "admin@"+name+".test")
	env.cat = models.Category{Slug: "hosts", NameRu: "Ведущие", NameKz: "Жүргізушілер"}
	env.cat2 = models.Category{Slug: "shows", NameRu: "Шоу", NameKz: "Шоу"}
	db.Create(&env.cat)
	db.Create(&env.cat2)
	return env
}

func (e *promoEnv) settings(enabled bool, price uint) {
	e.t.Helper()
	status, out := e.admin.do("PUT", "/api/admin/promotions/settings", map[string]any{
		"enabled": enabled, "price_kzt": price, "google_product_id": "promo_7d", "apple_product_id": "promo_7d_ios",
	})
	if status != http.StatusOK {
		e.t.Fatalf("settings: %d %v", status, out)
	}
}

// provider registers a user with an active provider profile.
func (e *promoEnv) provider(name string) apiClient {
	e.t.Helper()
	c := registerUser(e.t, e.base, name, strings.ToLower(strings.ReplaceAll(name, " ", "."))+"@"+strings.ReplaceAll(e.t.Name(), "/", "_")+".test")
	if status, out := c.do("POST", "/api/provider", map[string]any{"display_name": name, "city": "Алматы"}); status != http.StatusCreated {
		e.t.Fatalf("provider: %d %v", status, out)
	}
	return c
}

// listing creates a listing owned by c; created_at is spread out so the
// catalog order (newest first) is deterministic.
func (e *promoEnv) listing(c apiClient, name, city string, cat models.Category) uint {
	e.t.Helper()
	status, out := c.do("POST", "/api/provider/me/listings", map[string]any{
		"category_id": cat.ID, "name_ru": name, "name_kz": name, "city": city, "price": 1000,
	})
	if status != http.StatusCreated {
		e.t.Fatalf("listing: %d %v", status, out)
	}
	id := uint(out["listing"].(map[string]any)["id"].(float64))
	e.db.Model(&models.Listing{}).Where("id = ?", id).Update("created_at", time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC).Add(time.Duration(id)*time.Minute))
	return id
}

// buyGoogle runs the whole Google Play purchase for a listing and returns
// the purchase token.
func (e *promoEnv) buyGoogle(owner apiClient, listingID uint, txID string) string {
	e.t.Helper()
	status, out := owner.do("POST", "/api/promotions/orders", map[string]any{"listing_id": listingID, "channel": "google"})
	if status != http.StatusCreated {
		e.t.Fatalf("order: %d %v", status, out)
	}
	order := out["order"].(map[string]any)
	token := "purchase-" + txID
	e.google.set(token, promotion.GooglePurchase{
		PurchaseState: promotion.GooglePurchased, OrderID: txID, ObfuscatedExternalAccountID: order["token"].(string),
	})
	status, out = owner.do("POST", "/api/promotions/purchases/google", map[string]any{"order_id": order["id"], "purchase_token": token})
	if status != http.StatusCreated {
		e.t.Fatalf("confirm: %d %v", status, out)
	}
	return token
}

type feedPage struct {
	items  []map[string]any
	next   string
	total  int
	status int
}

func (e *promoEnv) feed(c apiClient, query string) feedPage {
	e.t.Helper()
	status, out := c.do("GET", "/api/listings/feed?"+query, nil)
	p := feedPage{status: status}
	if status != http.StatusOK {
		return p
	}
	for _, it := range out["items"].([]any) {
		p.items = append(p.items, it.(map[string]any))
	}
	if n, ok := out["next_cursor"].(string); ok {
		p.next = n
	}
	p.total = int(out["total"].(float64))
	return p
}

// feedAll follows next_cursor to the end.
func (e *promoEnv) feedAll(c apiClient, query string, limit int) []map[string]any {
	e.t.Helper()
	var all []map[string]any
	q := fmt.Sprintf("%s&limit=%d", query, limit)
	for i := 0; i < 50; i++ {
		p := e.feed(c, q)
		if p.status != http.StatusOK {
			e.t.Fatalf("feed: %d", p.status)
		}
		all = append(all, p.items...)
		if p.next == "" {
			return all
		}
		q = fmt.Sprintf("%s&limit=%d&cursor=%s", query, limit, p.next)
	}
	e.t.Fatal("feed never ended")
	return nil
}

func layoutOf(items []map[string]any) string {
	var parts []string
	for _, it := range items {
		id := int(it["id"].(float64))
		if it["promoted"] == true {
			parts = append(parts, fmt.Sprintf("[%d]", id))
		} else {
			parts = append(parts, fmt.Sprint(id))
		}
	}
	return strings.Join(parts, " ")
}

func promotedIDs(items []map[string]any) []int {
	var ids []int
	for _, it := range items {
		if it["promoted"] == true {
			ids = append(ids, int(it["id"].(float64)))
		}
	}
	return ids
}

func sortedInts(in []int) []int {
	out := append([]int(nil), in...)
	sort.Ints(out)
	return out
}

func (e *promoEnv) countPromotions(listingID uint) int64 {
	var n int64
	e.db.Model(&models.Promotion{}).Where("listing_id = ?", listingID).Count(&n)
	return n
}

func TestPromotionGooglePurchaseActivatesOnceAfterServerCheck(t *testing.T) {
	e := setupPromotions(t, nil, true)
	e.settings(true, 2500)
	owner := e.provider("Owner One")
	id := e.listing(owner, "Ведущий", "Алматы", e.cat)

	// Terms, price and duration are shown before paying.
	status, out := owner.do("GET", fmt.Sprintf("/api/promotions/listings/%d", id), nil)
	if status != http.StatusOK || out["can_purchase"] != true {
		t.Fatalf("status: %d %v", status, out)
	}
	pkg := out["package"].(map[string]any)
	if pkg["duration_days"].(float64) != 7 || pkg["auto_renew"] != false || pkg["price_kzt"].(float64) != 2500 {
		t.Fatalf("package %v", pkg)
	}
	ch := out["channels"].(map[string]any)
	if ch["google"].(map[string]any)["available"] != true || ch["web"].(map[string]any)["available"] != false {
		t.Fatalf("channels %v", ch)
	}

	status, out = owner.do("POST", "/api/promotions/orders", map[string]any{"listing_id": id, "channel": "google"})
	if status != http.StatusCreated {
		t.Fatalf("order: %d %v", status, out)
	}
	order := out["order"].(map[string]any)

	// The client claiming success isn't enough: unknown to Google → no promotion.
	status, _ = owner.do("POST", "/api/promotions/purchases/google", map[string]any{"order_id": order["id"], "purchase_token": "made-up"})
	if status != http.StatusBadGateway || e.countPromotions(id) != 0 {
		t.Fatalf("unverifiable purchase must not activate, got %d", status)
	}

	// Pending payment (e.g. cash at a store): accepted, not active yet.
	e.google.set("tok", promotion.GooglePurchase{PurchaseState: promotion.GooglePending, ObfuscatedExternalAccountID: order["token"].(string)})
	status, _ = owner.do("POST", "/api/promotions/purchases/google", map[string]any{"order_id": order["id"], "purchase_token": "tok"})
	if status != http.StatusAccepted || e.countPromotions(id) != 0 {
		t.Fatalf("pending must not activate, got %d", status)
	}

	// Paid.
	e.google.set("tok", promotion.GooglePurchase{PurchaseState: promotion.GooglePurchased, OrderID: "GPA.1", ObfuscatedExternalAccountID: order["token"].(string)})
	status, out = owner.do("POST", "/api/promotions/purchases/google", map[string]any{"order_id": order["id"], "purchase_token": "tok"})
	if status != http.StatusCreated {
		t.Fatalf("confirm: %d %v", status, out)
	}
	p := out["promotion"].(map[string]any)
	starts, _ := time.Parse(time.RFC3339, p["starts_at"].(string))
	ends, _ := time.Parse(time.RFC3339, p["ends_at"].(string))
	if p["running"] != true || ends.Sub(starts) != 7*24*time.Hour {
		t.Fatalf("promotion %v", p)
	}

	// Repeats of the same confirmation and the same store notification
	// return the existing promotion, never a second one.
	for i := 0; i < 3; i++ {
		status, _ = owner.do("POST", "/api/promotions/purchases/google", map[string]any{"order_id": order["id"], "purchase_token": "tok"})
		if status != http.StatusOK {
			t.Fatalf("repeat confirm: %d", status)
		}
		e.rtdn(t, fmt.Sprintf("msg-p-%d", i), map[string]any{"oneTimeProductNotification": map[string]any{"notificationType": 1, "purchaseToken": "tok", "sku": "promo_7d"}})
	}
	if e.countPromotions(id) != 1 {
		t.Fatalf("expected exactly one promotion, got %d", e.countPromotions(id))
	}
	if e.google.acks["tok"] != 1 || e.google.consumes["tok"] != 1 {
		t.Fatalf("acknowledge/consume once: %v %v", e.google.acks, e.google.consumes)
	}

	// Another purchase while running is refused.
	status, out = owner.do("POST", "/api/promotions/orders", map[string]any{"listing_id": id, "channel": "google"})
	if status != http.StatusConflict || out["error"] != "already_running" {
		t.Fatalf("second order while running: %d %v", status, out)
	}
}

func (e *promoEnv) rtdn(t *testing.T, messageID string, payload map[string]any) int {
	t.Helper()
	payload["packageName"] = "kz.mereytoi.mereytoi_app"
	data, _ := json.Marshal(payload)
	c := apiClient{t: t, base: e.base}
	status, _ := c.do("POST", "/api/promotions/webhooks/google?token="+rtdnToken, map[string]any{
		"message": map[string]any{"data": base64.StdEncoding.EncodeToString(data), "messageId": messageID},
	})
	return status
}

func TestPromotionGoogleCancelledOrMismatchedPaymentNeverActivates(t *testing.T) {
	e := setupPromotions(t, nil, true)
	e.settings(true, 2500)
	owner := e.provider("Owner Two")
	id := e.listing(owner, "Шоу", "Алматы", e.cat)

	_, out := owner.do("POST", "/api/promotions/orders", map[string]any{"listing_id": id, "channel": "google"})
	order := out["order"].(map[string]any)

	e.google.set("cancelled", promotion.GooglePurchase{PurchaseState: promotion.GoogleCanceled, ObfuscatedExternalAccountID: order["token"].(string)})
	status, out := owner.do("POST", "/api/promotions/purchases/google", map[string]any{"order_id": order["id"], "purchase_token": "cancelled"})
	if status != http.StatusConflict || out["error"] != "payment_cancelled" {
		t.Fatalf("cancelled: %d %v", status, out)
	}

	_, out = owner.do("POST", "/api/promotions/orders", map[string]any{"listing_id": id, "channel": "google"})
	order2 := out["order"].(map[string]any)
	// A real purchase, but made for another order (token of the first one).
	e.google.set("other", promotion.GooglePurchase{PurchaseState: promotion.GooglePurchased, OrderID: "GPA.9", ObfuscatedExternalAccountID: order["token"].(string)})
	status, out = owner.do("POST", "/api/promotions/purchases/google", map[string]any{"order_id": order2["id"], "purchase_token": "other"})
	if status != http.StatusConflict || out["error"] != "order_mismatch" {
		t.Fatalf("mismatch: %d %v", status, out)
	}

	// Someone else's order can't be confirmed.
	stranger := registerUser(t, e.base, "Stranger", "stranger@two.test")
	status, _ = stranger.do("POST", "/api/promotions/purchases/google", map[string]any{"order_id": order2["id"], "purchase_token": "other"})
	if status != http.StatusNotFound {
		t.Fatalf("foreign order: %d", status)
	}
	if e.countPromotions(id) != 0 {
		t.Fatal("no promotion may exist")
	}
}

func TestPromotionRefundRemovesAdAtOnce(t *testing.T) {
	e := setupPromotions(t, nil, true)
	e.settings(true, 2500)
	owner := e.provider("Owner Three")
	var ids []uint
	for i := 0; i < 5; i++ {
		ids = append(ids, e.listing(owner, fmt.Sprintf("L%d", i), "Алматы", e.cat))
	}
	token := e.buyGoogle(owner, ids[0], "GPA.R")
	viewer := registerUser(t, e.base, "Viewer", "viewer@refund.test")
	if got := promotedIDs(e.feed(viewer, "category=hosts").items); fmt.Sprint(got) != fmt.Sprint([]int{int(ids[0])}) {
		t.Fatalf("ad before refund: %v", got)
	}

	// Wrong webhook secret is refused.
	c := apiClient{t: t, base: e.base}
	if status, _ := c.do("POST", "/api/promotions/webhooks/google?token=nope", map[string]any{"message": map[string]any{"data": "e30=", "messageId": "x"}}); status != http.StatusUnauthorized {
		t.Fatalf("bad token: %d", status)
	}

	voided := map[string]any{"voidedPurchaseNotification": map[string]any{"purchaseToken": token, "orderId": "GPA.R", "productType": 2}}
	if status := e.rtdn(t, "void-1", voided); status != http.StatusNoContent {
		t.Fatalf("rtdn: %d", status)
	}
	if got := promotedIDs(e.feed(viewer, "category=hosts").items); len(got) != 0 {
		t.Fatalf("refunded listing still advertised: %v", got)
	}
	var p models.Promotion
	e.db.Where("listing_id = ?", ids[0]).First(&p)
	if p.Status != models.PromotionRefunded || p.RevokedAt == nil {
		t.Fatalf("promotion after refund: %+v", p)
	}
	// The listing itself stays in the catalog as a regular card.
	if p := e.feed(viewer, "category=hosts"); p.total != 5 {
		t.Fatalf("catalog total %d", p.total)
	}
	// A refunded promotion counts nothing.
	_, out := viewer.do("POST", "/api/promotions/events", map[string]any{"promotion_id": p.ID, "kind": "impression"})
	if out["counted"] != false {
		t.Fatalf("event on refunded: %v", out)
	}
	// Redelivered notification is harmless.
	if status := e.rtdn(t, "void-1", voided); status != http.StatusNoContent {
		t.Fatalf("redelivery: %d", status)
	}
}

func TestPromotionPurchaseCompletedOnlyByNotification(t *testing.T) {
	// The app closed before reporting: the store notification activates it.
	e := setupPromotions(t, nil, true)
	e.settings(true, 2500)
	owner := e.provider("Owner Four")
	id := e.listing(owner, "X", "Алматы", e.cat)
	_, out := owner.do("POST", "/api/promotions/orders", map[string]any{"listing_id": id, "channel": "google"})
	order := out["order"].(map[string]any)
	e.google.set("late", promotion.GooglePurchase{PurchaseState: promotion.GooglePurchased, OrderID: "GPA.L", ObfuscatedExternalAccountID: order["token"].(string)})
	e.rtdn(t, "late-1", map[string]any{"oneTimeProductNotification": map[string]any{"notificationType": 1, "purchaseToken": "late", "sku": "promo_7d"}})
	if e.countPromotions(id) != 1 {
		t.Fatal("notification must activate a verified purchase")
	}
	// Store API down: the notification asks to be redelivered.
	e.google.down = true
	if status := e.rtdn(t, "late-2", map[string]any{"oneTimeProductNotification": map[string]any{"notificationType": 1, "purchaseToken": "late", "sku": "promo_7d"}}); status != http.StatusBadGateway {
		t.Fatalf("store down: %d", status)
	}
	e.google.down = false
	if status := e.rtdn(t, "late-2", map[string]any{"oneTimeProductNotification": map[string]any{"notificationType": 1, "purchaseToken": "late", "sku": "promo_7d"}}); status != http.StatusNoContent || e.countPromotions(id) != 1 {
		t.Fatalf("redelivered after outage: %d, promotions %d", status, e.countPromotions(id))
	}
}

func TestPromotionApplePurchaseRefundAndReversal(t *testing.T) {
	e := setupPromotions(t, nil, true)
	e.settings(true, 2500)
	owner := e.provider("Owner Five")
	id := e.listing(owner, "Apple", "Алматы", e.cat)
	_, out := owner.do("POST", "/api/promotions/orders", map[string]any{"listing_id": id, "channel": "apple"})
	order := out["order"].(map[string]any)
	if order["product_id"] != "promo_7d_ios" {
		t.Fatalf("order %v", order)
	}
	tx := map[string]any{
		"transactionId": "1000000777", "originalTransactionId": "1000000777", "bundleId": "kz.mereytoi.mereytoiApp",
		"productId": "promo_7d_ios", "type": "Consumable", "appAccountToken": order["token"], "environment": "Sandbox",
		"purchaseDate": 1700000000000,
	}

	// Forged: signed by someone else.
	forger := promotiontest.NewAppleChain(promotiontest.Options{})
	status, _ := owner.do("POST", "/api/promotions/purchases/apple", map[string]any{"order_id": order["id"], "signed_transaction": forger.Sign(tx)})
	if status != http.StatusBadRequest || e.countPromotions(id) != 0 {
		t.Fatalf("forged transaction: %d", status)
	}

	signed := e.apple.Sign(tx)
	for i, want := range []int{http.StatusCreated, http.StatusOK} {
		status, out = owner.do("POST", "/api/promotions/purchases/apple", map[string]any{"order_id": order["id"], "signed_transaction": signed})
		if status != want {
			t.Fatalf("confirm %d: %d %v", i, status, out)
		}
	}
	if e.countPromotions(id) != 1 {
		t.Fatal("exactly one promotion")
	}

	notify := func(uuid, kind string, txOverrides map[string]any) int {
		info := map[string]any{}
		for k, v := range tx {
			info[k] = v
		}
		for k, v := range txOverrides {
			info[k] = v
		}
		c := apiClient{t: t, base: e.base}
		st, _ := c.do("POST", "/api/promotions/webhooks/apple", map[string]any{"signedPayload": e.apple.Sign(map[string]any{
			"notificationType": kind, "notificationUUID": uuid,
			"data": map[string]any{"bundleId": "kz.mereytoi.mereytoiApp", "environment": "Sandbox", "signedTransactionInfo": e.apple.Sign(info)},
		})})
		return st
	}
	if notify("n-1", "REFUND", map[string]any{"revocationDate": 1700000500000}) != http.StatusOK {
		t.Fatal("refund notification")
	}
	var p models.Promotion
	e.db.Where("listing_id = ?", id).First(&p)
	if p.Status != models.PromotionRefunded {
		t.Fatalf("after refund %s", p.Status)
	}
	notify("n-2", "REFUND_REVERSED", nil)
	e.db.Where("listing_id = ?", id).First(&p)
	if p.Status != models.PromotionActive {
		t.Fatalf("after reversal %s", p.Status)
	}
	// The same refund notification redelivered doesn't refund again.
	notify("n-1", "REFUND", map[string]any{"revocationDate": 1700000500000})
	e.db.Where("listing_id = ?", id).First(&p)
	if p.Status != models.PromotionActive {
		t.Fatalf("redelivered refund applied twice: %s", p.Status)
	}
	// Unsigned notification refused.
	c := apiClient{t: t, base: e.base}
	if st, _ := c.do("POST", "/api/promotions/webhooks/apple", map[string]any{"signedPayload": "a.b.c"}); st != http.StatusBadRequest {
		t.Fatalf("unsigned: %d", st)
	}
}

func TestPromotionOwnerRightsAndChannels(t *testing.T) {
	e := setupPromotions(t, nil, false) // no store credentials configured
	e.settings(true, 2500)
	owner := e.provider("Owner Six")
	id := e.listing(owner, "Rights", "Алматы", e.cat)
	stranger := registerUser(t, e.base, "Stranger", "stranger@six.test")

	if status, _ := stranger.do("GET", fmt.Sprintf("/api/promotions/listings/%d", id), nil); status != http.StatusForbidden {
		t.Fatalf("stranger reads stats: %d", status)
	}
	if status, out := stranger.do("POST", "/api/promotions/orders", map[string]any{"listing_id": id, "channel": "google"}); status != http.StatusForbidden {
		t.Fatalf("stranger buys: %d %v", status, out)
	}
	// A manager sees status/statistics but only the owner pays.
	manager := registerUser(t, e.base, "Manager", "manager@six.test")
	var mgr models.User
	e.db.Where("email = ?", "manager@six.test").First(&mgr)
	e.db.Create(&models.ListingManager{ListingID: id, UserID: mgr.ID, Role: models.ListingManagerRoleManager})
	status, out := manager.do("GET", fmt.Sprintf("/api/promotions/listings/%d", id), nil)
	if status != http.StatusOK || out["blocked_reason"] != "not_owner" {
		t.Fatalf("manager: %d %v", status, out)
	}
	if status, _ := e.admin.do("GET", fmt.Sprintf("/api/promotions/listings/%d", id), nil); status != http.StatusOK {
		t.Fatalf("admin: %d", status)
	}

	// No store credentials: purchases unavailable with a reason, nothing faked.
	status, out = owner.do("GET", fmt.Sprintf("/api/promotions/listings/%d", id), nil)
	ch := out["channels"].(map[string]any)
	if ch["google"].(map[string]any)["reason"] != "store_not_configured" || ch["apple"].(map[string]any)["reason"] != "store_not_configured" {
		t.Fatalf("channels: %v", ch)
	}
	for _, channel := range []string{"google", "apple", "web"} {
		status, out = owner.do("POST", "/api/promotions/orders", map[string]any{"listing_id": id, "channel": channel})
		if status != http.StatusServiceUnavailable {
			t.Fatalf("%s order without store: %d %v", channel, status, out)
		}
	}
	if status, out = owner.do("POST", "/api/promotions/purchases/google", map[string]any{"order_id": 1, "purchase_token": "x"}); status != http.StatusServiceUnavailable {
		t.Fatalf("confirm without store: %d %v", status, out)
	}
	// Admin settings are admin-only.
	if status, _ := owner.do("PUT", "/api/admin/promotions/settings", map[string]any{"enabled": true, "price_kzt": 1}); status != http.StatusForbidden {
		t.Fatalf("owner edits settings: %d", status)
	}
	if status, out := e.admin.do("PUT", "/api/admin/promotions/settings", map[string]any{"enabled": true, "price_kzt": 0}); status != http.StatusBadRequest {
		t.Fatalf("enabling without a price: %d %v", status, out)
	}
}

func TestPromotionModerationAndSwitches(t *testing.T) {
	e := setupPromotions(t, nil, true)
	e.settings(true, 2500)
	owner := e.provider("Owner Seven")
	var ids []uint
	for i := 0; i < 4; i++ {
		ids = append(ids, e.listing(owner, fmt.Sprintf("M%d", i), "Алматы", e.cat))
	}
	e.buyGoogle(owner, ids[0], "GPA.M")
	viewer := registerUser(t, e.base, "Viewer", "viewer@seven.test")
	if got := promotedIDs(e.feed(viewer, "category=hosts").items); len(got) != 1 {
		t.Fatalf("ad expected: %v", got)
	}

	// Hidden listing: out of ads (and of the catalog) at once.
	e.db.Model(&models.Listing{}).Where("id = ?", ids[0]).Update("is_active", false)
	if got := promotedIDs(e.feed(viewer, "category=hosts").items); len(got) != 0 {
		t.Fatalf("hidden listing advertised: %v", got)
	}
	e.db.Model(&models.Listing{}).Where("id = ?", ids[0]).Update("is_active", true)

	// Blocked provider: out of ads; the purchase is refused for new periods.
	e.db.Model(&models.Provider{}).Where("display_name = ?", "Owner Seven").Update("status", models.ProviderStatusSuspended)
	if got := promotedIDs(e.feed(viewer, "category=hosts").items); len(got) != 0 {
		t.Fatalf("suspended provider advertised: %v", got)
	}
	status, out := owner.do("POST", "/api/promotions/orders", map[string]any{"listing_id": ids[1], "channel": "google"})
	if status != http.StatusConflict || out["error"] != "provider_not_active" {
		t.Fatalf("order by suspended provider: %d %v", status, out)
	}
	e.db.Model(&models.Provider{}).Where("display_name = ?", "Owner Seven").Update("status", models.ProviderStatusActive)

	// Hidden listing can't be bought.
	e.db.Model(&models.Listing{}).Where("id = ?", ids[2]).Update("is_active", false)
	status, out = owner.do("POST", "/api/promotions/orders", map[string]any{"listing_id": ids[2], "channel": "google"})
	if status != http.StatusConflict || out["error"] != "listing_hidden" {
		t.Fatalf("order for hidden: %d %v", status, out)
	}

	// Admin switch off: ads and sales stop.
	e.settings(false, 2500)
	if got := promotedIDs(e.feed(viewer, "category=hosts").items); len(got) != 0 {
		t.Fatalf("ads with admin switch off: %v", got)
	}
	status, out = owner.do("POST", "/api/promotions/orders", map[string]any{"listing_id": ids[1], "channel": "google"})
	if status != http.StatusConflict || out["error"] != "promotions_disabled" {
		t.Fatalf("order with switch off: %d %v", status, out)
	}
}

func TestPromotionFeatureFlagOff(t *testing.T) {
	e := setupPromotions(t, func(c *config.Config) { c.PromotionsEnabled = false }, true)
	e.settings(true, 2500)
	owner := e.provider("Owner Eight")
	id := e.listing(owner, "Flag", "Алматы", e.cat)
	e.listing(owner, "Flag2", "Алматы", e.cat)
	// A promotion that exists in the DB (e.g. bought before the flag was turned off).
	e.db.Create(&models.Promotion{ListingID: id, OrderID: 999, UserID: 1, Channel: "google", ProductID: "promo_7d", TransactionKey: "google:x",
		Status: models.PromotionActive, StartsAt: e.clock.now().Add(-time.Hour), EndsAt: e.clock.now().Add(time.Hour)})
	if got := promotedIDs(e.feed(owner, "category=hosts").items); len(got) != 0 {
		t.Fatalf("ads with the flag off: %v", got)
	}
	status, out := owner.do("POST", "/api/promotions/orders", map[string]any{"listing_id": id, "channel": "google"})
	if status != http.StatusConflict || out["error"] != "promotions_disabled" {
		t.Fatalf("order with flag off: %d %v", status, out)
	}

	// The catalog itself keeps working with the flag off: every listing,
	// paged, newest first, each once, filters applied, no ads.
	for i := 0; i < 11; i++ {
		e.listing(owner, fmt.Sprintf("Off%02d", i), "Алматы", e.cat)
	}
	e.listing(owner, "Other city", "Астана", e.cat)
	e.listing(owner, "Other category", "Алматы", e.cat2)
	all := e.feedAll(owner, "category=hosts&city_id=1", 5)
	if len(all) != 13 {
		t.Fatalf("flag off: %d cards, want 13", len(all))
	}
	for i, it := range all {
		if it["promoted"] == true {
			t.Fatalf("ad with the flag off: %s", layoutOf(all))
		}
		if i > 0 && it["id"].(float64) > all[i-1]["id"].(float64) {
			t.Fatalf("order broken: %s", layoutOf(all))
		}
		if it["city"] != "Алматы" {
			t.Fatalf("city filter broken: %v", it)
		}
	}
	_, plain := owner.do("GET", "/api/listings?category=hosts&city_id=1", nil)
	if n := len(plain["listings"].([]any)); n != 13 {
		t.Fatalf("plain list with flag off: %d", n)
	}
}

func TestPromotionExpiresAfterSevenDays(t *testing.T) {
	e := setupPromotions(t, nil, true)
	e.settings(true, 2500)
	owner := e.provider("Owner Nine")
	id := e.listing(owner, "Exp", "Алматы", e.cat)
	e.listing(owner, "Exp2", "Алматы", e.cat)
	e.buyGoogle(owner, id, "GPA.E")
	viewer := registerUser(t, e.base, "Viewer", "viewer@nine.test")
	e.clock.add(7*24*time.Hour - time.Minute)
	if got := promotedIDs(e.feed(viewer, "category=hosts").items); len(got) != 1 {
		t.Fatalf("still running a minute before the end: %v", got)
	}
	e.clock.add(2 * time.Minute)
	if got := promotedIDs(e.feed(viewer, "category=hosts").items); len(got) != 0 {
		t.Fatalf("expired promotion advertised: %v", got)
	}
	_, out := owner.do("GET", fmt.Sprintf("/api/promotions/listings/%d", id), nil)
	if out["running"] != nil || out["can_purchase"] != true {
		t.Fatalf("after expiry: %v", out)
	}
	// No auto-renewal: nothing new was created.
	if e.countPromotions(id) != 1 {
		t.Fatal("auto-renewed")
	}
}

func TestPromotionFeedPlacementFiltersAndPagination(t *testing.T) {
	e := setupPromotions(t, nil, true)
	e.settings(true, 2500)
	a := e.provider("Adv A")
	b := e.provider("Adv B")
	var hosts []uint
	for i := 0; i < 20; i++ {
		owner := a
		if i%2 == 1 {
			owner = b
		}
		hosts = append(hosts, e.listing(owner, fmt.Sprintf("H%02d", i), "Алматы", e.cat))
	}
	astana := e.listing(a, "Astana host", "Астана", e.cat)
	show := e.listing(a, "Show", "Алматы", e.cat2)
	e.buyGoogle(a, hosts[2], "GPA.1")
	e.buyGoogle(a, hosts[4], "GPA.2")
	e.buyGoogle(b, hosts[5], "GPA.3")
	e.buyGoogle(a, astana, "GPA.4")
	e.buyGoogle(a, show, "GPA.5")

	viewer := registerUser(t, e.base, "Viewer", "viewer@feed.test")
	query := "category=hosts&city_id=1"

	full := e.feedAll(viewer, query, 100)
	if len(full) != 20 {
		t.Fatalf("Almaty hosts: %d cards, want 20 (no gaps, no extras)", len(full))
	}
	ads := promotedIDs(full)
	// Only the three Almaty host ads: not the Astana one, not the show.
	if len(ads) != 3 {
		t.Fatalf("ads %v in %s", ads, layoutOf(full))
	}
	for _, id := range ads {
		if uint(id) == astana || uint(id) == show {
			t.Fatalf("ad outside the filters: %d", id)
		}
	}
	// Positions: 2nd, then after every 6 regular cards.
	for i, it := range full {
		want := i == 1 || i == 8 || i == 15
		if (it["promoted"] == true) != want {
			t.Fatalf("ad positions wrong: %s", layoutOf(full))
		}
	}
	// Rotation: advertisers alternate (A, B, A) — one advertiser doesn't take every slot.
	owners := map[int]string{int(hosts[2]): "A", int(hosts[4]): "A", int(hosts[5]): "B"}
	if owners[ads[0]] == owners[ads[1]] {
		t.Fatalf("same advertiser in the first two slots: %v", ads)
	}
	// Each listing once; regular cards keep the newest-first order.
	seen := map[int]bool{}
	var regular []int
	for _, it := range full {
		id := int(it["id"].(float64))
		if seen[id] {
			t.Fatalf("listing %d twice: %s", id, layoutOf(full))
		}
		seen[id] = true
		if it["promoted"] != true {
			regular = append(regular, id)
		}
	}
	for i := 1; i < len(regular); i++ {
		if regular[i] > regular[i-1] {
			t.Fatalf("regular order broken: %v", regular)
		}
	}
	// Ads carry the label data; ratings untouched.
	for _, it := range full {
		if it["promoted"] == true && it["promotion_id"] == nil {
			t.Fatalf("ad without promotion id: %v", it)
		}
		if it["rating"].(float64) != 0 {
			t.Fatal("payment changed a rating")
		}
	}

	// Paged in fives: every card once, ads at the same positions, the same
	// ads and the same regular order. (Which of two equally-shown
	// advertisers goes first is decided per result on page one, so it may
	// differ from the unpaged request above.)
	for run := 0; run < 5; run++ {
		paged := e.feedAll(viewer, query, 5)
		if len(paged) != len(full) {
			t.Fatalf("paged %d cards, want %d", len(paged), len(full))
		}
		seenPaged := map[int]bool{}
		var pagedRegular []int
		for i, it := range paged {
			id := int(it["id"].(float64))
			if seenPaged[id] {
				t.Fatalf("listing %d repeated across pages: %s", id, layoutOf(paged))
			}
			seenPaged[id] = true
			if (it["promoted"] == true) != (full[i]["promoted"] == true) {
				t.Fatalf("ad positions differ:\n%s\n%s", layoutOf(paged), layoutOf(full))
			}
			if it["promoted"] != true {
				pagedRegular = append(pagedRegular, id)
			}
		}
		if fmt.Sprint(sortedInts(promotedIDs(paged))) != fmt.Sprint(sortedInts(ads)) {
			t.Fatalf("different ads: %v vs %v", promotedIDs(paged), ads)
		}
		if fmt.Sprint(pagedRegular) != fmt.Sprint(regular) {
			t.Fatalf("regular order differs:\n%v\n%v", pagedRegular, regular)
		}
	}
	// A cursor of another query or a forged one is refused.
	p := e.feed(viewer, query+"&limit=5")
	if bad := e.feed(viewer, "category=shows&limit=5&cursor="+p.next); bad.status != http.StatusBadRequest {
		t.Fatalf("cursor for another query: %d", bad.status)
	}
	if bad := e.feed(viewer, query+"&limit=5&cursor=abc.def"); bad.status != http.StatusBadRequest {
		t.Fatalf("forged cursor: %d", bad.status)
	}

	// Plain GET /api/listings is unchanged: no ad fields, same order.
	_, out := viewer.do("GET", "/api/listings?category=hosts&city_id=1", nil)
	plain := out["listings"].([]any)
	if len(plain) != 20 {
		t.Fatalf("plain list %d", len(plain))
	}
	if _, has := plain[0].(map[string]any)["promoted"]; has {
		t.Fatal("plain list must not change shape")
	}

	// No ads that match: regular result only.
	none := e.feedAll(viewer, "category=shows&city_id=2", 100)
	if len(none) != 0 {
		t.Fatalf("shows in Astana: %v", none)
	}
}

func TestPromotionRotationByImpressions(t *testing.T) {
	e := setupPromotions(t, nil, true)
	e.settings(true, 2500)
	a := e.provider("Rot A")
	b := e.provider("Rot B")
	var ids []uint
	for i := 0; i < 10; i++ {
		owner := a
		if i >= 5 {
			owner = b
		}
		ids = append(ids, e.listing(owner, fmt.Sprintf("R%d", i), "Алматы", e.cat))
	}
	e.buyGoogle(a, ids[0], "GPA.RA")
	e.buyGoogle(b, ids[9], "GPA.RB")
	var pa, pb models.Promotion
	e.db.Where("listing_id = ?", ids[0]).First(&pa)
	e.db.Where("listing_id = ?", ids[9]).First(&pb)
	e.db.Create(&models.PromotionStat{PromotionID: pa.ID, Kind: models.PromotionEventImpression, Count: 1000})
	e.db.Create(&models.PromotionStat{PromotionID: pb.ID, Kind: models.PromotionEventImpression, Count: 3})
	viewer := registerUser(t, e.base, "Viewer", "viewer@rot.test")
	for i := 0; i < 5; i++ {
		ads := promotedIDs(e.feedAll(viewer, "category=hosts", 100))
		if len(ads) != 2 || uint(ads[0]) != ids[9] {
			t.Fatalf("least-shown advertiser must lead: %v", ads)
		}
	}
	// Equal counts: both advertisers get the first slot over many requests.
	e.db.Model(&models.PromotionStat{}).Where("promotion_id = ?", pa.ID).Update("count", 3)
	first := map[int]bool{}
	for i := 0; i < 40; i++ {
		first[promotedIDs(e.feedAll(viewer, "category=hosts", 100))[0]] = true
	}
	if len(first) != 2 {
		t.Fatalf("equal advertisers must share the first slot: %v", first)
	}
}

func TestPromotionStatisticsCountRealViewsOnly(t *testing.T) {
	e := setupPromotions(t, nil, true)
	e.settings(true, 2500)
	owner := e.provider("Stats Owner")
	id := e.listing(owner, "Stats", "Алматы", e.cat)
	e.listing(owner, "Other", "Алматы", e.cat)
	e.buyGoogle(owner, id, "GPA.S")
	var p models.Promotion
	e.db.Where("listing_id = ?", id).First(&p)
	viewer := registerUser(t, e.base, "Viewer", "viewer@stats.test")
	viewer2 := registerUser(t, e.base, "Viewer Two", "viewer2@stats.test")

	send := func(c apiClient, kind string) any {
		_, out := c.do("POST", "/api/promotions/events", map[string]any{"promotion_id": p.ID, "kind": kind})
		return out["counted"]
	}
	if send(viewer, "impression") != true || send(viewer, "impression") != false {
		t.Fatal("repeat impression within the window must not count")
	}
	if send(viewer2, "impression") != true {
		t.Fatal("second viewer counts")
	}
	if send(owner, "impression") != false || send(owner, "click") != false {
		t.Fatal("owner's own views must not count")
	}
	for _, kind := range []string{"click", "chat", "call", "whatsapp"} {
		if send(viewer, kind) != true {
			t.Fatalf("%s not counted", kind)
		}
	}
	e.clock.add(31 * time.Minute)
	if send(viewer, "impression") != true {
		t.Fatal("after the window the viewer counts again")
	}
	if status, _ := viewer.do("POST", "/api/promotions/events", map[string]any{"promotion_id": p.ID, "kind": "order"}); status != http.StatusBadRequest {
		t.Fatalf("unknown kind: %d", status)
	}

	_, out := owner.do("GET", fmt.Sprintf("/api/promotions/listings/%d", id), nil)
	stats := out["running"].(map[string]any)["stats"].(map[string]any)
	want := map[string]float64{"impressions": 3, "clicks": 1, "chats": 1, "calls": 1, "whatsapp": 1}
	for k, v := range want {
		if stats[k].(float64) != v {
			t.Fatalf("stats %v, want %v", stats, want)
		}
	}
	if _, has := stats["orders"]; has {
		t.Fatal("taps must not be reported as orders")
	}
}
