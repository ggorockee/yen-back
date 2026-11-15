import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../core/rules.dart';
import 'models.dart';

/// Fetches rates and rules from the yen-back server and caches the last good
/// response so the app keeps working offline.
class RemoteRepository {
  RemoteRepository(this._prefs, {http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final SharedPreferences _prefs;
  final http.Client _client;
  final String _baseUrl;

  static const _ratesKey = 'cache.rates';
  static const _rulesKey = 'cache.rules';
  static const _timeout = Duration(seconds: 8);

  RateSnapshot? cachedRates() {
    final raw = _prefs.getString(_ratesKey);
    if (raw == null) return null;
    try {
      return RateSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  TaxFreeRules cachedRules() {
    final raw = _prefs.getString(_rulesKey);
    if (raw == null) return TaxFreeRules.defaults;
    try {
      return TaxFreeRules.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return TaxFreeRules.defaults;
    }
  }

  /// Throws on network or parse failure; the cache is left untouched then.
  Future<RateSnapshot> fetchRates() async {
    final body = await _get('/v1/rates/latest');
    final snap = RateSnapshot.fromJson(body);
    await _prefs.setString(_ratesKey, jsonEncode(snap.toJson()));
    return snap;
  }

  Future<TaxFreeRules> fetchRules() async {
    final body = await _get('/v1/rules');
    final rules = TaxFreeRules.fromJson(body);
    await _prefs.setString(_rulesKey, jsonEncode(rules.toJson()));
    return rules;
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final res = await _client.get(Uri.parse('$_baseUrl$path')).timeout(_timeout);
    if (res.statusCode != 200) {
      throw http.ClientException('HTTP ${res.statusCode}', res.request?.url);
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }
}
