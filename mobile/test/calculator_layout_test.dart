import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yen_back/services/analytics.dart';
import 'package:yen_back/state/providers.dart';
import 'package:yen_back/ui/calculator/calculator_screen.dart';

/// Regression: the calculator overflowed by 35px on iPhone 15 Pro when a tall
/// banner was shown. The result block must scale instead of overflowing.
void main() {
  for (final (name, size) in [('iPhone SE', const Size(750, 1334)), ('iPhone 15 Pro', const Size(1179, 2556))]) {
    testWidgets('no overflow on $name', (tester) async {
      await initializeDateFormatting('ko_KR');
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = name == 'iPhone SE' ? 2 : 3;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({'purchase.ad_free': true});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            prefsProvider.overrideWithValue(prefs),
            httpClientProvider.overrideWithValue(MockClient((_) async => http.Response('{}', 503))),
          ],
          // Simulate the space a 100px banner and nav bar take.
          child: const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  SizedBox(height: 100),
                  Expanded(child: CalculatorScreen()),
                ],
              ),
              bottomNavigationBar: SizedBox(height: 80),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final k in ['9', '9', '9', '9', '9', '9', '9', '9']) {
        await tester.tap(find.text(k).last);
      }
      await tester.pump();
      expect(find.text('¥99,999,999'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
