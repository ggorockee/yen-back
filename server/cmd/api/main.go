// Command api serves exchange rates and tax-free rules for the 돌려받엔 app.
package main

import (
	"context"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/ggorockee/yen-back/server/internal/config"
	"github.com/ggorockee/yen-back/server/internal/httpapi"
	"github.com/ggorockee/yen-back/server/internal/koreaexim"
	"github.com/ggorockee/yen-back/server/internal/places"
	"github.com/ggorockee/yen-back/server/internal/rates"
	"github.com/ggorockee/yen-back/server/internal/stores"
	"github.com/ggorockee/yen-back/server/internal/telemetry"
)

// Set at build time: -ldflags "-X main.version=... -X main.commit=...".
var (
	version = "dev"
	commit  = "none"
)

func main() {
	cfg, err := config.Load()
	log := newLogger(cfg.LogLevel)
	slog.SetDefault(log)
	if err == nil {
		err = run(cfg, log)
	}
	if err != nil {
		log.Error("server stopped", "err", err)
		os.Exit(1)
	}
}

func newLogger(level string) *slog.Logger {
	var l slog.Level
	if err := l.UnmarshalText([]byte(level)); err != nil {
		l = slog.LevelInfo
	}
	return slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: l})).
		With("service", "yen-back-server", "version", version)
}

func run(cfg config.Config, log *slog.Logger) error {
	if cfg.KoreaEximAPIKey == "" {
		log.Warn("KOREAEXIM_API_KEY is empty; collection will fail")
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	var store rates.Store
	if cfg.DatabaseURL != "" {
		pg, err := rates.NewPostgresStore(ctx, cfg.DatabaseURL)
		if err != nil {
			return err
		}
		defer pg.Close()
		store = pg
	} else {
		log.Warn("DATABASE_URL is empty; using in-memory store")
		store = rates.NewMemoryStore()
	}

	if _, err := stores.Load(); err != nil {
		return err
	}

	metrics := telemetry.New(version, commit, nil)
	svc := rates.NewService(store, koreaexim.New(cfg.KoreaEximURL, cfg.KoreaEximAPIKey), nil, log).
		WithObserver(metrics)
	svc.Prime(ctx)

	if cfg.CollectInterval > 0 {
		go collectLoop(ctx, svc, cfg.CollectInterval, log)
	}

	var searcher places.Searcher
	if cfg.PlacesAPIKey != "" {
		searcher = places.NewGoogleClient(cfg.PlacesAPIKey, "")
	} else {
		log.Warn("GOOGLE_PLACES_API_KEY is empty; branch search disabled")
	}
	placeSvc := places.NewService(searcher, cfg.PlacesDailyCap, nil).WithObserver(metrics)
	metrics.RegisterPlacesDailyCalls(placeSvc.CallsToday, cfg.PlacesDailyCap)

	api := httpapi.New(svc, httpapi.Options{InternalToken: cfg.InternalToken, Metrics: metrics, Log: log, Places: placeSvc})
	metricsApp := httpapi.NewMetricsApp(metrics)

	errCh := make(chan error, 2)
	go func() { errCh <- api.Listen(":" + cfg.Port) }()
	go func() { errCh <- metricsApp.Listen(":" + cfg.MetricsPort) }()
	log.Info("listening", "port", cfg.Port, "metrics_port", cfg.MetricsPort,
		"store", map[bool]string{true: "postgres", false: "memory"}[cfg.DatabaseURL != ""],
		"collect_interval", cfg.CollectInterval.String())

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
		log.Info("shutting down")
		_ = metricsApp.ShutdownWithTimeout(5 * time.Second)
		return api.ShutdownWithTimeout(10 * time.Second)
	}
}

// collectLoop is the in-cluster scheduler: it runs once at startup and then
// every interval. Each run makes at most a few upstream calls (it stops at the
// date already stored), well under the API's daily limit.
func collectLoop(ctx context.Context, svc *rates.Service, every time.Duration, log *slog.Logger) {
	t := time.NewTicker(every)
	defer t.Stop()
	for {
		cctx, cancel := context.WithTimeout(ctx, time.Minute)
		if _, err := svc.Collect(cctx); err != nil {
			log.Warn("scheduled collection failed", "err", err)
		}
		cancel()
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
	}
}
