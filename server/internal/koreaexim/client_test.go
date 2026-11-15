package koreaexim

import (
	"context"
	"errors"
	"math"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestParseCurUnit(t *testing.T) {
	cases := []struct {
		in   string
		code string
		unit int
	}{
		{"JPY(100)", "JPY", 100},
		{"USD", "USD", 1},
		{"IDR(100)", "IDR", 100},
		{" EUR ", "EUR", 1},
	}
	for _, c := range cases {
		code, unit := parseCurUnit(c.in)
		if code != c.code || unit != c.unit {
			t.Errorf("parseCurUnit(%q) = %q,%d want %q,%d", c.in, code, unit, c.code, c.unit)
		}
	}
}

func TestFetch(t *testing.T) {
	var gotQuery string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotQuery = r.URL.RawQuery
		_, _ = w.Write([]byte(`[
			{"result":1,"cur_unit":"JPY(100)","deal_bas_r":"921.35"},
			{"result":1,"cur_unit":"USD","deal_bas_r":"1,388.5"},
			{"result":1,"cur_unit":"EUR","deal_bas_r":"1,500"}
		]`))
	}))
	defer srv.Close()

	c := New(srv.URL, "key")
	date := time.Date(2026, 11, 13, 0, 0, 0, 0, time.UTC)
	rates, err := c.Fetch(context.Background(), date, "JPY", "USD")
	if err != nil {
		t.Fatal(err)
	}
	if len(rates) != 2 {
		t.Fatalf("got %d rates, want 2", len(rates))
	}
	if got := rates["JPY"].KRWPerUnit; math.Abs(got-9.2135) > 1e-9 {
		t.Errorf("JPY = %v, want 9.2135", got)
	}
	if got := rates["USD"].KRWPerUnit; got != 1388.5 {
		t.Errorf("USD = %v, want 1388.5", got)
	}
	if want := "authkey=key&data=AP01&searchdate=20261113"; gotQuery != want {
		t.Errorf("query = %q, want %q", gotQuery, want)
	}
}

func TestFetchEmpty(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`[]`))
	}))
	defer srv.Close()

	_, err := New(srv.URL, "key").Fetch(context.Background(), time.Now(), "JPY")
	if !errors.Is(err, ErrEmpty) {
		t.Fatalf("err = %v, want ErrEmpty", err)
	}
}

func TestFetchAPIError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`[{"result":3,"cur_unit":"","deal_bas_r":""}]`))
	}))
	defer srv.Close()

	_, err := New(srv.URL, "bad").Fetch(context.Background(), time.Now(), "JPY")
	if err == nil || errors.Is(err, ErrEmpty) {
		t.Fatalf("err = %v, want auth error", err)
	}
}

func TestFetchMissingCurrencyIsEmpty(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`[{"result":1,"cur_unit":"USD","deal_bas_r":"1,388.5"}]`))
	}))
	defer srv.Close()

	_, err := New(srv.URL, "key").Fetch(context.Background(), time.Now(), "JPY", "USD")
	if !errors.Is(err, ErrEmpty) {
		t.Fatalf("err = %v, want ErrEmpty", err)
	}
}

func TestFetchWithoutKey(t *testing.T) {
	if _, err := New("", "").Fetch(context.Background(), time.Now(), "JPY"); err == nil {
		t.Fatal("expected error without auth key")
	}
}
