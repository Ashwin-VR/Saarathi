import 'dart:math';

/// Type of emergency service extracted from OSM amenity tag.
enum EmergencyServiceType {
  hospital,
  police,
  fireStation;

  String get label {
    switch (this) {
      case EmergencyServiceType.hospital:    return 'Hospital';
      case EmergencyServiceType.police:      return 'Police';
      case EmergencyServiceType.fireStation: return 'Fire Station';
    }
  }

  String get osmAmenity {
    switch (this) {
      case EmergencyServiceType.hospital:    return 'hospital';
      case EmergencyServiceType.police:      return 'police';
      case EmergencyServiceType.fireStation: return 'fire_station';
    }
  }

  String get iconAsset {
    switch (this) {
      case EmergencyServiceType.hospital:    return 'assets/icons/hospital.png';
      case EmergencyServiceType.police:      return 'assets/icons/police.png';
      case EmergencyServiceType.fireStation: return 'assets/icons/fire.png';
    }
  }

  static EmergencyServiceType? fromOsmAmenity(String amenity) {
    switch (amenity) {
      case 'hospital':     return EmergencyServiceType.hospital;
      case 'police':       return EmergencyServiceType.police;
      case 'fire_station': return EmergencyServiceType.fireStation;
      default:             return null;
    }
  }
}

/// Immutable data class representing one emergency service POI from OSM.
class EmergencyService {
  final int osmId;
  final String name;
  final EmergencyServiceType type;
  final double lat;
  final double lng;

  const EmergencyService({
    required this.osmId,
    required this.name,
    required this.type,
    required this.lat,
    required this.lng,
  });

  // ── Computed ──────────────────────────────────────────────────────────────

  /// Haversine distance in kilometres from [userLat],[userLng].
  double distanceKm(double userLat, double userLng) {
    const r = 6371.0;
    final dLat = _toRad(lat - userLat);
    final dLng = _toRad(lng - userLng);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(userLat)) * cos(_toRad(lat)) *
            sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  String distanceLabel(double userLat, double userLng) {
    final km = distanceKm(userLat, userLng);
    if (km < 1.0) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(1)} km';
  }

  static double _toRad(double deg) => deg * pi / 180;

  // ── Serialisation ─────────────────────────────────────────────────────────

  factory EmergencyService.fromOverpassElement(Map<String, dynamic> el) {
    final tags = (el['tags'] as Map<String, dynamic>?) ?? {};
    final amenity = tags['amenity'] as String?;
    final building = tags['building'] as String?;
    final police = tags['police'] as String?;
    final emergency = tags['emergency'] as String?;

    final type = EmergencyServiceType.fromOsmAmenity(amenity ?? '') ??
        _inferFromAlternateTags(
          building: building,
          police: police,
          emergency: emergency,
          amenity: amenity,
        );
    if (type == null) {
      throw StateError('Unknown emergency service type: tags=$tags');
    }

    final latNum = el['center']?['lat'] ?? el['lat'];
    final lonNum = el['center']?['lon'] ?? el['lon'];

    return EmergencyService(
      osmId: el['id'] as int,
      name: tags['name'] as String? ??
          type.label,
      type: type,
      lat: (latNum as num).toDouble(),
      lng: (lonNum as num).toDouble(),
    );
  }

  static EmergencyServiceType? _inferFromAlternateTags({
    required String? building,
    required String? police,
    required String? emergency,
    String? amenity,
  }) {
    // Police variations used in OSM
    if (building == 'police' || police == 'station' || police == 'yes') {
      return EmergencyServiceType.police;
    }
    // Fire station variations — OSM uses both 'fire_station' and 'fire_service'
    if (building == 'fire_station' ||
        emergency == 'fire_station' ||
        emergency == 'fire_service' ||
        amenity == 'fire_station') {
      return EmergencyServiceType.fireStation;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'osmId': osmId,
        'name': name,
        'type': type.osmAmenity,
        'lat': lat,
        'lng': lng,
      };

  factory EmergencyService.fromJson(Map<String, dynamic> j) {
    return EmergencyService(
      osmId: j['osmId'] as int,
      name: j['name'] as String,
      type: EmergencyServiceType.fromOsmAmenity(j['type'] as String) ??
          EmergencyServiceType.hospital,
      lat: (j['lat'] as num).toDouble(),
      lng: (j['lng'] as num).toDouble(),
    );
  }

  EmergencyService copyWith({
    int? osmId,
    String? name,
    EmergencyServiceType? type,
    double? lat,
    double? lng,
  }) {
    return EmergencyService(
      osmId: osmId ?? this.osmId,
      name: name ?? this.name,
      type: type ?? this.type,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EmergencyService && other.osmId == osmId;

  @override
  int get hashCode => osmId.hashCode;

  @override
  String toString() =>
      'EmergencyService(id=$osmId, name=$name, type=${type.label}, lat=$lat, lng=$lng)';
}
