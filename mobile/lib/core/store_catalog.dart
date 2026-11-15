import 'dart:convert';

/// A tax-free store chain from the server's `/v1/stores` (bundled offline copy
/// in assets/stores.json). Branch names are typed by the user after picking.
class StoreBrand {
  const StoreBrand({
    required this.id,
    required this.ko,
    this.ja = '',
    this.en = '',
    this.category = '',
    this.aliases = const [],
  });

  final String id;
  final String ko;
  final String ja;
  final String en;
  final String category;
  final List<String> aliases;

  factory StoreBrand.fromJson(Map<String, dynamic> j) => StoreBrand(
    id: '${j['id'] ?? ''}',
    ko: '${j['ko'] ?? ''}',
    ja: '${j['ja'] ?? ''}',
    en: '${j['en'] ?? ''}',
    category: '${j['category'] ?? ''}',
    aliases: [for (final a in (j['aliases'] as List? ?? const [])) '$a'],
  );
}

/// One suggestion in the shop name field: a shop the user visited before, or
/// a chain from the catalog.
class ShopSuggestion {
  const ShopSuggestion.recent(this.name) : brand = null;
  ShopSuggestion.brand(StoreBrand this.brand) : name = brand.ko;

  final String name;
  final StoreBrand? brand;
  bool get isRecent => brand == null;
}

class StoreCatalog {
  const StoreCatalog({required this.version, required this.brands});

  final String version;
  final List<StoreBrand> brands;

  static const empty = StoreCatalog(version: '', brands: []);

  /// Parses the catalog JSON; entries without an id or Korean name are skipped.
  factory StoreCatalog.parse(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return StoreCatalog(
      version: '${j['version'] ?? ''}',
      brands: [
        for (final s in (j['stores'] as List? ?? const []))
          if (s is Map<String, dynamic>) StoreBrand.fromJson(s),
      ].where((b) => b.id.isNotEmpty && b.ko.isNotEmpty).toList(),
    );
  }

  /// Suggestions for [query]. With an empty query: recent shops first, then the
  /// catalog in its curated (popularity) order, so the list appears instantly
  /// on focus. With a query: matches ranked by where they match.
  List<ShopSuggestion> suggest(String query, {List<String> recent = const [], int limit = 12}) {
    final q = normalize(query);
    final out = <ShopSuggestion>[];
    final seen = <String>{};

    void add(ShopSuggestion s) {
      if (out.length < limit && seen.add(normalize(s.name))) out.add(s);
    }

    if (q.isEmpty) {
      for (final r in recent) {
        add(ShopSuggestion.recent(r));
      }
      for (final b in brands) {
        add(ShopSuggestion.brand(b));
      }
      return out;
    }

    // Rank: 0 = Korean name prefix, 1 = any name/alias prefix, 2 = contains.
    final ranked = <(int, int, ShopSuggestion)>[];
    for (final (i, r) in recent.indexed) {
      final n = normalize(r);
      if (n.startsWith(q)) {
        ranked.add((0, i, ShopSuggestion.recent(r)));
      } else if (n.contains(q)) {
        ranked.add((2, i, ShopSuggestion.recent(r)));
      }
    }
    for (final (i, b) in brands.indexed) {
      final ko = normalize(b.ko);
      final others = [b.ja, b.en, ...b.aliases].map(normalize).where((s) => s.isNotEmpty);
      final int rank;
      if (ko.startsWith(q)) {
        rank = 0;
      } else if (others.any((s) => s.startsWith(q))) {
        rank = 1;
      } else if (ko.contains(q) || others.any((s) => s.contains(q))) {
        rank = 2;
      } else {
        continue;
      }
      // Brands sort after recent shops of the same rank.
      ranked.add((rank, recent.length + i, ShopSuggestion.brand(b)));
    }
    ranked.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    for (final r in ranked) {
      add(r.$3);
    }
    return out;
  }

  /// Lowercase and strip spaces and separators so "Don Quijote", "돈 키호테"
  /// and "ドン・キホーテ" match their stored forms.
  static String normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s・\-_.·@]'), '');
}

/// A branch near the user, from the server's `/v1/places/search`.
class NearbyBranch {
  const NearbyBranch({required this.name, required this.address, required this.distanceM});

  final String name;
  final String address;
  final int distanceM;

  factory NearbyBranch.fromJson(Map<String, dynamic> j) => NearbyBranch(
    name: '${j['name'] ?? ''}',
    address: '${j['address'] ?? ''}',
    distanceM: (j['distance_m'] as num?)?.toInt() ?? 0,
  );

  /// "140m" under 1km, else "1.9km".
  String get distanceLabel => distanceM < 1000 ? '${distanceM}m' : '${(distanceM / 1000).toStringAsFixed(1)}km';
}
