import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:accident_app/shared/models/emergency_service.dart';
import 'package:accident_app/shared/services/location_service.dart';
import 'package:accident_app/shared/services/location_cache_service.dart';
import 'package:accident_app/shared/services/overpass_service.dart';
import 'package:accident_app/shared/services/ble_sos_service.dart';
import 'package:accident_app/shared/services/ble_mesh_service.dart';
import 'package:accident_app/shared/services/tts_service.dart';
import 'package:accident_app/shared/services/ignore_sos_service.dart';
import 'package:accident_app/shared/services/sensor_service.dart';
import 'package:accident_app/shared/services/vehicle_monitor_service.dart';
import 'package:accident_app/shared/services/sms_service.dart';
import 'package:accident_app/shared/services/sos_alert_service.dart';
import 'package:accident_app/shared/services/notification_service.dart';
import 'package:accident_app/shared/services/care_mode_service.dart';
import 'package:accident_app/shared/services/app_log_service.dart';
import 'package:accident_app/shared/services/demo_mode_service.dart';
import 'package:accident_app/shared/services/incident_history_service.dart';
import 'package:accident_app/features/bystander/providers/bystander_provider.dart';
import 'package:accident_app/shared/models/incident_record.dart';
import 'package:accident_app/shared/services/profile_service.dart';
import 'package:accident_app/shared/services/gemini_triage_service.dart';
import 'package:accident_app/shared/services/gemini_report_service.dart';
import 'package:accident_app/shared/services/incident_pdf_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';

/// True when the current SOS was sent using cached GPS coordinates (GPS was null).
final locationFallbackProvider = StateProvider<bool>((_) => false);

// ── Location state ────────────────────────────────────────────────────────────

final locationProvider = StreamProvider<Position>((ref) {
  return ref.watch(locationServiceProvider).positionStream();
});

final lastPositionProvider = Provider<Position?>((ref) {
  return ref.watch(locationProvider).valueOrNull;
});

// ── Nearby POI state ──────────────────────────────────────────────────────────

final nearbyServicesProvider =
    AsyncNotifierProvider<NearbyServicesNotifier, List<EmergencyService>>(
  NearbyServicesNotifier.new,
);

class NearbyServicesNotifier extends AsyncNotifier<List<EmergencyService>> {
  @override
  Future<List<EmergencyService>> build() async {
    final svc = ref.read(overpassServiceProvider);
    return svc.getCached();
  }

  Future<void> refresh(double lat, double lng) async {
    // Guard against invalid coordinates before hitting Overpass
    if (lat == 0.0 && lng == 0.0) {
      // ignore: avoid_print
      print('[NearbyServices] refresh skipped — GPS not ready (0,0)');
      return;
    }
    // Keep previous results visible while refreshing (better UX).
    state =
        const AsyncLoading<List<EmergencyService>>().copyWithPrevious(state);
    final svc = ref.read(overpassServiceProvider);
    state = await AsyncValue.guard(() => svc.fetchAndCache(lat, lng));
  }
}

final sortedServicesProvider = Provider<List<EmergencyService>>((ref) {
  final services = ref.watch(nearbyServicesProvider).valueOrNull ?? [];
  final position = ref.watch(lastPositionProvider);
  if (position == null) return services;
  final sorted = [...services];
  sorted.sort((a, b) => a
      .distanceKm(position.latitude, position.longitude)
      .compareTo(b.distanceKm(position.latitude, position.longitude)));
  return sorted;
});

// ── SOS state ─────────────────────────────────────────────────────────────────

/// States of the SOS pipeline.
enum SosStatus {
  idle, // Normal operation
  preAlert, // 10-second countdown — triggered by motion/crash/manual
  awaitingUserResponse, // 5-second MINOR response window (before escalation)
  active, // SOS is live — BLE broadcasting + SMS sent
  received, // Nearby BLE SOS received from another device
}

/// What triggered the pre-alert/SOS.
enum SosTrigger { manual, suddenStop, gForce, ble }

enum IncidentType { individual, vehicular, fire }

/// Specific emergency service type requested by the user.
enum EmergencyType {
  fire,    // 🔥 FIRE
  medical, // 🚑 AMBULANCE
  police,  // 🚔 POLICE
}

extension EmergencyTypeX on EmergencyType {
  String get label => switch (this) {
        EmergencyType.fire    => 'FIRE',
        EmergencyType.medical => 'AMBULANCE',
        EmergencyType.police  => 'POLICE',
      };

  String get emoji => switch (this) {
        EmergencyType.fire    => '🔥',
        EmergencyType.medical => '🚑',
        EmergencyType.police  => '🚔',
      };
}

