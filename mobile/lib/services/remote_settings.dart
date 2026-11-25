import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import '../core/app_version.dart';

/// Settings controlled from Firebase Remote Config, fixed for one app run.
///
/// The console values are versioned in firebase/remoteconfig.template.json.
class RemoteSettings {
  const RemoteSettings({
    this.showBannerAd = true,
    this.showInterstitialAd = true,
    this.interstitialMaxPerSession = 2,
    this.interstitialMinGap = const Duration(minutes: 3),
    this.updatePolicy = UpdatePolicy.none,
  });

  /// Used when Firebase is unavailable (offline first run, no config file):
  /// the app behaves as it did before Remote Config, with no update prompt.
  static const defaults = RemoteSettings();

  final bool showBannerAd;
  final bool showInterstitialAd;
  final int interstitialMaxPerSession;
  final Duration interstitialMinGap;
  final UpdatePolicy updatePolicy;

  static const _showBanner = 'show_banner_ad';
  static const _showInterstitial = 'show_interstitial_ad';
  static const _interstitialMax = 'interstitial_max_per_session';
  static const _interstitialGap = 'interstitial_min_gap_minutes';

  /// In-app defaults; keys must match firebase/remoteconfig.template.json.
  static const parameterDefaults = <String, Object>{
    _showBanner: true,
    _showInterstitial: true,
    _interstitialMax: 2,
    _interstitialGap: 3,
    'ios_min_version': '0.0.0',
    'ios_latest_version': '0.0.0',
    'ios_store_url': '',
    'android_min_version': '0.0.0',
    'android_latest_version': '0.0.0',
    'android_store_url': '',
    'update_message': '',
  };

  /// Builds settings from raw parameter values, correcting numbers that would
  /// break the ad frequency cap.
  factory RemoteSettings.from({
    required bool Function(String) getBool,
    required int Function(String) getInt,
    required String Function(String) getString,
    required bool isIOS,
  }) {
    final os = isIOS ? 'ios' : 'android';
    final max = getInt(_interstitialMax);
    final gap = getInt(_interstitialGap);
    return RemoteSettings(
      showBannerAd: getBool(_showBanner),
      showInterstitialAd: getBool(_showInterstitial),
      interstitialMaxPerSession: max < 0 ? defaults.interstitialMaxPerSession : max,
      interstitialMinGap: gap < 1 ? defaults.interstitialMinGap : Duration(minutes: gap),
      updatePolicy: UpdatePolicy(
        minVersion: AppVersion.parse(getString('${os}_min_version')),
        latestVersion: AppVersion.parse(getString('${os}_latest_version')),
        storeUrl: getString('${os}_store_url').trim(),
        message: getString('update_message').trim(),
      ),
    );
  }

  /// Starts Firebase (Analytics then records installs by itself) and reads
  /// Remote Config. Never throws and never blocks app startup.
  static Future<RemoteSettings> load() async {
    try {
      // Reads GoogleService-Info.plist / google-services.json.
      await Firebase.initializeApp();
      final config = FirebaseRemoteConfig.instance;
      await config.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 8),
          minimumFetchInterval: kReleaseMode ? const Duration(hours: 1) : Duration.zero,
        ),
      );
      await config.setDefaults(parameterDefaults);
      try {
        await config.fetchAndActivate();
      } catch (e) {
        // Offline: values activated on an earlier run still apply.
        debugPrint('[RemoteSettings] fetch failed, using the last values: $e');
      }
      return RemoteSettings.from(
        getBool: config.getBool,
        getInt: config.getInt,
        getString: config.getString,
        isIOS: Platform.isIOS,
      );
    } catch (e) {
      debugPrint('[RemoteSettings] Firebase unavailable, using defaults: $e');
      return defaults;
    }
  }
}
