import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final ignoreSosServiceProvider = Provider<IgnoreSosService>((ref) {
  return IgnoreSosService();
});

/// Persists a set of ignored SOS device IDs in SharedPreferences.
/// Once ignored, the same SOS from that device will not alert again
/// until the cache is cleared (or app is reinstalled).
class IgnoreSosService {
  static const _key = 'ignored_sos_devices_v1';

  Set<String>? _cache;

  Future<Set<String>> _getIgnored() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    _cache = Set<String>.from(list);
    return _cache!;
  }

  /// Returns true if [deviceId] has been previously ignored.
  Future<bool> isIgnored(String deviceId) async {
    final ignored = await _getIgnored();
    return ignored.contains(deviceId);
  }

  /// Ignore [deviceId] — its SOS will not trigger alerts again.
  Future<void> ignore(String deviceId) async {
    final ignored = await _getIgnored();
    if (ignored.add(deviceId)) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, ignored.toList());
      print('[IgnoreSos] 🚫 Ignored SOS from $deviceId');
    }
  }

  /// Remove [deviceId] from the ignore list.
  Future<void> unignore(String deviceId) async {
    final ignored = await _getIgnored();
    if (ignored.remove(deviceId)) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, ignored.toList());
      print('[IgnoreSos] ✅ Unignored $deviceId');
    }
  }

  /// Clear all ignored devices.
  Future<void> clearAll() async {
    _cache = {};
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    print('[IgnoreSos] 🔄 All ignored SOS devices cleared');
  }
}
