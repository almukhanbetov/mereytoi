package ratelimit

import (
	"sync"
	"testing"
	"time"
)

type clock struct{ t time.Time }

func (c *clock) now() time.Time { return c.t }

func TestMemoryAllowsUpToLimitPerKey(t *testing.T) {
	c := &clock{t: time.Unix(1_000_000, 0)}
	m := NewMemory(3, time.Minute).WithClock(c.now)
	for i := 0; i < 3; i++ {
		if !m.Allow("a") {
			t.Fatalf("event %d should be allowed", i+1)
		}
	}
	if m.Allow("a") {
		t.Fatal("4th event within the window must be refused")
	}
	if !m.Allow("b") {
		t.Fatal("another key has its own budget")
	}
}

func TestMemoryWindowSlides(t *testing.T) {
	c := &clock{t: time.Unix(1_000_000, 0)}
	m := NewMemory(2, time.Minute).WithClock(c.now)
	m.Allow("a")
	c.t = c.t.Add(30 * time.Second)
	m.Allow("a")
	if m.Allow("a") {
		t.Fatal("still 2 events in the last minute")
	}
	c.t = c.t.Add(31 * time.Second) // the first event has left the window
	if !m.Allow("a") {
		t.Fatal("one slot should have freed up")
	}
}

func TestMemoryBlockedDoesNotRecord(t *testing.T) {
	m := NewMemory(1, time.Minute)
	for i := 0; i < 5; i++ {
		if m.Blocked("a") {
			t.Fatal("checking must not consume the budget")
		}
	}
	m.Allow("a")
	if !m.Blocked("a") {
		t.Fatal("limit reached")
	}
}

func TestMemoryConcurrentAllowNeverExceedsLimit(t *testing.T) {
	m := NewMemory(10, time.Minute)
	var wg sync.WaitGroup
	var mu sync.Mutex
	allowed := 0
	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if m.Allow("k") {
				mu.Lock()
				allowed++
				mu.Unlock()
			}
		}()
	}
	wg.Wait()
	if allowed != 10 {
		t.Fatalf("allowed %d, want exactly 10", allowed)
	}
}

func TestMemorySweepsIdleKeys(t *testing.T) {
	c := &clock{t: time.Unix(1_000_000, 0)}
	m := NewMemory(1, time.Minute).WithClock(c.now)
	m.Allow("old")
	c.t = c.t.Add(2 * time.Minute)
	m.Allow("new")
	m.mu.Lock()
	_, stillThere := m.events["old"]
	m.mu.Unlock()
	if stillThere {
		t.Fatal("an idle key should be swept")
	}
}
