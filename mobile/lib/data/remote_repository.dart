import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../core/rules.dart';
import '../core/store_catalog.dart';
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
  static const _storesKey = 'cache.stores';
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

  /// Cached store catalog JSON, or null before the first successful fetch.
  String? cachedStoresJson() => _prefs.getString(_storesKey);

  /// Fetches the store catalog; validates it parses before caching.
  Future<StoreCatalog> fetchStores() async {
    final res = await _client.get(Uri.parse('$_baseUrl/v1/stores')).timeout(_timeout);
    if (res.statusCode != 200) {
      throw http.ClientException('HTTP ${res.statusCode}', res.request?.url);
    }
    final raw = utf8.decode(res.bodyBytes);
    final catalog = StoreCatalog.parse(raw);
    if (catalog.brands.isEmpty) throw const FormatException('empty store catalog');
    await _prefs.setString(_storesKey, raw);
    return catalog;
  }

  /// Branches matching [query] near the location, nearest first. Throws on
  /// network errors or when the server has search disabled or rate-limited.
  Future<List<NearbyBranch>> searchBranches(String query, double lat, double lng) async {
    final uri = Uri.parse('$_baseUrl/v1/places/search')
        .replace(queryParameters: {'q': query, 'lat': lat.toStringAsFixed(5), 'lng': lng.toStringAsFixed(5)});
    final res = await _client.get(uri).timeout(_timeout);
    if (res.statusCode != 200) {
      throw http.ClientException('HTTP ${res.statusCode}', uri);
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return [
      for (final p in (body['places'] as List? ?? const []))
        if (p is Map<String, dynamic>) NearbyBranch.fromJson(p),
    ].where((b) => b.name.isNotEmpty).toList();
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final res = await _client.get(Uri.parse('$_baseUrl$path')).timeout(_timeout);
    if (res.statusCode != 200) {
      throw http.ClientException('HTTP ${res.statusCode}', res.request?.url);
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }
}
