/// Represents a location result that may come from GPS or local cache.
class SafeLocation {
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final bool isFromCache;

  const SafeLocation({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.isFromCache,
  });

  /// Human-readable freshness label shown in the UI.
  String get freshnessLabel {
    if (!isFromCache) return 'Live location';
    final age = DateTime.now().difference(timestamp);
    final minutes = age.inMinutes;
    if (minutes < 1) return 'Using last known location (just now)';
    if (minutes == 1) return 'Using last known location (1 min ago)';
    if (minutes < 60) return 'Using last known location ($minutes min ago)';
    final hours = age.inHours;
    if (hours == 1) return 'Using last known location (1 hr ago)';
    return 'Using last known location ($hours hrs ago)';
  }

  /// True when the cached location is too old to be trustworthy (>1 hour).
  bool get isStale =>
      isFromCache && DateTime.now().difference(timestamp).inHours >= 1;

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'isFromCache': isFromCache,
      };

  factory SafeLocation.fromJson(Map<String, dynamic> json) => SafeLocation(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
        isFromCache: json['isFromCache'] as bool,
      );

  @override
  String toString() =>
      'SafeLocation(lat: $latitude, lng: $longitude, fromCache: $isFromCache, ts: $timestamp)';
}
