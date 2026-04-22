import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

final vehicleMonitorProvider = Provider<VehicleMonitorService>((ref) {
  final svc = VehicleMonitorService();
  ref.onDispose(svc.dispose);
  return svc;
});

/// Monitors GPS speed to detect sudden vehicular deceleration crash events.
///
/// Algorithm:
///   1. Maintain a fixed-capacity rolling window of speed samples.
///   2. When sustained speed ≥ [minSpeedKmh] km/h drops to ≤ [stopThresholdKmh]
///      within [dropWindowSec] seconds → emit [SuddenStopEvent].
///   3. Debounce: at least [cooldownSec] seconds between consecutive events.
class VehicleMonitorService {
  // ── Tunable thresholds ────────────────────────────────────────────────────
  static const double minSpeedKmh      = 25.0;
  static const double stopThresholdKmh = 3.0;
  static const int    dropWindowSec    = 5;
  static const int    cooldownSec      = 30;

  // ── Fixed-size ring buffer (avoids repeated allocation) ───────────────────
  static const int _kBufCap = 15;

  final _bufSpeed = List<double>.filled(_kBufCap, 0.0);
  final _bufTimeUs = List<int>.filled(_kBufCap, 0); // microsecondsSinceEpoch
  int _bufHead = 0; // ring write index
  int _bufLen  = 0; // number of valid entries

  StreamSubscription<Position>? _sub;
  int _lastEventUs = 0; // microseconds; 0 = never

  final _controller = StreamController<SuddenStopEvent>.broadcast();

  /// Fires whenever a sudden-stop crash signature is detected.
  Stream<SuddenStopEvent> get suddenStopEvents => _controller.stream;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void startMonitoring() {
    if (_sub != null) return;
    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );
    _sub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onPosition);
  }

  void stopMonitoring() {
    _sub?.cancel();
    _sub = null;
    _bufLen  = 0;
    _bufHead = 0;
  }

  void dispose() {
    stopMonitoring();
    _controller.close();
  }

  // ── Core logic ────────────────────────────────────────────────────────────

  void _onPosition(Position pos) {
    // Android can return -1.0 for speed when accuracy is insufficient — ignore
    if (pos.speed < 0) return;

    final nowUs   = DateTime.now().microsecondsSinceEpoch;
    final speedKmh = pos.speed * 3.6; // m/s → km/h

    // Write into ring buffer (overwrites oldest if full)
    _bufSpeed[_bufHead]  = speedKmh;
    _bufTimeUs[_bufHead] = nowUs;
    _bufHead = (_bufHead + 1) % _kBufCap;
    if (_bufLen < _kBufCap) _bufLen++;

    _checkForSuddenStop(nowUs);
  }

  void _checkForSuddenStop(int nowUs) {
    if (_bufLen < 3) return;

    // Cooldown guard (integer arithmetic only)
    if (_lastEventUs != 0 &&
        (nowUs - _lastEventUs) ~/ 1000000 < cooldownSec) {
      return;
    }

    final cutoffUs = nowUs - dropWindowSec * 1000000;

    // Single pass over ring buffer: collect valid recent samples
    double peak    = 0.0;
    double sumLast = 0.0;
    int    countLast = 0;
    int    validCount = 0;

    for (int i = 0; i < _bufLen; i++) {
      final idx = (_bufHead - 1 - i + _kBufCap) % _kBufCap;
      final tUs = _bufTimeUs[idx];
      if (tUs < cutoffUs) continue; // older than window — skip

      final spd = _bufSpeed[idx];
      validCount++;
      if (spd > peak) peak = spd;

      // Last 2 samples for "current" average
      if (countLast < 2) {
        sumLast += spd;
        countLast++;
      }
    }

    if (validCount < 2 || countLast < 2) return;

    final current = sumLast / countLast;

    if (peak >= minSpeedKmh && current <= stopThresholdKmh) {
      _lastEventUs = nowUs;
      // Reset buffer to avoid re-triggering on the same deceleration
      _bufLen  = 0;
      _bufHead = 0;

      _controller.add(SuddenStopEvent(
        peakSpeedKmh: peak,
        timestamp: DateTime.fromMicrosecondsSinceEpoch(nowUs),
      ));

      // ignore: avoid_print
      print('[VehicleMonitor] SuddenStop: peak=${peak.toStringAsFixed(1)} km/h');
    }
  }
}

class SuddenStopEvent {
  final double peakSpeedKmh;
  final DateTime timestamp;

  const SuddenStopEvent({
    required this.peakSpeedKmh,
    required this.timestamp,
  });

  @override
  String toString() =>
      'SuddenStop: was ${peakSpeedKmh.toStringAsFixed(1)} km/h @ $timestamp';
}
