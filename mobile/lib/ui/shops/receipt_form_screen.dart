import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/format.dart';
import '../../core/receipt_parser.dart';
import '../../core/tax.dart';
import '../../data/models.dart';
import '../../services/analytics.dart';
import '../../state/providers.dart';
import '../widgets.dart';

/// S4: attach a receipt photo (kept on the device) and its amounts.
class ReceiptFormScreen extends ConsumerStatefulWidget {
  const ReceiptFormScreen({super.key, required this.shopId});

  final int shopId;

  @override
  ConsumerState<ReceiptFormScreen> createState() => _ReceiptFormScreenState();
}

class _ReceiptFormScreenState extends ConsumerState<ReceiptFormScreen> {
  final _total = TextEditingController();
  final _tax = TextEditingController();
  bool _taxEdited = false;
  String? _imagePath;
  bool _saving = false;
  bool _scanning = false;
  ParsedReceipt? _scan;

  @override
  void dispose() {
    _total.dispose();
    _tax.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final x = await ImagePicker().pickImage(source: source, imageQuality: 80, maxWidth: 2000);
      if (x == null) return;
      setState(() => _imagePath = x.path);
      await _scanReceipt(x.path);
    } catch (_) {
      if (mounted) showSnack(context, '사진을 불러오지 못했어요. 권한 설정을 확인해 주세요.');
    }
  }

  /// Reads the photo on the device and pre-fills the amounts for review.
  Future<void> _scanReceipt(String path) async {
    setState(() {
      _scanning = true;
      _scan = null;
    });
    final lines = await ref.read(receiptOcrProvider).recognize(path);
    final parsed = ReceiptParser(catalog: ref.read(storeCatalogProvider)).parse(groupIntoRows(lines));
    if (!mounted || _imagePath != path) return;
    setState(() {
      _scanning = false;
      _scan = parsed;
      final total = parsed.totalInclYen;
      final tax = parsed.taxYen;
      if (total != null) _total.text = '$total';
      if (tax != null) {
        _tax.text = '$tax';
        _taxEdited = true;
      } else {
        _taxEdited = false;
        if (total != null) _onTotalChanged(_total.text);
      }
    });
    ref.read(analyticsProvider).track(parsed.isEmpty ? AppEvent.receiptScanEmpty : AppEvent.receiptScanned);
  }

  /// Suggests the tax at the standard rate until the user edits it.
  void _onTotalChanged(String v) {
    if (_taxEdited) return;
    final rate = ref.read(rulesProvider).standardTaxRatePct;
    final b = PriceBreakdown.from(parseYen(v), PriceMode.inclTax, rate);
    _tax.text = b.tax == 0 ? '' : '${b.tax}';
    setState(() {});
  }

  Future<void> _save() async {
    final total = parseYen(_total.text);
    final tax = parseYen(_tax.text);
    if (total <= 0 || tax < 0 || tax >= total) {
      showSnack(context, '결제 금액과 소비세를 확인해 주세요.');
      return;
    }
    setState(() => _saving = true);
    String? file;
    if (_imagePath != null) file = await ref.read(receiptFilesProvider).import(_imagePath!);
    await ref
        .read(entriesProvider.notifier)
        .addReceipt(shopId: widget.shopId, totalInclYen: total, taxYen: tax, imageFile: file);
    ref.read(analyticsProvider).track(AppEvent.receiptAdded);
    if (!mounted) return;
    Navigator.pop(context);
    ref.read(interstitialProvider).maybeShow(adFree: ref.read(adFreeProvider));
  }

  @override
  Widget build(BuildContext context) {
    final total = parseYen(_total.text);
    return Scaffold(
      appBar: AppBar(title: const Text('영수증 등록')),
      body: ListView(
        // Keep the last element (save button) clear of the home indicator.
        padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: _imagePath == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.receipt_long, size: 48),
                        const SizedBox(height: 8),
                        const Text('영수증 사진 (선택)'),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: () => _pick(ImageSource.camera),
                              icon: const Icon(Icons.photo_camera),
                              label: const Text('촬영'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () => _pick(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library),
                              label: const Text('앨범'),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(File(_imagePath!), fit: BoxFit.cover),
                        if (_scanning)
                          const ColoredBox(
                            color: Colors.black45,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(color: Colors.white),
                                  SizedBox(height: 12),
                                  Text('영수증 읽는 중…', style: TextStyle(color: Colors.white)),
                                ],
                              ),
                            ),
                          ),
                        Positioned(
                          right: 8,
                          top: 8,
                          child: IconButton.filledTonal(
                            onPressed: () => setState(() {
                              _imagePath = null;
                              _scan = null;
                              _scanning = false;
                            }),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Text('사진은 이 기기에만 저장되고 서버로 전송되지 않아요. 글자 인식도 기기 안에서 처리돼요.', style: Theme.of(context).textTheme.bodySmall),
          if (_scan != null) ...[
            const SizedBox(height: 12),
            _ScanResultCard(
              scan: _scan!,
              shop: ref.watch(shopTotalsProvider(widget.shopId))?.entry.shop,
              onRetry: _imagePath == null ? null : () => _scanReceipt(_imagePath!),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _total,
            decoration: const InputDecoration(labelText: '결제 금액 (세금 포함)', prefixText: '¥ '),
            keyboardType: TextInputType.number,
            onChanged: _onTotalChanged,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _tax,
            decoration: const InputDecoration(
              labelText: '소비세',
              prefixText: '¥ ',
              helperText: '영수증의 消費税 금액. 식품(8%)이 섞여 있으면 직접 고쳐 주세요.',
            ),
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() => _taxEdited = true),
          ),
          if (total > 0) ...[const SizedBox(height: 8), Text('세전 ${yen(total - parseYen(_tax.text))}')],
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _saving || total <= 0 ? null : _save,
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }
}

