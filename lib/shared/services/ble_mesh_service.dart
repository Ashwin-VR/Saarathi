import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:accident_app/shared/services/message_cache.dart';

final bleMeshServiceProvider = Provider<BleMeshService>((ref) {
  final svc = BleMeshService();
  ref.onDispose(svc.dispose);
  return svc;
});

/// BLE Mesh propagation:
/// - Each SOS message carries a unique ID and a TTL counter.
/// - When received: check cache → if unseen AND ttl>0 → rebroadcast with ttl-1.
/// - Loop prevention via MessageCache (LRU, 100-entry cap).
class BleMeshService {
  static const _methodChannel = MethodChannel('com.example.accident_app/ble_sos');
  static const _defaultTtl = 3; // max hops

  final MessageCache _cache = MessageCache(capacity: 100);

  // ── Receive & conditionally relay ─────────────────────────────────────────

  /// Call this when your BLE scanner receives a SOS.
  /// [messageId] must be a stable unique string (e.g. UUID from payload).
  /// [ttl] is the remaining hop count (embedded in payload by sender).
  /// Returns true if the message was relayed.
  Future<bool> relayIfNew({
    required String messageId,
    required int ttl,
    required String userId,
    double? lat,
    double? lng,
  }) async {
    if (!_isMobile) return false;

    if (_cache.contains(messageId)) {
      print('[BleMesh] ↩️  Message $messageId already seen — not relaying');
      return false;
    }
    if (ttl <= 0) {
      print('[BleMesh] ⛔ TTL exhausted for $messageId — dropping');
      _cache.add(messageId);
      return false;
    }

    _cache.add(messageId);
    final newTtl = ttl - 1;

    print('[BleMesh] 📡 RELAY $messageId TTL $ttl→$newTtl');

    try {
      await _methodChannel.invokeMethod('startAdvertising', {
        'userId': userId,
        'lat': lat,
        'lng': lng,
      });

      // Brief re-broadcast window (2 s), then stop so we don't permanently advertise
      await Future.delayed(const Duration(seconds: 2));
      await _methodChannel.invokeMethod('stopAdvertising');

      print('[BleMesh] ✅ Relay broadcast done for $messageId');
      return true;
    } on PlatformException catch (e) {
      print('[BleMesh] ❌ Relay error: ${e.code} ${e.message}');
      return false;
    } catch (e) {
      print('[BleMesh] ❌ Relay unexpected error: $e');
      return false;
    }
  }

  /// Mark message as seen without relaying (e.g. when the user ignores it).
  void markSeen(String messageId) {
    _cache.add(messageId);
    print('[BleMesh] 🚫 Marked $messageId as seen (no relay)');
  }

  bool hasSeen(String messageId) => _cache.contains(messageId);

  void clearCache() {
    _cache.clear();
    print('[BleMesh] 🔄 Mesh cache cleared');
  }

  Future<void> dispose() async {
    clearCache();
  }

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  static int get defaultTtl => _defaultTtl;
}
