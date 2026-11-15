// Package config loads settings from environment variables.
package config

import (
	"fmt"
	"os"
	"strconv"
	"time"
)

// Config is the server configuration.
type Config struct {
	Port            string        // PORT, default 8080
	KoreaEximAPIKey string        // KOREAEXIM_API_KEY, required to collect
	KoreaEximURL    string        // KOREAEXIM_URL, optional override of the endpoint
	DatabaseURL     string        // DATABASE_URL, empty = in-memory store
	InternalToken   string        // INTERNAL_TOKEN, empty = /internal disabled
	CollectInterval time.Duration // COLLECT_INTERVAL, e.g. "30m"; 0 = rely on an external scheduler
	MetricsPort     string        // METRICS_PORT, default 9090; serves /metrics only
	LogLevel        string        // LOG_LEVEL: debug, info (default), warn, error
	PlacesAPIKey    string        // GOOGLE_PLACES_API_KEY, empty = branch search disabled
	PlacesDailyCap  int           // PLACES_DAILY_LIMIT, default 160 billable calls per KST day (160 x 31 < 5,000 free/month)
}

// Load reads the configuration from the environment.
func Load() (Config, error) {
	c := Config{
		Port:            getenv("PORT", "8080"),
		KoreaEximAPIKey: os.Getenv("KOREAEXIM_API_KEY"),
		KoreaEximURL:    os.Getenv("KOREAEXIM_URL"),
		DatabaseURL:     os.Getenv("DATABASE_URL"),
		InternalToken:   os.Getenv("INTERNAL_TOKEN"),
		MetricsPort:     getenv("METRICS_PORT", "9090"),
		LogLevel:        getenv("LOG_LEVEL", "info"),
		PlacesAPIKey:    os.Getenv("GOOGLE_PLACES_API_KEY"),
		PlacesDailyCap:  160,
	}
	if v := os.Getenv("PLACES_DAILY_LIMIT"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil || n < 0 {
			return c, fmt.Errorf("PLACES_DAILY_LIMIT must be a non-negative integer, got %q", v)
		}
		c.PlacesDailyCap = n
	}
	if c.MetricsPort == c.Port {
		return c, fmt.Errorf("METRICS_PORT must differ from PORT (%s)", c.Port)
	}
	if v := os.Getenv("COLLECT_INTERVAL"); v != "" {
		d, err := time.ParseDuration(v)
		if err != nil || d < time.Minute {
			return c, fmt.Errorf("COLLECT_INTERVAL must be a duration of at least 1m, got %q", v)
		}
		c.CollectInterval = d
	}
	return c, nil
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
