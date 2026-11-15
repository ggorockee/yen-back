import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kReleaseMode;

/// Build-time configuration, set with `--dart-define`.
///
/// Ad unit IDs default to Google's official test units, so debug builds never
/// serve real ads. Release builds must pass the real IDs.
class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    // Release builds use production; debug builds reach a local server
    // (the Android emulator sees the host machine as 10.0.2.2).
    defaultValue: kReleaseMode ? 'https://yen-back.woohalabs.com' : 'http://10.0.2.2:8080',
  );

  static const removeAdsProductId = 'remove_ads';

  /// Upper bound for the system text scale (see YenBackApp.builder).
  static const maxTextScale = 1.5;

  static String get bannerAdUnitId => Platform.isIOS
      ? const String.fromEnvironment('ADMOB_BANNER_IOS', defaultValue: 'ca-app-pub-3940256099942544/2934735716')
      : const String.fromEnvironment('ADMOB_BANNER_ANDROID', defaultValue: 'ca-app-pub-3940256099942544/9214589741');

  static String get interstitialAdUnitId => Platform.isIOS
      ? const String.fromEnvironment('ADMOB_INTERSTITIAL_IOS', defaultValue: 'ca-app-pub-3940256099942544/4411468910')
      : const String.fromEnvironment(
          'ADMOB_INTERSTITIAL_ANDROID',
          defaultValue: 'ca-app-pub-3940256099942544/1033173712',
        );
}
