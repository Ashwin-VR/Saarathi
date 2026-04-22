import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

final sensorServiceProvider = Provider<SensorService>((ref) {
  final svc = SensorService();
  ref.onDispose(svc.dispose);
  return svc;
});

// ── Severity classification ───────────────────────────────────────────────────

enum CrashSeverity {
  /// Medium G-force; device continues moving after impact.
  minor,

  /// High G-force; abrupt stop; limited post-impact movement.
  serious,

  /// Very high G-force; near-zero post-impact movement; user inactivity detected.
  critical,
}

/// Monitors accelerometer for G-force spikes indicating a crash.
///
/// Algorithm:
///   1. Apply EMA smoothing to raw samples (precomputed complement).
///   2. If smoothed magnitude ≥ [thresholdG]: enter spike; track peak.
///   3. On spike exit (qualifies): open [_kPostImpactWindowMs]-ms window.
///      Samples are written into a fixed-size ring buffer — zero allocation
///      after the first window.
///   4. Timer fires → classify severity via running counters → emit [CrashEvent].
class SensorService {
  // ── Public thresholds (unchanged) ────────────────────────────────────────
  static const double thresholdG  = 2.5;
  static const int    minSpikeMs  = 40;
  static const int    debounceMs  = 8000;
  static const double emaAlpha    = 0.25;

  // ── Precomputed EMA complement (avoids subtraction every tick) ────────────
  static const double _emaComplement = 1.0 - emaAlpha; // 0.75

  // ── Severity G thresholds ─────────────────────────────────────────────────
  static const double _seriousG  = 3.5;
  static const double _criticalG = 5.5;

  // ── Post-impact observation ───────────────────────────────────────────────
  static const int    _kPostImpactWindowMs  = 3000;
  static const double _stillnessG           = 1.25;
  static const double _criticalStillRatio   = 0.85;
  static const double _seriousStillRatio    = 0.55;
  static const double _inactivityStillRatio = 0.90;

  // Precomputed confidence normalisation constants (no division per call)
  // gScore  = (peak - thresholdG) / (thresholdG * 2)  → divisor = 5.0
  static const double _gScoreDivisor  = thresholdG * 2.0; // 5.0
  // durScore = spikeDurationMs / 500
  static const double _durScoreDivisor = 500.0;

  // ── Fixed-size ring buffer for post-impact samples ────────────────────────
  // normalInterval ≈ 20 ms → 3000 ms / 20 ms = 150 samples max.
  // Allocate once; reuse across events.
  static const int _kBufSize = 160; // slight headroom
  final _ringBuf = List<double>.filled(_kBufSize, 0.0, growable: false);
  int _ringLen = 0; // number of valid entries in current window

  // Running stillness counter — incremented in the hot path, reset per window.
  int _stillCount = 0;

  // ── Primary state ─────────────────────────────────────────────────────────
  double  _ema          = 0.0;
  int     _spikeEntryUs = 0;  // microseconds since epoch (cheaper than DateTime diff)
  int     _lastEventUs  = 0;  // 0 = never
  bool    _inSpike      = false;

  // ── Spike-capture state ───────────────────────────────────────────────────
  double _peakG = 0.0;

  // ── Post-impact state ─────────────────────────────────────────────────────
  bool   _collectingPostImpact    = false;
  Timer? _postImpactTimer;

  // Captured spike snapshot (primitives only — no DateTime boxing until emit)
  double _capturedPeakG           = 0.0;
  int    _capturedSpikeDurationMs  = 0;
  int    _capturedTimestampUs      = 0; // microseconds since epoch
  double _capturedEmaAtEnd         = 0.0;

  // ── Stream ────────────────────────────────────────────────────────────────
  StreamSubscription<AccelerometerEvent>? _sub;
  final _controller = StreamController<CrashEvent>.broadcast();

  Stream<CrashEvent> get crashEvents => _controller.stream;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void startMonitoring() {
    if (_sub != null) return;
    _sub = accelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen(_onAccelerometer);
  }

  void stopMonitoring() {
    _sub?.cancel();
    _sub = null;
    _postImpactTimer?.cancel();
    _postImpactTimer = null;
    _resetHotPathState();
  }

  void dispose() {
    stopMonitoring();
    _controller.close();
  }

  // ── Hot path — called ~50 Hz ──────────────────────────────────────────────

