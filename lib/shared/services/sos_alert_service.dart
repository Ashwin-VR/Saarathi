import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final sosAlertServiceProvider = Provider<SosAlertService>((ref) {
  final svc = SosAlertService();
  ref.onDispose(svc.stopAlert);
  return svc;
});

/// Manages max-volume ringtone + continuous vibration when SOS is active.
/// Uses a dedicated MethodChannel so native code can override DnD / silent mode.
class SosAlertService {
  static const _channel = MethodChannel('com.example.accident_app/sos_alert');

  bool _isAlerting = false;
  Timer? _vibrateTimer;

  bool get isAlerting => _isAlerting;

  // ── Start SOS alert ───────────────────────────────────────────────────────

  Future<void> startAlert() async {
    if (_isAlerting) return;
    _isAlerting = true;

    if (!Platform.isAndroid && !Platform.isIOS) return;

    try {
      await _channel.invokeMethod('startSosAlert');
    } on PlatformException catch (e) {
      _log('startSosAlert error: ${e.code} ${e.message}');
    }

    // Flutter-side vibration fallback loop (every 600 ms) using HapticFeedback
    // The native side handles true continuous vibration; this is a UI-layer backup.
    _vibrateTimer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      if (_isAlerting) HapticFeedback.heavyImpact();
    });
  }

  // ── Stop SOS alert ────────────────────────────────────────────────────────

  Future<void> stopAlert() async {
    if (!_isAlerting) return;
    _isAlerting = false;
    _vibrateTimer?.cancel();
    _vibrateTimer = null;

    if (!Platform.isAndroid && !Platform.isIOS) return;

    try {
      await _channel.invokeMethod('stopSosAlert');
    } on PlatformException catch (e) {
      _log('stopSosAlert error: ${e.code} ${e.message}');
    }
  }

  void _log(String msg) {
    // ignore: avoid_print
    print('[SosAlertService] $msg');
  }
}
