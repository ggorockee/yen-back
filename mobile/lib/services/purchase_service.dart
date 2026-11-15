import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

import '../config.dart';

/// One-time "remove ads" purchase, abstracted so tests can use a fake.
abstract class Purchases {
  /// Starts listening to the store. Call once at launch so purchases that
  /// completed while the app was closed are delivered.
  void start();

  /// Localized price, or null when the store or product is unavailable.
  Future<String?> price();
  Future<void> buy();
  Future<void> restore();

  /// User-facing messages (errors, confirmations).
  Stream<String> get messages;
  Future<void> dispose();
}

/// Store-backed implementation.
///
/// MVP note: the entitlement is granted from the store's purchase stream
/// without server-side receipt validation.
class StorePurchases implements Purchases {
  StorePurchases(this._iap, {required this.onEntitled});

  final InAppPurchase _iap;

  /// Grants the entitlement; returns true if it was newly granted.
  final Future<bool> Function() onEntitled;
  final _messages = StreamController<String>.broadcast();
  StreamSubscription<List<PurchaseDetails>>? _sub;
  ProductDetails? _product;

  @override
  Stream<String> get messages => _messages.stream;

  @override
  void start() {
    _sub ??= _iap.purchaseStream.listen(_onPurchases, onError: (Object _) => _messages.add('결제 처리 중 오류가 발생했어요.'));
  }

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    await _messages.close();
  }

  @override
  Future<String?> price() async => (await _loadProduct())?.price;

  @override
  Future<void> buy() async {
    final product = await _loadProduct();
    if (product == null) {
      _messages.add('지금은 스토어에 연결할 수 없어요. 잠시 후 다시 시도해 주세요.');
      return;
    }
    try {
      await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));
    } catch (_) {
      _messages.add('결제를 시작하지 못했어요.');
    }
  }

  @override
  Future<void> restore() async {
    try {
      await _iap.restorePurchases();
    } catch (_) {
      _messages.add('구매 내역을 불러오지 못했어요.');
    }
  }

  /// Store connection failures (no Play services, simulator) mean "unavailable".
  Future<ProductDetails?> _loadProduct() async {
    if (_product != null) return _product;
    try {
      if (!await _iap.isAvailable()) return null;
      final res = await _iap.queryProductDetails({AppConfig.removeAdsProductId});
      if (res.productDetails.isEmpty) return null;
      return _product = res.productDetails.first;
    } catch (_) {
      return null;
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.productID != AppConfig.removeAdsProductId) continue;
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (await onEntitled()) _messages.add('광고가 제거됐어요. 고마워요!');
        case PurchaseStatus.error:
          _messages.add('결제에 실패했어요.');
        case PurchaseStatus.pending:
        case PurchaseStatus.canceled:
          break;
      }
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
    }
  }
}
