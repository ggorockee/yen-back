// Package telemetry exposes Prometheus metrics for the server, the rate
// collector and anonymous app activity. kube-prometheus-stack scrapes them via
// a ServiceMonitor (see deploy/helm).
//
// Every label has a bounded value set: routes come from the router's pattern
// (never the raw path), platforms and event names are allowlisted, and app
// versions that do not look like semver collapse into "other".
package telemetry

import (
	"regexp"
	"strconv"
	"strings"
	"sync/atomic"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"

	"github.com/ggorockee/yen-back/server/internal/rates"
)

const namespace = "yenback"

// Metrics holds every collector on a private registry.
type Metrics struct {
	Registry *prometheus.Registry

	httpRequests  *prometheus.CounterVec
	httpDuration  *prometheus.HistogramVec
	httpInFlight  prometheus.Gauge
	appRequests   *prometheus.CounterVec
	appEvents     *prometheus.CounterVec
	eventsReject  *prometheus.CounterVec
	collectorRuns *prometheus.CounterVec
	upstream      *prometheus.CounterVec
	collectorDur  prometheus.Histogram
	lastRun       prometheus.Gauge
	lastSuccess   prometheus.Gauge
	rateKRW       *prometheus.GaugeVec
	placesReqs    *prometheus.CounterVec
	placesCalls   *prometheus.CounterVec

	baseDate atomic.Int64 // unix seconds of the latest snapshot's base date, 0 = none
	now      func() time.Time
}

// New registers all collectors. version and commit label yenback_build_info.
func New(version, commit string, now func() time.Time) *Metrics {
	if now == nil {
		now = time.Now
	}
	reg := prometheus.NewRegistry()
	m := &Metrics{Registry: reg, now: now}
	f := func(c prometheus.Collector) { reg.MustRegister(c) }

	f(collectors.NewGoCollector())
	f(collectors.NewProcessCollector(collectors.ProcessCollectorOpts{}))

	buildInfo := prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Namespace: namespace, Name: "build_info", Help: "Build metadata; value is always 1.",
	}, []string{"version", "commit"})
	buildInfo.WithLabelValues(version, commit).Set(1)
	f(buildInfo)

	m.httpRequests = prometheus.NewCounterVec(prometheus.CounterOpts{
		Namespace: namespace, Name: "http_requests_total", Help: "HTTP requests by route pattern and status.",
	}, []string{"method", "route", "status"})
	m.httpDuration = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Namespace: namespace, Name: "http_request_duration_seconds", Help: "HTTP request latency.",
		Buckets: []float64{.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10},
	}, []string{"method", "route"})
	m.httpInFlight = prometheus.NewGauge(prometheus.GaugeOpts{
		Namespace: namespace, Name: "http_requests_in_flight", Help: "HTTP requests being served.",
	})
	m.appRequests = prometheus.NewCounterVec(prometheus.CounterOpts{
		Namespace: namespace, Name: "app_requests_total",
		Help: "API requests from the mobile app by platform and app version (from X-App-* headers).",
	}, []string{"platform", "app_version"})
	m.appEvents = prometheus.NewCounterVec(prometheus.CounterOpts{
		Namespace: namespace, Name: "app_events_total", Help: "Anonymous in-app activity events reported by the app.",
	}, []string{"event", "platform"})
	m.eventsReject = prometheus.NewCounterVec(prometheus.CounterOpts{
		Namespace: namespace, Name: "app_events_rejected_total", Help: "Activity events or batches rejected.",
	}, []string{"reason"})
	m.collectorRuns = prometheus.NewCounterVec(prometheus.CounterOpts{
		Namespace: namespace, Name: "collector_runs_total", Help: "Rate collection runs by outcome (ok, empty, error).",
	}, []string{"status"})
	m.upstream = prometheus.NewCounterVec(prometheus.CounterOpts{
		Namespace: namespace, Name: "collector_upstream_calls_total",
		Help: "Calls to the Korea Eximbank API by result (ok, empty, error).",
	}, []string{"result"})
	m.collectorDur = prometheus.NewHistogram(prometheus.HistogramOpts{
		Namespace: namespace, Name: "collector_run_duration_seconds", Help: "Duration of a rate collection run.",
		Buckets: []float64{.1, .25, .5, 1, 2.5, 5, 10, 30, 60},
	})
	m.lastRun = prometheus.NewGauge(prometheus.GaugeOpts{
		Namespace: namespace, Name: "collector_last_run_timestamp_seconds", Help: "Unix time of the last collection run.",
	})
	m.lastSuccess = prometheus.NewGauge(prometheus.GaugeOpts{
		Namespace: namespace, Name: "collector_last_success_timestamp_seconds",
		Help: "Unix time of the last run that finished without error.",
	})
	m.rateKRW = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Namespace: namespace, Name: "exchange_rate_krw", Help: "Latest KRW per 1 unit of the currency.",
	}, []string{"currency"})

	m.placesReqs = prometheus.NewCounterVec(prometheus.CounterOpts{
		Namespace: namespace, Name: "places_requests_total",
		Help: "Branch searches by outcome (ok, limited, out_of_area, invalid, error, disabled).",
	}, []string{"result"})
	m.placesCalls = prometheus.NewCounterVec(prometheus.CounterOpts{
		Namespace: namespace, Name: "places_upstream_calls_total",
		Help: "Billable Google Places API calls by result (ok, error).",
	}, []string{"result"})

	for _, c := range []prometheus.Collector{
		m.httpRequests, m.httpDuration, m.httpInFlight, m.appRequests, m.appEvents, m.eventsReject,
		m.collectorRuns, m.upstream, m.collectorDur, m.lastRun, m.lastSuccess, m.rateKRW,
		m.placesReqs, m.placesCalls,
	} {
		f(c)
	}

	// Computed at scrape time so they keep moving even if collection stops.
	f(prometheus.NewGaugeFunc(prometheus.GaugeOpts{
		Namespace: namespace, Name: "rate_base_date_timestamp_seconds",
		Help: "Unix time (midnight UTC) of the latest snapshot's KST base date; 0 when none.",
	}, func() float64 { return float64(m.baseDate.Load()) }))
	f(prometheus.NewGaugeFunc(prometheus.GaugeOpts{
		Namespace: namespace, Name: "rate_age_days",
		Help: "Calendar days between today (KST) and the latest snapshot's base date; -1 when none.",
	}, m.rateAgeDays))

	// Pre-create common series so absent() and rate() behave from the first scrape.
	for _, s := range []string{"ok", "limited", "out_of_area", "invalid", "error", "disabled"} {
		m.placesReqs.WithLabelValues(s)
	}
	m.placesCalls.WithLabelValues("ok")
	m.placesCalls.WithLabelValues("error")
	for _, s := range []string{"ok", "empty", "error"} {
		m.collectorRuns.WithLabelValues(s)
		m.upstream.WithLabelValues(s)
	}
	return m
}

