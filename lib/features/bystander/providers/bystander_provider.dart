import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/bystander_model.dart';

/// --------------------
/// STATE
/// --------------------

class BystanderState {
  final String? incidentId;
  final bool isActive;
  final List<Bystander> bystanders;

  const BystanderState({
    this.incidentId,
    this.isActive = false,
    this.bystanders = const [],
  });

  BystanderState copyWith({
    String? incidentId,
    bool? isActive,
    List<Bystander>? bystanders,
  }) {
    return BystanderState(
      incidentId: incidentId ?? this.incidentId,
      isActive: isActive ?? this.isActive,
      bystanders: bystanders ?? this.bystanders,
    );
  }
}

/// --------------------
/// PROXIMITY HELPER
/// --------------------

String getProximity(int? rssi) {
  if (rssi == null) return "UNKNOWN";
  if (rssi >= -60) return "VERY CLOSE";
  if (rssi >= -75) return "GETTING CLOSER";
  return "FAR";
}

/// --------------------
/// NOTIFIER
/// --------------------

class BystanderNotifier extends Notifier<BystanderState> {
  @override
  BystanderState build() {
    return const BystanderState();
  }

  /// Start incident (no fake users anymore)
  void startIncident() {
    final uuid = const Uuid().v4();

    state = BystanderState(
      incidentId: uuid,
      isActive: true,
      bystanders: [],
    );
  }

  /// Demo-only helpers: seed a few nearby bystanders with synthetic distances.
  /// Call only in debug/demo mode.
  void seedSyntheticBystanders({
    required double userLat,
    required double userLng,
  }) {
    final now = DateTime.now();

    Bystander mk(String id, String name, double meters, double dLat, double dLng) {
      return Bystander(
        id: id,
        name: name,
        distance: meters,
        role: BystanderRole.support,
        lat: userLat + dLat,
        lng: userLng + dLng,
        lastSeenAt: now,
      );
    }

    // Approx meters -> degrees.
    final latDegPerM = 1.0 / 111111.0;
    final lngDegPerM = 1.0 / (111111.0 * (cos(userLat * pi / 180).abs().clamp(0.2, 1.0)));

    final seeded = <Bystander>[
      mk('demo_8m',  'Bystander A',  8,  8  * latDegPerM, 0),
      mk('demo_16m', 'Bystander B', 16, 0,  16 * lngDegPerM),
      mk('demo_23m', 'Bystander C', 23, -23 * latDegPerM, -8 * lngDegPerM),
    ];

    // Assign roles by distance.
    seeded.sort((a, b) => a.distance.compareTo(b.distance));
    final updated = <Bystander>[];
    for (int i = 0; i < seeded.length; i++) {
      final role = switch (i) {
        0 => BystanderRole.responder,
        1 => BystanderRole.caller,
        2 => BystanderRole.coordinator,
        _ => BystanderRole.support,
      };
      updated.add(seeded[i].copyWith(role: role));
    }

    state = state.copyWith(
      isActive: true,
      bystanders: updated,
    );
  }

  /// Stop incident
  void stopIncident() {
    state = const BystanderState();
  }

  /// 🔥 MAIN ENTRY (called from BLE scan)
  void onSosReceived(
    String deviceId,
    double? lat,
    double? lng,
    int? rssi,
  ) {
    final proximity = getProximity(rssi);
    final now = DateTime.now();

    print("📶 DEVICE: $deviceId");
    print("📊 RSSI: $rssi");
    print("📊 PROXIMITY: $proximity");

    final existingIndex = state.bystanders.indexWhere((b) => b.id == deviceId);

    List<Bystander> updated = [...state.bystanders];

    if (existingIndex != -1) {
      // Update existing
      updated[existingIndex] = updated[existingIndex].copyWith(
        distance: _mapRssiToDistance(rssi),
        lat: lat,
        lng: lng,
        lastSeenAt: now,
      );
    } else {
      // Add new bystander
      updated.add(
        Bystander(
          id: deviceId,
          name: "Nearby User",
          distance: _mapRssiToDistance(rssi),
          role: BystanderRole.support,
          lat: lat,
          lng: lng,
          lastSeenAt: now,
        ),
      );
    }

    // Sort by distance
    updated.sort((a, b) => a.distance.compareTo(b.distance));

    // Assign roles
    for (int i = 0; i < updated.length; i++) {
      BystanderRole role;
      if (i == 0) {
        role = BystanderRole.responder;
      } else if (i == 1) {
        role = BystanderRole.caller;
      } else if (i == 2) {
        role = BystanderRole.coordinator;
      } else {
        role = BystanderRole.support;
      }

      updated[i] = updated[i].copyWith(role: role);
    }

    state = state.copyWith(
      isActive: true,
      bystanders: updated,
    );

    // 🔊 Feedback
    _handleFeedback(rssi);
  }

  /// --------------------
  /// RSSI → DISTANCE
  /// --------------------
  double _mapRssiToDistance(int? rssi) {
    if (rssi == null) return 999;

    // Approximation (good enough for demo)
    return pow(10, (-69 - rssi) / (10 * 2)).toDouble();
  }

  /// --------------------
  /// AUDIO / VIBRATION (LOG ONLY FOR NOW)
  /// --------------------
  void _handleFeedback(int? rssi) {
    if (rssi == null) return;

    if (rssi >= -60) {
      print("🔊 FAST BEEP (VERY CLOSE)");
    } else if (rssi >= -75) {
      print("🔊 MEDIUM BEEP (GETTING CLOSER)");
    } else {
      print("🔊 SLOW BEEP (FAR)");
    }
  }
}

/// --------------------
/// PROVIDER
/// --------------------

final bystanderProvider = NotifierProvider<BystanderNotifier, BystanderState>(
  BystanderNotifier.new,
);
