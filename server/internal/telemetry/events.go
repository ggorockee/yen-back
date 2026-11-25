package telemetry

// AllowedEvents is the allowlist for POST /v1/events. It must match the app's
// AppEvent enum (mobile/lib/services/analytics.dart). Unknown names are
// rejected rather than recorded, which keeps label cardinality fixed.
var AllowedEvents = map[string]bool{
	"app_open":             true,
	"item_added":           true,
	"shop_created":         true,
	"receipt_added":        true,
	"departure_set":        true,
	"checklist_completed":  true,
	"remove_ads_purchased": true,
	"onboarding_completed": true,
	"branch_picked":        true,
	"receipt_scanned":      true,
	"receipt_scan_empty":   true,
	"update_prompt_shown":  true,
	"force_update_shown":   true,
	"update_accepted":      true,
	"update_dismissed":     true,
}

const (
	// MaxEventsPerBatch bounds one request; the app sends at most one entry per event name.
	MaxEventsPerBatch = 20
	// MaxEventCount bounds a single entry's count so a bad client cannot skew totals.
	MaxEventCount = 500
)
