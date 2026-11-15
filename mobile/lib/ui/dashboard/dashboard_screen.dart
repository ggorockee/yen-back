import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/trip_summary.dart';
import '../../services/ads.dart';
import '../../state/providers.dart';
import '../settings/trip_form_sheet.dart';
import '../widgets.dart';
import 'checklist_screen.dart';

/// S5: totals, expected refund, Korean allowance and departure.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(summaryProvider);
    final rules = ref.watch(rulesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('내 여행')),
      body: summary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('불러오지 못했어요: $e')),
        data: (s) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (rules.notice.isNotEmpty)
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: ListTile(leading: const Icon(Icons.campaign_outlined), title: Text(rules.notice)),
              ),
            _DepartureCard(summary: s),
            if (s.deadlineMissed.isNotEmpty) _DeadlineWarning(summary: s),
            _RefundCard(summary: s),
            _DutyFreeCard(summary: s),
            const SizedBox(height: 8),
            const BannerAdBox(),
          ],
        ),
      ),
    );
  }
}

class _DepartureCard extends ConsumerWidget {
  const _DepartureCard({required this.summary});
  final TripSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(tripProvider).value;
    final dep = summary.departureAt;
    final days = summary.daysUntilDeparture(DateTime.now());
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.flight_takeoff),
                const SizedBox(width: 8),
                Text('출국', style: theme.textTheme.titleMedium),
                const Spacer(),
                if (days != null)
                  Text(
                    days > 0 ? 'D-$days' : (days == 0 ? 'D-Day' : '출국 완료'),
                    style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              dep == null
                  ? '출국일을 입력하면 세관 확인 알림을 보내드려요.'
                  : '${dateTimeLabel(dep)}${trip == null || trip.airport.isEmpty ? '' : ' · ${trip.airport}'}',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => showTripFormSheet(context),
                    child: Text(dep == null ? '출국일 입력' : '변경'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const ChecklistScreen())),
                    child: const Text('공항 체크리스트'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeadlineWarning extends StatelessWidget {
  const _DeadlineWarning({required this.summary});
  final TripSummary summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: ListTile(
        leading: Icon(Icons.warning_amber, color: scheme.onErrorContainer),
        title: const Text('세관 확인 기한이 출국일보다 먼저 끝나요'),
        subtitle: Text(
          summary.deadlineMissed.map((t) => '${t.entry.shop.name} (${dateLabel(t.customsDeadline)}까지)').join('\n'),
        ),
      ),
    );
  }
}

class _RefundCard extends ConsumerWidget {
  const _RefundCard({required this.summary});
  final TripSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rates = summary.rates;
    final theme = Theme.of(context);
    String krw(int y) => rates == null ? '' : ' · ${won(rates.yenToWon(y))}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('최대 예상 환급액', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '${yen(summary.refundYen)}${krw(summary.refundYen)}',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text('면세 대상 매장 ${summary.eligibleCount} / ${summary.shops.length}곳'),
            Text('총 결제 ${yen(summary.totalInclYen)}${krw(summary.totalInclYen)}'),
            const SizedBox(height: 8),
            const RefundDisclaimer(),
          ],
        ),
      ),
    );
  }
}

class _DutyFreeCard extends StatelessWidget {
  const _DutyFreeCard({required this.summary});
  final TripSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usdValue = summary.generalUsd;
    final limit = summary.dutyFreeLimitUsd;
    final over = summary.overDutyFreeLimit;
    final color = over ? theme.colorScheme.error : theme.colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('한국 입국 면세한도 (1인 \$$limit)', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (usdValue == null)
              const Text('환율 정보가 있어야 계산할 수 있어요.')
            else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: (usdValue / limit).clamp(0.0, 1.0), minHeight: 8, color: color),
              ),
              const SizedBox(height: 6),
              Text(
                '${usd(usdValue)} / \$$limit',
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
              if (over)
                Text('면세한도를 넘었어요. 입국 시 세관에 자진신고하면 가산세를 피할 수 있어요.', style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (summary.restrictedInclYen > 0) ...[
              const SizedBox(height: 8),
              Text(
                '술·담배·향수 ${yen(summary.restrictedInclYen)}은 별도 한도로 계산돼 위 금액에서 빠져 있어요.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '기준 환율로 계산한 참고 금액이에요. 세부 기준은 관세청 안내를 확인하세요.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
