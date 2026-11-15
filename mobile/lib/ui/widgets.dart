import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/trip_summary.dart';
import '../state/providers.dart';

/// "100엔 = 921원 · 11월 13일 기준" with offline/stale hints.
class RateInfoBar extends ConsumerWidget {
  const RateInfoBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rates = ref.watch(ratesProvider);
    final snap = rates.snapshot;
    final theme = Theme.of(context);

    final String text;
    var warn = false;
    if (snap == null) {
      text = rates.loading ? '환율 불러오는 중…' : '환율 정보가 없어요. 인터넷에 연결하면 받아와요.';
      warn = !rates.loading;
    } else {
      final per100 = (snap.jpyKrw * 100).toStringAsFixed(2);
      final suffix = rates.offline ? ' · 오프라인' : (snap.stale ? ' · 오래된 환율' : '');
      text = '100엔 = $per100원 · ${dateLabel(snap.baseDate)} 기준$suffix';
      warn = rates.offline || snap.stale;
    }

    return InkWell(
      onTap: rates.loading ? null : () => ref.read(ratesProvider.notifier).refresh(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(
              warn ? Icons.cloud_off_outlined : Icons.currency_exchange,
              size: 14,
              color: warn ? theme.colorScheme.error : theme.colorScheme.outline,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: warn ? theme.colorScheme.error : theme.colorScheme.outline,
                ),
              ),
            ),
            if (rates.loading) const SizedBox.square(dimension: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
          ],
        ),
      ),
    );
  }
}

/// Progress toward the 5,000-yen threshold.
class ThresholdProgress extends StatelessWidget {
  const ThresholdProgress({super.key, required this.totals});

  final ShopTotals totals;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = totals.eligible ? scheme.primary : scheme.tertiary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: totals.progress, minHeight: 8, color: color),
        ),
        const SizedBox(height: 6),
        Text(
          totals.eligible
              ? '면세 기준 달성 · 예상 환급 ${yen(totals.refundYen)}'
              : '${yen(totals.minPurchaseExclTaxYen)}까지 ${yen(totals.remainingYen)} 남음 (세전)',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class EligibleBadge extends StatelessWidget {
  const EligibleBadge({super.key, required this.eligible});
  final bool eligible;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: eligible ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        eligible ? '면세 대상' : '미달',
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: eligible ? scheme.onPrimaryContainer : scheme.onSurfaceVariant),
      ),
    );
  }
}

/// Standard refund disclaimer shown next to any refund figure.
class RefundDisclaimer extends StatelessWidget {
  const RefundDisclaimer({super.key});

  @override
  Widget build(BuildContext context) => Text(
    '최대 예상액이에요. 실제 환급액은 매장·환급 사업자의 수수료와 방식에 따라 달라질 수 있어요.',
    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
  );
}

/// Parses digits from a text field; empty or invalid is 0.
int parseYen(String s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}

Future<bool> confirm(BuildContext context, String title, String message, {String ok = '삭제'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
        ],
      ),
    ) ??
    false;
