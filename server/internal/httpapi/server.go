// Package httpapi exposes the public and internal HTTP endpoints.
package httpapi

import (
	"context"
	"crypto/subtle"
	"errors"
	"log/slog"
	"strconv"
	"strings"
	"time"

	"github.com/gofiber/adaptor/v2"
	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/recover"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	"github.com/ggorockee/yen-back/server/internal/places"
	"github.com/ggorockee/yen-back/server/internal/rates"
	"github.com/ggorockee/yen-back/server/internal/rules"
	"github.com/ggorockee/yen-back/server/internal/stores"
	"github.com/ggorockee/yen-back/server/internal/telemetry"
)

// RateService is the subset of rates.Service the handlers need.
type RateService interface {
	Latest(ctx context.Context) (rates.Snapshot, bool, error)
	Collect(ctx context.Context) (rates.CollectResult, error)
	IsStale(s rates.Snapshot) bool
	Ping(ctx context.Context) error
}

// Options configures the API app.
type Options struct {
	// InternalToken guards /internal/*; when empty the internal endpoints are disabled.
	InternalToken string
	Metrics       *telemetry.Metrics
	// Places searches chain branches; nil disables /v1/places/search.
	Places PlaceSearcher
	Log    *slog.Logger
}

// PlaceSearcher is the subset of places.Service the handlers need.
type PlaceSearcher interface {
	Search(ctx context.Context, query string, lat, lng float64) ([]places.Place, error)
}

// LatestResponse is the body of GET /v1/rates/latest.
type LatestResponse struct {
	BaseDate  string                `json:"base_date"`
	FetchedAt time.Time             `json:"fetched_at"`
	Source    string                `json:"source"`
	Stale     bool                  `json:"stale"`
	Rates     map[string]rates.Rate `json:"rates"`
}

type eventsRequest struct {
	Events []struct {
		Name  string `json:"name"`
		Count int    `json:"count"`
	} `json:"events"`
}

// New builds the public API app.
func New(svc RateService, opt Options) *fiber.App {
	if opt.Metrics == nil {
		opt.Metrics = telemetry.New("dev", "none", nil)
	}
	if opt.Log == nil {
		opt.Log = slog.Default()
	}
	m := opt.Metrics

	app := fiber.New(fiber.Config{
		AppName:               "yen-back",
		DisableStartupMessage: true,
		BodyLimit:             16 * 1024, // the largest legitimate body is a small events batch
		// Fiber strings are zero-copy views into reused request buffers by
		// default; metric labels outlive the request, so values must be copies.
		Immutable: true,
		ErrorHandler: func(c *fiber.Ctx, err error) error {
			code := fiber.StatusInternalServerError
			if e, ok := err.(*fiber.Error); ok {
				code = e.Code
			}
			return c.Status(code).JSON(fiber.Map{"error": err.Error()})
		},
	})
	app.Use(recover.New())
	app.Use(observe(m, opt.Log))

	app.Get("/healthz", func(c *fiber.Ctx) error { return c.SendString("ok") })
	app.Get("/readyz", func(c *fiber.Ctx) error {
		ctx, cancel := context.WithTimeout(c.UserContext(), 2*time.Second)
		defer cancel()
		if err := svc.Ping(ctx); err != nil {
			return fiber.NewError(fiber.StatusServiceUnavailable, "store unavailable")
		}
		return c.SendString("ok")
	})

	v1 := app.Group("/v1")
	v1.Get("/rates/latest", func(c *fiber.Ctx) error {
		snap, ok, err := svc.Latest(c.UserContext())
		if err != nil {
			return fiber.NewError(fiber.StatusServiceUnavailable, "rate store unavailable")
		}
		if !ok {
			return fiber.NewError(fiber.StatusServiceUnavailable, "no rates collected yet")
		}
		// Rates change at most once per business day; let CDNs and the app cache briefly.
		c.Set(fiber.HeaderCacheControl, "public, max-age=600")
		return c.JSON(LatestResponse{
			BaseDate:  snap.BaseDate.Format(time.DateOnly),
			FetchedAt: snap.FetchedAt,
			Source:    snap.Source,
			Stale:     svc.IsStale(snap),
			Rates:     snap.Rates,
		})
	})
	v1.Get("/rules", func(c *fiber.Ctx) error {
		c.Set(fiber.HeaderCacheControl, "public, max-age=3600")
		return c.JSON(rules.Current)
	})
	v1.Get("/stores", func(c *fiber.Ctx) error {
		// The catalog changes rarely; let the app and CDNs cache it for a day.
		c.Set(fiber.HeaderCacheControl, "public, max-age=86400")
		c.Set(fiber.HeaderContentType, fiber.MIMEApplicationJSONCharsetUTF8)
		return c.Send(stores.Raw())
	})
	v1.Get("/places/search", func(c *fiber.Ctx) error {
		if opt.Places == nil {
			return fiber.NewError(fiber.StatusServiceUnavailable, "branch search disabled")
		}
		lat, errLat := strconv.ParseFloat(c.Query("lat"), 64)
		lng, errLng := strconv.ParseFloat(c.Query("lng"), 64)
		if errLat != nil || errLng != nil {
			return fiber.NewError(fiber.StatusBadRequest, "lat and lng are required")
		}
		found, err := opt.Places.Search(c.UserContext(), c.Query("q"), lat, lng)
		switch {
		case errors.Is(err, places.ErrInvalid):
			return fiber.NewError(fiber.StatusBadRequest, "invalid query or location")
		case errors.Is(err, places.ErrDisabled):
			return fiber.NewError(fiber.StatusServiceUnavailable, "branch search disabled")
		case errors.Is(err, places.ErrLimited):
			return fiber.NewError(fiber.StatusTooManyRequests, "branch search temporarily unavailable")
		case err != nil:
			opt.Log.Warn("places search failed", "err", err)
			return fiber.NewError(fiber.StatusBadGateway, "branch search failed")
		}
		// Location-specific: cache only on the device.
		c.Set(fiber.HeaderCacheControl, "private, max-age=300")
		return c.JSON(fiber.Map{"places": found})
	})
	v1.Post("/events", func(c *fiber.Ctx) error {
		var req eventsRequest
		if err := c.BodyParser(&req); err != nil {
			m.EventRejected("malformed")
			return fiber.NewError(fiber.StatusBadRequest, "malformed body")
		}
		if len(req.Events) == 0 || len(req.Events) > telemetry.MaxEventsPerBatch {
			m.EventRejected("batch_size")
			return fiber.NewError(fiber.StatusBadRequest, "invalid batch size")
		}
		platform := c.Get("X-App-Platform")
		accepted := 0
		for _, e := range req.Events {
			switch {
			case !telemetry.AllowedEvents[e.Name]:
				m.EventRejected("unknown_event")
			case e.Count < 1 || e.Count > telemetry.MaxEventCount:
				m.EventRejected("invalid_count")
			default:
				m.AppEvent(e.Name, platform, e.Count)
				accepted++
			}
		}
		return c.Status(fiber.StatusAccepted).JSON(fiber.Map{"accepted": accepted})
	})

	internal := app.Group("/internal", requireToken(opt.InternalToken))
	internal.Post("/collect", func(c *fiber.Ctx) error {
		res, err := svc.Collect(c.UserContext())
		if err != nil {
			return fiber.NewError(fiber.StatusBadGateway, err.Error())
		}
		return c.JSON(fiber.Map{
			"status":    res.Status,
			"base_date": res.BaseDate.Format(time.DateOnly),
			"calls":     res.Calls,
		})
	})

	return app
}

