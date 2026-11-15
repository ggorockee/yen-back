import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yen_back/core/tax.dart';
import 'package:yen_back/data/app_database.dart';
import 'package:yen_back/data/models.dart';
import 'package:yen_back/data/remote_repository.dart';
import 'package:yen_back/services/ads.dart';
import 'package:yen_back/services/analytics.dart';
import 'package:yen_back/services/notification_service.dart';

void main() {
  sqfliteFfiInit();

  group('AppDatabase', () {
    late AppDatabase db;
    setUp(() async => db = await AppDatabase.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi));
    tearDown(() => db.close());

    test('starts with one active trip', () async {
      final trip = await db.trip();
      expect(trip.id, AppDatabase.activeTripId);
      expect(trip.departureAt, isNull);
    });

    test('saves departure', () async {
      final dep = DateTime(2026, 11, 18, 14, 30);
      await db.saveTrip((await db.trip()).copyWith(departureAt: dep, airport: 'KIX'));
      final t = await db.trip();
      expect(t.departureAt, dep);
      expect(t.airport, 'KIX');
    });

    test('shops, items and receipts round-trip; delete cascades', () async {
      final shopId = await db.addShop('돈키호테', DateTime(2026, 11, 15));
      await db.addItem(
        shopId: shopId,
        name: '곤약젤리',
        unitPriceYen: 1100,
        quantity: 3,
        priceMode: PriceMode.inclTax,
        taxRatePct: 8,
        category: ItemCategory.general,
      );
      await db.addReceipt(shopId: shopId, totalInclYen: 3300, taxYen: 244, imageFile: 'r.jpg');

      var entries = await db.entries();
      expect(entries, hasLength(1));
      expect(entries.first.shop.purchaseDate, DateTime(2026, 11, 15));
      expect(entries.first.items.single.quantity, 3);
      expect(entries.first.items.single.taxRatePct, 8);
      expect(entries.first.receipts.single.imageFile, 'r.jpg');

      final files = await db.deleteShop(shopId);
      expect(files, ['r.jpg']);
      entries = await db.entries();
      expect(entries, isEmpty);
    });

    test('orders shops newest first', () async {
      await db.addShop('A', DateTime(2026, 11, 14));
      await db.addShop('B', DateTime(2026, 11, 16));
      expect((await db.entries()).map((e) => e.shop.name), ['B', 'A']);
    });

    test('checklist toggles', () async {
      await db.setChecked('passport', true);
      await db.setChecked('kiosk_before_checkin', true);
      await db.setChecked('passport', false);
      expect(await db.checkedItems(), {'kiosk_before_checkin'});
    });
  });

  group('RemoteRepository', () {
    const ratesBody = {
      'base_date': '2026-11-13',
      'stale': false,
      'rates': {
        'JPY': {'krw_per_unit': 9.2135},
        'USD': {'krw_per_unit': 1388.5},
      },
    };

    test('caches rates and serves them offline', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final online = RemoteRepository(
        prefs,
        baseUrl: 'http://x',
        client: MockClient((_) async => http.Response(jsonEncode(ratesBody), 200)),
      );
      expect((await online.fetchRates()).jpyKrw, 9.2135);

      final offline = RemoteRepository(
        prefs,
        baseUrl: 'http://x',
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      await expectLater(offline.fetchRates(), throwsA(isA<http.ClientException>()));
      expect(offline.cachedRates()?.baseDate, DateTime(2026, 11, 13));
    });

    test('non-200 is an error and leaves cache intact', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = RemoteRepository(
        prefs,
        baseUrl: 'http://x',
        client: MockClient((_) async => http.Response('{"error":"x"}', 503)),
      );
      await expectLater(repo.fetchRates(), throwsA(anything));
      expect(repo.cachedRates(), isNull);
      expect(repo.cachedRules().minPurchaseExclTaxYen, 5000); // bundled defaults
    });

    test('rules from server are cached', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = RemoteRepository(
        prefs,
        baseUrl: 'http://x',
        client: MockClient((_) async => http.Response(jsonEncode({'min_purchase_excl_tax_yen': 6000}), 200)),
      );
      await repo.fetchRules();
      expect(repo.cachedRules().minPurchaseExclTaxYen, 6000);
    });
  });

  group('InterstitialPolicy', () {
    final start = DateTime(2026, 11, 15, 12);

    test('respects warmup, gap and session cap', () {
      final p = InterstitialPolicy(sessionStart: start);
      expect(p.canShow(start.add(const Duration(seconds: 30))), isFalse, reason: 'warmup');

      final t1 = start.add(const Duration(minutes: 2));
      expect(p.canShow(t1), isTrue);
      p.recordShown(t1);
      expect(p.canShow(t1.add(const Duration(minutes: 1))), isFalse, reason: 'gap');

      final t2 = t1.add(const Duration(minutes: 3));
      expect(p.canShow(t2), isTrue);
      p.recordShown(t2);
      expect(p.canShow(t2.add(const Duration(hours: 1))), isFalse, reason: 'cap');
    });
  });

  group('NotificationService.remindersFor', () {
    test('evening before at 20:00 and 3 hours before departure', () {
      final r = NotificationService.remindersFor(DateTime(2026, 12, 1, 10, 30));
      expect(r.map((e) => e.at), [DateTime(2026, 11, 30, 20), DateTime(2026, 12, 1, 7, 30)]);
      expect(r.map((e) => e.id).toSet(), hasLength(2));
    });
  });

  group('Analytics', () {
    test('batches counts and sends app headers', () async {
      http.Request? sent;
      final client = AppHttpClient(
        MockClient((req) async {
          sent = req;
          return http.Response('', 202);
        }),
        appVersion: '1.0.0',
      );
      final a = Analytics(client, baseUrl: 'http://x', flushAfter: const Duration(hours: 1))
        ..track(AppEvent.itemAdded)
        ..track(AppEvent.itemAdded)
        ..track(AppEvent.appOpen);
      await a.flush();

      expect(sent!.url.path, '/v1/events');
      expect(sent!.headers['X-App-Version'], '1.0.0');
      expect(sent!.headers['X-App-Platform'], isNotEmpty);
      final events = (jsonDecode(sent!.body) as Map)['events'] as List;
      expect(
        events,
        containsAll([
          {'name': 'item_added', 'count': 2},
          {'name': 'app_open', 'count': 1},
        ]),
      );

      sent = null;
      await a.flush(); // nothing pending
      expect(sent, isNull);
    });

    test('failures are swallowed', () async {
      final a = Analytics(MockClient((_) async => throw http.ClientException('offline')), baseUrl: 'http://x')
        ..track(AppEvent.appOpen);
      await a.flush();
    });
  });
}
