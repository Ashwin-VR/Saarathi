import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/safe_location.dart';
import 'location_cache_service.dart';
import 'package:geolocator/geolocator.dart';
// ---------------------------------------------------------------------------
// IMPORTANT: Replace the import below with your actual location service path.
// The wrapper only calls TWO things from your existing service:
//   1. getCurrentLocation() → returns an object with .latitude / .longitude
//   2. (nothing else — it does not touch SOS logic at all)
// ---------------------------------------------------------------------------

/// Thin wrapper that adds a cache fallback on top of the existing
/// [LocationService].  It does NOT modify or replace the original service.
class SafeLocationService {
  final LocationCacheService _cache;

  SafeLocationService(this._cache);

  /// Returns the current GPS location wrapped in [SafeLocation].
  /// Falls back to the last cached location if GPS fails for any reason
  /// (permission denied, airplane mode, poor signal, timeout, etc.).
  ///
  /// Returns `null` only when GPS fails AND no cache exists yet.
  Future<SafeLocation?> getSafeLocation() async {
    // ── 1. Try live GPS ─────────────────────────────────────
    try {
      final position = await Geolocator.getCurrentPosition();

      // Save to cache
      await _cache.cacheLocation(
        latitude: position.latitude,
        longitude: position.longitude,
      );

      return SafeLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: DateTime.now(),
        isFromCache: false,
      );
    } catch (_) {
      // ignore and fallback
    }

    // ── 2. Fallback to cache ────────────────────────────────
    final cached = await _cache.getLastKnownLocation();
    return cached;
  }
}

// ---------------------------------------------------------------------------
// Riverpod providers
// ---------------------------------------------------------------------------

/// Expose the cache service so it can be injected / overridden in tests.
final locationCacheServiceProvider = Provider<LocationCacheService>(
  (_) => LocationCacheService(),
);

/// Expose [SafeLocationService].
/// Override [locationServiceProvider] with your actual provider name.
final safeLocationServiceProvider = Provider<SafeLocationService>((ref) {
  final cache = ref.watch(locationCacheServiceProvider);
  return SafeLocationService(cache);
});

/// Async provider that resolves once with the best available location.
/// Useful for screens that need a one-shot location fetch (e.g. SOS trigger).
final safeLocationProvider = FutureProvider<SafeLocation?>((ref) async {
  final service = ref.watch(safeLocationServiceProvider);
  return service.getSafeLocation();
});
