// Package koreaexim is a client for the Korea Eximbank exchange-rate Open API.
//
// The API publishes rates once per business day around 11:00 KST. On
// non-business days, or before the daily publication, it returns an empty
// array (the spec says null; both are handled). Callers must treat an empty
// result as "no data for that date", not as an error.
package koreaexim

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/cookiejar"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// DefaultBaseURL is the request endpoint after the domain migration to oapi.koreaexim.go.kr.
const DefaultBaseURL = "https://oapi.koreaexim.go.kr/site/program/financial/exchangeJSON"

// ErrEmpty is returned when the API has no data for the requested date.
var ErrEmpty = errors.New("koreaexim: no data for date")

// Rate is one currency entry normalized to KRW per 1 unit of the currency.
type Rate struct {
	Currency   string  // ISO code, e.g. "JPY"
	Unit       int     // quoting unit used by the API, e.g. 100 for JPY(100)
	Raw        string  // deal_bas_r as returned by the API, e.g. "921.35"
	KRWPerUnit float64 // KRW for 1 unit of the currency
}

// Client fetches rates. It is safe for concurrent use.
type Client struct {
	baseURL string
	authKey string
	http    *http.Client
}

// New creates a client. baseURL may be empty to use DefaultBaseURL.
func New(baseURL, authKey string) *Client {
	if baseURL == "" {
		baseURL = DefaultBaseURL
	}
	// The API has been observed to redirect with a session cookie; a jar keeps
	// the redirect loop from failing.
	jar, _ := cookiejar.New(nil)
	return &Client{
		baseURL: baseURL,
		authKey: authKey,
		http:    &http.Client{Timeout: 10 * time.Second, Jar: jar},
	}
}

type apiItem struct {
	Result   int    `json:"result"`
	CurUnit  string `json:"cur_unit"`
	DealBasR string `json:"deal_bas_r"`
}

// Fetch returns the rates for the given date (interpreted as a KST calendar
// date) filtered to the requested currencies. It returns ErrEmpty when the API
// has no data for that date, or when any requested currency is missing.
func (c *Client) Fetch(ctx context.Context, date time.Time, currencies ...string) (map[string]Rate, error) {
	if c.authKey == "" {
		return nil, errors.New("koreaexim: auth key is not configured")
	}
	q := url.Values{}
	q.Set("authkey", c.authKey)
	q.Set("searchdate", date.Format("20060102"))
	q.Set("data", "AP01")

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"?"+q.Encode(), nil)
	if err != nil {
		return nil, err
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("koreaexim: request failed: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("koreaexim: unexpected status %d", resp.StatusCode)
	}

	var items []apiItem
	if err := json.NewDecoder(resp.Body).Decode(&items); err != nil {
		return nil, fmt.Errorf("koreaexim: decode: %w", err)
	}
	return parseItems(items, currencies)
}

func parseItems(items []apiItem, currencies []string) (map[string]Rate, error) {
	if len(items) == 0 {
		return nil, ErrEmpty
	}
	want := make(map[string]bool, len(currencies))
	for _, c := range currencies {
		want[c] = true
	}

	out := make(map[string]Rate, len(currencies))
	for _, it := range items {
		switch it.Result {
		case 1:
		case 2:
			return nil, errors.New("koreaexim: invalid data code (result=2)")
		case 3:
			// Keys are destroyed when the 2-year personal-data retention period
			// lapses without re-consent; a destroyed key cannot be reused.
			return nil, errors.New("koreaexim: invalid auth key (result=3); the key may have expired after 2 years without re-consent, apply for a new key")
		case 4:
			return nil, errors.New("koreaexim: daily request limit exceeded (result=4)")
		default:
			return nil, fmt.Errorf("koreaexim: api error (result=%d)", it.Result)
		}
		code, unit := parseCurUnit(it.CurUnit)
		if !want[code] {
			continue
		}
		v, err := strconv.ParseFloat(strings.ReplaceAll(it.DealBasR, ",", ""), 64)
		if err != nil || v <= 0 {
			return nil, fmt.Errorf("koreaexim: invalid deal_bas_r %q for %s", it.DealBasR, it.CurUnit)
		}
		out[code] = Rate{Currency: code, Unit: unit, Raw: it.DealBasR, KRWPerUnit: v / float64(unit)}
	}
	for c := range want {
		if _, ok := out[c]; !ok {
			return nil, ErrEmpty
		}
	}
	return out, nil
}

// parseCurUnit splits "JPY(100)" into ("JPY", 100) and "USD" into ("USD", 1).
func parseCurUnit(s string) (string, int) {
	s = strings.TrimSpace(s)
	open := strings.IndexByte(s, '(')
	if open < 0 || !strings.HasSuffix(s, ")") {
		return s, 1
	}
	n, err := strconv.Atoi(s[open+1 : len(s)-1])
	if err != nil || n <= 0 {
		return s[:open], 1
	}
	return s[:open], n
}
