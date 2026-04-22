import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kHistoryKey = 'incident_history_v1';
const _kMaxRecords = 50;

class IncidentHistoryEntry {
  final String id;
  final DateTime startTime;
  final DateTime endTime;
  final double? lat;
  final double? lng;
  final String trigger;
  final String? severity;

  const IncidentHistoryEntry({
    required this.id,
    required this.startTime,
    required this.endTime,
    this.lat,
    this.lng,
    required this.trigger,
    this.severity,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        'trigger': trigger,
        if (severity != null) 'severity': severity,
      };

  factory IncidentHistoryEntry.fromJson(Map<String, dynamic> map) =>
      IncidentHistoryEntry(
        id: map['id'] as String,
        startTime: DateTime.parse(map['startTime'] as String),
        endTime: DateTime.parse(map['endTime'] as String),
        lat: (map['lat'] as num?)?.toDouble(),
        lng: (map['lng'] as num?)?.toDouble(),
        trigger: map['trigger'] as String? ?? 'manual',
        severity: map['severity'] as String?,
      );
}

class IncidentHistoryService {
  Future<List<IncidentHistoryEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kHistoryKey) ?? [];
    return raw.map((s) {
      try {
        return IncidentHistoryEntry.fromJson(
            jsonDecode(s) as Map<String, dynamic>);
      } catch (_) {
        return null;
      }
    }).whereType<IncidentHistoryEntry>().toList();
  }

  Future<void> save(IncidentHistoryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kHistoryKey) ?? [];
    raw.add(jsonEncode(entry.toJson()));
    // FIFO: keep latest _kMaxRecords
    final trimmed = raw.length > _kMaxRecords
        ? raw.sublist(raw.length - _kMaxRecords)
        : raw;
    await prefs.setStringList(_kHistoryKey, trimmed);
  }
}

final incidentHistoryServiceProvider =
    Provider<IncidentHistoryService>((_) => IncidentHistoryService());

final incidentHistoryProvider =
    FutureProvider<List<IncidentHistoryEntry>>((ref) async {
  return ref.read(incidentHistoryServiceProvider).load();
});
