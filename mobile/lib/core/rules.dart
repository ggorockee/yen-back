/// Tax-free (Japan) and duty-free (Korea) figures.
///
/// The defaults ship with the app so it works offline on first launch; the
/// server's `/v1/rules` overrides them so a regulation change does not need an
/// app release.
class TaxFreeRules {
  const TaxFreeRules({
    required this.version,
    required this.effectiveFrom,
    required this.minPurchaseExclTaxYen,
    required this.customsDeadlineDays,
    required this.standardTaxRatePct,
    required this.reducedTaxRatePct,
    required this.koreaDutyFreeUsd,
    this.notice = '',
    this.sources = const [],
  });

  final String version;
  final DateTime effectiveFrom;

  /// Minimum pre-tax total at one store on one day to qualify for a refund.
  final int minPurchaseExclTaxYen;

  /// Customs confirmation must happen within this many days of purchase.
  final int customsDeadlineDays;
  final int standardTaxRatePct;

  /// Reduced rate for food and beverages.
  final int reducedTaxRatePct;

  /// Korean per-person allowance, excluding alcohol, tobacco and perfume.
  final int koreaDutyFreeUsd;
  final String notice;
  final List<RuleSource> sources;

  static final defaults = TaxFreeRules(
    version: '2026-11-01',
    effectiveFrom: DateTime(2026, 11, 1),
    minPurchaseExclTaxYen: 5000,
    customsDeadlineDays: 90,
    standardTaxRatePct: 10,
    reducedTaxRatePct: 8,
    koreaDutyFreeUsd: 800,
    sources: const [
      RuleSource('일본 관광청 - 리펀드 방식 안내', 'https://www.mlit.go.jp/kankocho/tax-free/page01_000001_00028.html'),
      RuleSource(
        '일본 국세청 - 면세 제도 팸플릿',
        'https://www.nta.go.jp/publication/pamph/shohi/menzei/202506/pdf/0025006-106.pdf',
      ),
      RuleSource('일본 세관 - Tax refund', 'https://www.customs.go.jp/kaigairyoko/taxrefund_e.html'),
      RuleSource('한국 관세청 - 여행자 휴대품 면세', 'https://www.customs.go.kr'),
    ],
  );

  /// Parses the server payload, falling back to [defaults] per field so a
  /// partial or malformed response never breaks the app.
  factory TaxFreeRules.fromJson(Map<String, dynamic> j) {
    final d = defaults;
    int intOr(String k, int fallback) {
      final v = j[k];
      return v is num && v > 0 ? v.toInt() : fallback;
    }

    final sources =
        (j['sources'] as List?)
            ?.whereType<Map>()
            .map((s) => RuleSource('${s['title'] ?? ''}', '${s['url'] ?? ''}'))
            .where((s) => s.title.isNotEmpty && s.url.isNotEmpty)
            .toList() ??
        const <RuleSource>[];

    return TaxFreeRules(
      version: j['version'] is String ? j['version'] as String : d.version,
      effectiveFrom: DateTime.tryParse('${j['effective_from']}') ?? d.effectiveFrom,
      minPurchaseExclTaxYen: intOr('min_purchase_excl_tax_yen', d.minPurchaseExclTaxYen),
      customsDeadlineDays: intOr('customs_deadline_days', d.customsDeadlineDays),
      standardTaxRatePct: intOr('standard_tax_rate_pct', d.standardTaxRatePct),
      reducedTaxRatePct: intOr('reduced_tax_rate_pct', d.reducedTaxRatePct),
      koreaDutyFreeUsd: intOr('korea_duty_free_usd', d.koreaDutyFreeUsd),
      notice: j['notice'] is String ? j['notice'] as String : '',
      sources: sources.isEmpty ? d.sources : sources,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'effective_from':
        '${effectiveFrom.year.toString().padLeft(4, '0')}-${effectiveFrom.month.toString().padLeft(2, '0')}-${effectiveFrom.day.toString().padLeft(2, '0')}',
    'min_purchase_excl_tax_yen': minPurchaseExclTaxYen,
    'customs_deadline_days': customsDeadlineDays,
    'standard_tax_rate_pct': standardTaxRatePct,
    'reduced_tax_rate_pct': reducedTaxRatePct,
    'korea_duty_free_usd': koreaDutyFreeUsd,
    'notice': notice,
    'sources': [
      for (final s in sources) {'title': s.title, 'url': s.url},
    ],
  };
}

class RuleSource {
  const RuleSource(this.title, this.url);
  final String title;
  final String url;
}
