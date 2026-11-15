package places

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// Dotonbori, Osaka.
const lat, lng = 34.6687, 135.5013

type fakeSearcher struct {
	calls  int
	places []Place
	err    error
}

func (f *fakeSearcher) SearchText(context.Context, string, float64, float64) ([]Place, error) {
	f.calls++
	return f.places, f.err
}

var donki = []Place{
	{ID: "far", Name: "돈키호테 우에혼마치점", Lat: 34.6627, Lng: 135.5213},
	{ID: "a", Name: "돈키호테", Lat: 34.66941, Lng: 135.50268},
	{ID: "b", Name: "돈키호테 도톤보리점", Lat: 34.66935, Lng: 135.50264},
}

func TestSearchDedupesSortsAndComputesDistance(t *testing.T) {
	svc := NewService(&fakeSearcher{places: donki}, 100, nil)
	got, err := svc.Search(context.Background(), "돈키호테", lat, lng)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 {
		t.Fatalf("got %d places, want 2 (duplicate spot merged): %+v", len(got), got)
	}
	if got[0].Name != "돈키호테 도톤보리점" {
		t.Errorf("nearest = %q, want the specific branch name", got[0].Name)
	}
	if got[0].DistanceM < 50 || got[0].DistanceM > 300 {
		t.Errorf("distance = %dm, want roughly 150m", got[0].DistanceM)
	}
	if got[1].DistanceM <= got[0].DistanceM {
		t.Error("not sorted by distance")
	}
}

func TestSearchCachesPerArea(t *testing.T) {
	f := &fakeSearcher{places: donki}
	svc := NewService(f, 100, nil)
	ctx := context.Background()

	_, _ = svc.Search(ctx, "돈키호테", lat, lng)
	_, _ = svc.Search(ctx, " 돈키 호테 ", lat+0.001, lng+0.001) // same ~1km cell, spacing ignored
	if f.calls != 1 {
		t.Fatalf("upstream calls = %d, want 1 (cache hit)", f.calls)
	}
	_, _ = svc.Search(ctx, "돈키호테", lat+0.05, lng)
	if f.calls != 2 {
		t.Fatalf("upstream calls = %d, want 2 (different area)", f.calls)
	}
}

func TestSearchCacheExpires(t *testing.T) {
	now := time.Date(2026, 11, 15, 12, 0, 0, 0, time.UTC)
	f := &fakeSearcher{places: donki}
	svc := NewService(f, 100, func() time.Time { return now })
	_, _ = svc.Search(context.Background(), "돈키호테", lat, lng)
	now = now.Add(25 * time.Hour)
	_, _ = svc.Search(context.Background(), "돈키호테", lat, lng)
	if f.calls != 2 {
		t.Fatalf("calls = %d, want 2 after TTL", f.calls)
	}
}

