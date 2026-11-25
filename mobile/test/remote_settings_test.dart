import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yen_back/core/app_version.dart';
import 'package:yen_back/services/ads.dart';
import 'package:yen_back/services/remote_settings.dart';

RemoteSettings settings(Map<String, Object> values, {bool isIOS = true}) {
  final v = {...RemoteSettings.parameterDefaults, ...values};
  return RemoteSettings.from(
    getBool: (k) => v[k]! as bool,
    getInt: (k) => v[k]! as int,
    getString: (k) => v[k]! as String,
    isIOS: isIOS,
  );
}

void main() {
  group('AppVersion', () {
    test('parses store versions, build numbers and bad input', () {
      expect(AppVersion.parse('1.2.3+45'), const AppVersion(1, 2, 3));
      expect(AppVersion.parse('1.0'), const AppVersion(1, 0, 0));
      expect(AppVersion.parse('abc'), AppVersion.zero);
    });

    test('compares numerically', () {
      expect(AppVersion.parse('1.9.9') < AppVersion.parse('1.10.0'), isTrue);
      expect(AppVersion.parse('1.10.0') < AppVersion.parse('1.9.9'), isFalse);
    });
  });

  group('UpdatePolicy', () {
    final current = AppVersion.parse('1.2.0');
    UpdateRequirement check({String min = '0.0.0', String latest = '0.0.0', String url = 'https://store'}) =>
        UpdatePolicy(
          minVersion: AppVersion.parse(min),
          latestVersion: AppVersion.parse(latest),
          storeUrl: url,
        ).evaluate(current);

    test('forced below min, optional below latest, none otherwise', () {
      expect(check(min: '1.3.0', latest: '1.3.0'), UpdateRequirement.force);
      expect(check(latest: '1.2.1'), UpdateRequirement.optional);
      expect(check(min: '1.2.0', latest: '1.2.0'), UpdateRequirement.none);
      expect(UpdatePolicy.none.evaluate(current), UpdateRequirement.none);
    });

    test('a missing store link never locks users out', () {
      expect(check(min: '9.0.0', latest: '9.0.0', url: ''), UpdateRequirement.none);
    });
  });

  group('RemoteSettings', () {
    test('in-app defaults keep ads as before and show no update prompt', () {
      final s = settings({});
      expect(s.showBannerAd, isTrue);
      expect(s.showInterstitialAd, isTrue);
      expect(s.interstitialMaxPerSession, RemoteSettings.defaults.interstitialMaxPerSession);
      expect(s.interstitialMinGap, RemoteSettings.defaults.interstitialMinGap);
      expect(s.updatePolicy.evaluate(AppVersion.parse('1.0')), UpdateRequirement.none);
    });

    test('reads the version rules of its own platform', () {
      final values = {'ios_min_version': '2.0.0', 'ios_store_url': 'https://ios'};
      expect(settings(values).updatePolicy.minVersion, const AppVersion(2, 0, 0));
      expect(settings(values, isIOS: false).updatePolicy.minVersion, AppVersion.zero);
    });

    test('corrects numbers that would break the ad frequency cap', () {
      final s = settings({'interstitial_max_per_session': -1, 'interstitial_min_gap_minutes': 0});
      expect(s.interstitialMaxPerSession, 2);
      expect(s.interstitialMinGap, const Duration(minutes: 3));
      expect(settings({'interstitial_max_per_session': 0}).interstitialMaxPerSession, 0);
    });

    test('console template has exactly the keys the app reads', () {
      final template = jsonDecode(File('../firebase/remoteconfig.template.json').readAsStringSync()) as Map;
      final groups = (template['parameterGroups'] as Map).values.cast<Map>();
      final keys = groups.expand((g) => (g['parameters'] as Map).keys.cast<String>()).toSet();
      expect(keys, RemoteSettings.parameterDefaults.keys.toSet());
    });
  });

  test('remote limits replace the interstitial frequency cap', () {
    final start = DateTime(2026, 11, 25, 12);
    final policy = InterstitialPolicy(sessionStart: start);
    InterstitialController(policy).enable(maxPerSession: 1, minGap: const Duration(minutes: 10));
    final first = start.add(const Duration(minutes: 2));
    policy.recordShown(first);
    expect(policy.canShow(first.add(const Duration(hours: 1))), isFalse);
    expect(policy.minGap, const Duration(minutes: 10));
  });
}