class SosState {
  final SosStatus status;
  final SosTrigger? trigger;
  final int countdownSeconds; // countdown remaining during preAlert
  final int
      responseCountdownSeconds; // countdown remaining in MINOR response window
  final IncidentType? selectedType;
  final CrashSeverity? selectedSeverity;
  final EmergencyType? activeEmergencyType;
  final String? statusText; // "Sending alert…", "Alert sent", "Retrying…"
  final String? incomingDeviceId;
  final double? incomingLat;
  final double? incomingLng;
  final int? incomingRssi;
  final IncidentRecord? lastResolvedIncident;

  const SosState({
    this.status = SosStatus.idle,
    this.trigger,
    this.countdownSeconds = 10,
    this.responseCountdownSeconds = 5,
    this.selectedType,
    this.selectedSeverity,
    this.activeEmergencyType,
    this.statusText,
    this.incomingDeviceId,
    this.incomingLat,
    this.incomingLng,
    this.incomingRssi,
    this.lastResolvedIncident,
  });

  SosState copyWith({
    SosStatus? status,
    SosTrigger? trigger,
    int? countdownSeconds,
    int? responseCountdownSeconds,
    IncidentType? selectedType,
    CrashSeverity? selectedSeverity,
    EmergencyType? activeEmergencyType,
    String? statusText,
    String? incomingDeviceId,
    double? incomingLat,
    double? incomingLng,
    int? incomingRssi,
    IncidentRecord? lastResolvedIncident,
  }) {
    return SosState(
      status: status ?? this.status,
      trigger: trigger ?? this.trigger,
      countdownSeconds: countdownSeconds ?? this.countdownSeconds,
      responseCountdownSeconds:
          responseCountdownSeconds ?? this.responseCountdownSeconds,
      selectedType: selectedType ?? this.selectedType,
      selectedSeverity: selectedSeverity ?? this.selectedSeverity,
      activeEmergencyType: activeEmergencyType ?? this.activeEmergencyType,
      statusText: statusText ?? this.statusText,
      incomingDeviceId: incomingDeviceId ?? this.incomingDeviceId,
      incomingLat: incomingLat ?? this.incomingLat,
      incomingLng: incomingLng ?? this.incomingLng,
      incomingRssi: incomingRssi ?? this.incomingRssi,
      lastResolvedIncident: lastResolvedIncident ?? this.lastResolvedIncident,
    );
  }
}

final sosStateProvider = NotifierProvider<SosNotifier, SosState>(
  SosNotifier.new,
);

class SosNotifier extends Notifier<SosState> {
  Timer? _countdownTimer;
  Timer? _responseTimer; // 5-second MINOR response window
  StreamSubscription<dynamic>? _stopSub;
  StreamSubscription<dynamic>? _crashSub;

  static const _countdownDuration = 10;
  static const _responseDuration = 5; // seconds for MINOR response
  static const _escalationStep2Severity = CrashSeverity.critical;

  // Re-entrant guard: prevents concurrent _activateSos invocations
  bool _activating = false;

  // Severity carried through the event pipeline
  CrashSeverity? _pendingSeverity;
  DateTime? _activeIncidentStartedAt;

  // Emergency type for quick-type buttons (FIRE / AMBULANCE / POLICE)
  EmergencyType? _pendingEmergencyType;

  // User's selected response during the MINOR response window
  String? _userResponse;

  // Latest sensor-trigger payload snapshot (for triage/SMS enrichment)
  CrashEvent? _lastCrashEvent;
  SuddenStopEvent? _lastSuddenStopEvent;

  // Optional pre-selection (non-blocking UI)
  IncidentType? _preselectedType;
  CrashSeverity? _preselectedSeverity;

