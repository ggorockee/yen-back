import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yen_back/config.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('remove-ads purchase is offered on Android', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(AppConfig.iapEnabled, isTrue);
  });

  test('remove-ads purchase stays hidden on iOS (no Korean tax ID for App Store sales)', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(AppConfig.iapEnabled, isFalse);
  });
}