func (m *Metrics) rateAgeDays() float64 {
	b := m.baseDate.Load()
	if b == 0 {
		return -1
	}
	return rates.KSTDate(m.now()).Sub(time.Unix(b, 0).UTC()).Hours() / 24
}

// HTTP records one request.
func (m *Metrics) HTTP(method, route string, status int, d time.Duration) {
	m.httpRequests.WithLabelValues(method, route, statusClass(status)).Inc()
	m.httpDuration.WithLabelValues(method, route).Observe(d.Seconds())
}

// InFlight adjusts the in-flight gauge by delta.
func (m *Metrics) InFlight(delta float64) { m.httpInFlight.Add(delta) }

// AppRequest counts a request carrying app headers.
func (m *Metrics) AppRequest(platform, version string) {
	m.appRequests.WithLabelValues(NormalizePlatform(platform), NormalizeVersion(version)).Inc()
}

// AppEvent counts n occurrences of an allowlisted event.
func (m *Metrics) AppEvent(event, platform string, n int) {
	m.appEvents.WithLabelValues(event, NormalizePlatform(platform)).Add(float64(n))
}

// EventRejected counts a rejected event or batch.
func (m *Metrics) EventRejected(reason string) { m.eventsReject.WithLabelValues(reason).Inc() }

// --- rates.Observer ---

func (m *Metrics) CollectorRun(status string, d time.Duration) {
	m.collectorRuns.WithLabelValues(status).Inc()
	m.collectorDur.Observe(d.Seconds())
	now := float64(m.now().Unix())
	m.lastRun.Set(now)
	if status != "error" {
		m.lastSuccess.Set(now)
	}
}

func (m *Metrics) UpstreamCall(result string) { m.upstream.WithLabelValues(result).Inc() }

func (m *Metrics) Snapshot(s rates.Snapshot) {
	if s.BaseDate.Unix() > m.baseDate.Load() {
		m.baseDate.Store(s.BaseDate.Unix())
	}
	for code, r := range s.Rates {
		m.rateKRW.WithLabelValues(code).Set(r.KRWPerUnit)
	}
}

// --- places.Observer ---

func (m *Metrics) PlacesRequest(result string)  { m.placesReqs.WithLabelValues(result).Inc() }
func (m *Metrics) PlacesUpstream(result string) { m.placesCalls.WithLabelValues(result).Inc() }

// RegisterPlacesDailyCalls exposes today's billable call count read at scrape time.
func (m *Metrics) RegisterPlacesDailyCalls(f func() int, limit int) {
	m.Registry.MustRegister(prometheus.NewGaugeFunc(prometheus.GaugeOpts{
		Namespace: namespace, Name: "places_daily_calls", Help: "Google Places calls made today (KST).",
	}, func() float64 { return float64(f()) }))
	m.Registry.MustRegister(prometheus.NewGaugeFunc(prometheus.GaugeOpts{
		Namespace: namespace, Name: "places_daily_limit", Help: "Configured daily cap for Google Places calls.",
	}, func() float64 { return float64(limit) }))
}

// --- label normalization ---

var semver = regexp.MustCompile(`^\d{1,3}\.\d{1,3}\.\d{1,4}$`)

// NormalizePlatform maps the X-App-Platform header to ios, android, other or none.
func NormalizePlatform(p string) string {
	switch p = strings.ToLower(strings.TrimSpace(p)); p {
	case "ios", "android":
		return p
	case "":
		return "none"
	default:
		return "other"
	}
}

// NormalizeVersion keeps x.y.z versions and maps anything else to "other" ("none" if empty).
func NormalizeVersion(v string) string {
	v = strings.TrimSpace(v)
	switch {
	case v == "":
		return "none"
	case semver.MatchString(v):
		return v
	default:
		return "other"
	}
}

func statusClass(code int) string {
	// Exact codes are useful (404 vs 401 vs 503) and bounded by the router.
	if code < 100 || code > 599 {
		return "other"
	}
	return strconv.Itoa(code)
}
