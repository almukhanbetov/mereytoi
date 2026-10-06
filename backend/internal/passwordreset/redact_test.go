package passwordreset

import (
	"bytes"
	"log"
	"strings"
	"testing"
	"time"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

func TestRedactedDBHidesQueryValues(t *testing.T) {
	var out bytes.Buffer
	orig := log.Writer()
	log.SetOutput(&out)
	t.Cleanup(func() { log.SetOutput(orig) })

	// The app's own logger setup (internal/db): Warn level, values shown.
	plain, err := gorm.Open(sqlite.Open("file:redact?mode=memory&cache=shared"), &gorm.Config{
		Logger: logger.New(log.Default(), logger.Config{SlowThreshold: 200 * time.Millisecond, LogLevel: logger.Warn}),
	})
	if err != nil {
		t.Fatal(err)
	}
	const phone, hash = "+77009998877", "$2a$10$secretbcrypthashvalue"
	failing := func(db *gorm.DB) {
		db.Exec("UPDATE no_such_table SET password_hash = ? WHERE phone_normalized = ?", hash, phone)
	}

	failing(plain)
	if !strings.Contains(out.String(), phone) {
		t.Fatalf("expected the default logger to leak values (the reason for RedactedDB):\n%s", out.String())
	}

	out.Reset()
	failing(RedactedDB(plain))
	logged := out.String()
	if !strings.Contains(logged, "no_such_table") {
		t.Fatalf("the failure itself should still be logged:\n%s", logged)
	}
	for _, secret := range []string{phone, hash} {
		if strings.Contains(logged, secret) {
			t.Errorf("redacted log contains %q:\n%s", secret, logged)
		}
	}
}
