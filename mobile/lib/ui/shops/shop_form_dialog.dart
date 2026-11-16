import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/store_catalog.dart';
import '../../data/models.dart';
import '../../services/analytics.dart';
import '../../services/location_service.dart';
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
  ref.read(interstitialProvider).maybeShow();
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

  // Nearby branches (Google Places via our server). Each search is a billable
  // call, so it runs once when a chain is picked from the list, or when the
  // user taps "근처 지점 찾기" for a name typed by hand; never per keystroke.
  LocationResult? _location;
  bool _locating = false;
  List<NearbyBranch>? _branches;
  bool _searching = false;
  bool _searchFailed = false;
  String? _searchedQuery;
  String? _pendingQuery;
  String? _pickedBranch;

  @override
  void initState() {
    super.initState();
    _name.addListener(_onChanged);
    _locate(request: true);
  }

  void _onChanged() {
    final text = _name.text.trim();
    if (text == _pickedBranch) return; // Text set by picking a branch.
    setState(() {
      _pickedBranch = null;
      // Typing something else hides results that no longer match.
      final searched = _searchedQuery;
      if (searched != null && !text.startsWith(searched)) {
        _searchedQuery = null;
        _branches = null;
        _searchFailed = false;
      }
    });
  }

  Future<void> _locate({required bool request}) async {
    setState(() => _locating = true);
    final loc = await ref.read(locationServiceProvider).current(request: request);
    if (!mounted) return;
    setState(() {
      _location = loc;
      _locating = false;
    });
    final pending = _pendingQuery;
    if (loc.ok && pending != null) _search(pending);
  }

  Future<void> _search(String q) async {
    q = q.trim();
    final loc = _location;
    if (q.runes.length < 2) return;
    if (loc == null || !loc.ok) {
      _pendingQuery = q; // Search once location becomes available.
      return;
    }
    _pendingQuery = null;
    setState(() {
      _searchedQuery = q;
      _branches = null;
      _searching = true;
      _searchFailed = false;
    });
    try {
      final found = await ref.read(remoteRepositoryProvider).searchBranches(q, loc.lat!, loc.lng!);
      if (mounted && _searchedQuery == q) setState(() => _branches = found);
    } catch (_) {
      if (mounted && _searchedQuery == q) setState(() => _searchFailed = true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _pickBranch(NearbyBranch b) {
    _pickedBranch = b.name;
    _name.text = b.name;
    _name.selection = TextSelection.collapsed(offset: b.name.length);
    _focus.unfocus();
    ref.read(analyticsProvider).track(AppEvent.branchPicked);
  }

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
        // Scrolls when large text or the nearby-branch list exceeds the screen.
        // (AlertDialog.scrollable would measure intrinsics, which the
        // LayoutBuilder below cannot provide.)
        child: SingleChildScrollView(
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
                  // Picking a chain is the one moment we look up its branches.
                  onSelected: (s) {
                    final brand = s.brand;
                    if (brand != null) _search(brand.ko);
                  },
                  optionsViewBuilder: (context, onSelected, options) =>
                      _SuggestionList(width: constraints.maxWidth, options: options.toList(), onSelected: onSelected),
                ),
              ),
              _NearbyBranches(
                location: _location,
                locating: _locating,
                searching: _searching,
                failed: _searchFailed,
                branches: _branches,
                picked: _pickedBranch,
                typed: _name.text.trim(),
                searched: _searchedQuery,
                onSearchTyped: () => _search(_name.text),
                onPick: _pickBranch,
                onAllowLocation: () async {
                  if (_location?.status == LocationStatus.deniedForever) {
                    final svc = ref.read(locationServiceProvider);
                    if (svc is DeviceLocationService) await svc.openSettings();
                    return;
                  }
                  await _locate(request: true);
                },
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

/// "근처 지점" section: nearest branches of the picked chain, or a hint.
class _NearbyBranches extends StatelessWidget {
  const _NearbyBranches({
    required this.location,
    required this.locating,
    required this.searching,
    required this.failed,
    required this.branches,
    required this.picked,
    required this.typed,
    required this.searched,
    required this.onSearchTyped,
    required this.onPick,
    required this.onAllowLocation,
  });

  final LocationResult? location;
  final bool locating;
  final bool searching;
  final bool failed;
  final List<NearbyBranch>? branches;
  final String? picked;
  final String typed;
  final String? searched;
  final VoidCallback onSearchTyped;
  final ValueChanged<NearbyBranch> onPick;
  final VoidCallback onAllowLocation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline);
    final loc = location;
    // A hand-typed name can be searched explicitly (one call per tap).
    final canSearchTyped = typed.runes.length >= 2 && typed != searched && typed != picked;

    Widget body;
    if (locating && loc == null) {
      body = Text('현재 위치 확인 중…', style: muted);
    } else if (loc == null || !loc.ok) {
      body = Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onAllowLocation,
          icon: const Icon(Icons.my_location, size: 18),
          label: Text(loc?.status == LocationStatus.serviceOff ? '위치 서비스를 켜면 근처 지점을 보여드려요' : '위치를 허용하고 근처 지점 보기'),
        ),
      );
    } else if (searching) {
      body = Text('지점 찾는 중…', style: muted);
    } else if (failed) {
      body = Text('지점을 불러오지 못했어요. 이름만 입력해도 괜찮아요.', style: muted);
    } else if (branches != null && branches!.isNotEmpty) {
      body = Column(
        children: [
          for (final b in branches!.take(5))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              leading: Icon(
                b.name == picked ? Icons.check_circle : Icons.place_outlined,
                size: 20,
                color: b.name == picked ? theme.colorScheme.primary : null,
              ),
              title: Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                [b.distanceLabel, if (b.address.isNotEmpty) b.address].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => onPick(b),
            ),
        ],
      );
    } else if (branches != null) {
      body = Text('근처에서 찾지 못했어요. 일본 현지에서만 보여드려요.', style: muted);
    } else if (canSearchTyped) {
      body = Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onSearchTyped,
          icon: const Icon(Icons.travel_explore, size: 18),
          label: Text('\'$typed\' 근처 지점 찾기', maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      );
    } else {
      body = Text('목록에서 매장을 고르면 가까운 지점을 보여드려요', style: muted);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.near_me_outlined, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 4),
              Text('근처 지점', style: theme.textTheme.labelLarge),
              const Spacer(),
              if (searching || locating)
                const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 4),
          body,
        ],
      ),
    );
  }
}