// NewMetricsApp serves /metrics on its own listener so it is never reachable
// through the public ingress; only the ServiceMonitor scrapes that port.
func NewMetricsApp(m *telemetry.Metrics) *fiber.App {
	app := fiber.New(fiber.Config{AppName: "yen-back-metrics", DisableStartupMessage: true})
	app.Get("/metrics", adaptor.HTTPHandler(promhttp.HandlerFor(m.Registry, promhttp.HandlerOpts{})))
	return app
}

// observe records HTTP metrics, counts app traffic and writes an access log.
func observe(m *telemetry.Metrics, log *slog.Logger) fiber.Handler {
	return func(c *fiber.Ctx) error {
		start := time.Now()
		m.InFlight(1)
		defer m.InFlight(-1)

		err := c.Next()

		// The error handler has not run yet; resolve the status it will send.
		status := c.Response().StatusCode()
		if err != nil {
			status = fiber.StatusInternalServerError
			if e, ok := err.(*fiber.Error); ok {
				status = e.Code
			}
		}

		// The matched pattern, never the raw path, keeps label cardinality bounded.
		route := c.Route().Path
		if route == "" || route == "/" && c.Path() != "/" {
			route = "unmatched"
		}
		elapsed := time.Since(start)
		m.HTTP(c.Method(), route, status, elapsed)

		if strings.HasPrefix(route, "/v1/") {
			m.AppRequest(c.Get("X-App-Platform"), c.Get("X-App-Version"))
		}
		if route != "/healthz" && route != "/readyz" {
			level := slog.LevelInfo
			if status >= 500 {
				level = slog.LevelError
			} else if status >= 400 {
				level = slog.LevelWarn
			}
			log.Log(c.UserContext(), level, "http request",
				"method", c.Method(), "route", route, "status", status,
				"duration_ms", elapsed.Milliseconds(),
				"platform", telemetry.NormalizePlatform(c.Get("X-App-Platform")),
				"app_version", telemetry.NormalizeVersion(c.Get("X-App-Version")))
		}
		return err
	}
}

func requireToken(token string) fiber.Handler {
	return func(c *fiber.Ctx) error {
		if token == "" {
			return fiber.ErrNotFound
		}
		got := c.Get("X-Internal-Token")
		if subtle.ConstantTimeCompare([]byte(got), []byte(token)) != 1 {
			return fiber.ErrUnauthorized
		}
		return c.Next()
	}
}
