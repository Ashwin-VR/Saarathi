import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:collection';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

final bleSosServiceProvider = Provider<BleSosService>((ref) {
  final svc = BleSosService();
  ref.onDispose(svc.dispose);
  return svc;
});

typedef SosReceivedCallback = void Function(
  String deviceId,
  double? lat,
  double? lng,
  int? rssi,
);

// ── Follow Mode direction enum ────────────────────────────────────────────────

enum FollowDirection { forward, wrongDirection, turnSlightly, lostSignal }

extension FollowDirectionExt on FollowDirection {
  String get label {
    switch (this) {
      case FollowDirection.forward:
        return 'Move forward';
      case FollowDirection.wrongDirection:
        return 'Wrong direction';
      case FollowDirection.turnSlightly:
        return 'Turn slightly';
      case FollowDirection.lostSignal:
        return 'Signal lost';
    }
  }
}

// ── BLE SOS Service ───────────────────────────────────────────────────────────

class BleSosService {
  // Advertising is disabled (flutter_ble_peripheral removed — NDK failures on API 34+)
  // Scanning via flutter_blue_plus is preserved for bystander detection.
  bool _isAdvertising = false;
  bool _isScanning = false;

  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _followTicker;

  // SOS service UUID
  static const _sosServiceUuid = '0000FFF0-0000-1000-8000-00805F9B34FB';

  // ── First Finder Lock ─────────────────────────────────────────────────────

  String? _lockedDeviceId;
  bool _isNavigator = false;

  final Map<String, Queue<int>> _rssiWindows = {};
  final Map<String, int> _hitCount = {};

  static const _windowSize = 8;
  static const _navigatorMinHits = 5;
  static const _navigatorMinRssi = -80;

  int? _currentSmoothed;
  int? _prevSmoothedRssi;

  SosReceivedCallback? _activeCallback;
  void Function(FollowDirection)? onFollowDirection;
  void Function(bool isNavigator)? onNavigatorStateChange;

  // ── Permission handling ──────────────────────────────────────────────────

  static Future<bool> requestBlePermissions() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;

