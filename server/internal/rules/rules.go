// Package rules holds the tax-free and duty-free figures the app relies on.
//
// They are served from the API so a regulation change only needs a server
// deploy, not an app release. Every figure must be re-checked against the
// official sources listed in Sources before changing Version.
package rules

// Source is an official reference for the figures.
type Source struct {
	Title string `json:"title"`
	URL   string `json:"url"`
}

// Rules is the payload of GET /v1/rules.
type Rules struct {
	Version string `json:"version"`

	// Japan refund method, effective for purchases from EffectiveFrom.
	EffectiveFrom         string   `json:"effective_from"`
	MinPurchaseExclTaxYen int      `json:"min_purchase_excl_tax_yen"` // same store, same day
	CustomsDeadlineDays   int      `json:"customs_deadline_days"`     // counted from purchase date
	StandardTaxRatePct    int      `json:"standard_tax_rate_pct"`
	ReducedTaxRatePct     int      `json:"reduced_tax_rate_pct"` // food and beverages
	KoreaDutyFreeUSD      int      `json:"korea_duty_free_usd"`  // per person, excludes alcohol/tobacco/perfume
	Notice                string   `json:"notice"`               // optional banner text shown in the app
	Sources               []Source `json:"sources"`
}

// Current is the rule set served today.
var Current = Rules{
	Version:               "2026-11-01",
	EffectiveFrom:         "2026-11-01",
	MinPurchaseExclTaxYen: 5000,
	CustomsDeadlineDays:   90,
	StandardTaxRatePct:    10,
	ReducedTaxRatePct:     8,
	KoreaDutyFreeUSD:      800,
	Sources: []Source{
		{Title: "일본 관광청 - 리펀드 방식 안내", URL: "https://www.mlit.go.jp/kankocho/tax-free/page01_000001_00028.html"},
		{Title: "일본 국세청 - 면세 제도 팸플릿", URL: "https://www.nta.go.jp/publication/pamph/shohi/menzei/202506/pdf/0025006-106.pdf"},
		{Title: "일본 세관 - Tax refund", URL: "https://www.customs.go.jp/kaigairyoko/taxrefund_e.html"},
		{Title: "한국 관세청 - 여행자 휴대품 면세", URL: "https://www.customs.go.kr"},
	},
}
