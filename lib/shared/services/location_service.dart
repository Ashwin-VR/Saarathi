import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'location_cache_service.dart';

final locationServiceProvider = Provider<LocationService>((ref) {
  final cache = ref.watch(locationCacheServiceProvider);
  return LocationService(cache);
});

class LocationService {
  static const _maxLastKnownAgeMs = 30000; // 30 seconds

  final LocationCacheService _cache;

  Position? _lastKnownPosition;

  LocationService(this._cache);

  // ── Public API ─────────────────────────────────────────

  Future<Position?> getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _log('Location service disabled');
      return await _getCachedPosition();
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _log('Location permission denied');
        return await _getCachedPosition();
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _log('Location permission permanently denied');
      return await _getCachedPosition();
    }

    try {
      // Try high-accuracy fix first, fall back to best-available
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 10),
      ).catchError((_) => Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ));

      _lastKnownPosition = pos;
      await _cache.cacheLocation(
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
      _log('GPS fix: ${pos.latitude}, ${pos.longitude}');
      return pos;
    } catch (e) {
      _log('GPS failed: $e → trying last known');
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          _lastKnownPosition = last;
          _log('Using last known: ${last.latitude}, ${last.longitude}');
          return last;
        }
      } catch (_) {}
      return await _getCachedPosition();
    }
  }

  Stream<Position> positionStream() {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // update every 5 m for better SOS accuracy
    );

    return Geolocator.getPositionStream(locationSettings: settings).map((pos) {
      _lastKnownPosition = pos;
      _cache.cacheLocation(
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
      return pos;
    });
  }

  Future<Position?> getLastKnownOrCurrent() async {
    final fresh = _freshLastKnown();
    if (fresh != null) return fresh;

    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && _isFresh(lastKnown)) {
        _lastKnownPosition = lastKnown;
        return lastKnown;
      }
    } catch (_) {}

    return getCurrentPosition();
  }

  // ── CACHE FALLBACK ─────────────────────────────────────

  Future<Position?> _getCachedPosition() async {
    final cached = await _cache.getLastKnownLocation();

    if (cached == null) {
      _log('No cached location available');
      return null;
    }

    _log('Using cached location');

    return Position(
      latitude: cached.latitude,
      longitude: cached.longitude,
      timestamp: cached.timestamp,
      accuracy: 0,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );
  }

  // ── Helpers ────────────────────────────────────────────

  Position? _freshLastKnown() {
    final pos = _lastKnownPosition;
    if (pos == null) return null;

    if (!_isFresh(pos)) {
      _lastKnownPosition = null;
      return null;
    }

    return pos;
  }

  bool _isFresh(Position pos) {
    final ageMs = DateTime.now().difference(pos.timestamp).inMilliseconds.abs();
    return ageMs <= _maxLastKnownAgeMs;
  }

  void _log(String msg) {
    print('[LocationService] $msg');
  }
}
