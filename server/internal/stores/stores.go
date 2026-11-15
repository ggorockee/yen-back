// Package stores serves the curated list of Japanese tax-free store chains
// the app offers when the user adds a shop. Editing stores.json and deploying
// the server updates every app without a release.
package stores

import (
	_ "embed"
	"encoding/json"
	"fmt"
)

//go:embed stores.json
var raw []byte

// Store is one chain. Branch names are typed by the user after picking it.
type Store struct {
	ID       string   `json:"id"`
	Ko       string   `json:"ko"`
	Ja       string   `json:"ja"`
	En       string   `json:"en"`
	Category string   `json:"category"`
	Aliases  []string `json:"aliases"`
}

// Catalog is the payload of GET /v1/stores.
type Catalog struct {
	Version string  `json:"version"`
	Note    string  `json:"note"`
	Stores  []Store `json:"stores"`
}

// Raw returns the embedded JSON as served.
func Raw() []byte { return raw }

// Load parses and validates the embedded catalog.
func Load() (Catalog, error) {
	var c Catalog
	if err := json.Unmarshal(raw, &c); err != nil {
		return c, fmt.Errorf("stores: parse: %w", err)
	}
	seen := map[string]bool{}
	for i, s := range c.Stores {
		if s.ID == "" || s.Ko == "" {
			return c, fmt.Errorf("stores: entry %d missing id or ko name", i)
		}
		if seen[s.ID] {
			return c, fmt.Errorf("stores: duplicate id %q", s.ID)
		}
		seen[s.ID] = true
	}
	return c, nil
}
