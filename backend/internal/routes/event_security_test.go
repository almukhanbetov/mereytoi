package routes_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/config"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
	"github.com/almukhanbetov/mereytoi/backend/internal/routes"
)

// This exercises the "Мой той" workspace end to end over real HTTP, through
// the exact same route tree production uses (routes.Register) — the goal is
// confidence in the permission rules from the brief's section 22
// ("server-side authorization, not just hiding buttons"), not just that the
// handlers compile.

func setupTestServer(t *testing.T) (*httptest.Server, *gorm.DB) {
	t.Helper()
	gin.SetMode(gin.TestMode)

	db, err := gorm.Open(sqlite.Open("file::memory:?cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatalf("failed to open in-memory db: %v", err)
	}
	if err := db.AutoMigrate(
		&models.User{}, &models.Category{}, &models.Listing{}, &models.Booking{}, &models.Comment{}, &models.Client{}, &models.SiteStatistics{},
		&models.Event{}, &models.EventMember{}, &models.EventInvitation{},
		&models.EventCandidate{}, &models.EventVote{}, &models.EventComment{},
		&models.EventActivity{}, &models.EventTask{},
		&models.EventRequest{}, &models.EventRequestRevision{},
	); err != nil {
		t.Fatalf("failed to migrate: %v", err)
	}

	r := gin.New()
	r.Use(cors.Default())
	cfg := config.Config{JWTSecret: "test-secret-only"}
	routes.Register(r, db, cfg)

	srv := httptest.NewServer(r)
	t.Cleanup(srv.Close)
	return srv, db
}

type apiClient struct {
	t     *testing.T
	base  string
	token string
}

func (c apiClient) do(method, path string, body any) (int, map[string]any) {
	c.t.Helper()
	var reader *bytes.Reader
	if body != nil {
		data, _ := json.Marshal(body)
		reader = bytes.NewReader(data)
	} else {
		reader = bytes.NewReader(nil)
	}
	req, err := http.NewRequest(method, c.base+path, reader)
	if err != nil {
		c.t.Fatalf("build request: %v", err)
	}
	req.Header.Set("Content-Type", "application/json")
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		c.t.Fatalf("do request: %v", err)
	}
	defer res.Body.Close()
	var out map[string]any
	_ = json.NewDecoder(res.Body).Decode(&out)
	return res.StatusCode, out
}

func registerUser(t *testing.T, base, name, email string) apiClient {
	t.Helper()
	c := apiClient{t: t, base: base}
	status, out := c.do("POST", "/api/auth/register", map[string]any{
		"name": name, "email": email, "phone": "", "password": "password123",
	})
	if status != http.StatusCreated {
		t.Fatalf("register %s failed: %d %v", email, status, out)
	}
	c.token, _ = out["token"].(string)
	return c
}

// registerAdmin registers a normal user then promotes them directly in the
// DB (there's no public admin-signup endpoint, matching production, where
// the first admin is always created out-of-band) and re-logs-in so the
// returned client's token actually carries role=admin.
func registerAdmin(t *testing.T, base string, db *gorm.DB, name, email string) apiClient {
	t.Helper()
	c := registerUser(t, base, name, email)
	if err := db.Model(&models.User{}).Where("email = ?", email).Update("role", "admin").Error; err != nil {
		t.Fatalf("promote to admin: %v", err)
	}
	status, out := c.do("POST", "/api/auth/login", map[string]any{"email": email, "password": "password123"})
	if status != http.StatusOK {
		t.Fatalf("admin re-login failed: %d %v", status, out)
	}
	c.token, _ = out["token"].(string)
	return c
}

func seedListing(t *testing.T, db *gorm.DB, name string, price uint) models.Listing {
	t.Helper()
	category := models.Category{Slug: name + "-cat", NameRu: name, NameKz: name}
	if err := db.Create(&category).Error; err != nil {
		t.Fatalf("seed category: %v", err)
	}
	listing := models.Listing{CategoryID: category.ID, NameRu: name, NameKz: name, Price: price, IsActive: true}
	if err := db.Create(&listing).Error; err != nil {
		t.Fatalf("seed listing: %v", err)
	}
	return listing
}

