import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'config.dart';
import 'core/app_version.dart';
import 'data/app_database.dart';
import 'data/receipt_files.dart';
import 'services/ad_consent.dart';
import 'services/analytics.dart';
import 'services/crash_reporting.dart';
import 'services/install_measurement.dart';
import 'services/notification_service.dart';
import 'services/remote_settings.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final (prefs, db, files, notifications, info, storesJson, _) = await (
    SharedPreferences.getInstance(),
    AppDatabase.open(),
    ReceiptFiles.open(),
    NotificationService.init(),
    PackageInfo.fromPlatform(),
    rootBundle.loadString('assets/stores.json'),
    initializeDateFormatting('ko_KR'),
  ).wait;

  // Started before consent: UMP passes consent choices on to Firebase.
  final firebase = RemoteSettings.startFirebase();
  unawaited(CrashReporting.enable(firebase));

  // Ads must never block startup. Consent (EEA/UK/CH) is asked after the first
  // frame, since the form needs a visible screen; ads load once it resolves.
  final adsReady = Completer<bool>();

  final container = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      databaseProvider.overrideWithValue(db),
      receiptFilesProvider.overrideWithValue(files),
      notificationsProvider.overrideWithValue(notifications),
      bundledStoresJsonProvider.overrideWithValue(storesJson),
      httpClientProvider.overrideWithValue(AppHttpClient(http.Client(), appVersion: info.version)),
      adsReadyProvider.overrideWithValue(adsReady.future),
      appVersionProvider.overrideWithValue(AppVersion.parse(info.version)),
      // Not awaited: the app opens right away and reacts when settings arrive.
      remoteSettingsProvider.overrideWithValue(RemoteSettings.load(firebase)),
    ],
  );
  container.read(analyticsProvider).track(AppEvent.appOpen);
  if (AppConfig.iapEnabled) container.read(purchasesProvider).start();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const _Lifecycle(child: YenBackApp()),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    adsReady.complete(_consentThenAds(firebase));
  });
}

Future<bool> _consentThenAds(Future<bool> firebase) async {
  await firebase;
  try {
    return await AdConsent.gatherAndStartAds();
  } catch (_) {
    return false;
  } finally {
    await InstallMeasurement.startIfAllowed();
  }
}

/// Flushes pending activity events when the app goes to the background.
class _Lifecycle extends ConsumerStatefulWidget {
  const _Lifecycle({required this.child});
  final Widget child;

  @override
  ConsumerState<_Lifecycle> createState() => _LifecycleState();
}

class _LifecycleState extends ConsumerState<_Lifecycle> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) ref.read(analyticsProvider).flush();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
