// Package rates collects exchange rates from Korea Eximbank and serves the
// most recent business day's snapshot.
package rates

import (
	"context"
	"sync"
	"time"
)

// Rate is one currency's rate normalized to KRW per 1 unit.
type Rate struct {
	KRWPerUnit float64 `json:"krw_per_unit"`
	Raw        string  `json:"raw"`
	Unit       int     `json:"unit"`
}

// Snapshot is the set of rates published for one business day.
type Snapshot struct {
	BaseDate  time.Time       // calendar date in KST, time component is zero
	FetchedAt time.Time       // when the server fetched it
	Source    string          // e.g. "koreaexim"
	Rates     map[string]Rate // keyed by currency code
}

// Store persists snapshots.
type Store interface {
	// Save stores a snapshot, replacing any existing one for the same date.
	Save(ctx context.Context, s Snapshot) error
	// Latest returns the snapshot with the most recent BaseDate.
	Latest(ctx context.Context) (Snapshot, bool, error)
	// Ping reports whether the store is reachable.
	Ping(ctx context.Context) error
	// RecordRun logs a collector run for operational tracking.
	RecordRun(ctx context.Context, status, message string) error
}

// MemoryStore is an in-process Store for local development and tests.
type MemoryStore struct {
	mu     sync.RWMutex
	byDate map[string]Snapshot
	latest string
	Runs   []string
}

// NewMemoryStore returns an empty MemoryStore.
func NewMemoryStore() *MemoryStore {
	return &MemoryStore{byDate: map[string]Snapshot{}}
}

func (m *MemoryStore) Save(_ context.Context, s Snapshot) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	key := s.BaseDate.Format(time.DateOnly)
	m.byDate[key] = s
	if key > m.latest {
		m.latest = key
	}
	return nil
}

func (m *MemoryStore) Latest(_ context.Context) (Snapshot, bool, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	s, ok := m.byDate[m.latest]
	return s, ok, nil
}

func (m *MemoryStore) Ping(context.Context) error { return nil }

func (m *MemoryStore) RecordRun(_ context.Context, status, message string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.Runs = append(m.Runs, status+": "+message)
	return nil
}
