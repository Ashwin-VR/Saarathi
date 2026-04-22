import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:accident_app/shared/services/sensor_service.dart';

final smsServiceProvider = Provider<SmsService>((ref) => SmsService());

/// Handles emergency SMS dispatches.
/// - Reads contacts from SharedPreferences.
/// - Embeds a map deep-link with live coordinates.
/// - Queues and retries if send fails (offline fallback).
/// - Persists the queue across app restarts via SharedPreferences.
class SmsService {
  final _queue = <_SmsJob>[];

  static const _contactsKey = 'emergency_contacts';
  static const _primaryContactKey = 'primary_emergency_contact';
  static const _smsChannel = MethodChannel('com.example.accident_app/sms');
  static const _queueKey = 'sms_offline_queue';

  SmsService() {
    _loadQueue();
  }

  // â”€â”€ Key API â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Send SOS SMS to all saved emergency contacts.
  /// [severity] is optional; defaults to [CrashSeverity.minor] when null.
  /// [userResponse] is an optional status message from the user.
  Future<void> sendSosAlerts({
    double? lat,
    double? lng,
    String? userName,
    CrashSeverity? severity,
    String? userResponse,
    String? emergencyTypeLabel, // e.g. "FIRE", "AMBULANCE", "POLICE"
    String? profileAge,
    String? profileBloodGroup,
    String? triageSummary,
    int? triageRiskPercent,
    ({String type, String severity})? structuredSelection,
  }) async {
    if (!Platform.isAndroid) {
      _log('SMS send skipped (iOS)');
      return;
    }

    final contacts = await _getContacts();
    if (contacts.isEmpty) {
      _log('No emergency contacts configured');
      return;
    }

    final link = _buildLocationLink(lat, lng);
    final body = _buildMessage(
      userName: userName,
      profileAge: profileAge,
      profileBloodGroup: profileBloodGroup,
      locationLink: link,
      lat: lat,
      lng: lng,
      severity: severity,
      userResponse: userResponse,
      emergencyTypeLabel: emergencyTypeLabel,
      triageSummary: triageSummary,
      triageRiskPercent: triageRiskPercent,
      structuredSelection: structuredSelection,
    );

    for (final number in contacts) {
      await _sendOrQueue(_normalizeNumber(number), body, throwOnFailure: false);
    }

    await _drainQueue(throwOnFailure: false);
  }

  /// Send SOS SMS to the *primary* emergency contact (user-chosen).
  /// [severity] is optional; [userResponse] is an optional user status string.
  Future<void> sendSosToPrimaryContact({
    double? lat,
    double? lng,
    String? userName,
    bool throwOnFailure = false,
    CrashSeverity? severity,
    String? userResponse,
    String? profileAge,
    String? profileBloodGroup,
    String? triageSummary,
    int? triageRiskPercent,
    ({String type, String severity})? structuredSelection,
  }) async {
    if (!Platform.isAndroid) {
      _log('SMS send skipped (iOS)');
      return;
    }
    final primary = await getPrimaryContact();
    if (primary == null) {
      const msg = 'No emergency contact configured';
      _log(msg);
      if (throwOnFailure) throw StateError(msg);
      return;
    }

    final link = _buildLocationLink(lat, lng);
    final body = _buildMessage(
      userName: userName,
      profileAge: profileAge,
      profileBloodGroup: profileBloodGroup,
      locationLink: link,
      lat: lat,
      lng: lng,
      severity: severity,
      userResponse: userResponse,
      triageSummary: triageSummary,
      triageRiskPercent: triageRiskPercent,
      structuredSelection: structuredSelection,
    );

    final normalized = _normalizeNumber(primary);
    await _sendOrQueue(normalized, body, throwOnFailure: throwOnFailure);
    await _drainQueue(throwOnFailure: throwOnFailure);
  }

