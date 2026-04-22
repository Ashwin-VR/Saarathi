import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:collection';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
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
  bool _isAdvertising = false;
  bool _isScanning = false;

  final FlutterBlePeripheral _blePeripheral = FlutterBlePeripheral();
  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _followTicker;

  // SOS service UUID (matches native Kotlin side)
  static const _sosServiceUuid = '0000FFF0-0000-1000-8000-00805F9B34FB';

  // ── First Finder Lock ─────────────────────────────────────────────────────

  String? _lockedDeviceId; // device this rescuer is tracking
  bool _isNavigator = false; // true if this device won the first-finder lock

  // Rolling RSSI window (last 8 reads per device)
  final Map<String, Queue<int>> _rssiWindows = {};
  final Map<String, int> _hitCount = {};

  static const _windowSize = 8;
  static const _navigatorMinHits = 5; // hits required before locking
  static const _navigatorMinRssi = -80; // threshold for strong enough signal

  // Latest smoothed RSSI for the locked device
  int? _currentSmoothed;
  int? _prevSmoothedRssi; // previous tick's value — for trend

  // Callbacks
  SosReceivedCallback? _activeCallback;
  void Function(FollowDirection)? onFollowDirection;
  void Function(bool isNavigator)? onNavigatorStateChange;

  // ─────────────────────────────────────────────
  // 🔐 PERMISSION HANDLING
  // ─────────────────────────────────────────────

  static Future<bool> requestBlePermissions() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;

    final statuses = await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
    ].request();

    final allGranted = statuses.values.every(
      (s) => s == PermissionStatus.granted || s == PermissionStatus.limited,
    );

    if (!allGranted) {
      print('[BleSosService] ❌ Permissions not fully granted: $statuses');
    } else {
      print('[BleSosService] ✅ All BLE/location permissions granted');
    }

    return allGranted;
  }

  // ─────────────────────────────────────────────
  // 📡 ADVERTISING (ONLY DURING SOS)
  // ─────────────────────────────────────────────

  Future<void> startAdvertising({
    required String userId,
    double? lat,
    double? lng,
  }) async {
    print('[BleSosService] 📡 startAdvertising called (userId=$userId)');

    if (_isAdvertising) {
      print('[BleSosService] ⚠️  Already advertising — skip');
      return;
    }

    if (!_isMobile) {
      print('[BleSosService] ⚠️  Not mobile — skip advertising');
      return;
    }

    final hasPerms = await requestBlePermissions();
    if (!hasPerms) {
      print('[BleSosService] ❌ Cannot advertise — permissions denied');
      return;
    }

    try {
      final eventId = DateTime.now().millisecondsSinceEpoch.toString();
      final message = 'SOS|$eventId|${lat ?? ''}|${lng ?? ''}';
      final messageBytes = utf8.encode(message);

      final advertiseData = AdvertiseData(
        serviceUuid: _sosServiceUuid,
        serviceDataUuid: _sosServiceUuid,
        serviceData: messageBytes,
        localName: 'ACCIDENT_SOS',
        includeDeviceName: false,
      );

      final settings = AdvertiseSettings(
        advertiseMode: AdvertiseMode.advertiseModeLowLatency,
        txPowerLevel: AdvertiseTxPower.advertiseTxPowerHigh,
        connectable: false,
        timeout: 0, // advertise indefinitely
      );

      await _blePeripheral.start(
        advertiseData: advertiseData,
        advertiseSettings: settings,
      );

      _isAdvertising = true;
      print('[BleSosService] ✅ BLE ADVERTISING STARTED');
    } catch (e) {
      print('[BleSosService] ❌ startAdvertising error: $e');
    }
  }

  Future<void> stopAdvertising() async {
    try {
      await _blePeripheral.stop();
    } catch (e) {
      print('[BleSosService] ❌ stopAdvertising error: $e');
    }
    _isAdvertising = false;
    print('[BleSosService] 🛑 BLE ADVERTISING STOPPED');
  }

  // ─────────────────────────────────────────────
  // 🔍 SCANNING
  // ─────────────────────────────────────────────

  Future<void> startScanning({
    required SosReceivedCallback onSosReceived,
  }) async {
    print('[BleSosService] 🔍 startScanning called');

    if (!_isMobile) {
      print('[BleSosService] ⚠️  Not mobile — skip scanning');
      return;
    }
    if (_isScanning) {
      print('[BleSosService] ⚠️  Already scanning — skip');
      return;
    }

    final hasPerms = await requestBlePermissions();
    if (!hasPerms) {
      print('[BleSosService] ❌ Cannot scan — permissions denied');
      return;
    }

    _activeCallback = onSosReceived;
    _isScanning = true;

    try {
      // Continuous scan — no timeout, removeIfGone=false prevents filter gaps
      await FlutterBluePlus.startScan(
        withServices: [Guid(_sosServiceUuid)],
        androidScanMode: AndroidScanMode.lowLatency,
        continuousUpdates: true,
        removeIfGone: const Duration(seconds: 3),
      );
    } catch (e) {
      // Fallback: unfiltered scan (some chipsets reject service-UUID filter)
      print(
          '[BleSosService] ⚠️  Filtered scan failed ($e) — retrying unfiltered');
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

    // 1-second ticker for follow mode updates
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
    print('[BleSosService] 🛑 BLE SCANNING STOPPED');
  }

  // ─────────────────────────────────────────────
  // 📊 SCAN RESULT PROCESSING
  // ─────────────────────────────────────────────

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
      print('RECEIVED LAT: $lat');
      print('RECEIVED LNG: $lng');

      // Update rolling RSSI window
      _rssiWindows.putIfAbsent(deviceId, () => Queue<int>());
      final window = _rssiWindows[deviceId]!;
      if (window.length >= _windowSize) window.removeFirst();
      window.addLast(rssi);

      _hitCount[deviceId] = (_hitCount[deviceId] ?? 0) + 1;

      final smoothed = _calcSmoothed(window);
      print(
          '[BleSosService] 📡 $deviceId | RSSI: $rssi | smoothed: $smoothed | hits: ${_hitCount[deviceId]}');

      // ── First Finder Lock ──────────────────────────────────────────────────
      if (_lockedDeviceId == null) {
        final isStrong = smoothed > _navigatorMinRssi;
        final isFrequent = (_hitCount[deviceId] ?? 0) >= _navigatorMinHits;

        if (isStrong && isFrequent) {
          _lockedDeviceId = deviceId;
          _isNavigator = true;
          print('[BleSosService] 🔒 FIRST FINDER LOCK → $deviceId (navigator)');
          onNavigatorStateChange?.call(true);
          _activeCallback?.call(deviceId, lat, lng, smoothed);
        }
        continue;
      }

      // ── Track locked device only ───────────────────────────────────────────
      if (_lockedDeviceId == deviceId) {
        _currentSmoothed = smoothed; // stored for follow ticker
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

  // ─────────────────────────────────────────────
  // 📈 FOLLOW MODE: 1-second tick
  // ─────────────────────────────────────────────

  void _onFollowTick(Timer _) {
    if (_lockedDeviceId == null || _currentSmoothed == null) {
      // No lock yet or signal lost
      if (_lockedDeviceId != null) {
        print('[BleSosService] ⚠️  Follow tick — signal lost');
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
      final delta = current - prev; // positive = getting stronger
      if (delta > 2) {
        direction = FollowDirection.forward; // Getting closer
      } else if (delta < -2) {
        direction = FollowDirection.wrongDirection;
      } else {
        direction = FollowDirection.turnSlightly;
      }
    }

    _prevSmoothedRssi = current;
    print('[BleSosService] 🧭 Follow direction → ${direction.label} '
        '(rssi=$current prev=$prev)');
    onFollowDirection?.call(direction);
  }

  // ─────────────────────────────────────────────
  // 📏 RSSI HELPERS
  // ─────────────────────────────────────────────

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

  // ─────────────────────────────────────────────
  // 🔄 RESET
  // ─────────────────────────────────────────────

  void resetDetection() {
    _lockedDeviceId = null;
    _isNavigator = false;
    _currentSmoothed = null;
    _prevSmoothedRssi = null;
    _rssiWindows.clear();
    _hitCount.clear();
    print('[BleSosService] 🔄 SOS detection reset');
  }

  // ─────────────────────────────────────────────
  // ♻️ LIFECYCLE
  // ─────────────────────────────────────────────

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
