// Package places finds nearby branches of a store chain via Google Places API
// (New) Text Search, so the app can show "돈키호테 도톤보리점 · 350m".
//
// Cost control: calls outside Japan never reach Google, and a daily cap (KST)
// stops upstream calls once reached; with the default of 160 a month stays
// inside the 5,000 free Text Search Pro calls. The app calls this once per
// shop added (when a chain is picked), not per keystroke.
//
// Terms: Google Maps Platform terms do not allow caching Places content such
// as names and addresses, so results are never cached or stored here. The
// user's location is used only for the request and never logged or stored.
package places

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/http"
	"sort"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

// DefaultBaseURL is the Places API (New) endpoint.
const DefaultBaseURL = "https://places.googleapis.com/v1/places:searchText"

var (
	// ErrDisabled means no API key is configured.
	ErrDisabled = errors.New("places: disabled (no API key)")
	// ErrLimited means the daily upstream cap was reached.
	ErrLimited = errors.New("places: daily limit reached")
	// ErrInvalid means the query or coordinates are malformed.
	ErrInvalid = errors.New("places: invalid query or location")
)

// Place is one branch, nearest first.
type Place struct {
	ID        string  `json:"id"`
	Name      string  `json:"name"`
	Address   string  `json:"address"`
	Lat       float64 `json:"lat"`
	Lng       float64 `json:"lng"`
	DistanceM int     `json:"distance_m"`
}

// Observer receives telemetry. Implemented by telemetry.Metrics.
type Observer interface {
	PlacesRequest(result string) // ok, limited, out_of_area, invalid, error, disabled
	PlacesUpstream(result string)
}

type nopObserver struct{}

func (nopObserver) PlacesRequest(string)  {}
func (nopObserver) PlacesUpstream(string) {}

// Searcher calls the upstream API. Separated for tests.
type Searcher interface {
	SearchText(ctx context.Context, query string, lat, lng float64) ([]Place, error)
}

// GoogleClient calls Places API (New) Text Search.
type GoogleClient struct {
	key     string
	baseURL string
	http    *http.Client
}

// NewGoogleClient returns a client; baseURL may be empty for the default.
func NewGoogleClient(key, baseURL string) *GoogleClient {
	if baseURL == "" {
		baseURL = DefaultBaseURL
	}
	return &GoogleClient{key: key, baseURL: baseURL, http: &http.Client{Timeout: 8 * time.Second}}
}

// searchRadiusM biases results to roughly walking/short-train distance.
const searchRadiusM = 3000.0

func (g *GoogleClient) SearchText(ctx context.Context, query string, lat, lng float64) ([]Place, error) {
	body, _ := json.Marshal(map[string]any{
		"textQuery":      query,
		"languageCode":   "ko",
		"regionCode":     "JP",
		"rankPreference": "DISTANCE",
		"pageSize":       10,
		"locationBias": map[string]any{
			"circle": map[string]any{
				"center": map[string]float64{"latitude": lat, "longitude": lng},
				"radius": searchRadiusM,
			},
		},
	})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, g.baseURL, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Goog-Api-Key", g.key)
	// Request only what the app shows; the field mask determines the billing SKU.
	req.Header.Set("X-Goog-FieldMask", "places.id,places.displayName,places.shortFormattedAddress,places.location")

	resp, err := g.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("places: request: %w", err)
	}
	defer resp.Body.Close()

	var out struct {
		Places []struct {
			ID          string `json:"id"`
			DisplayName struct {
				Text string `json:"text"`
			} `json:"displayName"`
			ShortFormattedAddress string `json:"shortFormattedAddress"`
			Location              struct {
				Latitude  float64 `json:"latitude"`
				Longitude float64 `json:"longitude"`
			} `json:"location"`
		} `json:"places"`
		Error *struct {
			Status  string `json:"status"`
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, fmt.Errorf("places: decode (status %d): %w", resp.StatusCode, err)
	}
	if resp.StatusCode != http.StatusOK || out.Error != nil {
		status := ""
		if out.Error != nil {
			status = out.Error.Status
		}
		return nil, fmt.Errorf("places: upstream status %d %s", resp.StatusCode, status)
	}

	places := make([]Place, 0, len(out.Places))
	for _, p := range out.Places {
		if p.DisplayName.Text == "" {
			continue
		}
		places = append(places, Place{
			ID: p.ID, Name: p.DisplayName.Text, Address: p.ShortFormattedAddress,
			Lat: p.Location.Latitude, Lng: p.Location.Longitude,
		})
	}
	return places, nil
}

// Service adds validation, the Japan check and the daily cap around a Searcher.
// It deliberately has no result cache (see the package comment).
type Service struct {
	searcher   Searcher
	dailyLimit int
	now        func() time.Time
	obs        Observer

	mu    sync.Mutex
	day   string
	calls int
}

// NewService returns a Service. A nil searcher disables search.
func NewService(s Searcher, dailyLimit int, now func() time.Time) *Service {
	if now == nil {
		now = time.Now
	}
	return &Service{
		searcher: s, dailyLimit: dailyLimit, now: now, obs: nopObserver{},
	}
}

