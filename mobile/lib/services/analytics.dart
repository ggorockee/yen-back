import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

/// Activity events reported to the server's `/v1/events`, which turns them into
/// Prometheus counters. Only the event name and a count are sent: no user id,
/// device id, amounts or any other personal data.
///
/// Names must match the server allowlist (server/internal/telemetry).
enum AppEvent {
  appOpen('app_open'),
  itemAdded('item_added'),
  shopCreated('shop_created'),
  receiptAdded('receipt_added'),
  departureSet('departure_set'),
  checklistCompleted('checklist_completed'),
  removeAdsPurchased('remove_ads_purchased'),
  onboardingCompleted('onboarding_completed'),
  branchPicked('branch_picked');

  const AppEvent(this.wire);
  final String wire;
}

/// Adds app identification headers to every request so the server can break
/// traffic down by platform and version.
class AppHttpClient extends http.BaseClient {
  AppHttpClient(this._inner, {required this.appVersion});

  final http.Client _inner;
  final String appVersion;

  static String get platform => Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'other');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['X-App-Platform'] = platform;
    request.headers['X-App-Version'] = appVersion;
    return _inner.send(request);
  }
}

/// Batches events and sends them best-effort. Failed batches are dropped:
/// activity metrics are approximate by design and must never affect the app.
class Analytics {
  Analytics(this._client, {String? baseUrl, this.flushAfter = const Duration(seconds: 20)})
    : _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;
  final Duration flushAfter;
  final Map<String, int> _pending = {};
  Timer? _timer;

  void track(AppEvent e) {
    _pending.update(e.wire, (n) => n + 1, ifAbsent: () => 1);
    _timer ??= Timer(flushAfter, flush);
  }

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return;
    final batch = Map.of(_pending);
    _pending.clear();
    try {
      await _client
          .post(
            Uri.parse('$_baseUrl/v1/events'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'events': [
                for (final e in batch.entries) {'name': e.key, 'count': e.value},
              ],
            }),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Best effort.
    }
  }
}

final httpClientProvider = Provider<http.Client>((_) => throw UnimplementedError());

final analyticsProvider = Provider<Analytics>((ref) {
  final a = Analytics(ref.watch(httpClientProvider));
  ref.onDispose(a.flush);
  return a;
});
