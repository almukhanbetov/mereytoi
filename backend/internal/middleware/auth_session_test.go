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
	validator := func(userID uint, iat int64) bool { return iat >= changedAt.Unix() }
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
	r := engine(func(uint, int64) bool { return false })
	rec := get(r, "/opt", token(t, time.Now()))
	if rec.Code != http.StatusOK || rec.Body.String() != "guest" {
		t.Fatalf("got %d %q, want 200 guest", rec.Code, rec.Body)
	}
	ok := engine(func(uint, int64) bool { return true })
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
