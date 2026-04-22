import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:accident_app/shared/models/emergency_service.dart';

final overpassServiceProvider = Provider<OverpassService>((ref) {
  return OverpassService();
});

class OverpassService {
  static const _overpassUrls = <String>[
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass.nchc.org.tw/api/interpreter',
  ];

  static const _cacheKey       = 'cached_emergency_pois_v2';
  static const _radiusMeters   = 20000; // 20 km
  static const _maxCachedPois  = 300;   // cap to prevent unbounded SharedPrefs growth

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: const {
      'User-Agent': 'accident_app_flutter/2.0 (Emergency SOS)',
    },
  ));

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Fetch from Overpass, cache locally. Falls back to cache on error.
  Future<List<EmergencyService>> fetchAndCache(double lat, double lng) async {
    // Guard: reject obviously invalid coordinates
    if (lat == 0.0 && lng == 0.0) {
      _log('⚠️  Skipping fetch — zero coordinates (GPS not ready)');
      return getCached();
    }
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      _log('⚠️  Skipping fetch — coordinates out of range: $lat, $lng');
      return getCached();
    }

    final query = _buildQuery(lat, lng, _radiusMeters);
    _log('Fetching POIs @ lat=${lat.toStringAsFixed(5)} '
        'lng=${lng.toStringAsFixed(5)} radius=${_radiusMeters}m');

    DioException? lastErr;
    for (final url in _overpassUrls) {
      try {
        _log('Trying endpoint: $url');
        final response = await _dio.post<String>(
          url,
          data: 'data=${Uri.encodeComponent(query)}',
          options: Options(contentType: 'application/x-www-form-urlencoded'),
        );

        if (response.data == null || response.data!.isEmpty) {
          _log('Empty response from $url — trying next');
          continue;
        }

        final json = jsonDecode(response.data!) as Map<String, dynamic>;
        final rawElements = json['elements'];
        if (rawElements == null || rawElements is! List) {
          _log('Malformed response from $url — no elements array');
          continue;
        }

        final elements = (rawElements).cast<Map<String, dynamic>>();
        _log('Received ${elements.length} raw elements from Overpass');

        final services = <EmergencyService>[];
        for (final el in elements) {
          try {
            services.add(EmergencyService.fromOverpassElement(el));
          } catch (e) {
            // Skip malformed elements silently — avoid failing the whole batch
          }
        }

        _log('Parsed ${services.length} valid POIs '
            '(hospitals: ${services.where((s) => s.type == EmergencyServiceType.hospital).length}, '
            'police: ${services.where((s) => s.type == EmergencyServiceType.police).length}, '
            'fire: ${services.where((s) => s.type == EmergencyServiceType.fireStation).length})');

        await _writeCache(services);
        return services;
      } on DioException catch (e) {
        _log('Overpass error from $url: [${e.type.name}] ${e.message}');
        lastErr = e;
        // try next endpoint
      } catch (e) {
        _log('Unexpected error from $url: $e');
        // try next endpoint
      }
    }

    _log('All endpoints failed. Last error: ${lastErr?.message}. Loading cache.');
    return getCached();
  }

  /// Return last cached list (empty if no cache yet).
  Future<List<EmergencyService>> getCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) {
        _log('Cache miss — no stored POIs');
        return [];
      }
      final list = (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
      _log('Loaded ${list.length} POIs from cache '
          '(cache size: ${raw.length ~/ 1024} KB)');
      return list.map(EmergencyService.fromJson).toList();
    } catch (e) {
      _log('Cache read error: $e — returning empty list');
      return [];
    }
  }

  // ── Private ────────────────────────────────────────────────────────────────

  Future<void> _writeCache(List<EmergencyService> services) async {
    try {
      // Cap entries to prevent unbounded storage growth (~70 MB issue)
      final capped = services.length > _maxCachedPois
          ? services.sublist(0, _maxCachedPois)
          : services;

      if (services.length > _maxCachedPois) {
        _log('Cache capped: ${services.length} → $_maxCachedPois entries');
      }

      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(capped.map((s) => s.toJson()).toList());
      await prefs.setString(_cacheKey, json);
      _log('Cache written: ${capped.length} POIs (${json.length ~/ 1024} KB)');
    } catch (e) {
      _log('Cache write error: $e');
    }
  }

  String _buildQuery(double lat, double lng, int radius) => '''
[out:json][timeout:30];
(
  node["amenity"="hospital"](around:$radius,$lat,$lng);
  way["amenity"="hospital"](around:$radius,$lat,$lng);
  relation["amenity"="hospital"](around:$radius,$lat,$lng);

  node["amenity"="police"](around:$radius,$lat,$lng);
  way["amenity"="police"](around:$radius,$lat,$lng);
  way["building"="police"](around:$radius,$lat,$lng);

  node["amenity"="fire_station"](around:$radius,$lat,$lng);
  way["amenity"="fire_station"](around:$radius,$lat,$lng);
  relation["amenity"="fire_station"](around:$radius,$lat,$lng);
  way["building"="fire_station"](around:$radius,$lat,$lng);
  node["emergency"="fire_station"](around:$radius,$lat,$lng);
  way["emergency"="fire_station"](around:$radius,$lat,$lng);
  node["emergency"="fire_service"](around:$radius,$lat,$lng);
  way["emergency"="fire_service"](around:$radius,$lat,$lng);
);
out center qt;
''';

  void _log(String msg) {
    // ignore: avoid_print
    print('[OverpassService] $msg');
  }
}
