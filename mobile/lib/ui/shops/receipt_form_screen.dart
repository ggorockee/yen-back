import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/format.dart';
import '../../core/tax.dart';
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

  @override
  void dispose() {
    _total.dispose();
    _tax.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final x = await ImagePicker().pickImage(source: source, imageQuality: 80, maxWidth: 2000);
      if (x != null) setState(() => _imagePath = x.path);
    } catch (_) {
      if (mounted) showSnack(context, '사진을 불러오지 못했어요. 권한 설정을 확인해 주세요.');
    }
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
                        Positioned(
                          right: 8,
                          top: 8,
                          child: IconButton.filledTonal(
                            onPressed: () => setState(() => _imagePath = null),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Text('사진은 이 기기에만 저장되고 서버로 전송되지 않아요.', style: Theme.of(context).textTheme.bodySmall),
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
