import 'package:flutter_test/flutter_test.dart';
import 'package:yen_back/config.dart';

void main() {
  test('remove-ads purchase is off by default (no Korean business registration for store sales)', () {
    expect(AppConfig.iapEnabled, isFalse);
  });
}
