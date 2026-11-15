import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/tax.dart';
import '../../services/ads.dart';
import '../../state/providers.dart';
import '../shops/item_form_sheet.dart';
import '../widgets.dart';

/// S1: enter a yen price, see tax split and KRW instantly.
class CalculatorScreen extends ConsumerStatefulWidget {
  const CalculatorScreen({super.key});

  @override
  ConsumerState<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends ConsumerState<CalculatorScreen> {
  String _digits = '';
  PriceMode _mode = PriceMode.inclTax;
  bool _reduced = false;

  static const _maxDigits = 8; // up to ¥99,999,999

  int get _amount => int.tryParse(_digits) ?? 0;

  void _press(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      if (key == '⌫') {
        if (_digits.isNotEmpty) _digits = _digits.substring(0, _digits.length - 1);
      } else if (_digits.length + key.length <= _maxDigits) {
        if (_digits.isEmpty && key.startsWith('0')) return;
        _digits += key;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final rules = ref.watch(rulesProvider);
    final rates = ref.watch(ratesProvider).snapshot;
    final rate = _reduced ? rules.reducedTaxRatePct : rules.standardTaxRatePct;
    final b = PriceBreakdown.from(_amount, _mode, rate);
    final theme = Theme.of(context);

    String krw(int y) => rates == null ? '—' : won(rates.yenToWon(y));

    return Scaffold(
      appBar: AppBar(title: const Text('돌려받엔')),
      body: SafeArea(
        child: Column(
          children: [
            const RateInfoBar(),
            const BannerAdBox(compact: true),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SegmentedButton<PriceMode>(
                          segments: [for (final m in PriceMode.values) ButtonSegment(value: m, label: Text(m.label))],
                          selected: {_mode},
                          showSelectedIcon: false,
                          onSelectionChanged: (s) => setState(() => _mode = s.first),
                        ),
                        const Spacer(),
                        ChoiceChip(
                          label: Text('${rules.reducedTaxRatePct}% 식품'),
                          selected: _reduced,
                          onSelected: (v) => setState(() => _reduced = v),
                        ),
                      ],
                    ),
                    // Scales down instead of overflowing on short screens or
                    // when a taller banner is shown.
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) => FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width: constraints.maxWidth,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                FittedBox(
                                  alignment: Alignment.centerRight,
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    _digits.isEmpty ? '¥0' : yen(_amount),
                                    style: theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                Text(
                                  '결제 금액 ${krw(b.inclTax)}',
                                  textAlign: TextAlign.right,
                                  style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary),
                                ),
                                const SizedBox(height: 12),
                                _line('세전', '${yen(b.exclTax)} · ${krw(b.exclTax)}'),
                                _line('소비세 ($rate%)', '${yen(b.tax)} · ${krw(b.tax)}'),
                                _line('세금 포함', '${yen(b.inclTax)} · ${krw(b.inclTax)}'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _Keypad(onKey: _press, onClear: () => setState(() => _digits = '')),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: _amount == 0
                    ? null
                    : () async {
                        final added = await showItemFormSheet(
                          context,
                          presetPriceYen: _amount,
                          presetMode: _mode,
                          presetRatePct: rate,
                        );
                        if (added == true) setState(() => _digits = '');
                      },
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('매장 장바구니에 담기'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Text(label, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
        const Spacer(),
        Text(value, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
      ],
    ),
  );
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onKey, required this.onClear});

  final ValueChanged<String> onKey;
  final VoidCallback onClear;

  static const _keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '00', '0', '⌫'];

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.headlineSmall;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          for (var row = 0; row < 4; row++)
            SizedBox(
              height: 52,
              child: Row(
                children: [for (final k in _keys.sublist(row * 3, row * 3 + 3)) Expanded(child: _key(k, style))],
              ),
            ),
        ],
      ),
    );
  }

  Widget _key(String k, TextStyle? style) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: () => onKey(k),
    onLongPress: k == '⌫' ? onClear : null,
    child: Center(
      child: k == '⌫'
          ? Semantics(label: '지우기, 길게 누르면 전체 삭제', child: const Icon(Icons.backspace_outlined))
          : Text(k, style: style),
    ),
  );
}
