import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yen_back/app.dart';
import 'package:yen_back/core/tax.dart';
import 'package:yen_back/data/app_database.dart';
import 'package:yen_back/data/models.dart';
import 'package:yen_back/data/receipt_files.dart';
import 'package:yen_back/services/analytics.dart';
import 'package:yen_back/services/notification_service.dart';
import 'package:yen_back/state/providers.dart';

/// Renders the app with demo data and captures App Store / Play screenshots.
/// See test_driver/screenshot_driver.dart for the command.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('store screenshots', (tester) async {
    await initializeDateFormatting('ko_KR');
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    // Ad-free so screenshots never show test ads.
    await prefs.setBool('purchase.ad_free', true);

    final dir = await getTemporaryDirectory();
    final dbPath = '${dir.path}/screenshots.db';
    if (File(dbPath).existsSync()) File(dbPath).deleteSync();
    final db = await AppDatabase.open(path: dbPath);
    await _seed(db);

    final client = MockClient((req) async {
      if (req.url.path == '/v1/rates/latest') {
        return http.Response(
          jsonEncode({
            'base_date': '2026-11-13',
            'stale': false,
            'rates': {
              'JPY': {'krw_per_unit': 9.21},
              'USD': {'krw_per_unit': 1388.5},
            },
          }),
          200,
        );
      }
      if (req.url.path == '/v1/events') return http.Response('', 202);
      return http.Response('{}', 200);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(db),
          receiptFilesProvider.overrideWithValue(ReceiptFiles(dir)),
          notificationsProvider.overrideWithValue(NotificationService(FlutterLocalNotificationsPlugin())),
          bundledStoresJsonProvider.overrideWithValue(await rootBundle.loadString('assets/stores.json')),
          httpClientProvider.overrideWithValue(client),
        ],
        child: const YenBackApp(),
      ),
    );
    await tester.pumpAndSettle();
    await binding.takeScreenshot('05_onboarding');

    await tester.tap(find.text('건너뛰기'));
    await tester.pumpAndSettle();
    for (final k in ['1', '2', '8', '00']) {
      await tester.tap(find.text(k).last);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await binding.takeScreenshot('01_calculator');

    await tester.tap(find.text('매장'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('02_shops');

    await tester.tap(find.text('돈키호테 도톤보리점'));
    await tester.pumpAndSettle();
    // Let the iOS page transition fully finish before capturing.
    await Future<void>.delayed(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('03_shop_detail');
    Navigator.of(tester.element(find.text('돈키호테 도톤보리점').last)).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('내 여행'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('04_trip');
  });
}

Future<void> _seed(AppDatabase db) async {
  final today = DateTime.now();
  final day = DateTime(today.year, today.month, today.day);
  final trip = await db.trip();
  await db.saveTrip(trip.copyWith(departureAt: day.add(const Duration(days: 3, hours: 14)), airport: 'KIX'));

  Future<void> shop(String name, DateTime date, List<(String, int, int, int)> items) async {
    final id = await db.addShop(name, date);
    for (final (n, price, qty, rate) in items) {
      await db.addItem(
        shopId: id,
        name: n,
        unitPriceYen: price,
        quantity: qty,
        priceMode: PriceMode.inclTax,
        taxRatePct: rate,
        category: ItemCategory.general,
      );
    }
  }

  await shop('마츠모토키요시 신사이바시점', day, [('선크림', 1580, 2, 10)]);
  await shop('빅카메라 난바점', day.subtract(const Duration(days: 1)), [('전동칫솔', 12800, 1, 10)]);
  await shop('돈키호테 도톤보리점', day, [('동전파스', 1078, 3, 10), ('곤약젤리', 498, 4, 8), ('휴족시간', 1298, 2, 10)]);
}