  @override
  SosState build() {
    // Initialise notification service
    ref.read(notificationServiceProvider).init();

    // Register care-mode → SOS callback to avoid circular dependency
    Future.microtask(() {
      ref.read(sosTriggerCallbackProvider.notifier).state = () {
        triggerSos();
      };
    });

    // Start passive BLE scan (device-to-device SOS beacons)
    final bleService = ref.read(bleSosServiceProvider);

    // Wire follow-mode direction callback → TTS + proximity state
    bleService.onFollowDirection = (direction) {
      ref.read(proximityProvider.notifier).updateDirection(direction);
      // TTS: speak only on change
      final phrase = switch (direction) {
        FollowDirection.forward => 'Getting closer',
        FollowDirection.wrongDirection => 'Wrong direction',
        FollowDirection.turnSlightly => 'Turn slightly',
        FollowDirection.lostSignal => 'Signal lost',
      };
      ref.read(ttsServiceProvider).speakOnChange(phrase);
    };

    // Wire navigator state callback
    bleService.onNavigatorStateChange = (isNavigator) {
      ref.read(proximityProvider.notifier).updateNavigatorStatus(isNavigator);
    };

    bleService.startScanning(
      onSosReceived: (deviceId, lat, lng, rssi) async {
        // ── Ignore SOS check ──────────────────────────────────────────────
        final ignored =
            await ref.read(ignoreSosServiceProvider).isIgnored(deviceId);
        if (ignored) {
          print('[SosNotifier] 🚫 SOS from $deviceId is ignored — skip');
          return;
        }

        // ── Mesh relay ────────────────────────────────────────────────────
        // Generate a stable message ID for this device's current SOS
        final meshId = 'sos_${deviceId.replaceAll(':', '')}';
        final userId = await _getOrCreateUserId();
        ref.read(bleMeshServiceProvider).relayIfNew(
              messageId: meshId,
              ttl: BleMeshService.defaultTtl,
              userId: userId,
              lat: lat,
              lng: lng,
            );

        // ── Update SOS state ──────────────────────────────────────────────
        state = state.copyWith(
          status: state.status == SosStatus.active
              ? SosStatus.active
              : SosStatus.received,
          incomingDeviceId: deviceId,
          incomingLat: lat,
          incomingLng: lng,
          incomingRssi: rssi,
        );
        ref.read(notificationServiceProvider).showSosReceived(
              incidentId: meshId,
              status: 'active',
              deviceId: deviceId,
              lat: lat,
              lng: lng,
            );
        addLog('SOS_RECEIVED');
        print('RSSI used for UI: $rssi');
        print('RSSI used for role: $rssi');
        // Push RSSI into proximity provider (rescuer side)
        ref.read(proximityProvider.notifier).updateRssi(rssi);
      },
    );

    // Start motion sensors
    _startSensorMonitoring();

    ref.onDispose(_cleanup);
    return const SosState();
  }

  // ── Motion monitoring ─────────────────────────────────────────────────────

  void _startSensorMonitoring() {
    // G-force crash detector
    final sensor = ref.read(sensorServiceProvider);
    sensor.startMonitoring();
    _crashSub = sensor.crashEvents.listen((event) {
      _lastCrashEvent = event;
      // Defer ALL state mutations off the sensor callback to avoid
      // blocking the UI/platform thread (prevents screen blackout).
      Future.microtask(() {
        if (state.status != SosStatus.idle) return;
        _log('CrashEvent received: ${event.severity.name.toUpperCase()} '
            'peak=${event.peakMagnitude.toStringAsFixed(2)}G '
            'conf=${event.confidence.toStringAsFixed(2)}');
        _pendingSeverity = event.severity;

        // For MINOR crashes only: open a 5-second user-response window
        // before advancing to the normal pre-alert countdown.
        if (event.severity == CrashSeverity.minor) {
          _beginMinorResponseWindow();
        } else {
          beginPreAlert(SosTrigger.gForce);
        }
      });
    });

    // Sudden stop (vehicle) detector — always goes straight to preAlert
    final vehicle = ref.read(vehicleMonitorProvider);
    vehicle.startMonitoring();
    _stopSub = vehicle.suddenStopEvents.listen((event) {
      _lastSuddenStopEvent = event;
      if (state.status == SosStatus.idle) {
        _log(
            'SuddenStop received: ${event.peakSpeedKmh.toStringAsFixed(1)} km/h');
        beginPreAlert(SosTrigger.suddenStop);
      }
    });
  }

  // ── MINOR response window ─────────────────────────────────────────────────

