import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yen_back/core/receipt_parser.dart';
import 'package:yen_back/core/store_catalog.dart';
import 'package:yen_back/services/receipt_ocr.dart';

import 'fixtures/receipt_donki.dart';

/// Runs the real on-device OCR (Apple Vision on iOS, ML Kit on Android) on a
/// receipt image, then the parser. Run on a simulator/emulator:
///   `flutter test integration_test/receipt_ocr_test.dart -d DEVICE_ID`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reads a Japanese receipt on device', (tester) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/receipt_donki.jpg');
    await file.writeAsBytes(base64Decode(receiptDonkiJpgBase64));

    final lines = await PlatformReceiptOcr().recognize(file.path);
    final rows = groupIntoRows(lines);
    // Printed so a failing run shows exactly what OCR returned.
    for (final r in rows) {
      // ignore: avoid_print
      print('OCR ROW: $r');
    }
    expect(lines, isNotEmpty, reason: 'OCR returned nothing');

    final catalog = StoreCatalog.parse(await rootBundle.loadString('assets/stores.json'));
    final r = ReceiptParser(catalog: catalog).parse(rows);
    // ignore: avoid_print
    print(
      'PARSED: total=${r.totalInclYen} tax=${r.taxYen} (10%=${r.tax10Yen}, 8%=${r.tax8Yen}) '
      'date=${r.purchaseDate} store=${r.store?.ko} warnings=${r.warnings}',
    );

    expect(r.totalInclYen, 4734);
    expect(r.taxYen, 424);
    expect(r.purchaseDate, DateTime(2026, 11, 15));
    expect(r.store?.id, 'donki');
  });
}
