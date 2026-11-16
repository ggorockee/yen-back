import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../core/format.dart';
import '../../services/ad_consent.dart';
import '../../state/providers.dart';
import 'trip_form_sheet.dart';

/// S7: trip, exchange rates, regulation sources and privacy.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _adPrivacyOptions = false;

  @override
  void initState() {
    super.initState();
    // Only users under a consent regulation (EEA/UK/CH) get the entry.
    ref.read(adsReadyProvider).then((_) => AdConsent.privacyOptionsRequired()).then((required) {
      if (mounted && required) setState(() => _adPrivacyOptions = true);
    }, onError: (Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final trip = ref.watch(tripProvider).value;
    final rules = ref.watch(rulesProvider);
    final rates = ref.watch(ratesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          const _Header('여행'),
          ListTile(
            leading: const Icon(Icons.flight_takeoff),
            title: const Text('출국 일시'),
            subtitle: Text(trip?.departureAt == null ? '미입력' : dateTimeLabel(trip!.departureAt!)),
            onTap: () => showTripFormSheet(context),
          ),
          const _Header('환율'),
          ListTile(
            leading: const Icon(Icons.currency_exchange),
            title: const Text('기준 환율 새로고침'),
            subtitle: Text(
              rates.snapshot == null
                  ? '받은 환율 없음'
                  : '한국수출입은행 매매기준율 · ${dateLabel(rates.snapshot!.baseDate)} 기준\n카드 결제 환율과는 차이가 있어요.',
            ),
            isThreeLine: rates.snapshot != null,
            onTap: () => ref.read(ratesProvider.notifier).refresh(),
          ),
          const _Header('제도 안내'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('일본 면세 리펀드 방식'),
            subtitle: Text(
              '${rules.effectiveFrom.year}년 ${rules.effectiveFrom.month}월 ${rules.effectiveFrom.day}일 구매분부터 적용. '
              '같은 날 같은 매장 세전 ${yen(rules.minPurchaseExclTaxYen)} 이상, '
              '구매일부터 ${rules.customsDeadlineDays}일 안에 출국하며 세관 확인.',
            ),
          ),
          for (final s in rules.sources)
            ListTile(
              dense: true,
              leading: const Icon(Icons.open_in_new, size: 18),
              title: Text(s.title),
              onTap: () => launchUrl(Uri.parse(s.url), mode: LaunchMode.externalApplication),
            ),
          const _Header('개인정보'),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('내 데이터는 기기에만 저장돼요'),
            subtitle: Text(
              '매장, 상품, 영수증 사진, 출국일은 이 기기에만 저장돼요. 서버에는 환율 조회, '
              '기능 사용 횟수(개인을 식별할 수 없는 집계), 근처 지점을 찾을 때의 현재 위치만 전송되고 '
              '위치는 저장하지 않아요. 앱을 삭제하면 모든 데이터가 지워져요.',
            ),
            isThreeLine: true,
          ),
          if (_adPrivacyOptions)
            const ListTile(
              leading: Icon(Icons.tune),
              title: Text('광고 개인정보 설정'),
              subtitle: Text('맞춤 광고 동의를 변경할 수 있어요.'),
              onTap: AdConsent.showPrivacyOptions,
            ),
          ListTile(
            leading: const Icon(Icons.policy_outlined),
            title: const Text('개인정보처리방침'),
            onTap: () => launchUrl(Uri.parse(AppConfig.privacyPolicyUrl), mode: LaunchMode.externalApplication),
          ),
          const _Header('안내'),
          const ListTile(
            leading: Icon(Icons.gavel_outlined),
            title: Text('비공식 앱'),
            subtitle: Text(
              '돌려받엔은 일본·한국 정부기관과 관련 없는 비공식 앱이에요. 계산 결과는 참고용이며, '
              '실제 환급과 면세 판단은 매장·세관의 안내를 따라 주세요.',
            ),
            isThreeLine: true,
          ),
          ListTile(leading: const Icon(Icons.rule), title: const Text('제도 기준 버전'), subtitle: Text(rules.version)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}