  /// Opens a [_responseDuration]-second window for the user to respond.
  /// If the user responds → cancel escalation, proceed to preAlert with
  /// current severity. If no response → escalate severity and proceed.
  void _beginMinorResponseWindow() {
    _userResponse = null;
    _responseTimer?.cancel();

    state = SosState(
      status: SosStatus.awaitingUserResponse,
      trigger: SosTrigger.gForce,
      responseCountdownSeconds: _responseDuration,
      selectedType: null,
      selectedSeverity: null,
    );
    _log('MINOR crash — opening ${_responseDuration}s response window');

    _responseTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final remaining = state.responseCountdownSeconds - 1;
      if (remaining <= 0) {
        t.cancel();
        _onResponseTimeout();
      } else {
        state = state.copyWith(responseCountdownSeconds: remaining);
      }
    });
  }

  /// Called when the response window expires with no user input.
  /// Escalates directly MINOR → CRITICAL and fires SOS immediately.
  void _onResponseTimeout() {
    _pendingSeverity = _escalationStep2Severity; // CRITICAL
    _log('No response — escalating to CRITICAL and sending full SOS');
    state = state.copyWith(status: SosStatus.idle);
    final locationService = ref.read(locationServiceProvider);
    unawaited(_activateSos(locationService));
  }

  void setUserSelection({
    required IncidentType type,
    required CrashSeverity severity,
  }) {
    if (state.status != SosStatus.awaitingUserResponse) return;
    _responseTimer?.cancel();
    _responseTimer = null;
    _pendingSeverity = severity;
    _userResponse = 'SELECTION|${type.name}|${severity.name}';
    state = state.copyWith(
      selectedType: type,
      selectedSeverity: severity,
      status: SosStatus.idle,
    );
    _log(
        'User selected type=${type.name}, severity=${severity.name} — sending SOS');
    final locationService = ref.read(locationServiceProvider);
    unawaited(_activateSos(locationService));
  }

  /// Optional pre-selection for manual SOS (non-blocking).
  /// When values are null, selection is cleared.
  void setOptionalPreselection({
    IncidentType? type,
    CrashSeverity? severity,
  }) {
    _preselectedType = type;
    _preselectedSeverity = severity;
    state = state.copyWith(
      selectedType: type,
      selectedSeverity: severity,
    );
  }

  /// Backward-compatible entrypoint for predefined quick response selections.
  void setUserResponse(String response) {
    if (state.status != SosStatus.awaitingUserResponse) return;
    final parts = response.trim().split('|');
    if (parts.length == 2) {
      IncidentType? type;
      for (final value in IncidentType.values) {
        if (value.name == parts[0]) {
          type = value;
          break;
        }
      }
      CrashSeverity? severity;
      for (final value in CrashSeverity.values) {
        if (value.name == parts[1]) {
          severity = value;
          break;
        }
      }
      if (type != null && severity != null) {
        setUserSelection(type: type, severity: severity);
        return;
      }
    }
    // Fallback to timeout behavior if malformed UI payload reaches notifier.
    _onResponseTimeout();
  }

  // ── Pre-alert countdown ───────────────────────────────────────────────────

  /// Start a 10-second countdown. If not cancelled, transitions to [active].
  void beginPreAlert(SosTrigger trigger) {
    if (state.status == SosStatus.preAlert ||
        state.status == SosStatus.active) {
      return;
    }

    _cancelCountdown();
    state = SosState(
      status: SosStatus.preAlert,
      trigger: trigger,
      countdownSeconds: _countdownDuration,
    );

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final remaining = state.countdownSeconds - 1;
      if (remaining <= 0) {
        t.cancel();
        final locationService = ref.read(locationServiceProvider);
        // Use unawaited to avoid blocking the Timer callback thread,
        // which would stall UI rendering and cause a screen blackout.
        unawaited(_activateSos(locationService));
      } else {
        state = state.copyWith(countdownSeconds: remaining);
      }
    });
  }

  /// Cancel the pre-alert countdown and return to idle.
  void cancelPreAlert() {
    _cancelCountdown();
    state = const SosState(status: SosStatus.idle);
  }

  // ── SOS active ────────────────────────────────────────────────────────────

  /// Manually trigger SOS (skips countdown).
  /// [emergencyType] is optional — when provided, SMS and history will reflect
  /// the specific service type (FIRE / AMBULANCE / POLICE).
  Future<bool> triggerSos({
    bool testMode = false,
    EmergencyType? emergencyType,
  }) async {
    try {
      _pendingEmergencyType = emergencyType;
      _pendingSeverity = null;
      _cancelCountdown();

      final locationService = ref.read(locationServiceProvider);
      await _activateSos(locationService, testMode: testMode);

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> triggerManualSos({
    required IncidentType type,
    required CrashSeverity severity,
  }) async {
    if (_activating) return;
    _pendingSeverity = severity;
    _userResponse = 'SELECTION|${type.name}|${severity.name}';
    state = state.copyWith(
      selectedType: type,
      selectedSeverity: severity,
    );
    _cancelCountdown();
    _responseTimer?.cancel();
    _responseTimer = null;
    final locationService = ref.read(locationServiceProvider);
    await _activateSos(locationService);
  }

  Future<void> _activateSos(
    LocationService locationService, {
    bool testMode = false,
  }) async {
    print("🚨 SOS ACTIVATED");
    if (_activating) {
      _log('_activateSos already in progress — skipping duplicate call');
      return;
    }
    _activating = true;

    final demoMode = ref.read(demoModeProvider);

    try {
      state = state.copyWith(
        statusText: 'Sending alert...',
        activeEmergencyType: _pendingEmergencyType,
      );

      final rawPosition = await locationService.getCurrentPosition();
      final userId = await _getOrCreateUserId();

      // ── FIX-1: GPS fallback ───────────────────────────────────────────────
      double? lat;
      double? lng;

      if (rawPosition != null) {
        lat = rawPosition.latitude;
        lng = rawPosition.longitude;
        ref.read(locationFallbackProvider.notifier).state = false;
      } else {
        final cached =
            await ref.read(locationCacheServiceProvider).getLastKnownLocation();
        if (cached != null) {
          _log(
              'GPS null — using cached location (${cached.latitude}, ${cached.longitude})');
          lat = cached.latitude;
          lng = cached.longitude;
          ref.read(locationFallbackProvider.notifier).state = true;
        } else {
          _log('GPS null AND no cache — sending SOS without coordinates');
          ref.read(locationFallbackProvider.notifier).state = false;
        }
      }
      // ─────────────────────────────────────────────────────────────────────

      if (lat != null && lng != null) {
        _log('SOS activated @ lat=${lat.toStringAsFixed(5)} '
            'lng=${lng.toStringAsFixed(5)}');
        print('SENDING SOS WITH LOCATION: $lat, $lng');
      } else {
        _log('SOS activated without coordinates');
      }
      addLog('SOS_TRIGGERED', testMode: testMode);

      // 1. Max volume + continuous vibration
      _log('Starting SOS alert...');
      await ref.read(sosAlertServiceProvider).startAlert();

      if (demoMode) {
        // ── DEMO MODE: skip BLE + SMS, just activate state ──────────────
        _log('DEMO MODE — skipping BLE advertising and SMS');
      } else {
        // ── Optional Gemini triage (<= 2s, never blocks SMS beyond timeout) ──
        final triageFuture = _tryGeminiTriage(
          lat: lat,
          lng: lng,
          timestamp: DateTime.now(),
          trigger: state.trigger ?? SosTrigger.manual,
          speedMps: rawPosition?.speed,
        );

        // 2. BLE advertising
        _log('Starting BLE advertising (userId=$userId)...');
        await ref.read(bleSosServiceProvider).startAdvertising(
              userId: userId,
              lat: lat ?? 0.0,
              lng: lng ?? 0.0,
            );
        print("📡 BLE ADVERTISING STARTED");

        // 3. SMS emergency contacts
        if (!testMode) {
          final profile = await ProfileService().load();
          final userName = profile.name ?? await _getUserName();
          final triage = await triageFuture;

          final structuredSelection = _selectionForSms();
          _log('Sending SOS SMS '
              '(type=${_pendingEmergencyType?.label ?? "SOS"}, '
              'severity=${_pendingSeverity?.name ?? "manual"}, '
              'userResponse=${_userResponse != null ? '"$_userResponse"' : 'none"'})...');
          await ref.read(smsServiceProvider).sendSosAlerts(
                lat: lat,
                lng: lng,
                userName: userName,
                severity: _pendingSeverity,
                userResponse: _userResponse,
                emergencyTypeLabel: _pendingEmergencyType?.label,
                profileAge: profile.age,
                profileBloodGroup: profile.bloodGroup,
                triageSummary: triage?.summaryLine,
                triageRiskPercent: triage?.injuryRiskPercent,
                structuredSelection: structuredSelection,
              );

          state = state.copyWith(statusText: 'Alert sent');
        }

        // ── PDF report: always generate locally (no Gemini needed) ──────────
        // Runs regardless of testMode/demoMode — purely local file write.
        // Future.microtask ensures this runs AFTER the current frame is
        // rendered, preventing UI lag / skipped frames during SOS activation.
        unawaited(Future.microtask(() async {
          try {
            final profile = await ProfileService().load();
            final triage = demoMode ? null : await triageFuture.catchError((_) => null);
            await _generateAndStoreGeminiReport(
              lat: lat,
              lng: lng,
              timestamp: DateTime.now(),
              profile: profile,
              triage: triage is GeminiTriageResult ? triage : null,
              trigger: state.trigger ?? SosTrigger.manual,
              speedMps: rawPosition?.speed,
            );
          } catch (e) {
            if (kDebugMode) {
              // ignore: avoid_print
              print('[SosNotifier] PDF wrapper error: $e');
            }
          }
        }));
      }

      // Trigger local bystander mock system
      ref.read(bystanderProvider.notifier).startIncident();
      if ((kDebugMode || demoMode) && lat != null && lng != null) {
        ref.read(bystanderProvider.notifier).seedSyntheticBystanders(
              userLat: lat,
              userLng: lng,
            );
      }
      _activeIncidentStartedAt = DateTime.now();

      state = state.copyWith(status: SosStatus.active);
      _log('SOS is now ACTIVE${demoMode ? " (DEMO)" : ""}');
    } finally {
      _activating = false;
      _pendingSeverity = null;
      _userResponse = null;
      // Note: _pendingEmergencyType is cleared AFTER cancelSos reads it
      state = state.copyWith(
        selectedType: null,
        selectedSeverity: null,
        // keep activeEmergencyType while active; cleared on cancelSos
      );
    }
  }

  ({String type, String severity})? _selectionForSms() {
    // Prefer explicit selection from response window; otherwise use preselection.
    final fromResponse = _parseSelection(_userResponse);
    if (fromResponse != null) return fromResponse;
    final type = _preselectedType;
    final sev = _preselectedSeverity;
    if (type == null || sev == null) return null;
    return (type: _labelIncidentType(type), severity: _labelSeverity(sev));
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

  String _labelIncidentType(IncidentType type) => switch (type) {
        IncidentType.individual => 'Individual',
        IncidentType.vehicular => 'Vehicular',
        IncidentType.fire => 'Fire',
      };

  String _labelSeverity(CrashSeverity sev) => switch (sev) {
        CrashSeverity.minor => 'Minor',
        CrashSeverity.serious => 'Serious',
        CrashSeverity.critical => 'Critical',
      };

  Future<GeminiTriageResult?> _tryGeminiTriage({
    required double? lat,
    required double? lng,
    required DateTime timestamp,
    required SosTrigger trigger,
    required double? speedMps,
  }) async {
    // Guard: no API key → skip immediately, return null (SMS still sends).
    const apiKey = String.fromEnvironment('GEMINI_API_KEY');
    if (apiKey.isEmpty) return null;

    try {
      // No internet → SMS only (no AI).
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) return null;

      final profile = await ProfileService().load();
      final crash = _lastCrashEvent;
      final stop = _lastSuddenStopEvent;

      // Build payload with NO null values to avoid Gemini 400 errors.
      final payload = <String, dynamic>{
        'timestamp': timestamp.toIso8601String(),
        'trigger_type': trigger.name,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (crash?.peakMagnitude != null) 'peak_g': crash!.peakMagnitude,
        if (crash?.duration != null)
          'duration_ms': crash!.duration.inMilliseconds,
        if (crash?.stillnessRatio != null)
          'stillness_ratio': crash!.stillnessRatio,
        if (speedMps != null) 'speed_mps': speedMps,
        if (stop?.peakSpeedKmh != null) 'peak_speed_kmh': stop!.peakSpeedKmh,
        if (profile.name != null) 'name': profile.name,
        if (profile.age != null) 'age': profile.age,
        if (profile.gender != null) 'gender': profile.gender,
        if (profile.bloodGroup != null) 'blood_group': profile.bloodGroup,
        if (_preselectedType != null) 'incident_type': _preselectedType!.name,
        if (_preselectedSeverity != null)
          'severity': _preselectedSeverity!.name,
      };

      return await ref
          .read(geminiTriageServiceProvider)
          .triage(sosPayload: payload, timeout: const Duration(seconds: 2));
    } catch (_) {
      return null;
    }
  }

  /// Generates a rich PDF incident report from LOCAL DATA ONLY.
  ///
  /// The PDF is ALWAYS generated regardless of network or Gemini availability.
  /// Gemini AI narrative is attempted afterward as best-effort enrichment only.
  Future<void> _generateAndStoreGeminiReport({
    required double? lat,
    required double? lng,
    required DateTime timestamp,
    required UserProfile profile,
    required GeminiTriageResult? triage,
    required SosTrigger trigger,
    required double? speedMps,
  }) async {
    try {
      final crash = _lastCrashEvent;

      // ── Step 1: Build all local values (no network needed) ────────────────
      String? gClass;
      if (crash != null) {
        final g = crash.peakMagnitude;
        gClass = g >= 4.0
            ? 'Severe (>= 4 G)'
            : g >= 2.5
                ? 'Moderate (>= 2.5 G)'
                : 'Low (< 2.5 G)';
      }

      final triageSuffix = triage != null
          ? '  |  Triage: ${triage.summaryLine} (Risk ${triage.injuryRiskPercent}%)'
          : '';
      final severityStr =
          '${_pendingEmergencyType?.label ?? trigger.name.toUpperCase()}'
          '$triageSuffix';

      final durationLabel =
          crash != null ? '${crash.duration.inMilliseconds} ms' : null;
      final stillnessLabel =
          crash != null ? crash.stillnessRatio.toStringAsFixed(2) : null;
      final speedLabel = speedMps != null
          ? '${(speedMps * 3.6).toStringAsFixed(1)} km/h'
          : null;

      // ── Step 2: Generate PDF immediately from local data ──────────────────
      // This ALWAYS runs. No API key needed. No network needed.
      final pdfPath = await IncidentPdfService().generateSosPdfExtended(
        userName: profile.name,
        gender: profile.gender,
        age: profile.age,
        bloodGroup: profile.bloodGroup,
        sos1: profile.sos1,
        sos2: profile.sos2,
        eventTime: timestamp,
        lat: lat,
        lng: lng,
        peakG: crash?.peakMagnitude,
        gClassification: gClass,
        severity: severityStr,
        trigger: trigger.name,
        durationMs: durationLabel,
        stillnessRatio: stillnessLabel,
        speedKmh: speedLabel,
        triageSummary: triage?.summaryLine,
        triageRiskPercent: triage?.injuryRiskPercent,
        aiNarrative: null, // Will be patched below if Gemini succeeds
      );

      // ── Step 3: Save PDF to persistent storage ────────────────────────────
      final docsDir = await getApplicationDocumentsDirectory();
      final reportsDir =
          Directory('${docsDir.path}${Platform.pathSeparator}reports');
      if (!reportsDir.existsSync()) {
        reportsDir.createSync(recursive: true);
      }
      final destPath =
          '${reportsDir.path}${Platform.pathSeparator}'
          'sos_${timestamp.millisecondsSinceEpoch}.pdf';
      await File(pdfPath).copy(destPath);

      if (kDebugMode) {
        // ignore: avoid_print
        print('[SosNotifier] PDF saved (local) → $destPath');
      }

      // ── Step 4: Optional Gemini enrichment (async, best-effort) ──────────
      // Only attempted when: API key present + online.
      // On any failure the PDF above is already safely saved — no re-gen.
      const _apiKey = String.fromEnvironment('GEMINI_API_KEY');
      if (_apiKey.isNotEmpty) {
        try {
          final connectivity = await Connectivity().checkConnectivity();
          if (!connectivity.contains(ConnectivityResult.none)) {
            final stop = _lastSuddenStopEvent;
            final payload = <String, dynamic>{
              'timestamp': timestamp.toIso8601String(),
              'trigger': trigger.name,
              if (lat != null) 'lat': lat,
              if (lng != null) 'lng': lng,
              if (profile.name?.isNotEmpty == true) 'name': profile.name,
              if (profile.age?.isNotEmpty == true) 'age': profile.age,
              if (profile.gender?.isNotEmpty == true) 'gender': profile.gender,
              if (profile.bloodGroup?.isNotEmpty == true)
                'blood_group': profile.bloodGroup,
              if (crash?.peakMagnitude != null) 'peak_g': crash!.peakMagnitude,
              if (crash?.duration != null)
                'duration_ms': crash!.duration.inMilliseconds,
              if (speedMps != null) 'speed_mps': speedMps,
              if (stop?.peakSpeedKmh != null)
                'peak_speed_kmh': stop!.peakSpeedKmh,
              if (triage != null) 'triage_summary': triage.summaryLine,
              if (triage != null) 'triage_risk': triage.injuryRiskPercent,
            };
            final narrative =
                await const GeminiReportService().generateReport(payload);
            if (narrative.isNotEmpty) {
              // Re-generate PDF with AI narrative appended.
              final enrichedPath =
                  await IncidentPdfService().generateSosPdfExtended(
                userName: profile.name,
                gender: profile.gender,
                age: profile.age,
                bloodGroup: profile.bloodGroup,
                sos1: profile.sos1,
                sos2: profile.sos2,
                eventTime: timestamp,
                lat: lat,
                lng: lng,
                peakG: crash?.peakMagnitude,
                gClassification: gClass,
                severity: severityStr,
                trigger: trigger.name,
                durationMs: durationLabel,
                stillnessRatio: stillnessLabel,
                speedKmh: speedLabel,
                triageSummary: triage?.summaryLine,
                triageRiskPercent: triage?.injuryRiskPercent,
                aiNarrative: narrative,
              );
              // Overwrite the plain PDF with the enriched one.
              await File(enrichedPath).copy(destPath);
              if (kDebugMode) {
                // ignore: avoid_print
                print('[SosNotifier] PDF re-saved with AI narrative → $destPath');
              }
            }
          }
        } catch (e) {
          // Gemini failure is silent — plain PDF is already saved above.
          if (kDebugMode) {
            // ignore: avoid_print
            print('[SosNotifier] Gemini enrichment skipped: $e');
          }
        }
      }
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SosNotifier] PDF generation error (non-fatal): $e\n$st');
      }
      // Fully non-blocking — swallow all errors.
    }
  }

  Future<void> cancelSos() async {
    final bystanders = ref.read(bystanderProvider).bystanders;
    final currentPosition = ref.read(lastPositionProvider);
    final incidentId = ref.read(bystanderProvider).incidentId ??
        'incident_${DateTime.now().millisecondsSinceEpoch}';
    final startedAt = _activeIncidentStartedAt ??
        DateTime.now().subtract(const Duration(minutes: 1));
    final endedAt = DateTime.now();
    final resolvedRecord = IncidentRecord(
      incidentId: incidentId,
      startTime: startedAt,
      endTime: endedAt,
      gpsTrace: [
        if (currentPosition != null)
          {
            'lat': currentPosition.latitude,
            'lng': currentPosition.longitude,
            'timestamp': endedAt.toIso8601String(),
          },
      ],
      sensorEvents: [
        {
          'trigger': state.trigger?.name ?? 'manual',
          if (state.selectedSeverity != null)
            'severity': state.selectedSeverity!.name,
          'timestamp': startedAt.toIso8601String(),
        },
      ],
      responders: bystanders
          .map((b) => {
                'id': b.id,
                'name': b.name,
                'role': b.role.name,
                'distance_m': b.distance,
              })
          .toList(),
      lat: currentPosition?.latitude,
      lng: currentPosition?.longitude,
    );

    _cancelCountdown();
    _responseTimer?.cancel();
    _responseTimer = null;
    _userResponse = null;
    await ref.read(bleSosServiceProvider).stopAdvertising();
    await ref.read(sosAlertServiceProvider).stopAlert();
    ref.read(bystanderProvider.notifier).stopIncident();
    state = SosState(
      status: SosStatus.idle,
      selectedType: null,
      selectedSeverity: null,
      activeEmergencyType: null,
      statusText: null,
      lastResolvedIncident: resolvedRecord,
    );
    _activeIncidentStartedAt = null;

    // ── PART 2: Save to incident history ──────────────────────────────────
    // Use EmergencyType label if set, otherwise fall back to SosTrigger name.
    final triggerLabel = _pendingEmergencyType?.label
        ?? (resolvedRecord.sensorEvents.isNotEmpty
            ? (resolvedRecord.sensorEvents.first['trigger'] as String? ?? 'manual')
            : 'manual');
    final histEntry = IncidentHistoryEntry(
      id: incidentId,
      startTime: startedAt,
      endTime: endedAt,
      lat: currentPosition?.latitude,
      lng: currentPosition?.longitude,
      trigger: triggerLabel,
      severity: resolvedRecord.sensorEvents.isNotEmpty
          ? resolvedRecord.sensorEvents.first['severity'] as String?
          : null,
    );
    unawaited(
      ref.read(incidentHistoryServiceProvider).save(histEntry),
    );
    _pendingEmergencyType = null;
  }

  void dismissIncoming() {
    state = const SosState(status: SosStatus.idle);
    ref.read(proximityProvider.notifier).reset();
    ref.read(ttsServiceProvider).stop();
  }

  /// User taps "Ignore" on an incoming SOS banner.
  Future<void> ignoreSos(String deviceId) async {
    await ref.read(ignoreSosServiceProvider).ignore(deviceId);
    // Also mark in mesh cache so we don't relay it again
    final meshId = 'sos_${deviceId.replaceAll(':', '')}';
    ref.read(bleMeshServiceProvider).markSeen(meshId);
    dismissIncoming();
    print('[SosNotifier] 🚫 SOS from $deviceId ignored and dismissed');
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  void _log(String msg) {
    // ignore: avoid_print
    print('[SosNotifier] $msg');
  }

  void _cleanup() {
    _cancelCountdown();
    _responseTimer?.cancel();
    _responseTimer = null;
    _stopSub?.cancel();
    _crashSub?.cancel();
    ref.read(sensorServiceProvider).stopMonitoring();
    ref.read(vehicleMonitorProvider).stopMonitoring();
    ref.read(bleSosServiceProvider).dispose();
    ref.read(sosAlertServiceProvider).stopAlert();
    ref.read(ttsServiceProvider).dispose();
  }

  Future<String> _getOrCreateUserId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('user_id');
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString('user_id', id);
    }
    return id;
  }

  Future<String?> _getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_name');
  }
}

