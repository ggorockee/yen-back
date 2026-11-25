import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yen_back/core/app_version.dart';
import 'package:yen_back/services/analytics.dart';
import 'package:yen_back/services/remote_settings.dart';
import 'package:yen_back/state/providers.dart';
import 'package:yen_back/ui/update_gate.dart';

void main() {
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> pump(WidgetTester tester, {String min = '0.0.0', String latest = '0.0.0'}) async {
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          httpClientProvider.overrideWithValue(MockClient((_) async => http.Response('', 202))),
          appVersionProvider.overrideWithValue(AppVersion.parse('1.0.0')),
          remoteSettingsProvider.overrideWithValue(
            Future.value(
              RemoteSettings(
                updatePolicy: UpdatePolicy(
                  minVersion: AppVersion.parse(min),
                  latestVersion: AppVersion.parse(latest),
                  storeUrl: 'https://apps.apple.com/app/id1',
                ),
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: UpdateGate(child: Text('home'))),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('no dialog when the version is current', (tester) async {
    await pump(tester);
    expect(find.text('home'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('forced update cannot be dismissed', (tester) async {
    await pump(tester, min: '2.0.0');
    expect(find.text('업데이트가 필요해요'), findsOneWidget);
    expect(find.text('나중에'), findsNothing);

    await tester.tapAt(const Offset(5, 5));
    await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pumpAndSettle();
    expect(find.text('업데이트가 필요해요'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('optional update is asked once per release', (tester) async {
    await pump(tester, latest: '1.1.0');
    expect(find.text('새 버전이 있어요'), findsOneWidget);
    await tester.tap(find.text('나중에'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));

    await pump(tester, latest: '1.1.0');
    expect(find.byType(AlertDialog), findsNothing);

    await pump(tester, latest: '1.2.0');
    expect(find.text('새 버전이 있어요'), findsOneWidget, reason: 'a newer release asks again');
    await tester.pump(const Duration(seconds: 30));
  });
}
