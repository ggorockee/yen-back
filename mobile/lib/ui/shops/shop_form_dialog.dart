import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../services/analytics.dart';
import '../../state/providers.dart';

/// Creates a shop, or edits [existing]. Returns the shop id on save.
Future<int?> showShopFormDialog(BuildContext context, WidgetRef ref, {Shop? existing}) async {
  final result = await showDialog<(String, DateTime)>(
    context: context,
    builder: (_) => _ShopFormDialog(existing: existing),
  );
  if (result == null) return null;
  final (name, date) = result;

  final notifier = ref.read(entriesProvider.notifier);
  if (existing != null) {
    await notifier.updateShop(existing.id, name, date);
    return existing.id;
  }
  final id = await notifier.addShop(name, date);
  ref.read(analyticsProvider).track(AppEvent.shopCreated);
  ref.read(interstitialProvider).maybeShow(adFree: ref.read(adFreeProvider));
  return id;
}

/// Owns its controller so it is disposed only after the close animation.
class _ShopFormDialog extends StatefulWidget {
  const _ShopFormDialog({this.existing});
  final Shop? existing;

  @override
  State<_ShopFormDialog> createState() => _ShopFormDialogState();
}

class _ShopFormDialogState extends State<_ShopFormDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late DateTime _date = widget.existing?.purchaseDate ?? dateOnly(DateTime.now());

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _name.text.trim();
    if (text.isEmpty) return;
    Navigator.pop(context, (text, _date));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? '새 매장' : '매장 수정'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _name,
          autofocus: true,
          decoration: const InputDecoration(labelText: '매장 이름', hintText: '예: 돈키호테 도톤보리점'),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event),
          title: Text('구매일 ${dateLabel(_date)}'),
          subtitle: const Text('날짜가 다르면 다른 매장으로 따로 계산돼요'),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime(2026, 1, 1),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (picked != null) setState(() => _date = dateOnly(picked));
          },
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
      FilledButton(onPressed: _name.text.trim().isEmpty ? null : _submit, child: const Text('저장')),
    ],
  );
}
