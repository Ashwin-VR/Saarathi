
enum BystanderRole {
  responder,
  caller,
  coordinator,
  support,
}

class Bystander {
  final String id;
  final String name;
  final double distance; // in meters
  final BystanderRole role;
  final bool isCurrentUser;
  final double? lat;
  final double? lng;
  final DateTime? lastSeenAt;

  Bystander({
    required this.id,
    required this.name,
    required this.distance,
    required this.role,
    this.isCurrentUser = false,
    this.lat,
    this.lng,
    this.lastSeenAt,
  });

  Bystander copyWith({
    String? id,
    String? name,
    double? distance,
    BystanderRole? role,
    bool? isCurrentUser,
    double? lat,
    double? lng,
    DateTime? lastSeenAt,
  }) {
    return Bystander(
      id: id ?? this.id,
      name: name ?? this.name,
      distance: distance ?? this.distance,
      role: role ?? this.role,
      isCurrentUser: isCurrentUser ?? this.isCurrentUser,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }
}
