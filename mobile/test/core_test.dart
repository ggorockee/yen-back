import 'package:flutter_test/flutter_test.dart';
import 'package:yen_back/core/rules.dart';
import 'package:yen_back/core/tax.dart';
import 'package:yen_back/core/trip_summary.dart';
import 'package:yen_back/data/models.dart';

Item item(
  int price, {
  int qty = 1,
  PriceMode mode = PriceMode.inclTax,
  int rate = 10,
  ItemCategory cat = ItemCategory.general,
}) => Item(
  id: 0,
  shopId: 1,
  name: 'x',
  unitPriceYen: price,
  quantity: qty,
  priceMode: mode,
  taxRatePct: rate,
  category: cat,
);

ShopEntry shop(DateTime date, {List<Item> items = const [], List<Receipt> receipts = const []}) => ShopEntry(
  shop: Shop(id: 1, tripId: 1, name: '돈키호테', purchaseDate: date),
  items: items,
  receipts: receipts,
);

final rules = TaxFreeRules.defaults;
final nov15 = DateTime(2026, 11, 15);

void main() {
  group('PriceBreakdown', () {
    test('tax-inclusive input splits exactly at 10%', () {
      final b = PriceBreakdown.from(1100, PriceMode.inclTax, 10);
      expect([b.exclTax, b.tax, b.inclTax], [1000, 100, 1100]);
    });

    test('tax-inclusive input rounds pre-tax down (conservative)', () {
      final b = PriceBreakdown.from(1000, PriceMode.inclTax, 10);
      expect([b.exclTax, b.tax, b.inclTax], [909, 91, 1000]);
    });

    test('pre-tax input rounds tax down', () {
      final b = PriceBreakdown.from(999, PriceMode.exclTax, 10);
      expect([b.exclTax, b.tax, b.inclTax], [999, 99, 1098]);
    });

    test('reduced 8% rate', () {
      final b = PriceBreakdown.from(1080, PriceMode.inclTax, 8);
      expect([b.exclTax, b.tax], [1000, 80]);
    });

    test('zero and negative are zero', () {
      expect(PriceBreakdown.from(0, PriceMode.inclTax, 10).inclTax, 0);
      expect(PriceBreakdown.from(-5, PriceMode.exclTax, 10).inclTax, 0);
    });
  });

  group('ShopTotals', () {
    test('below threshold shows remaining amount and no refund', () {
      final t = computeShopTotals(shop(nov15, items: [item(3300)]), rules);
      expect(t.amounts.exclTax, 3000);
      expect(t.eligible, isFalse);
      expect(t.remainingYen, 2000);
      expect(t.refundYen, 0);
      expect(t.progress, closeTo(0.6, 1e-9));
    });

    test('exactly 5,000 pre-tax qualifies; general and consumables combine', () {
      final t = computeShopTotals(shop(nov15, items: [item(3300), item(2160, rate: 8)]), rules);
      expect(t.amounts.exclTax, 5000);
      expect(t.eligible, isTrue);
      expect(t.remainingYen, 0);
      expect(t.refundYen, 300 + 160);
    });

    test('quantity multiplies the line', () {
      final t = computeShopTotals(shop(nov15, items: [item(1100, qty: 5)]), rules);
      expect(t.amounts.inclTax, 5500);
      expect(t.eligible, isTrue);
    });

    test('receipts override item estimates', () {
      final t = computeShopTotals(
        shop(nov15, items: [item(1000)], receipts: [const Receipt(id: 1, shopId: 1, totalInclYen: 6600, taxYen: 600)]),
        rules,
      );
      expect(t.fromReceipts, isTrue);
      expect(t.amounts.exclTax, 6000);
      expect(t.refundYen, 600);
    });

    test('customs deadline counts purchase day as day 1', () {
      final t = computeShopTotals(shop(nov15), rules);
      expect(t.customsDeadline, DateTime(2027, 2, 12)); // Nov 15 + 89 days
    });

    test('restricted categories are excluded from the general allowance', () {
      final t = computeShopTotals(
        shop(
          nov15,
          items: [
            item(11000),
            item(5500, cat: ItemCategory.alcohol),
          ],
        ),
        rules,
      );
      expect(t.restrictedInclYen, 5500);
      expect(t.generalInclYen, 11000);
    });
  });

  group('TripSummary', () {
    final rates = RateSnapshot(baseDate: DateTime(2026, 11, 13), jpyKrw: 9.0, usdKrw: 1400, stale: false);

    test('sums refunds of eligible shops only', () {
      final s = computeTripSummary(
        entries: [
          shop(nov15, items: [item(5500)]), // eligible, tax 500
          shop(nov15, items: [item(1100)]), // not eligible
        ],
        rules: rules,
        departureAt: DateTime(2026, 11, 18, 14),
        rates: rates,
      );
      expect(s.refundYen, 500);
      expect(s.eligibleCount, 1);
      expect(s.totalInclYen, 6600);
    });

    test('flags the Korean duty-free allowance in USD', () {
      // 130,000 yen * 9 / 1400 = 835.7 USD > 800
      final s = computeTripSummary(
        entries: [
          shop(nov15, items: [item(130000)]),
        ],
        rules: rules,
        departureAt: null,
        rates: rates,
      );
      expect(s.generalUsd, closeTo(835.71, 0.01));
      expect(s.overDutyFreeLimit, isTrue);
    });

    test('no rates means no USD figure and no warning', () {
      final s = computeTripSummary(
        entries: [
          shop(nov15, items: [item(500000)]),
        ],
        rules: rules,
        departureAt: null,
      );
      expect(s.generalUsd, isNull);
      expect(s.overDutyFreeLimit, isFalse);
    });

    test('lists eligible shops whose deadline passes before departure', () {
      final s = computeTripSummary(
        entries: [
          shop(DateTime(2026, 11, 1), items: [item(5500)]),
        ],
        rules: rules,
        departureAt: DateTime(2027, 2, 1, 9), // deadline 2027-01-29
      );
      expect(s.deadlineMissed, hasLength(1));
    });

    test('days until departure uses calendar days', () {
      final s = computeTripSummary(entries: const [], rules: rules, departureAt: DateTime(2026, 11, 17, 0, 30));
      expect(s.daysUntilDeparture(DateTime(2026, 11, 15, 23, 59)), 2);
    });
  });

  group('TaxFreeRules.fromJson', () {
    test('reads server values', () {
      final r = TaxFreeRules.fromJson({
        'version': '2027-04-01',
        'effective_from': '2026-11-01',
        'min_purchase_excl_tax_yen': 10000,
        'customs_deadline_days': 60,
        'korea_duty_free_usd': 1000,
        'notice': '공지',
      });
      expect(r.version, '2027-04-01');
      expect(r.minPurchaseExclTaxYen, 10000);
      expect(r.customsDeadlineDays, 60);
      expect(r.koreaDutyFreeUsd, 1000);
      expect(r.standardTaxRatePct, 10); // missing -> default
      expect(r.notice, '공지');
      expect(r.sources, isNotEmpty); // missing -> default sources
    });

    test('ignores invalid values', () {
      final r = TaxFreeRules.fromJson({'min_purchase_excl_tax_yen': -1, 'customs_deadline_days': 'x'});
      expect(r.minPurchaseExclTaxYen, 5000);
      expect(r.customsDeadlineDays, 90);
    });

    test('round-trips through toJson', () {
      final r = TaxFreeRules.fromJson(TaxFreeRules.defaults.toJson());
      expect(r.effectiveFrom, DateTime(2026, 11, 1));
      expect(r.sources.length, TaxFreeRules.defaults.sources.length);
    });
  });

  group('RateSnapshot', () {
    test('parses server JSON and converts', () {
      final r = RateSnapshot.fromJson({
        'base_date': '2026-11-13',
        'stale': false,
        'rates': {
          'JPY': {'krw_per_unit': 9.2135, 'raw': '921.35', 'unit': 100},
          'USD': {'krw_per_unit': 1388.5, 'raw': '1,388.5', 'unit': 1},
        },
      });
      expect(r.yenToWon(1000), 9214);
      expect(RateSnapshot.fromJson(r.toJson()).jpyKrw, 9.2135);
    });

    test('rejects missing rates', () {
      expect(
        () => RateSnapshot.fromJson({
          'base_date': '2026-11-13',
          'rates': {
            'JPY': {'krw_per_unit': 0},
          },
        }),
        throwsA(anything),
      );
    });
  });
}
