package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

const testSecret = "test-secret"

func token(t *testing.T, iat time.Time) string {
	t.Helper()
	s, err := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub": 7, "role": "user", "iat": iat.Unix(), "exp": time.Now().Add(time.Hour).Unix(),
	}).SignedString([]byte(testSecret))
	if err != nil {
		t.Fatal(err)
	}
	return s
}

// engine serves /req (RequireAuth) and /opt (OptionalAuth); /opt answers
// "user" or "guest". validator nil installs none.
func engine(validator SessionValidator) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	g := r.Group("")
	if validator != nil {
		g.Use(WithSessionValidator(validator))
	}
	g.GET("/req", RequireAuth(testSecret), func(c *gin.Context) { c.String(200, "ok") })
	g.GET("/opt", OptionalAuth(testSecret), func(c *gin.Context) {
		if _, ok := c.Get(ContextUserIDKey); ok {
			c.String(200, "user")
			return
		}
		c.String(200, "guest")
	})
	return r
}

func get(r *gin.Engine, path, tok string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, path, nil)
	req.Header.Set("Authorization", "Bearer "+tok)
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)
	return rec
}

func TestRequireAuthRejectsRetiredSession(t *testing.T) {
	changedAt := time.Now().Truncate(time.Second)
	validator := func(userID uint, iat int64) Session {
		if iat >= changedAt.Unix() {
			return Session{Valid: true, Role: "user"}
		}
		return Session{Error: "session_expired"}
	}
	r := engine(validator)

	old := get(r, "/req", token(t, changedAt.Add(-time.Minute)))
	if old.Code != http.StatusUnauthorized || old.Body.String() != `{"error":"session_expired"}` {
		t.Fatalf("old token: %d %s", old.Code, old.Body)
	}
	// Minted in the very second of the change — the token the change
	// itself hands back — must still work.
	if rec := get(r, "/req", token(t, changedAt)); rec.Code != http.StatusOK {
		t.Fatalf("same-second token: %d", rec.Code)
	}
	if rec := get(r, "/req", token(t, changedAt.Add(time.Second))); rec.Code != http.StatusOK {
		t.Fatalf("newer token: %d", rec.Code)
	}
}

func TestOptionalAuthTreatsRetiredSessionAsGuest(t *testing.T) {
	r := engine(func(uint, int64) Session { return Session{Error: "session_expired"} })
	rec := get(r, "/opt", token(t, time.Now()))
	if rec.Code != http.StatusOK || rec.Body.String() != "guest" {
		t.Fatalf("got %d %q, want 200 guest", rec.Code, rec.Body)
	}
	ok := engine(func(uint, int64) Session { return Session{Valid: true, Role: "user"} })
	if rec := get(ok, "/opt", token(t, time.Now())); rec.Body.String() != "user" {
		t.Fatalf("valid session should be a user, got %q", rec.Body)
	}
}

func TestNoValidatorKeepsSignatureOnlyBehaviour(t *testing.T) {
	r := engine(nil)
	if rec := get(r, "/req", token(t, time.Now().Add(-48*time.Hour))); rec.Code != http.StatusOK {
		t.Fatalf("got %d", rec.Code)
	}
}

// The role is the validator's (read from the database), not the token's:
// a "user" token passes RequireAdmin once the account is admin, and an
// admin token stops passing once it isn't.
func TestRoleComesFromValidatorNotToken(t *testing.T) {
	for _, tc := range []struct {
		dbRole string
		want   int
	}{{"admin", http.StatusOK}, {"user", http.StatusForbidden}} {
		gin.SetMode(gin.TestMode)
		r := gin.New()
		g := r.Group("")
		g.Use(WithSessionValidator(func(uint, int64) Session { return Session{Valid: true, Role: tc.dbRole} }))
		g.GET("/admin", RequireAuth(testSecret), RequireAdmin(), func(c *gin.Context) { c.String(200, "ok") })
		if rec := get(r, "/admin", token(t, time.Now())); rec.Code != tc.want {
			t.Fatalf("db role %s: got %d want %d", tc.dbRole, rec.Code, tc.want)
		}
	}
}

func TestBlockedSessionIsRejectedWithItsTerm(t *testing.T) {
	until := time.Date(2026, 12, 1, 0, 0, 0, 0, time.UTC)
	r := engine(func(uint, int64) Session {
		return Session{Error: "account_blocked", BlockedUntil: &until, BlockReason: "Спам"}
	})
	rec := get(r, "/req", token(t, time.Now()))
	if rec.Code != http.StatusUnauthorized || rec.Body.String() != `{"blocked_until":"2026-12-01T00:00:00Z","error":"account_blocked","reason":"Спам"}` {
		t.Fatalf("got %d %s", rec.Code, rec.Body)
	}
	if rec := get(r, "/opt", token(t, time.Now())); rec.Body.String() != "guest" {
		t.Fatalf("blocked token on optional auth: %q", rec.Body)
	}
}