func TestDailyLimitResetsAtKSTMidnight(t *testing.T) {
	now := time.Date(2026, 11, 15, 14, 0, 0, 0, time.UTC) // 23:00 KST
	f := &fakeSearcher{places: donki}
	svc := NewService(f, 2, func() time.Time { return now })
	ctx := context.Background()

	for i := range 2 {
		if _, err := svc.Search(ctx, "q", lat+float64(i), lng); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := svc.Search(ctx, "q", lat+0.5, lng); !errors.Is(err, ErrLimited) {
		t.Fatalf("err = %v, want ErrLimited", err)
	}
	if svc.CallsToday() != 2 {
		t.Errorf("CallsToday = %d", svc.CallsToday())
	}
	now = now.Add(2 * time.Hour) // 01:00 KST next day
	if _, err := svc.Search(ctx, "q", lat+0.5, lng); err != nil {
		t.Fatalf("after reset: %v", err)
	}
}

func TestOutsideJapanSkipsUpstream(t *testing.T) {
	f := &fakeSearcher{places: donki}
	got, err := NewService(f, 100, nil).Search(context.Background(), "돈키호테", 37.5665, 126.9780) // Seoul
	if err != nil || len(got) != 0 || f.calls != 0 {
		t.Fatalf("got=%v err=%v calls=%d", got, err, f.calls)
	}
}

func TestInvalidAndDisabled(t *testing.T) {
	svc := NewService(&fakeSearcher{}, 100, nil)
	for _, q := range []string{"", "   ", string(make([]rune, 41))} {
		if _, err := svc.Search(context.Background(), q, lat, lng); !errors.Is(err, ErrInvalid) {
			t.Errorf("query %q: err = %v, want ErrInvalid", q, err)
		}
	}
	if _, err := svc.Search(context.Background(), "q", 91, lng); !errors.Is(err, ErrInvalid) {
		t.Errorf("bad lat: err = %v", err)
	}
	if _, err := NewService(nil, 100, nil).Search(context.Background(), "q", lat, lng); !errors.Is(err, ErrDisabled) {
		t.Errorf("nil searcher: err = %v", err)
	}
}

func TestUpstreamErrorNotCached(t *testing.T) {
	f := &fakeSearcher{err: errors.New("boom")}
	svc := NewService(f, 100, nil)
	_, _ = svc.Search(context.Background(), "q", lat, lng)
	f.err, f.places = nil, donki
	if got, err := svc.Search(context.Background(), "q", lat, lng); err != nil || len(got) == 0 {
		t.Fatalf("got=%v err=%v", got, err)
	}
}

func TestGoogleClientRequestAndParse(t *testing.T) {
	var gotBody map[string]any
	var gotHeaders http.Header
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotHeaders = r.Header
		b, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(b, &gotBody)
		_, _ = w.Write([]byte(`{"places":[{"id":"x","displayName":{"text":"돈키호테 도톤보리점","languageCode":"ko"},
			"shortFormattedAddress":"7-13 Souemonchō","location":{"latitude":34.6693,"longitude":135.5026}},
			{"id":"empty","displayName":{"text":""}}]}`))
	}))
	defer srv.Close()

	got, err := NewGoogleClient("k", srv.URL).SearchText(context.Background(), "돈키호테", lat, lng)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0].Name != "돈키호테 도톤보리점" || got[0].Address != "7-13 Souemonchō" {
		t.Fatalf("got %+v", got)
	}
	if gotHeaders.Get("X-Goog-Api-Key") != "k" || gotHeaders.Get("X-Goog-FieldMask") == "" {
		t.Errorf("headers = %v", gotHeaders)
	}
	if gotBody["languageCode"] != "ko" || gotBody["rankPreference"] != "DISTANCE" {
		t.Errorf("body = %v", gotBody)
	}
}

func TestGoogleClientUpstreamError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusForbidden)
		_, _ = w.Write([]byte(`{"error":{"code":403,"status":"PERMISSION_DENIED","message":"no"}}`))
	}))
	defer srv.Close()
	if _, err := NewGoogleClient("k", srv.URL).SearchText(context.Background(), "q", lat, lng); err == nil {
		t.Fatal("expected error")
	}
}

func TestInJapan(t *testing.T) {
	in := map[string][2]float64{
		"Tokyo": {35.6812, 139.7671}, "Osaka": {34.6687, 135.5013}, "Kyoto": {35.0116, 135.7681},
		"Fukuoka": {33.5902, 130.4017}, "Sapporo": {43.0618, 141.3545}, "Naha": {26.2124, 127.6809},
		"Hiroshima": {34.3853, 132.4553}, "Kanazawa": {36.5613, 136.6562}, "Nagasaki": {32.7503, 129.8779},
	}
	out := map[string][2]float64{
		"Seoul": {37.5665, 126.9780}, "Busan": {35.1796, 129.0756}, "Jeju": {33.4996, 126.5312},
		"Ulleungdo": {37.4845, 130.9058}, "Vladivostok": {43.1155, 131.8855}, "Taipei": {25.0330, 121.5654},
		"Shanghai": {31.2304, 121.4737},
	}
	for name, c := range in {
		if !InJapan(c[0], c[1]) {
			t.Errorf("%s should be in Japan", name)
		}
	}
	for name, c := range out {
		if InJapan(c[0], c[1]) {
			t.Errorf("%s should be outside Japan", name)
		}
	}
}
