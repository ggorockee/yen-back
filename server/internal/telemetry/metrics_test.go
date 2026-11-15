package telemetry

import (
	"strings"
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus/testutil"

	"github.com/ggorockee/yen-back/server/internal/rates"
)

func TestNormalize(t *testing.T) {
	for in, want := range map[string]string{"ios": "ios", " Android ": "android", "": "none", "web": "other"} {
		if got := NormalizePlatform(in); got != want {
			t.Errorf("NormalizePlatform(%q) = %q, want %q", in, got, want)
		}
	}
	for in, want := range map[string]string{"1.0.0": "1.0.0", "10.20.300": "10.20.300", "": "none", "1.0": "other", "1.0.0-beta": "other", strings.Repeat("9", 40): "other"} {
		if got := NormalizeVersion(in); got != want {
			t.Errorf("NormalizeVersion(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestCollectorAndRateGauges(t *testing.T) {
	now := time.Date(2026, 11, 15, 10, 0, 0, 0, rates.KST)
	m := New("dev", "none", func() time.Time { return now })

	if got := gathered(t, m, "yenback_rate_age_days"); got != -1 {
		t.Errorf("age without snapshot = %v, want -1", got)
	}

	m.Snapshot(rates.Snapshot{
		BaseDate: time.Date(2026, 11, 13, 0, 0, 0, 0, time.UTC),
		Rates:    map[string]rates.Rate{"JPY": {KRWPerUnit: 9.2}},
	})
	m.CollectorRun("ok", time.Second)
	m.CollectorRun("error", time.Second)
	m.UpstreamCall("empty")

	if got := testutil.ToFloat64(m.rateKRW.WithLabelValues("JPY")); got != 9.2 {
		t.Errorf("JPY gauge = %v", got)
	}
	if got := testutil.ToFloat64(m.collectorRuns.WithLabelValues("error")); got != 1 {
		t.Errorf("error runs = %v", got)
	}
	if got := testutil.ToFloat64(m.lastSuccess); got != float64(now.Unix()) {
		t.Errorf("last success = %v", got)
	}

	// Age keeps growing at scrape time without new collections.
	now = now.Add(48 * time.Hour)
	if got := gathered(t, m, "yenback_rate_age_days"); got != 4 {
		t.Errorf("age = %v, want 4", got)
	}

	// An older snapshot never moves the base date backwards.
	m.Snapshot(rates.Snapshot{BaseDate: time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC)})
	if got := m.baseDate.Load(); got != time.Date(2026, 11, 13, 0, 0, 0, 0, time.UTC).Unix() {
		t.Errorf("base date moved backwards: %v", got)
	}
}

// gathered returns the value of a single-series gauge from the registry.
func gathered(t *testing.T, m *Metrics, name string) float64 {
	t.Helper()
	mfs, err := m.Registry.Gather()
	if err != nil {
		t.Fatal(err)
	}
	for _, mf := range mfs {
		if mf.GetName() == name {
			return mf.GetMetric()[0].GetGauge().GetValue()
		}
	}
	t.Fatalf("metric %s not found", name)
	return 0
}