    final statuses = await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    return statuses.values.every(
      (s) => s == PermissionStatus.granted || s == PermissionStatus.limited,
    );
  }

  // ── Advertising (no-op — BLE peripheral advertising removed) ───────────

  Future<void> startAdvertising({
    required String userId,
    double? lat,
    double? lng,
  }) async {
    // BLE advertising is disabled in this build.
    // SMS + WhatsApp alerts handle emergency notification instead.
    _isAdvertising = false;
    print('[BleSosService] ℹ️  BLE advertising disabled (removed flutter_ble_peripheral)');
  }

  Future<void> stopAdvertising() async {
    _isAdvertising = false;
  }

  // ── Scanning ──────────────────────────────────────────────────────────────

  Future<void> startScanning({
    required SosReceivedCallback onSosReceived,
  }) async {
    if (!_isMobile) return;
    if (_isScanning) return;

    final hasPerms = await requestBlePermissions();
    if (!hasPerms) {
      print('[BleSosService] ❌ Cannot scan — permissions denied');
      return;
    }

    _activeCallback = onSosReceived;
    _isScanning = true;

    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(_sosServiceUuid)],
        androidScanMode: AndroidScanMode.lowLatency,
        continuousUpdates: true,
        removeIfGone: const Duration(seconds: 3),
      );
    } catch (e) {
      try {
        await FlutterBluePlus.startScan(
          androidScanMode: AndroidScanMode.lowLatency,
          continuousUpdates: true,
          removeIfGone: const Duration(seconds: 3),
        );
      } catch (e2) {
        print('[BleSosService] ❌ startScan error: $e2');
        _isScanning = false;
        return;
      }
    }

    _scanSub = FlutterBluePlus.scanResults.listen(
      _processScanResults,
      onError: (e) => print('[BleSosService] ❌ SCAN ERROR: $e'),
    );

    _followTicker = Timer.periodic(const Duration(seconds: 1), _onFollowTick);
    print('[BleSosService] ✅ BLE SCANNING STARTED');
  }

  Future<void> stopScanning() async {
    if (!_isScanning) return;
    _followTicker?.cancel();
    _followTicker = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      print('[BleSosService] ❌ stopScan error: $e');
    }
    await _scanSub?.cancel();
    _scanSub = null;
    _isScanning = false;
    _activeCallback = null;
  }

  void _processScanResults(List<ScanResult> results) {
    for (final result in results) {
      final deviceId = result.device.remoteId.str;
      final rssi = result.rssi;
      final parts = _extractSosParts(result);
      double? lat;
      double? lng;
      if (parts.length >= 4) {
        lat = double.tryParse(parts[2]);
        lng = double.tryParse(parts[3]);
      }

      _rssiWindows.putIfAbsent(deviceId, () => Queue<int>());
      final window = _rssiWindows[deviceId]!;
      if (window.length >= _windowSize) window.removeFirst();
      window.addLast(rssi);

      _hitCount[deviceId] = (_hitCount[deviceId] ?? 0) + 1;
      final smoothed = _calcSmoothed(window);

      if (_lockedDeviceId == null) {
        final isStrong = smoothed > _navigatorMinRssi;
        final isFrequent = (_hitCount[deviceId] ?? 0) >= _navigatorMinHits;
        if (isStrong && isFrequent) {
          _lockedDeviceId = deviceId;
          _isNavigator = true;
          onNavigatorStateChange?.call(true);
          _activeCallback?.call(deviceId, lat, lng, smoothed);
        }
        continue;
      }

      if (_lockedDeviceId == deviceId) {
        _currentSmoothed = smoothed;
        _activeCallback?.call(deviceId, lat, lng, smoothed);
      }
    }
  }

  List<String> _extractSosParts(ScanResult result) {
    for (final bytes in result.advertisementData.serviceData.values) {
      final message = _decodeSosMessage(bytes);
      if (message != null) return message.split('|');
    }
    for (final bytes in result.advertisementData.manufacturerData.values) {
      final message = _decodeSosMessage(bytes);
      if (message != null) return message.split('|');
    }
    return const [];
  }

  String? _decodeSosMessage(List<int> bytes) {
    if (bytes.isEmpty) return null;
    final message = utf8
        .decode(bytes, allowMalformed: true)
        .replaceAll('\u0000', '')
        .trim();
    if (!message.startsWith('SOS|')) return null;
    return message;
  }

  void _onFollowTick(Timer _) {
    if (_lockedDeviceId == null || _currentSmoothed == null) {
      if (_lockedDeviceId != null) {
        onFollowDirection?.call(FollowDirection.lostSignal);
      }
      return;
    }
    final current = _currentSmoothed!;
    final prev = _prevSmoothedRssi;
    FollowDirection direction;
    if (prev == null) {
      direction = FollowDirection.turnSlightly;
    } else {
      final delta = current - prev;
      if (delta > 2) {
        direction = FollowDirection.forward;
      } else if (delta < -2) {
        direction = FollowDirection.wrongDirection;
      } else {
        direction = FollowDirection.turnSlightly;
      }
    }
    _prevSmoothedRssi = current;
    onFollowDirection?.call(direction);
  }

  int _calcSmoothed(Queue<int> window) {
    if (window.isEmpty) return -100;
    return window.reduce((a, b) => a + b) ~/ window.length;
  }

  String getProximityLabel(int rssi) {
    if (rssi > -60) return 'VERY CLOSE 🔴';
    if (rssi > -70) return 'CLOSE 🟠';
    if (rssi > -80) return 'NEARBY 🟡';
    return 'FAR ⚪';
  }

  void resetDetection() {
    _lockedDeviceId = null;
    _isNavigator = false;
    _currentSmoothed = null;
    _prevSmoothedRssi = null;
    _rssiWindows.clear();
    _hitCount.clear();
  }

  Future<void> dispose() async {
    await stopAdvertising();
    await stopScanning();
  }

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;
  bool get isAdvertising => _isAdvertising;
  bool get isScanning => _isScanning;
  bool get isNavigator => _isNavigator;
  String? get lockedDeviceId => _lockedDeviceId;
  int? get currentSmoothedRssi => _currentSmoothed;
}
