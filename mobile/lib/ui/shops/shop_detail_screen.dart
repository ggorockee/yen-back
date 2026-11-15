import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../widgets.dart';
import 'item_form_sheet.dart';
import 'receipt_form_screen.dart';
import 'shop_form_dialog.dart';

/// S3: one store visit: items, receipts, threshold and customs deadline.
class ShopDetailScreen extends ConsumerWidget {
  const ShopDetailScreen({super.key, required this.shopId});

  final int shopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(shopTotalsProvider(shopId));
    final rates = ref.watch(ratesProvider).snapshot;
    if (t == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final shop = t.entry.shop;
    final notifier = ref.read(entriesProvider.notifier);
    final files = ref.read(receiptFilesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(shop.name),
        actions: [
          IconButton(
            tooltip: '수정',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showShopFormDialog(context, ref, existing: shop),
          ),
          IconButton(
            tooltip: '삭제',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (!await confirm(context, '매장 삭제', '${shop.name}의 상품과 영수증 사진이 모두 삭제돼요.')) return;
              await notifier.deleteShop(shop.id);
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: ListView(
        // Keep the last element (save button) clear of the home indicator.
        padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${dateLabel(shop.purchaseDate)} 구매', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  _row('세전 합계', yen(t.amounts.exclTax)),
                  _row('소비세', yen(t.amounts.tax)),
                  _row(
                    '결제 합계',
                    '${yen(t.amounts.inclTax)}${rates == null ? '' : ' · ${won(rates.yenToWon(t.amounts.inclTax))}'}',
                  ),
                  const SizedBox(height: 12),
                  ThresholdProgress(totals: t),
                  const SizedBox(height: 8),
                  Text('세관 확인 기한: ${dateLabel(t.customsDeadline)}까지 (구매일 포함 90일)', style: theme.textTheme.bodySmall),
                  if (t.fromReceipts) Text('영수증에 입력한 금액으로 계산하고 있어요.', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('상품 ${t.entry.items.length}개', style: theme.textTheme.titleMedium),
              TextButton.icon(
                onPressed: () => showItemFormSheet(context, shopId: shop.id),
                icon: const Icon(Icons.add),
                label: const Text('상품 추가'),
              ),
            ],
          ),
          if (t.entry.items.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('담은 상품이 없어요.')),
          for (final it in t.entry.items)
            Dismissible(
              key: ValueKey('item-${it.id}'),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 16),
                color: theme.colorScheme.errorContainer,
                child: const Icon(Icons.delete_outline),
              ),
              onDismissed: (_) => notifier.deleteItem(it.id),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(it.quantity > 1 ? '${it.name} × ${it.quantity}' : it.name),
                subtitle: Text(
                  '${it.priceMode.label} ${yen(it.unitPriceYen)} · ${it.taxRatePct}%'
                  '${it.category == ItemCategory.general ? '' : ' · ${it.category.label}'}',
                ),
                trailing: Text(yen(it.breakdown.inclTax), style: theme.textTheme.titleSmall),
              ),
            ),
          const Divider(height: 32),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('영수증 ${t.entry.receipts.length}장', style: theme.textTheme.titleMedium),
              TextButton.icon(
                onPressed: () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptFormScreen(shopId: shop.id))),
                icon: const Icon(Icons.receipt_long),
                label: const Text('영수증 등록'),
              ),
            ],
          ),
          for (final r in t.entry.receipts)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: r.imageFile == null
                  ? const CircleAvatar(child: Icon(Icons.receipt_outlined))
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(
                        files.file(r.imageFile!),
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
                      ),
                    ),
              title: Text('결제 ${yen(r.totalInclYen)}'),
              subtitle: Text('소비세 ${yen(r.taxYen)}'),
              onTap: r.imageFile == null ? null : () => _showImage(context, files.file(r.imageFile!).path),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await confirm(context, '영수증 삭제', '사진과 입력한 금액이 삭제돼요.')) {
                    await notifier.deleteReceipt(r);
                  }
                },
              ),
            ),
          const SizedBox(height: 16),
          const RefundDisclaimer(),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(width: 12),
        Expanded(child: Text(value, textAlign: TextAlign.end)),
      ],
    ),
  );

  void _showImage(BuildContext context, String path) => showDialog<void>(
    context: context,
    builder: (c) => Dialog(child: InteractiveViewer(child: Image.file(File(path)))),
  );
}
