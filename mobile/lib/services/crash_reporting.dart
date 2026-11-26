import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Sends crashes to Firebase Crashlytics in release builds.
///
/// Only crash reports go to Google: the error, its stack trace, the device
/// model, OS and app version. Shops, items, amounts, receipt photos and trip
/// dates are never attached.
class CrashReporting {
  const CrashReporting._();

  /// Hooks Flutter and platform errors into Crashlytics once [firebaseReady]
  /// resolves to true. Never throws and never blocks startup.
  static Future<void> enable(Future<bool> firebaseReady) async {
    try {
      if (!await firebaseReady) return;
      final crashlytics = FirebaseCrashlytics.instance;
      await crashlytics.setCrashlyticsCollectionEnabled(kReleaseMode);
      if (!kReleaseMode) return;

      FlutterError.onError = (details) {
        // Silent errors (a failed image load, for example) leave the screen
        // usable, so they are reported without counting as a crash.
        if (details.silent) {
          crashlytics.recordFlutterError(details);
        } else {
          crashlytics.recordFlutterFatalError(details);
        }
      };
      // Uncaught async errors do not close the app: report them as non-fatal.
      PlatformDispatcher.instance.onError = (error, stack) {
        crashlytics.recordError(error, stack);
        return true;
      };
    } catch (e) {
      debugPrint('[CrashReporting] unavailable: $e');
    }
  }
}
