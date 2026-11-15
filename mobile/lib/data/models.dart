import '../core/tax.dart';

/// Korean customs treats these separately from the general USD allowance.
enum ItemCategory {
  general('general', '일반'),
  alcohol('alcohol', '술'),
  tobacco('tobacco', '담배'),
  perfume('perfume', '향수');

  const ItemCategory(this.code, this.label);
  final String code;
  final String label;

  static ItemCategory fromCode(String? code) => values.firstWhere((c) => c.code == code, orElse: () => general);
}

/// A trip. The MVP keeps a single active trip.
class Trip {
  const Trip({required this.id, required this.name, this.departureAt, this.airport = ''});

  final int id;
  final String name;
  final DateTime? departureAt;
  final String airport;

  Trip copyWith({String? name, DateTime? departureAt, bool clearDeparture = false, String? airport}) => Trip(
    id: id,
    name: name ?? this.name,
    departureAt: clearDeparture ? null : (departureAt ?? this.departureAt),
    airport: airport ?? this.airport,
  );
}

/// One store visit on one day: the unit the 5,000-yen rule applies to.
class Shop {
  const Shop({required this.id, required this.tripId, required this.name, required this.purchaseDate});

  final int id;
  final int tripId;
  final String name;

  /// Calendar date (time is midnight local).
  final DateTime purchaseDate;
}

class Item {
  const Item({
    required this.id,
    required this.shopId,
    required this.name,
    required this.unitPriceYen,
    required this.quantity,
    required this.priceMode,
    required this.taxRatePct,
    required this.category,
  });

  final int id;
  final int shopId;
  final String name;
  final int unitPriceYen;
  final int quantity;
  final PriceMode priceMode;
  final int taxRatePct;
  final ItemCategory category;

  PriceBreakdown get breakdown => PriceBreakdown.from(unitPriceYen * quantity, priceMode, taxRatePct);
}

class Receipt {
  const Receipt({
    required this.id,
    required this.shopId,
    required this.totalInclYen,
    required this.taxYen,
    this.imageFile,
  });

  final int id;
  final int shopId;

  /// File name inside the app's receipts directory. Only the name is stored
  /// because the iOS container path changes between app updates.
  final String? imageFile;
  final int totalInclYen;
  final int taxYen;
}

/// A shop with its line items and receipts.
class ShopEntry {
  const ShopEntry({required this.shop, this.items = const [], this.receipts = const []});
  final Shop shop;
  final List<Item> items;
  final List<Receipt> receipts;
}

/// Exchange rates for one business day, normalized to KRW per 1 unit.
class RateSnapshot {
  const RateSnapshot({required this.baseDate, required this.jpyKrw, required this.usdKrw, required this.stale});

  final DateTime baseDate;
  final double jpyKrw;
  final double usdKrw;
  final bool stale;

  /// Parses the server's `/v1/rates/latest` body.
  factory RateSnapshot.fromJson(Map<String, dynamic> j) {
    final rates = j['rates'] as Map<String, dynamic>;
    double rate(String code) {
      final v = (rates[code] as Map<String, dynamic>)['krw_per_unit'];
      if (v is! num || v <= 0) throw FormatException('invalid $code rate');
      return v.toDouble();
    }

    return RateSnapshot(
      baseDate: DateTime.parse(j['base_date'] as String),
      jpyKrw: rate('JPY'),
      usdKrw: rate('USD'),
      stale: j['stale'] == true,
    );
  }

  /// Serialized in the same shape as the server so one parser serves both.
  Map<String, dynamic> toJson() => {
    'base_date':
        '${baseDate.year.toString().padLeft(4, '0')}-${baseDate.month.toString().padLeft(2, '0')}-${baseDate.day.toString().padLeft(2, '0')}',
    'stale': stale,
    'rates': {
      'JPY': {'krw_per_unit': jpyKrw},
      'USD': {'krw_per_unit': usdKrw},
    },
  };

  int yenToWon(int yen) => (yen * jpyKrw).round();
  double yenToUsd(int yen) => yen * jpyKrw / usdKrw;
}
