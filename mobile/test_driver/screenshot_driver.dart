import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Saves screenshots taken by integration_test/store_screenshots_test.dart.
///   flutter drive --driver=test_driver/screenshot_driver.dart \
///     --target=integration_test/store_screenshots_test.dart -d SIMULATOR_ID
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final file = File('build/store_screenshots/$name.png');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    return true;
  },
);
