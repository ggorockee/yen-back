package rates

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"github.com/ggorockee/yen-back/server/internal/koreaexim"
)

// Currencies served by the API.
var Currencies = []string{"JPY", "USD"}

// Fetcher abstracts the upstream rate API.
type Fetcher interface {
	Fetch(ctx context.Context, date time.Time, currencies ...string) (map[string]koreaexim.Rate, error)
}

// KST is Korea Standard Time; the upstream publishes per KST business day.
var KST = time.FixedZone("KST", 9*60*60)

const (
	// lookbackDays bounds how far back a collection walks to find the most
	// recent published date (covers long holidays such as Chuseok).
	lookbackDays = 10
	// staleAfterDays marks a snapshot stale when it is older than this many
	// calendar days (a normal weekend plus a holiday stays fresh).
	staleAfterDays = 4
	// healRetryInterval throttles on-demand collection when the store is empty.
	healRetryInterval = 5 * time.Minute
)

// Observer receives collection telemetry. Implemented by telemetry.Metrics.
type Observer interface {
	CollectorRun(status string, d time.Duration) // status: ok, empty, error
	UpstreamCall(result string)                  // result: ok, empty, error
	Snapshot(s Snapshot)                         // latest snapshot seen or saved
}

type nopObserver struct{}

func (nopObserver) CollectorRun(string, time.Duration) {}
func (nopObserver) UpstreamCall(string)                {}
func (nopObserver) Snapshot(Snapshot)                  {}

// Service coordinates collection and lookup.
type Service struct {
	store   Store
	fetcher Fetcher
	now     func() time.Time
	log     *slog.Logger
	obs     Observer

	mu          sync.Mutex
	lastAttempt time.Time
}

// NewService creates a Service. now may be nil to use time.Now.
func NewService(store Store, fetcher Fetcher, now func() time.Time, log *slog.Logger) *Service {
	if now == nil {
		now = time.Now
	}
	if log == nil {
		log = slog.Default()
	}
	return &Service{store: store, fetcher: fetcher, now: now, log: log, obs: nopObserver{}}
}

// WithObserver sets the telemetry observer and returns s.
func (s *Service) WithObserver(o Observer) *Service {
	if o != nil {
		s.obs = o
	}
	return s
}

// Ping checks the store; used by the readiness probe.
func (s *Service) Ping(ctx context.Context) error { return s.store.Ping(ctx) }

// Prime loads the stored snapshot into telemetry at startup.
func (s *Service) Prime(ctx context.Context) {
	if snap, ok, err := s.store.Latest(ctx); err == nil && ok {
		s.obs.Snapshot(snap)
	}
}

// CollectResult describes what a collection did.
type CollectResult struct {
	Status   string    `json:"status"` // "updated" or "unchanged"
	BaseDate time.Time `json:"-"`
	Calls    int       `json:"calls"`
}

// Collect fetches the most recent published rates. It walks back from today
// (KST) until it finds data or reaches the date already stored, so a run on a
// holiday or before 11:00 KST costs only a few upstream calls.
func (s *Service) Collect(ctx context.Context) (CollectResult, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.collectLocked(ctx)
}

func (s *Service) collectLocked(ctx context.Context) (res CollectResult, err error) {
	start := s.now()
	s.lastAttempt = start
	defer func() {
		status := "ok"
		switch {
		case err != nil:
			status = "error"
		case res.Status == "unchanged":
			status = "empty"
		}
		s.obs.CollectorRun(status, s.now().Sub(start))
	}()

	latest, hasLatest, err := s.store.Latest(ctx)
	if err != nil {
		return CollectResult{}, err
	}

	today := KSTDate(s.now())
	if hasLatest {
		s.obs.Snapshot(latest)
	}
	res = CollectResult{Status: "unchanged", BaseDate: latest.BaseDate}
	for d := 0; d <= lookbackDays; d++ {
		date := today.AddDate(0, 0, -d)
		if hasLatest && !date.After(latest.BaseDate) {
			break
		}
		res.Calls++
		fetched, err := s.fetcher.Fetch(ctx, date, Currencies...)
		if errors.Is(err, koreaexim.ErrEmpty) {
			s.obs.UpstreamCall("empty")
			continue
		}
		if err != nil {
			s.obs.UpstreamCall("error")
			s.record(ctx, "error", err.Error())
			return res, err
		}

		s.obs.UpstreamCall("ok")
		snap := Snapshot{BaseDate: date, FetchedAt: s.now().UTC(), Source: "koreaexim", Rates: map[string]Rate{}}
		for code, r := range fetched {
			snap.Rates[code] = Rate{KRWPerUnit: r.KRWPerUnit, Raw: r.Raw, Unit: r.Unit}
		}
		if err := s.store.Save(ctx, snap); err != nil {
			s.record(ctx, "error", err.Error())
			return res, err
		}
		s.obs.Snapshot(snap)
		res.Status, res.BaseDate = "updated", date
		s.record(ctx, "ok", fmt.Sprintf("saved %s after %d call(s)", date.Format(time.DateOnly), res.Calls))
		return res, nil
	}

	if !hasLatest {
		msg := fmt.Sprintf("no data in the last %d days", lookbackDays)
		s.record(ctx, "empty", msg)
		return res, errors.New(msg)
	}
	s.record(ctx, "empty", fmt.Sprintf("no newer data than %s", latest.BaseDate.Format(time.DateOnly)))
	return res, nil
}

// Latest returns the newest snapshot. When nothing is stored yet (fresh
// deployment, in-memory store after a restart) it collects on demand, at most
// once per healRetryInterval.
func (s *Service) Latest(ctx context.Context) (Snapshot, bool, error) {
	snap, ok, err := s.store.Latest(ctx)
	if err != nil || ok {
		return snap, ok, err
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	// Another request may have filled the store while we waited.
	if snap, ok, err = s.store.Latest(ctx); err != nil || ok {
		return snap, ok, err
	}
	if !s.lastAttempt.IsZero() && s.now().Sub(s.lastAttempt) < healRetryInterval {
		return Snapshot{}, false, nil
	}
	if _, err := s.collectLocked(ctx); err != nil {
		s.log.Warn("on-demand collection failed", "err", err)
	}
	return s.store.Latest(ctx)
}

// IsStale reports whether a snapshot is older than staleAfterDays.
func (s *Service) IsStale(snap Snapshot) bool {
	return KSTDate(s.now()).Sub(snap.BaseDate) > staleAfterDays*24*time.Hour
}

func (s *Service) record(ctx context.Context, status, msg string) {
	if err := s.store.RecordRun(ctx, status, msg); err != nil {
		s.log.Warn("record collector run", "err", err)
	}
	s.log.Info("collector run", "status", status, "message", msg)
}

// KSTDate returns the KST calendar date of t as midnight UTC, the
// representation used for BaseDate throughout the package.
func KSTDate(t time.Time) time.Time {
	k := t.In(KST)
	return time.Date(k.Year(), k.Month(), k.Day(), 0, 0, 0, 0, time.UTC)
}
