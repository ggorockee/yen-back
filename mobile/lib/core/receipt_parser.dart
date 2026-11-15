import 'store_catalog.dart';

/// One recognized text line with its box in normalized image coordinates
/// (0..1, origin top-left), as returned by the platform OCR.
class OcrLine {
  const OcrLine(this.text, {this.left = 0, this.top = 0, this.width = 0, this.height = 0});

  final String text;
  final double left;
  final double top;
  final double width;
  final double height;

  double get centerY => top + height / 2;

  factory OcrLine.fromMap(Map<Object?, Object?> m) {
    double d(String k) => (m[k] as num?)?.toDouble() ?? 0;
    return OcrLine('${m['text'] ?? ''}', left: d('left'), top: d('top'), width: d('width'), height: d('height'));
  }
}

/// Receipts print the label on the left and the amount on the right; OCR
/// often returns them as separate lines. Lines whose vertical centers are
/// within half a line height are merged into one row, ordered left to right.
List<String> groupIntoRows(List<OcrLine> lines) {
  final sorted = [...lines.where((l) => l.text.trim().isNotEmpty)]..sort((a, b) => a.centerY.compareTo(b.centerY));
  final rows = <List<OcrLine>>[];
  for (final line in sorted) {
    final row = rows.isEmpty ? null : rows.last;
    if (row != null) {
      final rowCenter = row.map((l) => l.centerY).reduce((a, b) => a + b) / row.length;
      final rowHeight = row.map((l) => l.height).reduce((a, b) => a > b ? a : b);
      final tolerance = 0.5 * (line.height < rowHeight ? line.height : rowHeight);
      if ((line.centerY - rowCenter).abs() <= tolerance) {
        row.add(line);
        continue;
      }
    }
    rows.add([line]);
  }
  return [for (final row in rows) (row..sort((a, b) => a.left.compareTo(b.left))).map((l) => l.text.trim()).join(' ')];
}

enum ReceiptWarning {
  /// No total line found.
  noTotal,

  /// No tax line found and it could not be derived.
  noTax,

  /// Tax computed from the per-rate base amounts, not printed directly.
  taxEstimated,

  /// The tax read does not fit the total (misread); it was discarded.
  taxInconsistent,

  /// The total line disagreed with the subtotal or per-rate amounts (OCR
  /// misread, e.g. "¥" read as "4") and was corrected from them.
  totalCorrected,
}

/// Values read from a Japanese receipt. Every field may be null; the user
/// confirms them before saving.
class ParsedReceipt {
  const ParsedReceipt({
    this.totalInclYen,
    this.taxYen,
    this.tax10Yen,
    this.tax8Yen,
    this.purchaseDate,
    this.store,
    this.warnings = const [],
  });

  final int? totalInclYen;
  final int? taxYen;
  final int? tax10Yen;
  final int? tax8Yen;
  final DateTime? purchaseDate;
  final StoreBrand? store;
  final List<ReceiptWarning> warnings;

  bool get isEmpty => totalInclYen == null && taxYen == null && purchaseDate == null && store == null;
}

/// Rule-based parser for Japanese receipt text. No network, no AI service:
/// Japanese receipts use a small, regulated vocabulary (合計, 消費税, 10%対象,
/// 内税/外税) and since the 2023 invoice rules most show tax per rate.
class ReceiptParser {
  const ReceiptParser({this.catalog = StoreCatalog.empty});

  final StoreCatalog catalog;

  static const _totalKeys = ['合計', 'お買上', 'お買い上げ', '御買上', 'お会計', 'ご請求', '請求額'];
  static const _notTotalKeys = ['小計', '点数', '品数', '預', '釣', 'お返し', '対象', '消費税', '内税', '外税', '税額'];
  static const _taxKeys = ['消費税', '税額', '内税', '外税'];

