import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yen_back/app.dart';
import 'package:yen_back/data/app_database.dart';
import 'package:yen_back/data/receipt_files.dart';
import 'package:yen_back/services/analytics.dart';
import 'package:yen_back/services/location_service.dart';
import 'package:yen_back/services/notification_service.dart';
import 'package:yen_back/state/providers.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('onboarding → calculator → add item to a new shop', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await initializeDateFormatting('ko_KR');
    // Ad-free so the test never touches the AdMob platform channel.
    SharedPreferences.setMockInitialValues({'purchase.ad_free': true});
    final prefs = await SharedPreferences.getInstance();
    final db = await tester.runAsync(
      () => AppDatabase.open(path: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate),
    );
    final events = <String>[];
    final searches = <String>[];

    final client = MockClient((req) async {
      switch (req.url.path) {
        case '/v1/rates/latest':
          return http.Response(
            jsonEncode({
              'base_date': '2026-11-13',
              'stale': false,
              'rates': {
                'JPY': {'krw_per_unit': 9.0},
                'USD': {'krw_per_unit': 1400.0},
              },
            }),
            200,
          );
        case '/v1/places/search':
          searches.add(req.url.queryParameters['q'] ?? '');
          return http.Response(
            jsonEncode({
              'places': [
                {'id': 'a', 'name': '돈키호테 도톤보리점', 'address': '7-13 Souemoncho', 'distance_m': 140},
                {'id': 'b', 'name': '돈키호테 난바센니치마에점', 'address': '12-7 Nanbasennichimae', 'distance_m': 1949},
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        case '/v1/events':
          events.add(req.body);
          return http.Response('', 202);
        default:
          return http.Response('{}', 200);
      }
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(db!),
          receiptFilesProvider.overrideWithValue(ReceiptFiles(Directory.systemTemp)),
          notificationsProvider.overrideWithValue(NotificationService(FlutterLocalNotificationsPlugin())),
          bundledStoresJsonProvider.overrideWithValue(File('assets/stores.json').readAsStringSync()),
          httpClientProvider.overrideWithValue(client),
          locationServiceProvider.overrideWithValue(_FakeLocation()),
        ],
        child: const YenBackApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Onboarding
    expect(find.text('일본 면세가 바뀌었어요'), findsOneWidget);
    await tester.tap(find.text('건너뛰기'));
    await tester.pumpAndSettle();

    // Calculator: ¥1,100 tax-inclusive at 10%
    expect(find.textContaining('100엔 = 900.00원'), findsOneWidget);
    for (final k in ['1', '1', '00']) {
      await tester.tap(find.text(k).last);
      await tester.pump();
    }
    expect(find.text('¥1,100'), findsOneWidget);
    expect(find.textContaining('결제 금액 9,900원'), findsOneWidget);
    expect(find.text('¥1,000 · 9,000원'), findsOneWidget); // 세전
    expect(find.text('¥100 · 900원'), findsOneWidget); // 소비세

    // Add to a new shop
    await tester.tap(find.text('매장 장바구니에 담기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('새 매장'));
    await tester.pumpAndSettle();
    // Suggestions appear on focus; typing an alias narrows to the chain.
    expect(find.text('빅카메라'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '매장 이름'), '돈키');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(searches, isEmpty, reason: 'typing must not call the paid API');
    await tester.tap(find.text('돈키호테').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '돈키호테 '), findsOneWidget);

    // Picking the chain loads its nearby branches once; tapping one fills the name.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(searches, ['돈키호테'], reason: 'exactly one call when a chain is picked');
    expect(find.text('140m · 7-13 Souemoncho'), findsOneWidget);
    expect(find.text('1.9km · 12-7 Nanbasennichimae'), findsOneWidget);
    await tester.tap(find.text('돈키호테 도톤보리점'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '돈키호테 도톤보리점'), findsOneWidget);
    expect(searches, ['돈키호테'], reason: 'picking a branch must not call again');
    await tester.tap(find.text('저장'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('담기'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.textContaining('¥4,000 남았어요'), findsOneWidget);

    // Shop list shows the remaining amount
    await tester.tap(find.text('매장'));
    await tester.pumpAndSettle();
    expect(find.text('돈키호테 도톤보리점'), findsOneWidget);
    expect(find.textContaining('¥4,000 남음'), findsOneWidget);

    // Dashboard renders with the summary
    await tester.tap(find.text('내 여행'));
    await tester.pumpAndSettle();
    expect(find.textContaining('면세 대상 매장 0 / 1곳'), findsOneWidget);

    await tester.runAsync(() => db.close());
  });
}

class _FakeLocation implements LocationService {
  @override
  Future<LocationResult> current({bool request = true}) async =>
      const LocationResult(LocationStatus.ok, lat: 34.6687, lng: 135.5013);
}
