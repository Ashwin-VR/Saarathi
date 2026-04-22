// ADDED — new file, zero coupling to existing logic
import 'dart:async';
import 'package:flutter/services.dart';

/// Maps raw RSSI dBm to a human-readable proximity label.
/// Thresholds are calibrated for BLE at 0 dBm TX power (typical phone).
String getProximity(int rssi) {
  if (rssi >= -60) return 'VERY CLOSE';
  if (rssi >= -75) return 'GETTING CLOSER';
  return 'FAR';
}

/// Colour associated with each proximity band (for UI use).
/// Returns a hex-style int ready for Color().
int getProximityColor(String proximity) {
  switch (proximity) {
    case 'VERY CLOSE':
      return 0xFFD32F2F; // red
    case 'GETTING CLOSER':
      return 0xFFF9A825; // amber
    default:
      return 0xFF388E3C; // green
  }
}

/// Emoji badge for the proximity label.
String getProximityEmoji(String proximity) {
  switch (proximity) {
    case 'VERY CLOSE':
      return '🔴';
    case 'GETTING CLOSER':
      return '🟡';
    default:
      return '🟢';
  }
}

/// Lightweight, non-blocking proximity feedback manager.
/// Uses only [HapticFeedback] — no extra packages needed.
/// Call [update] whenever RSSI changes; it self-throttles the pulse interval.
class ProximityFeedback {
  Timer? _timer;
  String _lastProximity = '';

  // ADDED — pulse intervals per band (ms)
  static const _intervals = {
    'VERY CLOSE': 300,
    'GETTING CLOSER': 700,
    'FAR': 1500,
  };

  /// Call this whenever a new RSSI arrives.
  void update(String proximity) {
    if (proximity == _lastProximity) return; // no change → skip
    _lastProximity = proximity;
    _timer?.cancel();

    final ms = _intervals[proximity] ?? 1500;
    // Fire one immediate pulse, then repeat at the band interval.
    _pulse(proximity);
    _timer = Timer.periodic(Duration(milliseconds: ms), (_) {
      _pulse(proximity);
    });
  }

  void _pulse(String proximity) {
    switch (proximity) {
      case 'VERY CLOSE':
        HapticFeedback.heavyImpact();
        break;
      case 'GETTING CLOSER':
        HapticFeedback.mediumImpact();
        break;
      default:
        HapticFeedback.lightImpact();
    }
  }

  /// Must be called when the rescuer stops tracking (banner dismissed / idle).
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _lastProximity = '';
  }
}
