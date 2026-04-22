import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/safe_location.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Persists the last successfully obtained GPS location so the app can
/// fall back to it when GPS is unavailable.
///
///
final locationCacheServiceProvider = Provider<LocationCacheService>((ref) {
  return LocationCacheService();
});

/// Uses [SharedPreferences] — no database or Firebase required.
class LocationCacheService {
  static const _cacheKey = 'last_known_location';

  // ---------------------------------------------------------------------------
  // Write
  // ---------------------------------------------------------------------------

  /// Saves [latitude] / [longitude] with the current timestamp.
  /// Call this every time a real GPS fix is obtained.
  Future<void> cacheLocation({
    required double latitude,
    required double longitude,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final location = SafeLocation(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.now(),
      isFromCache: false, // it's "live" at the moment we write it
    );
    await prefs.setString(_cacheKey, jsonEncode(location.toJson()));
  }

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  /// Returns the last cached [SafeLocation], or `null` if nothing has been
  /// stored yet.
  Future<SafeLocation?> getLastKnownLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return null;

      final json = jsonDecode(raw) as Map<String, dynamic>;
      // Force isFromCache = true when reading back from storage
      return SafeLocation(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
        isFromCache: true,
      );
    } catch (_) {
      // Corrupted cache — silently ignore
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Clear
  // ---------------------------------------------------------------------------

  /// Removes the cached entry (e.g. on logout or reset).
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
  }
}
