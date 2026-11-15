import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/rules.dart';
import '../core/store_catalog.dart';
import '../core/tax.dart';
import '../core/trip_summary.dart';
import '../data/app_database.dart';
import '../data/models.dart';
import '../data/receipt_files.dart';
import '../data/remote_repository.dart';
import '../services/ads.dart';
import '../services/analytics.dart';
import '../services/notification_service.dart';
import '../services/purchase_service.dart';

// Dependencies created in main() and injected with overrides.

final prefsProvider = Provider<SharedPreferences>((_) => throw UnimplementedError());
final databaseProvider = Provider<AppDatabase>((_) => throw UnimplementedError());
final receiptFilesProvider = Provider<ReceiptFiles>((_) => throw UnimplementedError());
final notificationsProvider = Provider<NotificationService>((_) => throw UnimplementedError());

final remoteRepositoryProvider = Provider<RemoteRepository>(
  (ref) => RemoteRepository(ref.watch(prefsProvider), client: ref.watch(httpClientProvider)),
);

/// Preloads only for users who see ads; ad-free users never request one.
final interstitialProvider = Provider<InterstitialController>((ref) {
  final c = InterstitialController(InterstitialPolicy(sessionStart: DateTime.now()));
  if (!ref.read(adFreeProvider)) c.preload();
  return c;
});

// Preferences

class OnboardingNotifier extends Notifier<bool> {
  static const _key = 'onboarding.done';

  @override
  bool build() => ref.watch(prefsProvider).getBool(_key) ?? false;

  Future<void> complete() async {
    await ref.read(prefsProvider).setBool(_key, true);
    state = true;
  }
}

final onboardingDoneProvider = NotifierProvider<OnboardingNotifier, bool>(OnboardingNotifier.new);

class AdFreeNotifier extends Notifier<bool> {
  static const _key = 'purchase.ad_free';

  @override
  bool build() => ref.watch(prefsProvider).getBool(_key) ?? false;

  Future<void> grant() async {
    await ref.read(prefsProvider).setBool(_key, true);
    state = true;
  }
}

final adFreeProvider = NotifierProvider<AdFreeNotifier, bool>(AdFreeNotifier.new);

// Remote data with offline cache

class RulesNotifier extends Notifier<TaxFreeRules> {
  @override
  TaxFreeRules build() {
    final repo = ref.watch(remoteRepositoryProvider);
    Future.microtask(refresh);
    return repo.cachedRules();
  }

  Future<void> refresh() async {
    try {
      final rules = await ref.read(remoteRepositoryProvider).fetchRules();
      if (ref.mounted) state = rules;
    } catch (_) {
      // Keep cached or bundled rules.
    }
  }
}

final rulesProvider = NotifierProvider<RulesNotifier, TaxFreeRules>(RulesNotifier.new);

class RatesState {
  const RatesState({this.snapshot, this.loading = false, this.offline = false});

  /// Last good snapshot (from the server or the cache), null on first launch offline.
  final RateSnapshot? snapshot;
  final bool loading;

  /// The last refresh failed; [snapshot] may be old.
  final bool offline;
}

class RatesNotifier extends Notifier<RatesState> {
  @override
  RatesState build() {
    final cached = ref.watch(remoteRepositoryProvider).cachedRates();
    Future.microtask(refresh);
    return RatesState(snapshot: cached, loading: true);
  }

  Future<void> refresh() async {
    state = RatesState(snapshot: state.snapshot, loading: true);
    try {
      final snap = await ref.read(remoteRepositoryProvider).fetchRates();
      if (ref.mounted) state = RatesState(snapshot: snap);
    } catch (_) {
      if (ref.mounted) state = RatesState(snapshot: state.snapshot, offline: true);
    }
  }
}

final ratesProvider = NotifierProvider<RatesNotifier, RatesState>(RatesNotifier.new);

// Local trip data

class TripNotifier extends AsyncNotifier<Trip> {
  @override
  Future<Trip> build() => ref.watch(databaseProvider).trip();

  Future<void> save(Trip trip) async {
    await ref.read(databaseProvider).saveTrip(trip);
    await ref.read(notificationsProvider).scheduleDeparture(trip.departureAt);
    state = AsyncData(trip);
  }
}

final tripProvider = AsyncNotifierProvider<TripNotifier, Trip>(TripNotifier.new);

class EntriesNotifier extends AsyncNotifier<List<ShopEntry>> {
  AppDatabase get _db => ref.read(databaseProvider);

  @override
  Future<List<ShopEntry>> build() => ref.watch(databaseProvider).entries();

  Future<void> _reload() async => state = AsyncData(await _db.entries());

  Future<int> addShop(String name, DateTime date) async {
    final id = await _db.addShop(name, date);
    await _reload();
    return id;
  }

  Future<void> updateShop(int id, String name, DateTime date) async {
    await _db.updateShop(id, name, date);
    await _reload();
  }

