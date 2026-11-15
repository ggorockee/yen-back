package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/ggorockee/yen-back/server/internal/places"
	"github.com/ggorockee/yen-back/server/internal/telemetry"
)

type fakePlaces struct {
	got   string
	found []places.Place
	err   error
}

func (f *fakePlaces) Search(_ context.Context, q string, _, _ float64) ([]places.Place, error) {
	f.got = q
	return f.found, f.err
}

func placesReq(t *testing.T, p PlaceSearcher, url string) (int, string, http.Header) {
	t.Helper()
	app := New(&fakeService{}, Options{Metrics: telemetry.New("dev", "none", nil), Places: p})
	resp, err := app.Test(httptest.NewRequest(http.MethodGet, url, nil))
	if err != nil {
		t.Fatal(err)
	}
	b, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, string(b), resp.Header
}

func TestPlacesSearch(t *testing.T) {
	f := &fakePlaces{found: []places.Place{{ID: "x", Name: "돈키호테 도톤보리점", DistanceM: 150}}}
	code, body, h := placesReq(t, f, "/v1/places/search?q=%EB%8F%88%ED%82%A4%ED%98%B8%ED%85%8C&lat=34.6687&lng=135.5013")
	if code != http.StatusOK {
		t.Fatalf("status = %d body = %s", code, body)
	}
	if f.got != "돈키호테" {
		t.Errorf("query = %q", f.got)
	}
	var got struct {
		Places []places.Place `json:"places"`
	}
	_ = json.Unmarshal([]byte(body), &got)
	if len(got.Places) != 1 || got.Places[0].DistanceM != 150 {
		t.Errorf("body = %s", body)
	}
	if h.Get("Cache-Control") != "private, max-age=300" {
		t.Errorf("cache-control = %q", h.Get("Cache-Control"))
	}
}

func TestPlacesSearchErrors(t *testing.T) {
	ok := "/v1/places/search?q=x&lat=34.6&lng=135.5"
	cases := []struct {
		name string
		p    PlaceSearcher
		url  string
		want int
	}{
		{"disabled (nil)", nil, ok, http.StatusServiceUnavailable},
		{"missing lat", &fakePlaces{}, "/v1/places/search?q=x&lng=135.5", http.StatusBadRequest},
		{"invalid", &fakePlaces{err: places.ErrInvalid}, ok, http.StatusBadRequest},
		{"disabled", &fakePlaces{err: places.ErrDisabled}, ok, http.StatusServiceUnavailable},
		{"limited", &fakePlaces{err: places.ErrLimited}, ok, http.StatusTooManyRequests},
		{"upstream", &fakePlaces{err: errors.New("boom")}, ok, http.StatusBadGateway},
	}
	for _, c := range cases {
		// A typed nil interface is not nil; pass a real nil for the first case.
		var p PlaceSearcher
		if c.p != nil {
			p = c.p
		}
		if code, body, _ := placesReq(t, p, c.url); code != c.want {
			t.Errorf("%s: status = %d, want %d (%s)", c.name, code, c.want, body)
		}
	}
}
