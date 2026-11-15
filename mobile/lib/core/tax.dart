/// Whether an entered yen amount already includes consumption tax.
enum PriceMode {
  inclTax('incl', '세금 포함'),
  exclTax('excl', '세전');

  const PriceMode(this.code, this.label);
  final String code;
  final String label;

  static PriceMode fromCode(String? code) => values.firstWhere((m) => m.code == code, orElse: () => inclTax);
}

/// Pre-tax, tax and tax-inclusive amounts in whole yen.
class PriceBreakdown {
  const PriceBreakdown({required this.exclTax, required this.tax, required this.inclTax});

  final int exclTax;
  final int tax;
  final int inclTax;

  static const zero = PriceBreakdown(exclTax: 0, tax: 0, inclTax: 0);

  /// Splits [amountYen] at [ratePct].
  ///
  /// Rounding (stores differ, so this is an approximation):
  /// - pre-tax input: tax is rounded down, the most common practice.
  /// - tax-inclusive input: the pre-tax amount is rounded down, which keeps the
  ///   5,000-yen eligibility check conservative (never overstates).
  factory PriceBreakdown.from(int amountYen, PriceMode mode, int ratePct) {
    if (amountYen <= 0) return zero;
    switch (mode) {
      case PriceMode.exclTax:
        final tax = amountYen * ratePct ~/ 100;
        return PriceBreakdown(exclTax: amountYen, tax: tax, inclTax: amountYen + tax);
      case PriceMode.inclTax:
        final excl = amountYen * 100 ~/ (100 + ratePct);
        return PriceBreakdown(exclTax: excl, tax: amountYen - excl, inclTax: amountYen);
    }
  }

  PriceBreakdown operator +(PriceBreakdown o) =>
      PriceBreakdown(exclTax: exclTax + o.exclTax, tax: tax + o.tax, inclTax: inclTax + o.inclTax);
}