  void _onAccelerometer(AccelerometerEvent event) {
    // 1. Magnitude → g  (single sqrt, fused multiply-add)
    final raw = sqrt(
          event.x * event.x + event.y * event.y + event.z * event.z,
        ) *
        0.10193679918; // 1/9.81 precomputed — eliminates division every tick

    // 2. EMA update (no new object, precomputed complement)
    _ema = emaAlpha * raw + _emaComplement * _ema;

    // 3. Post-impact fast path — write sample and return immediately
    if (_collectingPostImpact) {
      if (_ringLen < _kBufSize) {
        _ringBuf[_ringLen++] = _ema;
        if (_ema <= _stillnessG) _stillCount++; // running counter — no second pass needed
      }
      return;
    }

    // 4. Spike detection
    final nowUs = DateTime.now().microsecondsSinceEpoch;

    if (_ema >= thresholdG) {
      if (!_inSpike) {
        _inSpike      = true;
        _spikeEntryUs = nowUs;
        _peakG        = _ema;
      } else if (_ema > _peakG) {
        _peakG = _ema; // branch-friendly: usually false once peak is set
      }
      return; // nothing more to do while in-spike
    }

    // 5. Below threshold — was there a qualifying spike?
    if (!_inSpike) return; // common case: never spiked — early exit

    final spikeDurMs = (nowUs - _spikeEntryUs) ~/ 1000;
    _inSpike = false;

    if (spikeDurMs < minSpikeMs) {
      // Noise — reset peak only, no debounce update
      _peakG = 0.0;
      return;
    }

    final sinceLastMs = _lastEventUs == 0
        ? debounceMs + 1
        : (nowUs - _lastEventUs) ~/ 1000;

    if (sinceLastMs < debounceMs) {
      _peakG = 0.0;
      return;
    }

    // 6. Qualifying spike — snapshot and open post-impact window
    _lastEventUs             = nowUs;
    _capturedPeakG           = _peakG;
    _capturedSpikeDurationMs = spikeDurMs;
    _capturedTimestampUs     = nowUs;
    _capturedEmaAtEnd        = _ema;
    _peakG                   = 0.0;

    // Reset buffer counters (no List allocation)
    _ringLen    = 0;
    _stillCount = 0;

    _collectingPostImpact = true;

    // Single active timer guaranteed: stopMonitoring cancels it;
    // we only reach here after debounce ensures no overlap.
    _postImpactTimer = Timer(
      const Duration(milliseconds: _kPostImpactWindowMs),
      _emitClassifiedEvent,
    );
  }

  // ── Classification (runs once per event, off hot path) ───────────────────

  void _emitClassifiedEvent() {
    _collectingPostImpact = false;

    // stillnessRatio from running counter — no second scan of the buffer
    final double stillRatio =
        _ringLen > 0 ? _stillCount / _ringLen : 0.0;

    final severity   = _classifySeverity(stillRatio);
    final confidence = _computeConfidence(stillRatio, severity);

    // Build DateTime only at emit (one allocation per crash event)
    final ts = DateTime.fromMicrosecondsSinceEpoch(_capturedTimestampUs);

    _controller.add(CrashEvent(
      magnitude:     _capturedEmaAtEnd,
      peakMagnitude: _capturedPeakG,
      duration:      Duration(milliseconds: _capturedSpikeDurationMs),
      timestamp:     ts,
      severity:      severity,
      confidence:    confidence,
      stillnessRatio: stillRatio,
    ));

    // ignore: avoid_print
    print('[SensorService] '
        'peak=${_capturedPeakG.toStringAsFixed(2)}G '
        '${severity.name.toUpperCase()} '
        'conf=${confidence.toStringAsFixed(2)}');
  }

  // ── Pure functions (precomputed inputs — no list traversal) ──────────────

  CrashSeverity _classifySeverity(double stillRatio) {
    if (_capturedPeakG >= _criticalG &&
        stillRatio >= _criticalStillRatio &&
        stillRatio >= _inactivityStillRatio) {
      return CrashSeverity.critical;
    }
    if (_capturedPeakG >= _seriousG && stillRatio >= _seriousStillRatio) {
      return CrashSeverity.serious;
    }
    return CrashSeverity.minor;
  }

  double _computeConfidence(double stillRatio, CrashSeverity severity) {
    // All three scores clamp-and-scale with precomputed divisors
    final gScore   = ((_capturedPeakG - thresholdG) / _gScoreDivisor).clamp(0.0, 1.0);
    final durScore = (_capturedSpikeDurationMs / _durScoreDivisor).clamp(0.0, 1.0);
    final stillScore = severity == CrashSeverity.minor
        ? 1.0 - stillRatio   // motion supports MINOR
        : stillRatio;         // stillness supports SERIOUS / CRITICAL

    // Weighted sum — constants folded by compiler
    return (0.50 * gScore + 0.25 * durScore + 0.25 * stillScore).clamp(0.0, 1.0);
  }

  // ── Internal reset ────────────────────────────────────────────────────────

  void _resetHotPathState() {
    _ema                  = 0.0;
    _inSpike              = false;
    _peakG                = 0.0;
    _spikeEntryUs         = 0;
    _collectingPostImpact = false;
    _ringLen              = 0;
    _stillCount           = 0;
  }

  // ── Accessors (unchanged) ─────────────────────────────────────────────────

  double get currentG    => _ema;
  bool   get isMonitoring => _sub != null;
}

// ── Event model (unchanged public surface) ────────────────────────────────────

class CrashEvent {
  final double        magnitude;
  final double        peakMagnitude;
  final Duration      duration;
  final DateTime      timestamp;
  final CrashSeverity severity;
  final double        confidence;
  final double stillnessRatio;

  const CrashEvent({
    required this.magnitude,
    required this.peakMagnitude,
    required this.duration,
    required this.timestamp,
    this.severity   = CrashSeverity.minor,
    this.confidence = 0.5,
    this.stillnessRatio = 0.0,
  });

  @override
  String toString() =>
      'CrashEvent(${peakMagnitude.toStringAsFixed(2)}G, '
      '${duration.inMilliseconds}ms, '
      '${severity.name.toUpperCase()}, '
      'conf=${confidence.toStringAsFixed(2)} '
      '@ $timestamp)';
}
