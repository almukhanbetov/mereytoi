package recoverycode

import (
	"os"
	"sync"
	"testing"
	"time"

	"golang.org/x/crypto/bcrypt"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// Two recoveries with the same code that both get past the account lookup
// before either writes — the worst interleaving — must still succeed only
// once. Needs a real, disposable Postgres (the test drops its tables):
//
//	MEREYTOI_TEST_POSTGRES_DSN="host=... dbname=... sslmode=disable" go test ./internal/recoverycode -run Interleaved
func TestInterleavedRecoveryRedeemsOnce(t *testing.T) {
	dsn := os.Getenv("MEREYTOI_TEST_POSTGRES_DSN")
	if dsn == "" {
		t.Skip("MEREYTOI_TEST_POSTGRES_DSN not set")
	}
	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.Migrator().DropTable(&models.RecoveryAttempt{}, &models.User{}); err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(&models.User{}, &models.RecoveryAttempt{}); err != nil {
		t.Fatal(err)
	}
	code, hash, _ := NewCode()
	pw, _ := bcrypt.GenerateFromPassword([]byte("oldpass1"), bcrypt.MinCost)
	u := models.User{Name: "I", Email: "i@test.local", PasswordHash: string(pw), Role: "user",
		Status: models.UserStatusActive, RecoveryCodeHash: hash}
	if err := db.Create(&u).Error; err != nil {
		t.Fatal(err)
	}

	svc := New(db)
	var arrived sync.WaitGroup
	arrived.Add(2)
	svc.afterLookup = func() {
		arrived.Done()
		done := make(chan struct{})
		go func() { arrived.Wait(); close(done) }()
		select {
		case <-done:
		case <-time.After(5 * time.Second):
			t.Error("the two requests never met after the lookup")
		}
	}

	var wg sync.WaitGroup
	results := make([]error, 2)
	for i := range results {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			_, results[i] = svc.Recover(Identifier{Email: "i@test.local"}, code, "NewPass12"+string(rune('0'+i)), "192.0.2.1")
		}(i)
	}
	wg.Wait()
	ok := 0
	for _, err := range results {
		if err == nil {
			ok++
		} else if err != ErrInvalid {
			t.Fatalf("unexpected error: %v", err)
		}
	}
	if ok != 1 {
		t.Fatalf("%d of 2 interleaved recoveries succeeded: %v", ok, results)
	}
}