// TestFullCollaborativeFlow walks through the acceptance scenario from the
// brief's section 25, points 1-16: two users share one event, add/vote/
// comment on a candidate, one is selected, budget reacts, a task is created
// and completed by the other member.
func TestFullCollaborativeFlow(t *testing.T) {
	srv, db := setupTestServer(t)
	base := srv.URL

	owner := registerUser(t, base, "Мухтар", "mukhtar@example.com")
	guest := registerUser(t, base, "Айжан", "aizhan@example.com")

	status, out := owner.do("POST", "/api/events", map[string]any{
		"title": "Свадьба Мухтара и Айжан", "type": "wedding", "city": "Алматы", "guests": 150, "budget_total": 3000000,
	})
	if status != http.StatusCreated {
		t.Fatalf("create event: %d %v", status, out)
	}
	event := out["event"].(map[string]any)
	eventID := int(event["id"].(float64))
	eventPath := func(p string) string { return "/api/events/" + itoa(eventID) + p }

	// Owner invites, guest accepts.
	status, out = owner.do("POST", eventPath("/invitations"), map[string]any{"role": "editor"})
	if status != http.StatusCreated {
		t.Fatalf("create invitation: %d %v", status, out)
	}
	token := out["invitation"].(map[string]any)["token"].(string)

	status, out = guest.do("POST", "/api/invitations/"+token+"/accept", nil)
	if status != http.StatusOK {
		t.Fatalf("accept invitation: %d %v", status, out)
	}
	if out["role"] != "editor" {
		t.Fatalf("expected editor role, got %v", out["role"])
	}

	// Both see the same event.
	if status, _ := guest.do("GET", eventPath(""), nil); status != http.StatusOK {
		t.Fatalf("guest should see the shared event, got %d", status)
	}

	listing := seedListing(t, db, "AURORA QUINTET", 170000)

	status, out = owner.do("POST", eventPath("/candidates"), map[string]any{"listing_id": listing.ID})
	if status != http.StatusCreated {
		t.Fatalf("add candidate: %d %v", status, out)
	}
	candidate := out["candidate"].(map[string]any)
	candID := int(candidate["id"].(float64))
	candPath := eventPath("/candidates/" + itoa(candID))

	// Guest sees the candidate the owner added.
	status, out = guest.do("GET", eventPath("/candidates"), nil)
	if status != http.StatusOK || len(out["candidates"].([]any)) != 1 {
		t.Fatalf("guest should see 1 candidate: %d %v", status, out)
	}

	// Guest votes; owner sees the vote.
	if status, _ := guest.do("POST", candPath+"/vote", map[string]any{"value": "up"}); status != http.StatusOK {
		t.Fatalf("vote failed: %d", status)
	}
	status, out = owner.do("GET", eventPath("/candidates"), nil)
	cands := out["candidates"].([]any)
	votes := cands[0].(map[string]any)["votes"].(map[string]any)
	if votes["up"].(float64) != 1 {
		t.Fatalf("expected 1 up-vote visible to owner, got %v", votes)
	}

	// Guest comments; owner sees it.
	if status, _ := guest.do("POST", eventPath("/comments"), map[string]any{"body": "Мне нравится стиль", "candidate_id": candID}); status != http.StatusCreated {
		t.Fatalf("comment failed: %d", status)
	}
	status, out = owner.do("GET", eventPath("/comments")+"?candidate_id="+itoa(candID), nil)
	if status != http.StatusOK || len(out["comments"].([]any)) != 1 {
		t.Fatalf("owner should see the comment: %d %v", status, out)
	}

	// Owner selects the candidate — budget should reflect it.
	if status, _ := owner.do("PUT", candPath, map[string]any{"status": "selected"}); status != http.StatusOK {
		t.Fatalf("select candidate failed: %d", status)
	}
	status, out = owner.do("GET", eventPath("/summary"), nil)
	if status != http.StatusOK || out["spent"].(float64) != 170000 {
		t.Fatalf("budget should show 170000 spent: %d %v", status, out)
	}

	// Guest (editor) creates a task; owner marks it done.
	status, out = guest.do("POST", eventPath("/tasks"), map[string]any{"title": "Позвонить ресторану"})
	if status != http.StatusCreated {
		t.Fatalf("create task: %d %v", status, out)
	}
	taskID := int(out["task"].(map[string]any)["id"].(float64))
	if status, _ := owner.do("PUT", eventPath("/tasks/"+itoa(taskID)), map[string]any{"status": "done"}); status != http.StatusOK {
		t.Fatalf("complete task: %d", status)
	}

	// Activity feed recorded the story.
	status, out = owner.do("GET", eventPath("/activity"), nil)
	if status != http.StatusOK {
		t.Fatalf("activity feed: %d", status)
	}
	activity := out["activity"].([]any)
	if len(activity) < 6 {
		t.Fatalf("expected several activity entries (created/joined/added/voted/commented/selected/task), got %d: %v", len(activity), activity)
	}
}

