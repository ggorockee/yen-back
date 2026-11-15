package httpapi

import (
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/ggorockee/yen-back/server/internal/rates"
	"github.com/ggorockee/yen-back/server/internal/telemetry"
)

func scrape(t *testing.T, m *telemetry.Metrics) string {
	t.Helper()
	resp, err := NewMetricsApp(m).Test(httptest.NewRequest(http.MethodGet, "/metrics", nil))
	if err != nil {
		t.Fatal(err)
	}
	b, _ := io.ReadAll(resp.Body)
	return string(b)
}

func mustContain(t *testing.T, body string, lines ...string) {
	t.Helper()
	for _, l := range lines {
		if !strings.Contains(body, l) {
			t.Errorf("metrics missing %q", l)
		}
	}
}

func TestMetricsRecordRequestsAndAppTraffic(t *testing.T) {
	m := telemetry.New("1.2.3", "abc", nil)
	svc := &fakeService{ok: true, snap: rates.Snapshot{BaseDate: time.Date(2026, 11, 13, 0, 0, 0, 0, time.UTC)}}
	app := New(svc, Options{Metrics: m})

	req := httptest.NewRequest(http.MethodGet, "/v1/rates/latest", nil)
	req.Header.Set("X-App-Platform", "iOS")
	req.Header.Set("X-App-Version", "1.0.0")
	if _, err := app.Test(req); err != nil {
		t.Fatal(err)
	}
	// Raw paths must not become labels.
	for _, p := range []string{"/nope/1", "/nope/2", "/v1/rates/../x"} {
		if _, err := app.Test(httptest.NewRequest(http.MethodGet, p, nil)); err != nil {
			t.Fatal(err)
		}
	}

	body := scrape(t, m)
	mustContain(t, body,
		`yenback_build_info{commit="abc",version="1.2.3"} 1`,
		`yenback_http_requests_total{method="GET",route="/v1/rates/latest",status="200"} 1`,
		`yenback_http_requests_total{method="GET",route="unmatched",status="404"} 3`,
		`yenback_app_requests_total{app_version="1.0.0",platform="ios"} 1`,
		`yenback_http_request_duration_seconds_bucket`,
		`go_goroutines`,
	)
	if strings.Contains(body, "/nope/") {
		t.Error("raw path leaked into labels")
	}
}

func TestMetricsServerErrorStatus(t *testing.T) {
	m := telemetry.New("dev", "none", nil)
	app := New(&fakeService{err: errors.New("db down")}, Options{Metrics: m})
	if _, err := app.Test(httptest.NewRequest(http.MethodGet, "/v1/rates/latest", nil)); err != nil {
		t.Fatal(err)
	}
	mustContain(t, scrape(t, m), `yenback_http_requests_total{method="GET",route="/v1/rates/latest",status="503"} 1`)
}

func TestEvents(t *testing.T) {
	m := telemetry.New("dev", "none", nil)
	app := New(&fakeService{}, Options{Metrics: m})

	post := func(body string) int {
		req := httptest.NewRequest(http.MethodPost, "/v1/events", strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-App-Platform", "android")
		resp, err := app.Test(req)
		if err != nil {
			t.Fatal(err)
		}
		return resp.StatusCode
	}

	if code := post(`{"events":[{"name":"item_added","count":3},{"name":"evil","count":1},{"name":"app_open","count":99999}]}`); code != http.StatusAccepted {
		t.Fatalf("status = %d", code)
	}
	if code := post(`{"events":[]}`); code != http.StatusBadRequest {
		t.Errorf("empty batch status = %d", code)
	}
	if code := post(`not json`); code != http.StatusBadRequest {
		t.Errorf("malformed status = %d", code)
	}

	body := scrape(t, m)
	mustContain(t, body,
		`yenback_app_events_total{event="item_added",platform="android"} 3`,
		`yenback_app_events_rejected_total{reason="unknown_event"} 1`,
		`yenback_app_events_rejected_total{reason="invalid_count"} 1`,
		`yenback_app_events_rejected_total{reason="batch_size"} 1`,
		`yenback_app_events_rejected_total{reason="malformed"} 1`,
	)
	if strings.Contains(body, `event="evil"`) {
		t.Error("unknown event recorded as a label")
	}
}

func TestReadyz(t *testing.T) {
	ok, _ := do(t, &fakeService{}, "", httptest.NewRequest(http.MethodGet, "/readyz", nil))
	if ok.StatusCode != http.StatusOK {
		t.Errorf("ready status = %d", ok.StatusCode)
	}
	bad, _ := do(t, &fakeService{pingErr: errors.New("down")}, "", httptest.NewRequest(http.MethodGet, "/readyz", nil))
	if bad.StatusCode != http.StatusServiceUnavailable {
		t.Errorf("not-ready status = %d", bad.StatusCode)
	}
}

// Regression: without Immutable, label values were views into reused fasthttp
// buffers and later requests corrupted them (e.g. platform="and", method="GETT").
func TestMetricLabelsSurviveBufferReuse(t *testing.T) {
	m := telemetry.New("dev", "none", nil)
	app := New(&fakeService{}, Options{Metrics: m})

	send := func(method, path, platform, body string) {
		req := httptest.NewRequest(method, path, strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-App-Platform", platform)
		req.Header.Set("X-App-Version", "1.0.0")
		if _, err := app.Test(req); err != nil {
			t.Fatal(err)
		}
	}
	send(http.MethodPost, "/v1/events", "ios", `{"events":[{"name":"app_open","count":1}]}`)
	for range 5 {
		send(http.MethodGet, "/v1/rules", "android", "")
	}

	body := scrape(t, m)
	mustContain(t, body,
		`yenback_app_events_total{event="app_open",platform="ios"} 1`,
		`yenback_app_requests_total{app_version="1.0.0",platform="ios"} 1`,
		`yenback_app_requests_total{app_version="1.0.0",platform="android"} 5`,
		`yenback_http_requests_total{method="POST",route="/v1/events",status="202"} 1`,
	)
	for _, bad := range []string{`platform="and"`, `method="GETT"`, `method="GEST"`} {
		if strings.Contains(body, bad) {
			t.Errorf("corrupted label %s", bad)
		}
	}
}
