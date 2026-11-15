import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../services/analytics.dart';
import '../../state/providers.dart';
import '../settings/trip_form_sheet.dart';

/// S0: three pages explaining the refund method, then optional departure input.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _page = PageController();
  int _index = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    ref.read(analyticsProvider).track(AppEvent.onboardingCompleted);
    await ref.read(onboardingDoneProvider.notifier).complete();
  }

  @override
  Widget build(BuildContext context) {
    final rules = ref.watch(rulesProvider);
    final hasDeparture = ref.watch(tripProvider).value?.departureAt != null;
    final pages = [
      (
        Icons.receipt_long,
        '일본 면세가 바뀌었어요',
        '${rules.effectiveFrom.year}년 ${rules.effectiveFrom.month}월부터 매장에서는 세금까지 내고, '
            '출국할 때 세관 확인을 받으면 소비세를 돌려받는 "리펀드 방식"이에요.',
      ),
      (
        Icons.storefront,
        '${number(rules.minPurchaseExclTaxYen)}엔, ${rules.customsDeadlineDays}일',
        '같은 날 같은 매장에서 세전 ${number(rules.minPurchaseExclTaxYen)}엔 이상 사야 하고, '
            '구매일부터 ${rules.customsDeadlineDays}일 안에 출국하면서 짐을 부치기 전에 세관 확인을 받아야 해요.',
      ),
      (Icons.notifications_active, '돌려받엔이 챙겨드려요', '매장별로 남은 금액을 알려주고, 출국 전날과 공항 가기 전에 세관 확인을 잊지 않게 알려드려요.'),
    ];
    final last = _index == pages.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _finish, child: const Text('건너뛰기')),
            ),
            Expanded(
              child: PageView(
                controller: _page,
                onPageChanged: (i) => setState(() => _index = i),
                children: [
                  for (final (icon, title, body) in pages)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, size: 72, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(height: 24),
                          Text(
                            title,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Text(body, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < pages.length; i++)
                  Container(
                    margin: const EdgeInsets.all(4),
                    width: i == _index ? 18 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _index
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  if (last && !hasDeparture)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: () => showTripFormSheet(context),
                      icon: const Icon(Icons.flight_takeoff),
                      label: const Text('출국일 입력하고 알림 받기'),
                    ),
                  const SizedBox(height: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: last
                        ? _finish
                        : () => _page.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                    child: Text(last ? '시작하기' : '다음'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
