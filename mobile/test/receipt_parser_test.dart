import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yen_back/core/receipt_parser.dart';
import 'package:yen_back/core/store_catalog.dart';

final catalog = StoreCatalog.parse(File('assets/stores.json').readAsStringSync());
final parser = ReceiptParser(catalog: catalog);

ParsedReceipt parse(String text) => parser.parse(text.trim().split('\n'));

void main() {
  group('real-world layouts (synthetic, modeled on common receipts)', () {
    test('Don Quijote style: tax-inclusive with per-rate breakdown', () {
      final r = parse('''
ドン・キホーテ 道頓堀店
大阪市中央区宗右衛門町7-13
2026年11月15日(日) 14:32  レジ03
コアラのマーチ ※          ¥216
じゃがりこ ※              ¥162
ロキソニンS               ¥1,078
資生堂 アネッサ           ¥3,278
小計                      ¥4,734
合計  4点                 ¥4,734
(10%対象   ¥4,356  内税 ¥396)
(8%対象      ¥378  内税  ¥28)
※は軽減税率対象商品です
お預り                   ¥10,000
お釣り                    ¥5,266
''');
      expect(r.totalInclYen, 4734);
      expect(r.tax10Yen, 396);
      expect(r.tax8Yen, 28);
      expect(r.taxYen, 424);
      expect(r.purchaseDate, DateTime(2026, 11, 15));
      expect(r.store?.id, 'donki');
      expect(r.warnings, isEmpty);
    });

    test('drugstore style: full-width digits and a single 内消費税等 line', () {
      final r = parse('''
マツモトキヨシ 心斎橋店
２０２６／１１／１４ １８：０５
ビオレUV                 ￥１，０７８
合　計                   ￥５，５００
（内消費税等             ￥５００）
''');
      expect(r.totalInclYen, 5500);
      expect(r.taxYen, 500);
      expect(r.purchaseDate, DateTime(2026, 11, 14));
      expect(r.store?.id, 'matsukiyo');
    });

    test('electronics style: tax-exclusive (外税) with subtotal', () {
      final r = parse('''
ビックカメラ なんば店
R8.11.13
小計                     ¥20,000
外税 10%                 ¥2,000
お買上合計               ¥22,000
''');
      expect(r.totalInclYen, 22000);
      expect(r.tax10Yen, 2000);
      expect(r.taxYen, 2000);
      expect(r.purchaseDate, DateTime(2026, 11, 13)); // 令和8年
      expect(r.store?.id, 'bic-camera');
    });

    test('no total line: total = subtotal + external tax', () {
      final r = parse('''
小計    ¥1,000
外税    ¥100
''');
      expect(r.totalInclYen, 1100);
      expect(r.taxYen, 100);
    });

    test('tax derived from per-rate bases when not printed (inclusive)', () {
      final r = parse('''
合計            ¥5,460
10%対象         ¥3,300
8%対象          ¥2,160
''');
      expect(r.tax10Yen, 300);
      expect(r.tax8Yen, 160);
      expect(r.taxYen, 460);
      expect(r.warnings, contains(ReceiptWarning.taxEstimated));
    });

    test('tax derived from bases on an exclusive receipt', () {
      final r = parse('''
10%対象   ¥3,000
8%対象    ¥2,000
合計      ¥5,460
''');
      expect(r.tax10Yen, 300);
      expect(r.tax8Yen, 160);
      expect(r.taxYen, 460);
    });
  });

  group('actual on-device OCR output', () {
    // Verbatim rows from ML Kit on an Android emulator (2026-11-15) reading
    // integration_test/fixtures/receipt_donki.jpg: note ¥ read as 4 and the
    // comma read as a period in the subtotal.
    test('Android ML Kit rows parse correctly despite misreads', () {
      final r = parse('''
ドン·キホーテ 道頓堀店
2026年11月15日(日) 14:32
コアラのマーチ ※ 4216
じゃがりこ※ ¥162
ロキソンS 1,078
資生堂 アネッサ ¥3,278
小計 44.734
合計 4点 ¥4,734
(10%対象 ¥4,356 内税 ¥396)
(8%対象¥378 内税 ¥28)
※は軽減税率対象商品です
お預り 10,000
お釣り ¥5,266
''');
      expect(r.totalInclYen, 4734);
      expect(r.taxYen, 424);
      expect(r.purchaseDate, DateTime(2026, 11, 15));
      expect(r.store?.id, 'donki');
      expect(r.warnings, isEmpty);
    });

    test('a total misread with ¥ as a leading 4 is corrected from the subtotal', () {
      final r = parse('''
小計 ¥4,734
合計 44,734
(10%対象 ¥4,356 内税 ¥396)
(8%対象 ¥378 内税 ¥28)
''');
      expect(r.totalInclYen, 4734);
      expect(r.taxYen, 424);
      expect(r.warnings, contains(ReceiptWarning.totalCorrected));
    });

    test('subtotal and per-rate bases together outvote a misread total', () {
      final r = parse('''
小計 ¥5,460
合計 ¥8,460
10%対象 ¥3,300
8%対象 ¥2,160
''');
      expect(r.totalInclYen, 5460);
      expect(r.warnings, contains(ReceiptWarning.totalCorrected));
    });

    test('a single disagreeing subtotal does not override the total', () {
      expect(parser.parse(['小計 44.734', '合計 ¥4,734']).totalInclYen, 4734);
    });

    test('period as thousands separator', () {
      expect(ReceiptParser.lastAmount('小計 44.734'), 44734);
      expect(ReceiptParser.lastAmount('合計 ¥4.734'), 4734);
    });
  });

  group('robustness', () {
    test('ignores change, deposit, counts, item lines and 税込 labels', () {
      final r = parse('''
おにぎり ¥150(税込)
合計点数 3点
お預り ¥10,000
合計 ¥450
お釣り ¥9,550
''');
      expect(r.totalInclYen, 450);
      expect(r.taxYen, isNull);
      expect(r.warnings, contains(ReceiptWarning.noTax));
    });

    test('OCR spaces inside numbers and backslash yen', () {
      expect(ReceiptParser.lastAmount('合計 \\ 5, 500'.replaceAll('\\', '¥')), 5500);
      expect(ReceiptParser.lastAmount(ReceiptParser.normalize('合計 \\5,500')), 5500);
    });

    test('rates, dates and times are not amounts', () {
      expect(ReceiptParser.lastAmount('消費税 10%'), isNull);
      expect(ReceiptParser.lastAmount('2026/11/15 14:32'), isNull);
      expect(ReceiptParser.lastAmount('(8%対象 ¥378 内税 ¥28)'), 28);
    });

    test('a misread tax larger than 10/110 of the total is discarded', () {
      final r = parse('''
合計 ¥1,100
内消費税等 ¥1,000
''');
      expect(r.totalInclYen, 1100);
      expect(r.taxYen, isNull);
      expect(r.warnings, contains(ReceiptWarning.taxInconsistent));
    });

    test('invalid dates are skipped', () {
      expect(parse('2026年13月40日\n2026年11月2日').purchaseDate, DateTime(2026, 11, 2));
    });

    test('unknown store and empty text', () {
      final r = parse('ローカル商店\n合計 ¥800');
      expect(r.store, isNull);
      expect(parser.parse(const []).isEmpty, isTrue);
    });
  });

  group('groupIntoRows', () {
    test('merges label and amount on the same baseline, left to right', () {
      final rows = groupIntoRows(const [
        OcrLine('¥4,734', left: 0.7, top: 0.505, width: 0.2, height: 0.03),
        OcrLine('ドン・キホーテ', left: 0.2, top: 0.05, width: 0.5, height: 0.04),
        OcrLine('合計', left: 0.05, top: 0.50, width: 0.1, height: 0.03),
        OcrLine('(内税 ¥396)', left: 0.4, top: 0.55, width: 0.4, height: 0.03),
      ]);
      expect(rows, ['ドン・キホーテ', '合計 ¥4,734', '(内税 ¥396)']);
    });

    test('a slightly tilted photo still pairs label and amount', () {
      final rows = groupIntoRows(const [
        OcrLine('合計', left: 0.05, top: 0.500, width: 0.1, height: 0.030),
        OcrLine('¥5,500', left: 0.7, top: 0.512, width: 0.2, height: 0.030),
        OcrLine('内消費税等', left: 0.05, top: 0.545, width: 0.2, height: 0.030),
        OcrLine('¥500', left: 0.7, top: 0.556, width: 0.1, height: 0.030),
      ]);
      expect(rows, ['合計 ¥5,500', '内消費税等 ¥500']);
    });

    test('map conversion from the platform channel', () {
      final l = OcrLine.fromMap({'text': '合計', 'left': 0.1, 'top': 0.2, 'width': 0.3, 'height': 0.04});
      expect([l.text, l.left, l.centerY], ['合計', 0.1, closeTo(0.22, 1e-9)]);
    });
  });
}