  // â”€â”€ Contact management â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<List<String>> _getContacts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_contactsKey) ?? [];
  }

  /// Save a phone number to the persistent emergency contacts list.
  static Future<void> addContact(String phoneNumber) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_contactsKey) ?? [];
    if (!existing.contains(phoneNumber)) {
      existing.add(phoneNumber);
      await prefs.setStringList(_contactsKey, existing);
    }
  }

  /// Remove a phone number from the contacts list.
  static Future<void> removeContact(String phoneNumber) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_contactsKey) ?? [];
    existing.remove(phoneNumber);
    await prefs.setStringList(_contactsKey, existing);

    // If the removed number was primary, clear it.
    final primary = prefs.getString(_primaryContactKey);
    if (primary == phoneNumber) {
      await prefs.remove(_primaryContactKey);
    }
  }

  static Future<List<String>> getContacts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_contactsKey) ?? [];
  }

  static Future<void> setPrimaryContact(String phoneNumber) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_primaryContactKey, phoneNumber);
  }

  static Future<String?> getPrimaryContact() async {
    final prefs = await SharedPreferences.getInstance();
    final primary = prefs.getString(_primaryContactKey);
    if (primary != null && primary.trim().isNotEmpty) return primary;
    final contacts = prefs.getStringList(_contactsKey) ?? [];
    return contacts.isEmpty ? null : contacts.first;
  }

  // â”€â”€ Internal send logic â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _sendOrQueue(
    String number,
    String body, {
    required bool throwOnFailure,
  }) async {
    try {
      final permGranted = await _ensureSmsPermissionGranted();
      if (!permGranted) {
        const msg = 'SMS permission not granted';
        _log('$msg â€” ${throwOnFailure ? "not queueing" : "queueing"}');
        if (throwOnFailure) throw StateError(msg);
        _queue.add(_SmsJob(number: number, body: body, attempt: 0));
        await _persistQueue();
        return;
      }

      if (!Platform.isAndroid) return;
      await _smsChannel.invokeMethod('sendSms', {
        'to': number,
        'message': body,
      });
      _log('âœ… SMS sent to $number');
    } catch (e) {
      _log('SMS send failed for $number: $e');
      if (throwOnFailure) rethrow;
      _log('Queueing for retry');
      _queue.add(_SmsJob(number: number, body: body, attempt: 0));
      await _persistQueue();
    }
  }

  Future<bool> _ensureSmsPermissionGranted() async {
    final status = await Permission.sms.status;
    if (status.isGranted || status.isLimited) return true;
    final requested = await Permission.sms.request();
    return requested.isGranted || requested.isLimited;
  }

  Future<void> _drainQueue({required bool throwOnFailure}) async {
    final toRetry = List<_SmsJob>.from(_queue);
    _queue.clear();

    for (final job in toRetry) {
      if (job.attempt >= 3) {
        _log('Dropping SMS to ${job.number} after 3 attempts');
        continue;
      }
      try {
        final permGranted = await _ensureSmsPermissionGranted();
        if (!permGranted) {
          const msg = 'SMS permission still missing';
          _log('$msg â€” keeping queued');
          if (throwOnFailure) throw StateError(msg);
          _queue.add(_SmsJob(
            number: job.number,
            body: job.body,
            attempt: job.attempt + 1,
          ));
          continue;
        }
        if (Platform.isAndroid) {
          await _smsChannel.invokeMethod('sendSms', {
            'to': job.number,
            'message': job.body,
          });
        }
        _log('âœ… Retry SMS sent to ${job.number}');
      } catch (e) {
        _log('Retry failed (${job.attempt + 1}) for ${job.number}: $e');
        if (throwOnFailure) rethrow;
        _queue.add(_SmsJob(
          number: job.number,
          body: job.body,
          attempt: job.attempt + 1,
        ));
      }
    }
    await _persistQueue();
  }

  String _normalizeNumber(String raw) {
    final trimmed = raw.trim();
    // Keep a leading '+' if present; strip spaces/dashes/brackets.
    final hasPlus = trimmed.startsWith('+');
    final digitsOnly = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    return hasPlus ? '+$digitsOnly' : digitsOnly;
  }

  // â”€â”€ Message builder â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  String _buildLocationLink(double? lat, double? lng) {
    if (lat != null && lng != null) {
      return 'https://www.google.com/maps?q=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
    }
    return 'Location unavailable';
  }

  String _buildMessage({
    String? userName,
    String? profileAge,
    String? profileBloodGroup,
    required String locationLink,
    double? lat,
    double? lng,
    CrashSeverity? severity,
    String? userResponse,
    String? emergencyTypeLabel, // FIRE | AMBULANCE | POLICE
    String? triageSummary,
    int? triageRiskPercent,
    ({String type, String severity})? structuredSelection,
  }) {
    final selected = structuredSelection ?? _parseSelection(userResponse);
    if (selected != null) {
      final b = StringBuffer()
        ..writeln('Type: ${selected.type}')
        ..writeln('Severity: ${selected.severity}');
      if (lat != null && lng != null) {
        b.writeln(
            'Lat/Lng: ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}');
      }
      if (triageSummary != null && triageSummary.trim().isNotEmpty) {
        b.writeln('Triage: ${triageSummary.trim()}');
        if (triageRiskPercent != null) {
          b.writeln('Risk: ${triageRiskPercent.clamp(0, 100)}%');
        }
      }
      final who = (userName != null && userName.isNotEmpty) ? userName : null;
      final age = (profileAge != null && profileAge.isNotEmpty)
          ? profileAge
          : null;
      final bg = (profileBloodGroup != null && profileBloodGroup.isNotEmpty)
          ? profileBloodGroup
          : null;
      if (who != null || age != null || bg != null) {
        final parts = [
          if (who != null) who,
          if (age != null) 'Age $age',
          if (bg != null) 'Blood $bg',
        ];
        b.writeln('Profile: ${parts.join(', ')}');
      }
      b
        ..writeln('Location: $locationLink')
        ..write('Please call emergency services immediately.');
      return b.toString();
    }

    final sev = severity ?? CrashSeverity.minor;
    final who =
        (userName != null && userName.isNotEmpty) ? userName : 'Someone';
    final time = _formatTime(DateTime.now());
    // Use specific emergency type header if provided
    final header = emergencyTypeLabel != null
        ? _emergencyTypeHeader(emergencyTypeLabel)
        : 'EMERGENCY SOS - ${_severityLabel(sev)}';
    final b = StringBuffer()
      ..writeln(header)
      ..writeln(emergencyTypeLabel != null
          ? 'Immediate response required!'
          : _severityDescription(sev));
    // Inject user response if provided (replaces the generic "needs urgent help" line)
    if (userResponse != null && userResponse.isNotEmpty) {
      b.writeln('User Status: $userResponse');
    } else {
      b.writeln('$who needs urgent help!');
    }

    b.writeln('Time: $time');
    if (lat != null && lng != null) {
      b.writeln(
          'Lat/Lng: ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}');
    }
    if (triageSummary != null && triageSummary.trim().isNotEmpty) {
      b.writeln('Triage: ${triageSummary.trim()}');
      if (triageRiskPercent != null) {
        b.writeln('Risk: ${triageRiskPercent.clamp(0, 100)}%');
      }
    }
    final profileParts = <String>[];
    if (userName != null && userName.isNotEmpty) profileParts.add(userName);
    if (profileAge != null && profileAge.isNotEmpty) {
      profileParts.add('Age $profileAge');
    }
    if (profileBloodGroup != null && profileBloodGroup.isNotEmpty) {
      profileParts.add('Blood $profileBloodGroup');
    }
    if (profileParts.isNotEmpty) {
      b.writeln('Profile: ${profileParts.join(', ')}');
    }
    b
      ..writeln('Location: $locationLink')
      ..write('Please call emergency services immediately.');
    return b.toString();
  }

  @visibleForTesting
  String buildSosMessageForTest({
    String? userName,
    String? profileAge,
    String? profileBloodGroup,
    required double? lat,
    required double? lng,
    CrashSeverity? severity,
    String? userResponse,
    String? emergencyTypeLabel,
    String? triageSummary,
    int? triageRiskPercent,
    ({String type, String severity})? structuredSelection,
  }) {
    final link = _buildLocationLink(lat, lng);
    return _buildMessage(
      userName: userName,
      profileAge: profileAge,
      profileBloodGroup: profileBloodGroup,
      locationLink: link,
      lat: lat,
      lng: lng,
      severity: severity,
      userResponse: userResponse,
      emergencyTypeLabel: emergencyTypeLabel,
      triageSummary: triageSummary,
      triageRiskPercent: triageRiskPercent,
      structuredSelection: structuredSelection,
    );
  }

  /// Returns an emoji+label header for FIRE / AMBULANCE / POLICE messages.
  String _emergencyTypeHeader(String label) {
    return switch (label) {
      'FIRE'      => 'FIRE EMERGENCY',
      'AMBULANCE' => 'AMBULANCE EMERGENCY',
      'POLICE'    => 'POLICE EMERGENCY',
      _           => 'EMERGENCY SOS',
    };
  }

  ({String type, String severity})? _parseSelection(String? userResponse) {
    if (userResponse == null || userResponse.isEmpty) return null;
    final parts = userResponse.split('|');
    if (parts.length != 3 || parts.first != 'SELECTION') return null;
    final type = switch (parts[1]) {
      'individual' => 'Individual',
      'vehicular' => 'Vehicular',
      'fire' => 'Fire',
      _ => null,
    };
    final severity = switch (parts[2]) {
      'minor' => 'Minor',
      'serious' => 'Serious',
      'critical' => 'Critical',
      _ => null,
    };
    if (type == null || severity == null) return null;
    return (type: type, severity: severity);
  }

  // â”€â”€ Severity helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  String _severityLabel(CrashSeverity sev) {
    switch (sev) {
      case CrashSeverity.critical:
        return 'CRITICAL';
      case CrashSeverity.serious:
        return 'SERIOUS';
      case CrashSeverity.minor:
        return 'MINOR';
    }
  }

  /// One-line urgency description shown below the header.
  String _severityDescription(CrashSeverity sev) {
    switch (sev) {
      case CrashSeverity.critical:
        return 'CRITICAL crash detected â€” person may be unconscious. Respond immediately!';
      case CrashSeverity.serious:
        return 'Serious crash detected â€” injuries likely. Please respond urgently.';
      case CrashSeverity.minor:
        return 'Minor crash detected â€” please check on this person.';
    }
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m ${dt.day}/${dt.month}/${dt.year}';
  }

  void _log(String msg) {
    // ignore: avoid_print
    print('[SmsService] $msg');
  }

  // â”€â”€ Queue persistence â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Serialises the in-memory queue to SharedPreferences so pending messages
  /// survive app restarts.
  Future<void> _persistQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = _queue
          .map((j) => jsonEncode({
                'number': j.number,
                'body': j.body,
                'attempt': j.attempt,
              }))
          .toList();
      await prefs.setStringList(_queueKey, encoded);
    } catch (e) {
      _log('Failed to persist queue: $e');
    }
  }

  /// Restores the queue from SharedPreferences (called once in constructor).
  Future<void> _loadQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_queueKey) ?? [];
      for (final item in raw) {
        final map = jsonDecode(item) as Map<String, dynamic>;
        _queue.add(_SmsJob(
          number: map['number'] as String,
          body: map['body'] as String,
          attempt: (map['attempt'] as num).toInt(),
        ));
      }
      if (_queue.isNotEmpty) {
        _log('Loaded ${_queue.length} queued SMS job(s) from storage');
      }
    } catch (e) {
      _log('Failed to load persisted queue: $e');
    }
  }
}

// â”€â”€ Offline queue model â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _SmsJob {
  final String number;
  final String body;
  final int attempt;
  _SmsJob({required this.number, required this.body, required this.attempt});
}
