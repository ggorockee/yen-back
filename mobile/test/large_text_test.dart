import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yen_back/app.dart';
import 'package:yen_back/config.dart';
import 'package:yen_back/core/receipt_parser.dart';
import 'package:yen_back/core/tax.dart';
import 'package:yen_back/data/app_database.dart';
import 'package:yen_back/data/models.dart';
import 'package:yen_back/data/receipt_files.dart';
import 'package:yen_back/services/analytics.dart';
import 'package:yen_back/services/location_service.dart';
import 'package:yen_back/services/purchase_service.dart';
import 'package:yen_back/services/receipt_ocr.dart';
import 'package:yen_back/state/providers.dart';

/// App Store review rejects layouts that break at large Dynamic Type sizes.
/// This walks every screen, sheet and dialog with the system text size at the
/// iOS maximum (~310%; the app caps it at AppConfig.maxTextScale) on the
/// smallest supported phone and on a large one. Any overflow fails the test.
void main() {
  sqfliteFfiInit();

  const devices = [
    ('iPhone SE (375x667)', Size(750, 1334), 2.0),
    ('iPhone 15 Pro Max (430x932)', Size(1290, 2796), 3.0),
  ];

  for (final (name, size, dpr) in devices) {
    testWidgets('every screen survives the largest text size on $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = dpr;
      tester.platformDispatcher.textScaleFactorTestValue = 3.1;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final db = await _pumpApp(tester, onboarded: true);

      Future<void> check(String step) async {
        await tester.pumpAndSettle();
        // The console output above the failure names the overflowing widget.
        expect(tester.takeException(), isNull, reason: 'layout broke at: $step');
      }

      Future<void> back() async {
        tester.state<NavigatorState>(find.byType(Navigator).last).pop();
        await tester.pumpAndSettle();
      }

      // Hidden tabs keep their lists in the tree; scroll the visible one.
      Future<void> scrollTo(Finder target) async {
        final list = find.byType(ListView).hitTestable().first;
        await tester.fling(list, const Offset(0, 5000), 5000); // back to the top
        await tester.pumpAndSettle();
        await tester.dragUntilVisible(target, list, const Offset(0, -250));
      }

      // The system asks for 310%; the app applies its cap.
      final ctx = tester.element(find.textContaining('100엔 =').first);
      expect(MediaQuery.textScalerOf(ctx).scale(10), closeTo(10 * AppConfig.maxTextScale, 1e-9));

      // Calculator with the longest amount.
      await check('calculator');
      // Text taller than a fixed box is clipped without an overflow error, so
      // check the keypad digits (52pt rows) explicitly.
      for (final k in ['1', '5', '00']) {
        expect(tester.getRect(find.text(k).last).height, lessThanOrEqualTo(52), reason: 'keypad "$k" clipped');
      }
      for (final k in ['9', '9', '9', '9', '9', '9', '9', '9']) {
        await tester.tap(find.text(k).last);
      }
      await check('calculator with ¥99,999,999');
      await tester.tap(find.text('8% 식품'));
      await check('calculator reduced rate');

      // Add-item sheet.
      await tester.tap(find.byIcon(Icons.add_shopping_cart));
      await check('add item sheet');
      await back(); // dismiss the sheet
      await check('after add item sheet');

      // Shops tab and detail.
      await tester.tap(find.byIcon(Icons.storefront_outlined));
      await check('shops list');
      await tester.tap(find.text(_longShop).first);
      await check('shop detail');
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await check('delete confirmation dialog');
      await tester.tap(find.text('취소'));
      await check('after delete dialog');
      await scrollTo(find.text('영수증 등록'));
      await tester.tap(find.text('영수증 등록'));
      await check('receipt form');
      await tester.tap(find.text('앨범'));
      await check('receipt form with scan result');
      await back();
      await scrollTo(find.text('상품 추가'));
      await tester.tap(find.text('상품 추가'));
      await check('item sheet from detail');
      await back();
      await check('after item sheet');
      await back();

      // New shop dialog with the store dropdown and nearby branches.
      await tester.tap(find.byIcon(Icons.add_business));
      await check('new shop dialog');
      await tester.enterText(find.byType(TextField).first, '돈키');
      await check('new shop dialog suggestions');
      await tester.tap(find.text('돈키호테').last);
      await check('new shop dialog nearby branches');
      await tester.tap(find.text('취소'));
      await check('after new shop dialog');

      // Trip dashboard, checklist and trip sheet.
      await tester.tap(find.byIcon(Icons.flight_takeoff_outlined));
      await check('dashboard');
      await scrollTo(find.text('공항 체크리스트'));
      await tester.tap(find.text('공항 체크리스트'));
      await check('checklist');
      await back();
      await tester.tap(find.text('변경'));
      await check('trip sheet');
      await back();
      await check('after trip sheet');

      // Settings, scrolled to the end.
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await check('settings');
      await scrollTo(find.text('제도 기준 버전'));
      await check('settings bottom');

      await tester.runAsync(db.close);
    });

    testWidgets('onboarding survives the largest text size on $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = dpr;
      tester.platformDispatcher.textScaleFactorTestValue = 3.1;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final db = await _pumpApp(tester, onboarded: false);
      for (var page = 0; page < 3; page++) {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'onboarding page ${page + 1}');
        if (page < 2) await tester.tap(find.text('다음'));
      }
      await tester.runAsync(db.close);
    });
  }
}

