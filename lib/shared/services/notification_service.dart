import 'dart:async';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final svc = NotificationService();
  svc.init();
  return svc;
});

/// Notification IDs (stable, unique)
abstract class NotifId {
  static const wellnessCheck = 1001;
  static const sosReceived = 1002;
  static const careModeActive = 1003;
}

class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  final Set<String> _notifiedIncidentStatus = <String>{};
  final Map<String, DateTime> _lastNotifiedAtByIncident = <String, DateTime>{};
  static const Duration _sosCooldown = Duration(seconds: 45);

  // Callback for when the user taps a notification
  void Function(NotificationResponse)? onNotificationTap;

  Future<void> init() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) {
        onNotificationTap?.call(response);
      },
    );

    try {
      // Request Android 13+ notification permission
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      // Ignore if another permission request is in progress
    }

    _initialized = true;
  }

  // ── Wellness check notification ───────────────────────────────────────────

  Future<void> showWellnessCheck({required int missedCount}) async {
    await _ensureInit();
    const androidDetails = AndroidNotificationDetails(
      'wellness_check',
      'Wellness Check',
      channelDescription:
          'Periodic wellness check-ins while Care Mode is active',
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      actions: [
        AndroidNotificationAction(
          'confirm_safe',
          'I\'m Safe ✓',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );
    final body = missedCount > 0
        ? '⚠️ $missedCount check(s) missed! Tap to confirm you\'re safe.'
        : 'Tap to confirm you\'re safe — otherwise SOS will activate.';

    await _plugin.show(
      NotifId.wellnessCheck,
      '🛡️ Care Mode: Wellness Check',
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: 'wellness_check',
    );
  }

  Future<void> cancelWellnessCheck() async {
    await _plugin.cancel(NotifId.wellnessCheck);
  }

  // ── BLE SOS received notification ─────────────────────────────────────────

  Future<void> showSosReceived({
    required String incidentId,
    String status = 'active',
    required String deviceId,
    double? lat,
    double? lng,
  }) async {
    await _ensureInit();
    final dedupeKey = '$incidentId|$status';
    if (_notifiedIncidentStatus.contains(dedupeKey)) {
      return;
    }
    final now = DateTime.now();
    final lastNotifiedAt = _lastNotifiedAtByIncident[incidentId];
    if (lastNotifiedAt != null &&
        now.difference(lastNotifiedAt) < _sosCooldown) {
      return;
    }
    _notifiedIncidentStatus.add(dedupeKey);
    _lastNotifiedAtByIncident[incidentId] = now;
    final locationStr = lat != null && lng != null
        ? '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}'
        : 'Unknown location';

    const androidDetails = AndroidNotificationDetails(
      'sos_alert',
      'SOS Alert',
      channelDescription: 'Incoming BLE SOS alerts from nearby devices',
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      color: Color(0xFFD32F2F),
      actions: [
        AndroidNotificationAction(
          'view_map',
          'View on Map',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.critical,
    );

    await _plugin.show(
      NotifId.sosReceived,
      '🚨 SOS RECEIVED — Nearby Emergency!',
      'Device: $deviceId · Location: $locationStr',
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: lat != null && lng != null ? '$lat,$lng' : '',
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _ensureInit() async {
    if (!_initialized) await init();
  }
}
