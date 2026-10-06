// Package ratelimit counts events per key over a sliding time window.
//
// Handlers depend only on the Limiter interface; Memory is the in-process
// implementation, which is enough while the backend runs as a single
// instance (a restart simply forgets the counts). A shared store (Redis)
// can implement the same interface later without touching any handler.
package ratelimit

import (
	"sync"
	"time"
)

// Limiter allows at most a fixed number of events per key per window.
type Limiter interface {
	// Allow records one event for key if the key is still under its limit,
	// and reports whether it was.
	Allow(key string) bool
	// Blocked reports whether key has already used up its limit, without
	// recording anything — for "count only the failures" checks.
	Blocked(key string) bool
}

// Memory is an in-process sliding-window Limiter, safe for concurrent use.
type Memory struct {
	limit  int
	window time.Duration
	now    func() time.Time

	mu        sync.Mutex
	events    map[string][]time.Time
	lastSweep time.Time
}

// NewMemory allows limit events per key in any window-long period.
func NewMemory(limit int, window time.Duration) *Memory {
	return &Memory{limit: limit, window: window, now: time.Now, events: map[string][]time.Time{}}
}

// WithClock replaces the clock (tests only).
func (m *Memory) WithClock(now func() time.Time) *Memory {
	m.now = now
	return m
}

func (m *Memory) Allow(key string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	now := m.now()
	m.sweep(now)
	recent := m.recent(key, now)
	if len(recent) >= m.limit {
		return false
	}
	m.events[key] = append(recent, now)
	return true
}

func (m *Memory) Blocked(key string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	return len(m.recent(key, m.now())) >= m.limit
}

// recent drops key's events that have left the window, stores what's left
// and returns it. Callers hold mu.
func (m *Memory) recent(key string, now time.Time) []time.Time {
	cutoff := now.Add(-m.window)
	kept := m.events[key][:0]
	for _, t := range m.events[key] {
		if t.After(cutoff) {
			kept = append(kept, t)
		}
	}
	if len(kept) == 0 {
		delete(m.events, key)
		return nil
	}
	m.events[key] = kept
	return kept
}

// sweep drops keys with no events left in the window, at most once per
// window, so memory stays bounded by recent traffic. Callers hold mu.
func (m *Memory) sweep(now time.Time) {
	if now.Sub(m.lastSweep) < m.window {
		return
	}
	m.lastSweep = now
	for key := range m.events {
		m.recent(key, now)
	}
}
