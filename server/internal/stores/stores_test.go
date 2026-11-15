package stores

import (
	"bytes"
	"os"
	"testing"
)

func TestLoad(t *testing.T) {
	c, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if c.Version == "" || len(c.Stores) < 10 {
		t.Fatalf("catalog looks empty: version=%q stores=%d", c.Version, len(c.Stores))
	}
}

// The app bundles the same file for offline first launch; they must not drift.
func TestMobileBundleMatches(t *testing.T) {
	mobile, err := os.ReadFile("../../../mobile/assets/stores.json")
	if err != nil {
		t.Skipf("mobile asset not available: %v", err)
	}
	if !bytes.Equal(bytes.TrimSpace(mobile), bytes.TrimSpace(raw)) {
		t.Fatal("mobile/assets/stores.json differs from server/internal/stores/stores.json; copy the server file to the app")
	}
}
