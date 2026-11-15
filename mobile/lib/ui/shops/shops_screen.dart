import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../services/ads.dart';
import '../../state/providers.dart';
import '../widgets.dart';
import 'shop_detail_screen.dart';
import 'shop_form_dialog.dart';

/// S2: store visits with progress toward the 5,000-yen threshold.
class ShopsScreen extends ConsumerWidget {
  const ShopsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(summaryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('매장별 장바구니')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showShopFormDialog(context, ref),
        icon: const Icon(Icons.add_business),
        label: const Text('새 매장'),
      ),
      body: summary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('불러오지 못했어요: $e')),
        data: (s) {
          if (s.shops.isEmpty) {
            return const _Empty();
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            children: [
              for (final t in s.shops)
                Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ShopDetailScreen(shopId: t.entry.shop.id)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  t.entry.shop.name,
                                  style: Theme.of(context).textTheme.titleMedium,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              EligibleBadge(eligible: t.eligible),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${dateLabel(t.entry.shop.purchaseDate)} · 세전 ${yen(t.amounts.exclTax)}'
                            '${t.fromReceipts ? ' · 영수증 기준' : ''}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 10),
                          ThresholdProgress(totals: t),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              const BannerAdBox(),
            ],
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storefront_outlined, size: 56, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          const Text('아직 매장이 없어요', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('계산기에서 가격을 입력하고 "담기"를 누르거나\n새 매장을 추가해 보세요.', textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
