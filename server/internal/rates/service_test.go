package rates

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/ggorockee/yen-back/server/internal/koreaexim"
)

// fakeFetcher returns data only for the dates in published.
type fakeFetcher struct {
	published map[string]float64 // date -> JPY deal_bas_r per 100 yen
	err       error
	calls     []string
}

func (f *fakeFetcher) Fetch(_ context.Context, date time.Time, _ ...string) (map[string]koreaexim.Rate, error) {
	key := date.Format(time.DateOnly)
	f.calls = append(f.calls, key)
	if f.err != nil {
		return nil, f.err
	}
	v, ok := f.published[key]
	if !ok {
		return nil, koreaexim.ErrEmpty
	}
	return map[string]koreaexim.Rate{
		"JPY": {Currency: "JPY", Unit: 100, KRWPerUnit: v / 100},
		"USD": {Currency: "USD", Unit: 1, KRWPerUnit: 1388.5},
	}, nil
}

// Sunday 2026-11-15 10:00 KST.
var sundayMorning = time.Date(2026, 11, 15, 10, 0, 0, 0, KST)

func fixedNow(t time.Time) func() time.Time { return func() time.Time { return t } }

func TestCollectWalksBackToLastBusinessDay(t *testing.T) {
	f := &fakeFetcher{published: map[string]float64{"2026-11-13": 921.35}}
	store := NewMemoryStore()
	svc := NewService(store, f, fixedNow(sundayMorning), nil)

	res, err := svc.Collect(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if res.Status != "updated" || res.BaseDate.Format(time.DateOnly) != "2026-11-13" {
		t.Fatalf("res = %+v", res)
	}
	if res.Calls != 3 { // 15, 14, 13
		t.Errorf("calls = %d, want 3 (%v)", res.Calls, f.calls)
	}
	snap, ok, _ := store.Latest(context.Background())
	if !ok || snap.Rates["JPY"].KRWPerUnit != 9.2135 {
		t.Fatalf("snapshot = %+v", snap)
	}
}

func TestCollectStopsAtStoredDate(t *testing.T) {
	f := &fakeFetcher{published: map[string]float64{"2026-11-13": 921.35}}
	svc := NewService(NewMemoryStore(), f, fixedNow(sundayMorning), nil)
	if _, err := svc.Collect(context.Background()); err != nil {
		t.Fatal(err)
	}
	f.calls = nil

	res, err := svc.Collect(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if res.Status != "unchanged" || len(f.calls) != 2 { // 15, 14; 13 already stored
		t.Fatalf("res = %+v calls = %v", res, f.calls)
	}
}

func TestCollectNothingPublished(t *testing.T) {
	f := &fakeFetcher{published: map[string]float64{}}
	svc := NewService(NewMemoryStore(), f, fixedNow(sundayMorning), nil)
	if _, err := svc.Collect(context.Background()); err == nil {
		t.Fatal("expected error when nothing is published in the lookback window")
	}
	if len(f.calls) != lookbackDays+1 {
		t.Errorf("calls = %d, want %d", len(f.calls), lookbackDays+1)
	}
}

func TestCollectUpstreamError(t *testing.T) {
	f := &fakeFetcher{err: errors.New("boom")}
	store := NewMemoryStore()
	svc := NewService(store, f, fixedNow(sundayMorning), nil)
	if _, err := svc.Collect(context.Background()); err == nil {
		t.Fatal("expected error")
	}
	if len(store.Runs) != 1 {
		t.Errorf("runs = %v", store.Runs)
	}
}

func TestLatestHealsEmptyStoreAndThrottles(t *testing.T) {
	f := &fakeFetcher{published: map[string]float64{}}
	now := sundayMorning
	svc := NewService(NewMemoryStore(), f, func() time.Time { return now }, nil)

	if _, ok, _ := svc.Latest(context.Background()); ok {
		t.Fatal("expected no snapshot")
	}
	first := len(f.calls)

	// Within the retry interval: no upstream calls.
	now = now.Add(time.Minute)
	_, _, _ = svc.Latest(context.Background())
	if len(f.calls) != first {
		t.Fatalf("expected throttled, calls went %d -> %d", first, len(f.calls))
	}

	// After the interval, with data published: heals.
	f.published["2026-11-13"] = 921.35
	now = now.Add(healRetryInterval)
	snap, ok, err := svc.Latest(context.Background())
	if err != nil || !ok || snap.BaseDate.Format(time.DateOnly) != "2026-11-13" {
		t.Fatalf("snap=%+v ok=%v err=%v", snap, ok, err)
	}
}

func TestIsStale(t *testing.T) {
	svc := NewService(NewMemoryStore(), &fakeFetcher{}, fixedNow(sundayMorning), nil)
	cases := map[string]bool{
		"2026-11-13": false, // Friday, normal weekend
		"2026-11-11": false, // exactly 4 days
		"2026-11-10": true,
	}
	for d, want := range cases {
		date, _ := time.Parse(time.DateOnly, d)
		if got := svc.IsStale(Snapshot{BaseDate: date}); got != want {
			t.Errorf("IsStale(%s) = %v, want %v", d, got, want)
		}
	}
}

func TestKSTDate(t *testing.T) {
	// 2026-11-14 16:00 UTC is 2026-11-15 01:00 KST.
	got := KSTDate(time.Date(2026, 11, 14, 16, 0, 0, 0, time.UTC))
	if got.Format(time.DateOnly) != "2026-11-15" {
		t.Errorf("KSTDate = %s", got)
	}
}
