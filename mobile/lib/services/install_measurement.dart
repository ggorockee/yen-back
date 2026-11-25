import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Firebase Analytics for install measurement.
///
/// Collection is off in Info.plist / AndroidManifest.xml and starts only where
/// UMP says consent is not needed (outside the EEA, UK and Switzerland). A UMP
/// status of "obtained" also covers users who refused, and refusals reach
/// Analytics only when consent mode is on in AdMob (Privacy & messaging >
/// European regulations > Settings), which it is not. So it stays off there.
class InstallMeasurement {
  static bool allowedBy(ConsentStatus status) => status == ConsentStatus.notRequired;

  /// Call after the consent check. Never throws.
  static Future<void> startIfAllowed() async {
    try {
      if (Firebase.apps.isEmpty) return;
      final allowed = allowedBy(await ConsentInformation.instance.getConsentStatus());
      // Also switches off for a user who moved into a consent region.
      await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(allowed);
    } catch (e) {
      debugPrint('[InstallMeasurement] not started: $e');
    }
  }
}
