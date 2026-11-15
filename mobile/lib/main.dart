import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'data/receipt_files.dart';
import 'services/analytics.dart';
import 'services/notification_service.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final (prefs, db, files, notifications, info, _) = await (
    SharedPreferences.getInstance(),
    AppDatabase.open(),
    ReceiptFiles.open(),
    NotificationService.init(),
    PackageInfo.fromPlatform(),
    initializeDateFormatting('ko_KR'),
  ).wait;

  // Ads must never block startup; the SDK initializes in the background.
  MobileAds.instance.initialize();

  final container = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      databaseProvider.overrideWithValue(db),
      receiptFilesProvider.overrideWithValue(files),
      notificationsProvider.overrideWithValue(notifications),
      httpClientProvider.overrideWithValue(AppHttpClient(http.Client(), appVersion: info.version)),
    ],
  );
  container.read(analyticsProvider).track(AppEvent.appOpen);
  container.read(purchasesProvider).start();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const _Lifecycle(child: YenBackApp()),
    ),
  );
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