/// What OCR read, with anything the user should double-check.
class _ScanResultCard extends StatelessWidget {
  const _ScanResultCard({required this.scan, required this.shop, required this.onRetry});

  final ParsedReceipt scan;
  final Shop? shop;
  final VoidCallback? onRetry;

  static String _warning(ReceiptWarning w) => switch (w) {
    ReceiptWarning.noTotal => '합계 금액을 찾지 못했어요. 직접 입력해 주세요.',
    ReceiptWarning.noTax => '소비세 줄을 찾지 못해 10%로 계산해 채웠어요.',
    ReceiptWarning.taxEstimated => '세율별 대상 금액으로 소비세를 계산했어요.',
    ReceiptWarning.taxInconsistent => '소비세를 확실히 읽지 못했어요. 직접 확인해 주세요.',
    ReceiptWarning.totalCorrected => '합계를 소계와 비교해 바로잡았어요. 금액을 확인해 주세요.',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (scan.isEmpty) {
      return Card(
        color: theme.colorScheme.surfaceContainerHighest,
        child: ListTile(
          leading: const Icon(Icons.text_snippet_outlined),
          title: const Text('글자를 읽지 못했어요'),
          subtitle: const Text('밝은 곳에서 영수증을 평평하게 펴고 다시 찍어 보세요. 금액은 직접 입력해도 돼요.'),
          trailing: onRetry == null ? null : TextButton(onPressed: onRetry, child: const Text('다시 읽기')),
        ),
      );
    }

    final notes = [for (final w in scan.warnings) _warning(w)];
    final date = scan.purchaseDate;
    final s = shop;
    if (date != null && s != null && dateOnly(date) != dateOnly(s.purchaseDate)) {
      notes.add('영수증 날짜(${dateLabel(date)})가 매장 구매일(${dateLabel(s.purchaseDate)})과 달라요.');
    }
    final store = scan.store;
    if (store != null && s != null && !s.name.contains(store.ko)) {
      notes.add('영수증 매장(${store.ko})이 "${s.name}"과 다를 수 있어요.');
    }
    final rates = [
      if (scan.tax10Yen != null) '10% ${yen(scan.tax10Yen!)}',
      if (scan.tax8Yen != null) '8% ${yen(scan.tax8Yen!)}',
    ];

    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: TextStyle(color: theme.colorScheme.outline)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );

    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.document_scanner_outlined, size: 18, color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: 6),
                Expanded(child: Text('영수증에서 읽은 값이에요. 맞는지 확인해 주세요.', style: theme.textTheme.labelLarge)),
              ],
            ),
            const SizedBox(height: 8),
            if (scan.totalInclYen != null) row('합계', yen(scan.totalInclYen!)),
            if (scan.taxYen != null)
              row('소비세', [yen(scan.taxYen!), if (rates.isNotEmpty) '(${rates.join(' · ')})'].join(' ')),
            if (date != null) row('날짜', dateLabel(date)),
            if (store != null) row('매장', store.ko),
            for (final n in notes)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: theme.colorScheme.error),
                    const SizedBox(width: 4),
                    Expanded(child: Text(n, style: theme.textTheme.bodySmall)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
