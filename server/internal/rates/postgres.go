package rates

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const schema = `
CREATE TABLE IF NOT EXISTS exchange_rates (
	base_date    date        NOT NULL,
	currency     text        NOT NULL,
	krw_per_unit numeric(18,6) NOT NULL,
	raw_value    text        NOT NULL,
	unit         integer     NOT NULL,
	source       text        NOT NULL,
	fetched_at   timestamptz NOT NULL,
	PRIMARY KEY (base_date, currency)
);
CREATE TABLE IF NOT EXISTS collector_runs (
	id      bigserial   PRIMARY KEY,
	run_at  timestamptz NOT NULL DEFAULT now(),
	status  text        NOT NULL,
	message text        NOT NULL
);`

// PostgresStore is a Store backed by PostgreSQL.
type PostgresStore struct {
	pool *pgxpool.Pool
}

// NewPostgresStore connects and creates the tables if they do not exist.
func NewPostgresStore(ctx context.Context, dsn string) (*PostgresStore, error) {
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		return nil, fmt.Errorf("postgres: connect: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("postgres: ping: %w", err)
	}
	if _, err := pool.Exec(ctx, schema); err != nil {
		pool.Close()
		return nil, fmt.Errorf("postgres: migrate: %w", err)
	}
	return &PostgresStore{pool: pool}, nil
}

// Close releases the connection pool.
func (p *PostgresStore) Close() { p.pool.Close() }

func (p *PostgresStore) Save(ctx context.Context, s Snapshot) error {
	return pgx.BeginFunc(ctx, p.pool, func(tx pgx.Tx) error {
		for code, r := range s.Rates {
			_, err := tx.Exec(ctx, `
				INSERT INTO exchange_rates (base_date, currency, krw_per_unit, raw_value, unit, source, fetched_at)
				VALUES ($1, $2, $3, $4, $5, $6, $7)
				ON CONFLICT (base_date, currency) DO UPDATE SET
					krw_per_unit = EXCLUDED.krw_per_unit,
					raw_value    = EXCLUDED.raw_value,
					unit         = EXCLUDED.unit,
					source       = EXCLUDED.source,
					fetched_at   = EXCLUDED.fetched_at`,
				s.BaseDate, code, r.KRWPerUnit, r.Raw, r.Unit, s.Source, s.FetchedAt)
			if err != nil {
				return fmt.Errorf("postgres: save %s: %w", code, err)
			}
		}
		return nil
	})
}

func (p *PostgresStore) Latest(ctx context.Context) (Snapshot, bool, error) {
	// max() over an empty table yields NULL, hence the pointer.
	var base *time.Time
	if err := p.pool.QueryRow(ctx, `SELECT max(base_date) FROM exchange_rates`).Scan(&base); err != nil {
		return Snapshot{}, false, fmt.Errorf("postgres: latest date: %w", err)
	}
	if base == nil {
		return Snapshot{}, false, nil
	}

	rows, err := p.pool.Query(ctx, `
		SELECT currency, krw_per_unit::float8, raw_value, unit, source, fetched_at
		FROM exchange_rates WHERE base_date = $1`, *base)
	if err != nil {
		return Snapshot{}, false, fmt.Errorf("postgres: latest rows: %w", err)
	}
	defer rows.Close()

	s := Snapshot{BaseDate: *base, Rates: map[string]Rate{}}
	for rows.Next() {
		var code string
		var r Rate
		var fetched time.Time
		if err := rows.Scan(&code, &r.KRWPerUnit, &r.Raw, &r.Unit, &s.Source, &fetched); err != nil {
			return Snapshot{}, false, err
		}
		if fetched.After(s.FetchedAt) {
			s.FetchedAt = fetched
		}
		s.Rates[code] = r
	}
	return s, true, rows.Err()
}

func (p *PostgresStore) Ping(ctx context.Context) error { return p.pool.Ping(ctx) }

func (p *PostgresStore) RecordRun(ctx context.Context, status, message string) error {
	_, err := p.pool.Exec(ctx, `INSERT INTO collector_runs (status, message) VALUES ($1, $2)`, status, message)
	return err
}