// TestOutsiderCannotAccessEventByGuessingID is the brief's section 22/25
// point 19 in isolation: a user who was never invited must not be able to
// reach the event by ID — and the response must not even confirm it exists.
func TestOutsiderCannotAccessEventByGuessingID(t *testing.T) {
	srv, _ := setupTestServer(t)
	base := srv.URL

	owner := registerUser(t, base, "Мухтар", "owner2@example.com")
	outsider := registerUser(t, base, "Чужой", "outsider@example.com")

	status, out := owner.do("POST", "/api/events", map[string]any{"title": "Приватное мероприятие", "type": "wedding"})
	if status != http.StatusCreated {
		t.Fatalf("create event: %d %v", status, out)
	}
	eventID := int(out["event"].(map[string]any)["id"].(float64))

	status, _ = outsider.do("GET", "/api/events/"+itoa(eventID), nil)
	if status != http.StatusNotFound {
		t.Fatalf("outsider should get 404 (not 403 — must not confirm existence), got %d", status)
	}

	status, _ = outsider.do("POST", "/api/events/"+itoa(eventID)+"/candidates", map[string]any{"listing_id": 1})
	if status != http.StatusNotFound {
		t.Fatalf("outsider should not be able to add candidates either, got %d", status)
	}
}

// TestViewerCannotEditButCanVote checks the one asymmetric rule in the
// permission matrix: a Наблюдатель can vote but cannot shortlist, comment,
// or change event details.
func TestViewerCannotEditButCanVote(t *testing.T) {
	srv, db := setupTestServer(t)
	base := srv.URL

	owner := registerUser(t, base, "Мухтар", "owner3@example.com")
	viewer := registerUser(t, base, "Мама", "viewer@example.com")

	status, out := owner.do("POST", "/api/events", map[string]any{"title": "Той", "type": "toi"})
	if status != http.StatusCreated {
		t.Fatalf("create event: %d %v", status, out)
	}
	eventID := int(out["event"].(map[string]any)["id"].(float64))
	eventPath := func(p string) string { return "/api/events/" + itoa(eventID) + p }

	status, out = owner.do("POST", eventPath("/invitations"), map[string]any{"role": "viewer"})
	if status != http.StatusCreated {
		t.Fatalf("invite: %d %v", status, out)
	}
	token := out["invitation"].(map[string]any)["token"].(string)
	if status, _ = viewer.do("POST", "/api/invitations/"+token+"/accept", nil); status != http.StatusOK {
		t.Fatalf("accept: %d", status)
	}

	listing := seedListing(t, db, "Ведущий Х", 100000)
	status, out = owner.do("POST", eventPath("/candidates"), map[string]any{"listing_id": listing.ID})
	if status != http.StatusCreated {
		t.Fatalf("owner add candidate: %d %v", status, out)
	}
	candID := int(out["candidate"].(map[string]any)["id"].(float64))
	candPath := eventPath("/candidates/" + itoa(candID))

	// Viewer CAN vote.
	if status, out := viewer.do("POST", candPath+"/vote", map[string]any{"value": "up"}); status != http.StatusOK {
		t.Fatalf("viewer should be able to vote, got %d %v", status, out)
	}

	// Viewer CANNOT add a candidate, comment, or edit the event.
	if status, _ := viewer.do("POST", eventPath("/candidates"), map[string]any{"listing_id": listing.ID}); status != http.StatusForbidden {
		t.Fatalf("viewer should not be able to add candidates, got %d", status)
	}
	if status, _ := viewer.do("POST", eventPath("/comments"), map[string]any{"body": "hi"}); status != http.StatusForbidden {
		t.Fatalf("viewer should not be able to comment, got %d", status)
	}
	if status, _ := viewer.do("PUT", eventPath(""), map[string]any{"title": "Hacked", "type": "toi"}); status != http.StatusForbidden {
		t.Fatalf("viewer should not be able to edit the event, got %d", status)
	}
	if status, _ := viewer.do("POST", eventPath("/invitations"), map[string]any{"role": "editor"}); status != http.StatusForbidden {
		t.Fatalf("viewer should not be able to invite, got %d", status)
	}
}

