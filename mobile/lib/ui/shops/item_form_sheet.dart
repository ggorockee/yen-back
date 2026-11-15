import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/tax.dart';
import '../../data/models.dart';
import '../../services/analytics.dart';
import '../../state/providers.dart';
import '../widgets.dart';
import 'shop_form_dialog.dart';

/// Adds an item to a shop. From the calculator the price is preset and the
/// user picks (or creates) the shop; from a shop's detail page [shopId] is fixed.
Future<bool?> showItemFormSheet(
  BuildContext context, {
  int? shopId,
  int? presetPriceYen,
  PriceMode presetMode = PriceMode.inclTax,
  int? presetRatePct,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _ItemFormSheet(
    fixedShopId: shopId,
    presetPriceYen: presetPriceYen,
    presetMode: presetMode,
    presetRatePct: presetRatePct,
  ),
);

class _ItemFormSheet extends ConsumerStatefulWidget {
  const _ItemFormSheet({this.fixedShopId, this.presetPriceYen, required this.presetMode, this.presetRatePct});

  final int? fixedShopId;
  final int? presetPriceYen;
  final PriceMode presetMode;
  final int? presetRatePct;

  @override
  ConsumerState<_ItemFormSheet> createState() => _ItemFormSheetState();
}

class _ItemFormSheetState extends ConsumerState<_ItemFormSheet> {
  late final _name = TextEditingController();
  late final _price = TextEditingController(text: widget.presetPriceYen?.toString() ?? '');
  late PriceMode _mode = widget.presetMode;
  int? _ratePct;
  int _qty = 1;
  ItemCategory _category = ItemCategory.general;
  int? _shopId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ratePct = widget.presetRatePct;
    _shopId = widget.fixedShopId;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _newShop() async {
    final id = await showShopFormDialog(context, ref);
    if (id != null) setState(() => _shopId = id);
  }

  Future<void> _save() async {
    final price = parseYen(_price.text);
    final shopId = _shopId;
    if (price <= 0 || shopId == null) return;
    setState(() => _saving = true);
    final rules = ref.read(rulesProvider);
    await ref
        .read(entriesProvider.notifier)
        .addItem(
          shopId: shopId,
          name: _name.text.trim().isEmpty ? '상품' : _name.text.trim(),
          unitPriceYen: price,
          quantity: _qty,
          priceMode: _mode,
          taxRatePct: _ratePct ?? rules.standardTaxRatePct,
          category: _category,
        );
    ref.read(analyticsProvider).track(AppEvent.itemAdded);
    if (!mounted) return;
    final totals = ref.read(shopTotalsProvider(shopId));
    Navigator.pop(context, true);
    if (totals != null) {
      showSnack(
        context,
        totals.eligible
            ? '${totals.entry.shop.name}: 면세 기준 달성! 예상 환급 ${yen(totals.refundYen)}'
            : '${totals.entry.shop.name}: ${yen(totals.minPurchaseExclTaxYen)}까지 ${yen(totals.remainingYen)} 남았어요',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rules = ref.watch(rulesProvider);
    final rate = _ratePct ?? rules.standardTaxRatePct;
    final today = dateOnly(DateTime.now());
    final shops = (ref.watch(entriesProvider).value ?? const <ShopEntry>[])
        .where((e) => widget.fixedShopId != null || e.shop.purchaseDate == today)
        .toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('상품 담기', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            if (widget.fixedShopId == null) ...[
              Text('오늘 방문한 매장', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final e in shops)
                    ChoiceChip(
                      label: Text(e.shop.name),
                      selected: _shopId == e.shop.id,
                      onSelected: (_) => setState(() => _shopId = e.shop.id),
                    ),
                  ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('새 매장'), onPressed: _newShop),
                ],
              ),
              Text(
                '면세 기준(세전 ${yen(rules.minPurchaseExclTaxYen)})은 같은 날 같은 매장 구매만 합산돼요.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '상품명 (선택)', hintText: '예: 곤약젤리'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _price,
              decoration: const InputDecoration(labelText: '단가 (엔)', prefixText: '¥ '),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SegmentedButton<PriceMode>(
                  segments: [for (final m in PriceMode.values) ButtonSegment(value: m, label: Text(m.label))],
                  selected: {_mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
                const Spacer(),
                DropdownButton<int>(
                  value: rate,
                  items: [
                    DropdownMenuItem(value: rules.standardTaxRatePct, child: Text('${rules.standardTaxRatePct}%')),
                    DropdownMenuItem(value: rules.reducedTaxRatePct, child: Text('${rules.reducedTaxRatePct}% 식품')),
                  ],
                  onChanged: (v) => setState(() => _ratePct = v),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('수량'),
                IconButton(
                  onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$_qty', style: Theme.of(context).textTheme.titleMedium),
                IconButton(onPressed: () => setState(() => _qty++), icon: const Icon(Icons.add_circle_outline)),
                const Spacer(),
                DropdownButton<ItemCategory>(
                  value: _category,
                  items: [for (final c in ItemCategory.values) DropdownMenuItem(value: c, child: Text(c.label))],
                  onChanged: (v) => setState(() => _category = v ?? ItemCategory.general),
                ),
              ],
            ),
            if (_category != ItemCategory.general)
              Text('술·담배·향수는 한국 입국 시 800달러와 별도 한도가 적용돼요.', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _saving || _shopId == null || parseYen(_price.text) <= 0 ? null : _save,
              child: Text(_shopId == null ? '매장을 선택하세요' : '담기'),
            ),
          ],
        ),
      ),
    );
  }
}
