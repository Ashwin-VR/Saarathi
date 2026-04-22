class IncidentRecord {
  final String incidentId;
  final DateTime startTime;
  final DateTime endTime;
  final List<Map<String, dynamic>> gpsTrace;
  final List<Map<String, dynamic>> sensorEvents;
  final List<Map<String, dynamic>> responders;
  final double? lat;
  final double? lng;

  const IncidentRecord({
    required this.incidentId,
    required this.startTime,
    required this.endTime,
    required this.gpsTrace,
    required this.sensorEvents,
    required this.responders,
    this.lat,
    this.lng,
  });

  Map<String, dynamic> toGeminiPayload() {
    return {
      'incident_id': incidentId,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'gps_trace': gpsTrace,
      'sensor_events': sensorEvents,
      'responders': responders,
    };
  }
}
