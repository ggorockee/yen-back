package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/ggorockee/yen-back/server/internal/rates"
)

type fakeService struct {
	snap       rates.Snapshot
	ok         bool
	err        error
	collected  int
	collectErr error
	pingErr    error
}

func (f *fakeService) Latest(context.Context) (rates.Snapshot, bool, error) {
	return f.snap, f.ok, f.err
}

func (f *fakeService) Collect(context.Context) (rates.CollectResult, error) {
	f.collected++
	return rates.CollectResult{Status: "updated", BaseDate: f.snap.BaseDate, Calls: 1}, f.collectErr
}

func (f *fakeService) IsStale(rates.Snapshot) bool { return false }

func (f *fakeService) Ping(context.Context) error { return f.pingErr }

func do(t *testing.T, svc RateService, token string, req *http.Request) (*http.Response, string) {
	t.Helper()
	resp, err := New(svc, Options{InternalToken: token}).Test(req)
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(resp.Body)
	return resp, string(body)
}

func TestLatest(t *testing.T) {
	svc := &fakeService{ok: true, snap: rates.Snapshot{
		BaseDate:  time.Date(2026, 11, 13, 0, 0, 0, 0, time.UTC),
		FetchedAt: time.Date(2026, 11, 13, 2, 12, 0, 0, time.UTC),
		Source:    "koreaexim",
		Rates:     map[string]rates.Rate{"JPY": {KRWPerUnit: 9.2135, Raw: "921.35", Unit: 100}},
	}}
	resp, body := do(t, svc, "", httptest.NewRequest(http.MethodGet, "/v1/rates/latest", nil))
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d body = %s", resp.StatusCode, body)
	}
	var got LatestResponse
	if err := json.Unmarshal([]byte(body), &got); err != nil {
		t.Fatal(err)
	}
	if got.BaseDate != "2026-11-13" || got.Rates["JPY"].KRWPerUnit != 9.2135 {
		t.Errorf("got %+v", got)
	}
	if resp.Header.Get("Cache-Control") == "" {
		t.Error("missing Cache-Control")
	}
}

func TestLatestEmptyAndError(t *testing.T) {
	for name, svc := range map[string]*fakeService{
		"empty": {ok: false},
		"error": {err: errors.New("db down")},
	} {
		resp, _ := do(t, svc, "", httptest.NewRequest(http.MethodGet, "/v1/rates/latest", nil))
		if resp.StatusCode != http.StatusServiceUnavailable {
			t.Errorf("%s: status = %d, want 503", name, resp.StatusCode)
		}
	}
}

func TestRules(t *testing.T) {
	resp, body := do(t, &fakeService{}, "", httptest.NewRequest(http.MethodGet, "/v1/rules", nil))
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d", resp.StatusCode)
	}
	var got map[string]any
	_ = json.Unmarshal([]byte(body), &got)
	if got["min_purchase_excl_tax_yen"] != float64(5000) || got["korea_duty_free_usd"] != float64(800) {
		t.Errorf("rules = %s", body)
	}
}

func TestInternalCollectAuth(t *testing.T) {
	newReq := func(token string) *http.Request {
		r := httptest.NewRequest(http.MethodPost, "/internal/collect", nil)
		if token != "" {
			r.Header.Set("X-Internal-Token", token)
		}
		return r
	}

	svc := &fakeService{}
	if resp, _ := do(t, svc, "", newReq("anything")); resp.StatusCode != http.StatusNotFound {
		t.Errorf("disabled: status = %d, want 404", resp.StatusCode)
	}
	if resp, _ := do(t, svc, "secret", newReq("wrong")); resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("wrong token: status = %d, want 401", resp.StatusCode)
	}
	if svc.collected != 0 {
		t.Fatal("collect ran without auth")
	}
	if resp, body := do(t, svc, "secret", newReq("secret")); resp.StatusCode != http.StatusOK {
		t.Errorf("ok: status = %d body = %s", resp.StatusCode, body)
	}
	if svc.collected != 1 {
		t.Errorf("collected = %d", svc.collected)
	}

	failing := &fakeService{collectErr: errors.New("upstream")}
	if resp, _ := do(t, failing, "secret", newReq("secret")); resp.StatusCode != http.StatusBadGateway {
		t.Errorf("upstream error: status = %d, want 502", resp.StatusCode)
	}
}