// TestVoteIsUpsertNotDuplicate ensures a member can change their vote but
// never accumulates two rows for the same candidate.
func TestVoteIsUpsertNotDuplicate(t *testing.T) {
	srv, db := setupTestServer(t)
	base := srv.URL
	owner := registerUser(t, base, "Мухтар", "owner4@example.com")

	status, out := owner.do("POST", "/api/events", map[string]any{"title": "Той", "type": "toi"})
	if status != http.StatusCreated {
		t.Fatalf("create event: %d %v", status, out)
	}
	eventID := int(out["event"].(map[string]any)["id"].(float64))
	listing := seedListing(t, db, "Декор Y", 50000)
	status, out = owner.do("POST", "/api/events/"+itoa(eventID)+"/candidates", map[string]any{"listing_id": listing.ID})
	candID := int(out["candidate"].(map[string]any)["id"].(float64))
	votePath := "/api/events/" + itoa(eventID) + "/candidates/" + itoa(candID) + "/vote"

	owner.do("POST", votePath, map[string]any{"value": "up"})
	owner.do("POST", votePath, map[string]any{"value": "down"}) // changed their mind

	var count int64
	db.Model(&models.EventVote{}).Where("candidate_id = ?", candID).Count(&count)
	if count != 1 {
		t.Fatalf("expected exactly 1 vote row after changing vote twice, got %d", count)
	}
	var vote models.EventVote
	db.Where("candidate_id = ?", candID).First(&vote)
	if vote.Value != "down" {
		t.Fatalf("expected the vote to reflect the latest choice 'down', got %q", vote.Value)
	}
}

// TestOwnerCannotBeRemovedOrDemoted covers the brief's "owner can change
// roles / remove members" while never allowing the owner to be locked out
// of their own event.
func TestOwnerCannotBeRemovedOrDemoted(t *testing.T) {
	srv, _ := setupTestServer(t)
	base := srv.URL
	owner := registerUser(t, base, "Мухтар", "owner5@example.com")

	status, out := owner.do("POST", "/api/events", map[string]any{"title": "Той", "type": "toi"})
	if status != http.StatusCreated {
		t.Fatalf("create event: %d %v", status, out)
	}
	eventID := int(out["event"].(map[string]any)["id"].(float64))
	ownerID := int(out["event"].(map[string]any)["owner_id"].(float64))
	base2 := "/api/events/" + itoa(eventID) + "/members/" + itoa(ownerID)

	if status, _ := owner.do("PUT", base2, map[string]any{"role": "viewer"}); status != http.StatusForbidden {
		t.Fatalf("should not be able to demote the owner, got %d", status)
	}
	if status, _ := owner.do("DELETE", base2, nil); status != http.StatusForbidden {
		t.Fatalf("should not be able to remove the owner, got %d", status)
	}
}

func itoa(n int) string {
	return strconv.Itoa(n)
}
