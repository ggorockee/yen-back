import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/analytics.dart';
import '../../state/providers.dart';

/// S6: what to do at the airport, in order.
class ChecklistScreen extends ConsumerWidget {
  const ChecklistScreen({super.key});

  static const items = [
    ('kiosk_before_checkin', '짐을 부치기 전에 세관 확인', '출국장 면세 키오스크에서 먼저 확인받아요. 짐을 부친 뒤에는 확인받을 수 없어요.'),
    ('passport', '여권 준비', '면세 구매 때 등록한 여권이 필요해요.'),
    ('goods_in_hand', '구매한 물건 지참', '세관이 실물을 확인할 수 있어요. 위탁 수하물에 넣기 전에 확인받으세요.'),
    ('consumables_unopened', '식품·화장품은 일본에서 쓰지 않기', '일본 안에서 소비한 물건은 환급받을 수 없어요.'),
    ('refund_method', '환급 방법 확인', '환급 시점과 수단(카드·현금 등)은 매장이나 환급 사업자마다 달라요.'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checked = ref.watch(checklistProvider).value ?? const <String>{};
    final done = items.where((i) => checked.contains(i.$1)).length;

    return Scaffold(
      appBar: AppBar(title: Text('공항 체크리스트 $done/${items.length}')),
      body: ListView(
        children: [
          for (final (key, title, desc) in items)
            CheckboxListTile(
              value: checked.contains(key),
              title: Text(title),
              subtitle: Text(desc),
              onChanged: (v) async {
                await ref.read(checklistProvider.notifier).toggle(key, v ?? false);
                final now = ref.read(checklistProvider).value ?? const <String>{};
                if (v == true && items.every((i) => now.contains(i.$1))) {
                  ref.read(analyticsProvider).track(AppEvent.checklistCompleted);
                }
              },
            ),
        ],
      ),
    );
  }
}
