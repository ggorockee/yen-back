import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/store_catalog.dart';
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
class _ShopFormDialog extends ConsumerStatefulWidget {
  const _ShopFormDialog({this.existing});
  final Shop? existing;

  @override
  ConsumerState<_ShopFormDialog> createState() => _ShopFormDialogState();
}

class _ShopFormDialogState extends ConsumerState<_ShopFormDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  final _focus = FocusNode();
  late DateTime _date = widget.existing?.purchaseDate ?? dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    _name.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _name.removeListener(_onChanged);
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _name.text.trim();
    if (text.isEmpty) return;
    Navigator.pop(context, (text, _date));
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(storeCatalogProvider);
    final recent = ref.watch(recentShopNamesProvider);

    return AlertDialog(
      title: Text(widget.existing == null ? '새 매장' : '매장 수정'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LayoutBuilder(
              builder: (context, constraints) => RawAutocomplete<ShopSuggestion>(
                textEditingController: _name,
                focusNode: _focus,
                // A chain fills "돈키호테 " so the branch name can be typed next.
                displayStringForOption: (s) => s.isRecent ? s.name : '${s.name} ',
                optionsBuilder: (value) => catalog.suggest(value.text, recent: recent),
                fieldViewBuilder: (context, controller, focusNode, onSubmit) => TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '매장 이름',
                    hintText: '예: 돈키호테 도톤보리점',
                    helperText: '목록에서 고른 뒤 지점명을 이어서 입력하세요',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                optionsViewBuilder: (context, onSelected, options) =>
                    _SuggestionList(width: constraints.maxWidth, options: options.toList(), onSelected: onSelected),
              ),
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
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(onPressed: _name.text.trim().isEmpty ? null : _submit, child: const Text('저장')),
      ],
    );
  }
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({required this.width, required this.options, required this.onSelected});

  final double width;
  final List<ShopSuggestion> options;
  final AutocompleteOnSelected<ShopSuggestion> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width, maxHeight: 280),
          child: ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (context, i) {
              final s = options[i];
              final b = s.brand;
              return ListTile(
                dense: true,
                leading: Icon(s.isRecent ? Icons.history : Icons.storefront_outlined, size: 20),
                title: Text(s.name),
                subtitle: b == null
                    ? const Text('최근 방문')
                    : Text([b.ja, b.category].where((x) => x.isNotEmpty).join(' · ')),
                trailing: b == null ? null : Icon(Icons.north_west, size: 16, color: theme.colorScheme.outline),
                onTap: () => onSelected(s),
              );
            },
          ),
        ),
      ),
    );
  }
}