  Future<void> deleteShop(int id) async {
    final files = await _db.deleteShop(id);
    await ref.read(receiptFilesProvider).delete(files);
    await _reload();
  }

  Future<void> addItem({
    required int shopId,
    required String name,
    required int unitPriceYen,
    int quantity = 1,
    required PriceMode priceMode,
    required int taxRatePct,
    ItemCategory category = ItemCategory.general,
  }) async {
    await _db.addItem(
      shopId: shopId,
      name: name,
      unitPriceYen: unitPriceYen,
      quantity: quantity,
      priceMode: priceMode,
      taxRatePct: taxRatePct,
      category: category,
    );
    await _reload();
  }

  Future<void> deleteItem(int id) async {
    await _db.deleteItem(id);
    await _reload();
  }

  Future<void> addReceipt({
    required int shopId,
    required int totalInclYen,
    required int taxYen,
    String? imageFile,
  }) async {
    await _db.addReceipt(shopId: shopId, totalInclYen: totalInclYen, taxYen: taxYen, imageFile: imageFile);
    await _reload();
  }

  Future<void> deleteReceipt(Receipt r) async {
    await _db.deleteReceipt(r.id);
    if (r.imageFile != null) await ref.read(receiptFilesProvider).delete([r.imageFile!]);
    await _reload();
  }
}

final entriesProvider = AsyncNotifierProvider<EntriesNotifier, List<ShopEntry>>(EntriesNotifier.new);

class ChecklistNotifier extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() => ref.watch(databaseProvider).checkedItems();

  Future<void> toggle(String key, bool done) async {
    await ref.read(databaseProvider).setChecked(key, done);
    final next = {...?state.value};
    done ? next.add(key) : next.remove(key);
    state = AsyncData(next);
  }
}

final checklistProvider = AsyncNotifierProvider<ChecklistNotifier, Set<String>>(ChecklistNotifier.new);

// Derived

final summaryProvider = Provider<AsyncValue<TripSummary>>((ref) {
  final trip = ref.watch(tripProvider);
  final entries = ref.watch(entriesProvider);
  final rules = ref.watch(rulesProvider);
  final rates = ref.watch(ratesProvider).snapshot;

  if (trip.hasError) return AsyncError(trip.error!, trip.stackTrace ?? StackTrace.current);
  if (entries.hasError) return AsyncError(entries.error!, entries.stackTrace ?? StackTrace.current);
  final t = trip.value;
  final e = entries.value;
  if (t == null || e == null) return const AsyncLoading();
  return AsyncData(computeTripSummary(entries: e, rules: rules, departureAt: t.departureAt, rates: rates));
});

/// Totals for one shop, or null if it no longer exists.
final shopTotalsProvider = Provider.family<ShopTotals?, int>((ref, shopId) {
  final summary = ref.watch(summaryProvider).value;
  if (summary == null) return null;
  for (final s in summary.shops) {
    if (s.entry.shop.id == shopId) return s;
  }
  return null;
});

/// App-wide purchase service; started in main() so pending purchases are
/// delivered even before the settings screen is opened.
final purchasesProvider = Provider<Purchases>((ref) {
  final p = StorePurchases(
    InAppPurchase.instance,
    onEntitled: () async {
      if (ref.read(adFreeProvider)) return false;
      await ref.read(adFreeProvider.notifier).grant();
      ref.read(analyticsProvider).track(AppEvent.removeAdsPurchased);
      return true;
    },
  );
  ref.onDispose(p.dispose);
  return p;
});

// Store catalog for the shop name field

/// The bundled assets/stores.json, loaded in main() for offline first launch.
final bundledStoresJsonProvider = Provider<String>((_) => '{"version":"","stores":[]}');

class StoreCatalogNotifier extends Notifier<StoreCatalog> {
  @override
  StoreCatalog build() {
    final repo = ref.watch(remoteRepositoryProvider);
    Future.microtask(refresh);
    for (final raw in [repo.cachedStoresJson(), ref.watch(bundledStoresJsonProvider)]) {
      if (raw == null) continue;
      try {
        final c = StoreCatalog.parse(raw);
        if (c.brands.isNotEmpty) return c;
      } catch (_) {
        // Fall through to the next source.
      }
    }
    return StoreCatalog.empty;
  }

  Future<void> refresh() async {
    try {
      final c = await ref.read(remoteRepositoryProvider).fetchStores();
      if (ref.mounted) state = c;
    } catch (_) {
      // Keep cached or bundled catalog.
    }
  }
}

final storeCatalogProvider = NotifierProvider<StoreCatalogNotifier, StoreCatalog>(StoreCatalogNotifier.new);

/// Distinct shop names the user has entered, most recent first.
final recentShopNamesProvider = Provider<List<String>>((ref) {
  final entries = ref.watch(entriesProvider).value ?? const <ShopEntry>[];
  final seen = <String>{};
  return [
    for (final e in entries)
      if (seen.add(e.shop.name)) e.shop.name,
  ];
});