// ── Filter state (for POI type filtering) ─────────────────────────────────────

final activeFilterProvider = StateProvider<Set<EmergencyServiceType>>((ref) {
  return EmergencyServiceType.values.toSet();
});

// ── Proximity + Follow Mode state provider ────────────────────────────────────

class ProximityState {
  final int? rssi;
  final String proximity; // 'VERY CLOSE' | 'GETTING CLOSER' | 'FAR'
  final FollowDirection? direction; // latest follow-mode direction
  final bool isNavigator; // true = this device won First Finder Lock

  const ProximityState({
    this.rssi,
    this.proximity = 'FAR',
    this.direction,
    this.isNavigator = false,
  });

  ProximityState copyWith({
    int? rssi,
    String? proximity,
    FollowDirection? direction,
    bool? isNavigator,
  }) =>
      ProximityState(
        rssi: rssi ?? this.rssi,
        proximity: proximity ?? this.proximity,
        direction: direction ?? this.direction,
        isNavigator: isNavigator ?? this.isNavigator,
      );
}

final proximityProvider =
    NotifierProvider<ProximityNotifier, ProximityState>(ProximityNotifier.new);

class ProximityNotifier extends Notifier<ProximityState> {
  @override
  ProximityState build() => const ProximityState();

  void updateRssi(int? rssi) {
    if (rssi == null) return;
    final proximity = _proximityFromRssi(rssi);
    state = state.copyWith(rssi: rssi, proximity: proximity);
  }

  void updateDirection(FollowDirection dir) {
    state = state.copyWith(direction: dir);
  }

  void updateNavigatorStatus(bool isNav) {
    state = state.copyWith(isNavigator: isNav);
  }

  void reset() {
    state = const ProximityState();
  }

  String _proximityFromRssi(int rssi) {
    if (rssi >= -60) return 'VERY CLOSE';
    if (rssi >= -75) return 'GETTING CLOSER';
    return 'FAR';
  }
}