const _longShop = '돈키호테 도톤보리미도스지점 (2층 화장품 코너)';

Future<AppDatabase> _pumpApp(WidgetTester tester, {required bool onboarded}) async {
  await initializeDateFormatting('ko_KR');
  SharedPreferences.setMockInitialValues({'purchase.ad_free': true, 'onboarding.done': onboarded});
  final prefs = await SharedPreferences.getInstance();
  final db = await AppDatabase.open(path: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate);

  // Realistic data with the longest strings the UI shows.
  final trip = await db.trip();
  await db.saveTrip(trip.copyWith(departureAt: DateTime(2026, 11, 18, 14, 30), airport: '간사이국제공항 제1터미널 국제선'));
  final shop = await db.addShop(_longShop, DateTime(2026, 11, 15));
  await db.addItem(
    shopId: shop,
    name: '시세이도 아넷사 퍼펙트 UV 스킨케어 밀크 대용량 세트',
    unitPriceYen: 3278,
    quantity: 12,
    priceMode: PriceMode.inclTax,
    taxRatePct: 10,
    category: ItemCategory.general,
  );
  await db.addItem(
    shopId: shop,
    name: '산토리 위스키 히비키',
    unitPriceYen: 33000,
    quantity: 2,
    priceMode: PriceMode.inclTax,
    taxRatePct: 10,
    category: ItemCategory.alcohol,
  );
  await db.addReceipt(shopId: shop, totalInclYen: 105336, taxYen: 9576);
  await db.addShop('다이소', DateTime(2026, 11, 14));

  final photo = File('${Directory.systemTemp.path}/large_text_receipt.jpg')..writeAsBytesSync([0]);
  ImagePickerPlatform.instance = _FakePicker(photo.path);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(db),
        receiptFilesProvider.overrideWithValue(ReceiptFiles(Directory.systemTemp)),
        bundledStoresJsonProvider.overrideWithValue(File('assets/stores.json').readAsStringSync()),
        httpClientProvider.overrideWithValue(MockClient(_api)),
        purchasesProvider.overrideWithValue(_FakePurchases()),
        locationServiceProvider.overrideWithValue(_FakeLocation()),
        receiptOcrProvider.overrideWithValue(_FakeOcr()),
      ],
      child: const YenBackApp(),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

Future<http.Response> _api(http.Request req) async {
  final body = switch (req.url.path) {
    '/v1/rates/latest' => {
      'base_date': '2026-11-13',
      'stale': true,
      'rates': {
        'JPY': {'krw_per_unit': 9.2135},
        'USD': {'krw_per_unit': 1388.5},
      },
    },
    '/v1/rules' => {'notice': '2026년 11월 1일부터 일본 면세가 리펀드 방식으로 바뀌었어요. 출국할 때 세관 확인을 꼭 받으세요.'},
    '/v1/places/search' => {
      'places': [
        {
          'name': '돈키호테 도톤보리미도스지점 별관 2층',
          'address': '2-chōme-5-9 Nishishinsaibashi, Chuo Ward, Osaka',
          'distance_m': 142,
        },
        {'name': '돈키호테 난바센니치마에점', 'address': '12-7 Nanbasennichimae, Chuo Ward, Osaka', 'distance_m': 1949},
      ],
    },
    _ => <String, Object>{},
  };
  return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
}

class _FakeOcr implements ReceiptOcr {
  @override
  Future<List<OcrLine>> recognize(String imagePath) async => [
    for (final (i, r) in const [
      'ドン・キホーテ 道頓堀店',
      '2026年11月14日 14:32',
      '小計 ¥4,734',
      '合計 44,734',
      '（10%対象 ¥4,356 内税 ¥396）',
      '（8%対象 ¥378 内税 ¥28）',
    ].indexed)
      OcrLine(r, top: i * 0.05, height: 0.03, width: 0.9),
  ];
}

class _FakePicker extends ImagePickerPlatform {
  _FakePicker(this.path);
  final String path;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => XFile(path);
}

class _FakeLocation implements LocationService {
  @override
  Future<LocationResult> current({bool request = true}) async =>
      const LocationResult(LocationStatus.ok, lat: 34.6687, lng: 135.5013);
}

class _FakePurchases implements Purchases {
  @override
  void start() {}
  @override
  Future<String?> price() async => '₩3,300';
  @override
  Future<void> buy() async {}
  @override
  Future<void> restore() async {}
  @override
  Stream<String> get messages => const Stream.empty();
  @override
  Future<void> dispose() async {}
}
