import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config.dart';
import '../state/providers.dart';

/// Pure frequency policy for interstitials, kept separate for testing.
///
/// Shown only after a completed action (saving a shop or receipt), never during
/// calculation: at most [maxPerSession] per session, [minGap] apart, and not in
/// the first [warmup] after launch.
class InterstitialPolicy {
  InterstitialPolicy({
    required this.sessionStart,
    this.maxPerSession = 2,
    this.minGap = const Duration(minutes: 3),
    this.warmup = const Duration(minutes: 1),
  });

  final DateTime sessionStart;
  final int maxPerSession;
  final Duration minGap;
  final Duration warmup;

  int _shown = 0;
  DateTime? _lastShown;

  bool canShow(DateTime now) {
    if (_shown >= maxPerSession) return false;
    if (now.difference(sessionStart) < warmup) return false;
    final last = _lastShown;
    return last == null || now.difference(last) >= minGap;
  }

  void recordShown(DateTime now) {
    _shown++;
    _lastShown = now;
  }
}

/// Preloads one interstitial and shows it when the policy allows.
class InterstitialController {
  InterstitialController(this._policy);

  final InterstitialPolicy _policy;
  InterstitialAd? _ad;
  bool _loading = false;
  bool _enabled = false;

  /// Allows ad requests; called once consent permits ads.
  void enable() => _enabled = true;

  void preload() {
    if (!_enabled || _ad != null || _loading) return;
    _loading = true;
    InterstitialAd.load(
      adUnitId: AppConfig.interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loading = false;
          _ad = ad;
        },
        onAdFailedToLoad: (_) => _loading = false,
      ),
    );
  }

  /// Call after the user finishes an action.
  void maybeShow() {
    final ad = _ad;
    final now = DateTime.now();
    if (ad == null || !_policy.canShow(now)) {
      preload();
      return;
    }
    _ad = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        preload();
      },
      onAdFailedToShowFullScreenContent: (a, _) {
        a.dispose();
        preload();
      },
    );
    _policy.recordShown(now);
    ad.show();
  }
}

/// Adaptive anchored banner. Collapses to nothing for ad-free users or when
/// no ad loads (offline), so it never leaves an empty gap.
class BannerAdBox extends ConsumerStatefulWidget {
  const BannerAdBox({super.key, this.compact = false});

  /// Uses the fixed 320x50 banner instead of a large adaptive one, for screens
  /// where vertical space matters (the calculator).
  final bool compact;

  @override
  ConsumerState<BannerAdBox> createState() => _BannerAdBoxState();
}

class _BannerAdBoxState extends ConsumerState<BannerAdBox> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_requested) {
      _requested = true;
      _load(MediaQuery.sizeOf(context).width.truncate());
    }
  }

  Future<void> _load(int width) async {
    if (!await ref.read(adsReadyProvider) || !mounted) return;
    final size = widget.compact ? AdSize.banner : await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (!mounted || size == null) return;
    final ad = BannerAd(
      adUnitId: AppConfig.bannerAdUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) => ad.dispose(),
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      ),
    );
  }
}
