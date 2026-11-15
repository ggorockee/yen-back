import '../data/models.dart';
import 'rules.dart';
import 'tax.dart';

/// Refund status of one store visit.
class ShopTotals {
  const ShopTotals({
    required this.entry,
    required this.amounts,
    required this.fromReceipts,
    required this.restrictedInclYen,
    required this.minPurchaseExclTaxYen,
    required this.customsDeadline,
  });

  final ShopEntry entry;

  /// Totals from receipts when any exist (actual amounts), else from items.
  final PriceBreakdown amounts;
  final bool fromReceipts;

  /// Tax-inclusive total of alcohol, tobacco and perfume items.
  final int restrictedInclYen;
  final int minPurchaseExclTaxYen;

  /// Last day to get customs confirmation, counting the purchase day as day 1
  /// (the conservative reading; official texts differ on the start day).
  final DateTime customsDeadline;

  bool get eligible => amounts.exclTax >= minPurchaseExclTaxYen;
  int get remainingYen => eligible ? 0 : minPurchaseExclTaxYen - amounts.exclTax;
  double get progress => (amounts.exclTax / minPurchaseExclTaxYen).clamp(0.0, 1.0);

  /// Refund before operator fees; zero when the threshold is not met.
  int get refundYen => eligible ? amounts.tax : 0;

  /// Purchase amount counted against the general Korean USD allowance.
  int get generalInclYen {
    final v = amounts.inclTax - restrictedInclYen;
    return v < 0 ? 0 : v;
  }
}

ShopTotals computeShopTotals(ShopEntry entry, TaxFreeRules rules) {
  final restricted = entry.items
      .where((i) => i.category != ItemCategory.general)
      .fold(0, (sum, i) => sum + i.breakdown.inclTax);

  final PriceBreakdown amounts;
  final fromReceipts = entry.receipts.isNotEmpty;
  if (fromReceipts) {
    amounts = entry.receipts.fold(
      PriceBreakdown.zero,
      (sum, r) => sum + PriceBreakdown(exclTax: r.totalInclYen - r.taxYen, tax: r.taxYen, inclTax: r.totalInclYen),
    );
  } else {
    amounts = entry.items.fold(PriceBreakdown.zero, (sum, i) => sum + i.breakdown);
  }

  final d = entry.shop.purchaseDate;
  return ShopTotals(
    entry: entry,
    amounts: amounts,
    fromReceipts: fromReceipts,
    restrictedInclYen: restricted,
    minPurchaseExclTaxYen: rules.minPurchaseExclTaxYen,
    customsDeadline: DateTime(d.year, d.month, d.day + rules.customsDeadlineDays - 1),
  );
}

/// Everything the dashboard shows for a trip.
class TripSummary {
  const TripSummary({required this.shops, required this.dutyFreeLimitUsd, required this.departureAt, this.rates});

  final List<ShopTotals> shops;
  final int dutyFreeLimitUsd;
  final DateTime? departureAt;
  final RateSnapshot? rates;

  int get totalInclYen => shops.fold(0, (s, t) => s + t.amounts.inclTax);
  int get refundYen => shops.fold(0, (s, t) => s + t.refundYen);
  int get eligibleCount => shops.where((t) => t.eligible).length;
  int get restrictedInclYen => shops.fold(0, (s, t) => s + t.restrictedInclYen);
  int get generalInclYen => shops.fold(0, (s, t) => s + t.generalInclYen);

  /// General purchases in USD, or null without rates.
  double? get generalUsd => rates?.yenToUsd(generalInclYen);
  bool get overDutyFreeLimit => (generalUsd ?? 0) > dutyFreeLimitUsd;

  /// Eligible shops whose customs deadline passes before departure; their tax
  /// cannot be refunded on this departure.
  List<ShopTotals> get deadlineMissed {
    final dep = departureAt;
    if (dep == null) return const [];
    final depDay = DateTime(dep.year, dep.month, dep.day);
    return shops.where((t) => t.eligible && depDay.isAfter(t.customsDeadline)).toList();
  }

  /// Calendar days until departure (0 = today), or null when unset.
  int? daysUntilDeparture(DateTime now) {
    final dep = departureAt;
    if (dep == null) return null;
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(dep.year, dep.month, dep.day).difference(today).inDays;
  }
}

TripSummary computeTripSummary({
  required List<ShopEntry> entries,
  required TaxFreeRules rules,
  required DateTime? departureAt,
  RateSnapshot? rates,
}) => TripSummary(
  shops: [for (final e in entries) computeShopTotals(e, rules)],
  dutyFreeLimitUsd: rules.koreaDutyFreeUsd,
  departureAt: departureAt,
  rates: rates,
);