// WithObserver sets the telemetry observer and returns s.
func (s *Service) WithObserver(o Observer) *Service {
	if o != nil {
		s.obs = o
	}
	return s
}

// CallsToday reports upstream calls made today (KST), for metrics.
func (s *Service) CallsToday() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.day != kstDay(s.now()) {
		return 0
	}
	return s.calls
}

// japanBoxes cover the main Japanese islands. A single bounding box would also
// contain the Korean peninsula, so regional boxes are used; Korea (and Jeju,
// Ulleungdo, Vladivostok, Taiwan) fall outside all of them.
var japanBoxes = [][4]float64{ // minLat, maxLat, minLng, maxLng
	{24.0, 28.6, 122.9, 131.4}, // Okinawa, Ryukyu islands
	{30.9, 34.0, 129.4, 132.1}, // Kyushu
	{32.7, 36.0, 130.8, 137.0}, // western Honshu, Shikoku
	{33.4, 41.6, 135.0, 142.1}, // central and eastern Honshu
	{41.3, 45.6, 139.3, 146.0}, // Hokkaido
}

// InJapan reports whether a coordinate is in Japan (approximately). Requests
// from elsewhere, e.g. planning at home in Korea, skip the paid API.
func InJapan(lat, lng float64) bool {
	for _, b := range japanBoxes {
		if lat >= b[0] && lat <= b[1] && lng >= b[2] && lng <= b[3] {
			return true
		}
	}
	return false
}

// Search returns branches matching query near (lat, lng), nearest first.
// Outside Japan it returns an empty list without calling upstream.
func (s *Service) Search(ctx context.Context, query string, lat, lng float64) ([]Place, error) {
	query = strings.TrimSpace(query)
	n := utf8.RuneCountInString(query)
	if n < 1 || n > 40 || math.IsNaN(lat) || math.IsNaN(lng) || math.Abs(lat) > 90 || math.Abs(lng) > 180 {
		s.obs.PlacesRequest("invalid")
		return nil, ErrInvalid
	}
	if s.searcher == nil {
		s.obs.PlacesRequest("disabled")
		return nil, ErrDisabled
	}
	if !InJapan(lat, lng) {
		s.obs.PlacesRequest("out_of_area")
		return []Place{}, nil
	}

	if !s.takeCall() {
		s.obs.PlacesRequest("limited")
		return nil, ErrLimited
	}

	places, err := s.searcher.SearchText(ctx, query, lat, lng)
	if err != nil {
		s.obs.PlacesUpstream("error")
		s.obs.PlacesRequest("error")
		return nil, err
	}
	s.obs.PlacesUpstream("ok")
	s.obs.PlacesRequest("ok")
	return withDistance(dedupe(places), lat, lng), nil
}

// takeCall reserves one upstream call under the daily (KST) cap.
func (s *Service) takeCall() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if d := kstDay(s.now()); d != s.day {
		s.day, s.calls = d, 0
	}
	if s.dailyLimit > 0 && s.calls >= s.dailyLimit {
		return false
	}
	s.calls++
	return true
}

var kst = time.FixedZone("KST", 9*60*60)

func kstDay(t time.Time) string { return t.In(kst).Format(time.DateOnly) }

// sameStoreM is the distance under which two results are treated as one store.
const sameStoreM = 30.0

// dedupe merges results within sameStoreM of each other; Google sometimes
// returns both "돈키호테" and "돈키호테 도톤보리점" a few meters apart. The more
// specific (longer) name wins. n is at most 10, so O(n^2) is fine.
func dedupe(in []Place) []Place {
	out := make([]Place, 0, len(in))
next:
	for _, p := range in {
		for i, q := range out {
			if haversineM(p.Lat, p.Lng, q.Lat, q.Lng) < sameStoreM {
				if utf8.RuneCountInString(p.Name) > utf8.RuneCountInString(q.Name) {
					out[i] = p
				}
				continue next
			}
		}
		out = append(out, p)
	}
	return out
}

// withDistance returns a copy with distances from the caller, nearest first.
func withDistance(in []Place, lat, lng float64) []Place {
	out := make([]Place, len(in))
	for i, p := range in {
		p.DistanceM = int(math.Round(haversineM(lat, lng, p.Lat, p.Lng)))
		out[i] = p
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].DistanceM < out[j].DistanceM })
	return out
}

func haversineM(lat1, lng1, lat2, lng2 float64) float64 {
	const r = 6371000.0
	rad := math.Pi / 180
	dLat := (lat2 - lat1) * rad
	dLng := (lng2 - lng1) * rad
	a := math.Sin(dLat/2)*math.Sin(dLat/2) + math.Cos(lat1*rad)*math.Cos(lat2*rad)*math.Sin(dLng/2)*math.Sin(dLng/2)
	return 2 * r * math.Asin(math.Sqrt(a))
}
