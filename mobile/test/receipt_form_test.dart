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
import 'package:yen_back/core/receipt_parser.dart';
import 'package:yen_back/data/app_database.dart';
import 'package:yen_back/data/receipt_files.dart';
import 'package:yen_back/services/analytics.dart';
import 'package:yen_back/services/receipt_ocr.dart';
import 'package:yen_back/state/providers.dart';
import 'package:yen_back/ui/shops/receipt_form_screen.dart';

/// Rows exactly as Apple Vision returned them for the fixture receipt
/// (integration_test/receipt_ocr_test.dart, iOS 17 simulator, 2026-11-15).
const _visionRows = [
  'ドン・キホーテ 道頓堀店',
  '2026年11月15日（日）14:32',
  'コアラのマーチ ※ ¥216',
  '小計 ¥4,734',
  '合計 4点 ¥4,734',
  '（10%対象 ¥4,356 内税 ¥396）',
  '（8%対象 ¥378 内税 ¥28）',
  'お預り ¥10,000',
];

class _FakeOcr implements ReceiptOcr {
  _FakeOcr(this.rows);
  final List<String> rows;
  int calls = 0;

  @override
  Future<List<OcrLine>> recognize(String imagePath) async {
    calls++;
    return [for (final (i, r) in rows.indexed) OcrLine(r, left: 0.05, top: i * 0.05, width: 0.9, height: 0.03)];
  }
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

void main() {
  sqfliteFfiInit();

  Future<(AppDatabase, int)> pumpScreen(WidgetTester tester, ReceiptOcr ocr, {required DateTime shopDate}) async {
    await initializeDateFormatting('ko_KR');
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final photo = File('${Directory.systemTemp.path}/receipt_test_${DateTime.now().microsecondsSinceEpoch}.jpg')
      ..writeAsBytesSync([0]);
    ImagePickerPlatform.instance = _FakePicker(photo.path);

    SharedPreferences.setMockInitialValues({'purchase.ad_free': true});
    final prefs = await SharedPreferences.getInstance();
    final db = await AppDatabase.open(path: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate);
    final shopId = await db.addShop('돈키호테 도톤보리점', shopDate);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(db),
          receiptFilesProvider.overrideWithValue(ReceiptFiles(Directory.systemTemp)),
          httpClientProvider.overrideWithValue(MockClient((_) async => http.Response('{}', 503))),
          receiptOcrProvider.overrideWithValue(ocr),
        ],
        child: MaterialApp(home: ReceiptFormScreen(shopId: shopId)),
      ),
    );
    await tester.pumpAndSettle();
    return (db, shopId);
  }

  testWidgets('a picked photo is read on device and pre-fills the amounts', (tester) async {
    final ocr = _FakeOcr(_visionRows);
    final (db, shopId) = await pumpScreen(tester, ocr, shopDate: DateTime(2026, 11, 14));

    await tester.tap(find.text('앨범'));
    await tester.pumpAndSettle();

    expect(ocr.calls, 1);
    expect(find.text('영수증에서 읽은 값이에요. 맞는지 확인해 주세요.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.widgetWithText(TextField, '424'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.widgetWithText(TextField, '4734'), findsOneWidget);
    expect(find.widgetWithText(TextField, '424'), findsOneWidget);
    expect(find.text('¥424 (10% ¥396 · 8% ¥28)'), findsOneWidget);
    // The receipt says 11/15 but the shop was entered as 11/14.
    expect(find.textContaining('매장 구매일'), findsOneWidget);
    // Same chain as the shop name: no store warning.
    expect(find.textContaining('다를 수 있어요'), findsNothing);

    await tester.scrollUntilVisible(find.text('저장'), 200, scrollable: find.byType(Scrollable).first);
    await tester.runAsync(() async {
      await tester.tap(find.text('저장'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    final saved = (await db.entries()).single.receipts.single;
    expect([saved.totalInclYen, saved.taxYen], [4734, 424]);
    await db.close();
  });

  testWidgets('unreadable photo asks to retake and leaves fields empty', (tester) async {
    final ocr = _FakeOcr(const []);
    final (db, _) = await pumpScreen(tester, ocr, shopDate: DateTime(2026, 11, 15));

    await tester.tap(find.text('촬영'));
    await tester.pumpAndSettle();
    expect(find.text('글자를 읽지 못했어요'), findsOneWidget);
    await tester.tap(find.text('다시 읽기'));
    await tester.pumpAndSettle();
    expect(ocr.calls, 2);
    await db.close();
  });
}