  ParsedReceipt parse(List<String> rows) {
    final normalized = rows.map(normalize).toList();
    final warnings = <ReceiptWarning>[];

    int? total;
    int? subtotal;
    int? printedTax; // tax without a rate ("内消費税等 ¥460")
    final rateTax = <int, int>{};
    final rateBase = <int, int>{};
    var externalTax = false;

    for (final row in normalized) {
      final compact = row.replaceAll(' ', '');
      final amount = lastAmount(row);
      final rate = _rate(compact);
      final isTax = _taxKeys.any(compact.contains) && !compact.contains('税込合計');
      if (compact.contains('外税')) externalTax = true;

      if (isTax) {
        if (amount == null) continue;
        if (rate != null) {
          rateTax[rate] = (rateTax[rate] ?? 0) + amount;
        } else {
          printedTax = printedTax == null || amount > printedTax ? amount : printedTax;
        }
      } else if (compact.contains('対象') && rate != null) {
        if (amount != null) rateBase[rate] = amount;
      } else if (compact.contains('小計')) {
        if (amount != null) subtotal = amount;
      } else if (_totalKeys.any(compact.contains) && !_notTotalKeys.any(compact.contains)) {
        if (amount != null && (total == null || amount > total)) total = amount;
      }
    }

    int? tax = printedTax ?? (rateTax.isEmpty ? null : rateTax.values.reduce((a, b) => a + b));
    int? tax10 = rateTax[10];
    int? tax8 = rateTax[8];

    if (total == null && subtotal != null) {
      total = externalTax && tax != null ? subtotal + tax : subtotal;
    }

    // Cross-check the total against independent sources and fix OCR misreads.
    final sources = <int>[
      if (subtotal != null) externalTax && tax != null ? subtotal + tax : subtotal,
      if (rateBase.isNotEmpty && !externalTax) rateBase.values.reduce((a, b) => a + b),
    ];
    final t = total;
    if (t != null && sources.isNotEmpty && !sources.contains(t)) {
      final fixed = correctTotal(t, sources);
      if (fixed != null) {
        total = fixed;
        warnings.add(ReceiptWarning.totalCorrected);
      }
    }

    // Derive tax from per-rate bases ("10%対象 ¥3,300") when not printed.
    if (tax == null && rateBase.isNotEmpty) {
      final sumBase = rateBase.values.reduce((a, b) => a + b);
      int inclTax(int base, int r) => base - base * 100 ~/ (100 + r);
      int exclTax(int base, int r) => base * r ~/ 100;
      final exclusive =
          total != null &&
          (sumBase - total).abs() > 1 &&
          (sumBase + rateBase.entries.fold(0, (s, e) => s + exclTax(e.value, e.key)) - total).abs() <= 2;
      final perRate = {
        for (final e in rateBase.entries) e.key: exclusive ? exclTax(e.value, e.key) : inclTax(e.value, e.key),
      };
      tax10 = perRate[10];
      tax8 = perRate[8];
      tax = perRate.values.reduce((a, b) => a + b);
      warnings.add(ReceiptWarning.taxEstimated);
    }

    // Tax can never exceed 10/110 of a tax-inclusive total.
    if (tax != null && total != null && (tax <= 0 || tax >= total || tax > total * 10 ~/ 110 + 2)) {
      tax = null;
      tax10 = null;
      tax8 = null;
      warnings.add(ReceiptWarning.taxInconsistent);
    }

    if (total == null) warnings.add(ReceiptWarning.noTotal);
    if (tax == null && !warnings.contains(ReceiptWarning.taxInconsistent)) warnings.add(ReceiptWarning.noTax);

    return ParsedReceipt(
      totalInclYen: total,
      taxYen: tax,
      tax10Yen: tax10,
      tax8Yen: tax8,
      purchaseDate: _date(normalized),
      store: _store(normalized),
      warnings: warnings,
    );
  }

  /// A total that disagrees with the other sources is replaced when the
  /// difference looks like an OCR misread: a "¥" read as a leading "4"
  /// ("44734" for 4734), or when every other source agrees on one value.
  static int? correctTotal(int total, List<int> sources) {
    final s = total.toString();
    for (final v in sources) {
      if (s == '4$v') return v;
    }
    // Two independent sources (subtotal, per-rate amounts) outvote one line.
    if (sources.length >= 2 && sources.every((v) => v == sources.first)) return sources.first;
    return null;
  }

  /// Full-width ASCII to half-width, yen signs unified, ideographic spaces.
  static String normalize(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      if (r >= 0xFF01 && r <= 0xFF5E) {
        b.writeCharCode(r - 0xFEE0);
      } else if (r == 0x3000) {
        b.write(' ');
      } else if (r == 0xFFE5 || r == 0x5C) {
        b.write('¥'); // ￥ and the backslash many receipt printers use for yen
      } else {
        b.writeCharCode(r);
      }
    }
    return b.toString();
  }

  static final _noise = [
    RegExp(r'\d+(\.\d+)?\s*%'), // rates
    RegExp(r'\d+\s*(点|個|品)'), // item counts
    RegExp(r'\d{1,4}[/.\-年]\d{1,2}[/.\-月]\d{1,2}日?'), // dates
    RegExp(r'\d{1,2}:\d{2}(:\d{2})?'), // times
    RegExp(r'No\.?\s*\d+', caseSensitive: false),
  ];
  static final _amount = RegExp(r'-?\d{1,3}(?:,\d{3})+|-?\d+');

  /// The last money amount in a row (amounts are right-aligned on receipts).
  static int? lastAmount(String row) {
    var s = row;
    for (final p in _noise) {
      s = s.replaceAll(p, ' ');
    }
    // "¥ 5, 500" → "¥5,500": OCR often inserts spaces inside numbers.
    s = s.replaceAllMapped(RegExp(r'(\d)\s*,\s*(\d{3})'), (m) => '${m[1]},${m[2]}');
    // Yen has no decimals: "44.734" is a misread "4,734" separator.
    s = s.replaceAllMapped(RegExp(r'(\d)\.(\d{3})(?!\d)'), (m) => '${m[1]},${m[2]}');
    final matches = _amount.allMatches(s).toList();
    if (matches.isEmpty) return null;
    final v = int.tryParse(matches.last.group(0)!.replaceAll(',', ''));
    return v == null || v < 0 ? null : v;
  }

  static int? _rate(String compact) {
    if (compact.contains('10%')) return 10;
    if (compact.contains('8%') || compact.contains('軽減')) return 8;
    return null;
  }

  static final _dateWestern = RegExp(r'(20\d{2})\s*[年/.\-]\s*(\d{1,2})\s*[月/.\-]\s*(\d{1,2})');
  static final _dateReiwa = RegExp(r'(?:令和|R)\s*(\d{1,2})\s*[年/.]\s*(\d{1,2})\s*[月/.]\s*(\d{1,2})');

  static DateTime? _date(List<String> rows) {
    for (final row in rows) {
      for (final (re, yearOf) in [
        (_dateWestern, (int y) => y),
        (_dateReiwa, (int y) => 2018 + y), // 令和1年 = 2019
      ]) {
        final m = re.firstMatch(row);
        if (m == null) continue;
        final y = yearOf(int.parse(m[1]!)), mo = int.parse(m[2]!), d = int.parse(m[3]!);
        if (mo < 1 || mo > 12 || d < 1 || d > 31) continue;
        final date = DateTime(y, mo, d);
        if (date.month == mo && date.day == d) return date;
      }
    }
    return null;
  }

  StoreBrand? _store(List<String> rows) {
    // The store name is printed in the header.
    final head = rows.take(8).map(StoreCatalog.normalize).toList();
    for (final b in catalog.brands) {
      final names = [b.ja, if (b.en.length >= 3) b.en].map(StoreCatalog.normalize).where((n) => n.length >= 2);
      if (head.any((row) => names.any(row.contains))) return b;
    }
    return null;
  }
}
