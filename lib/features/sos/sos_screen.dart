import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:accident_app/shared/providers/app_state.dart';
import 'package:accident_app/core/router/app_router.dart';
import 'package:accident_app/shared/services/location_service.dart';
import 'package:accident_app/shared/services/sms_service.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:accident_app/features/bystander/widgets/bystander_list_widget.dart';
import 'package:accident_app/shared/services/sensor_service.dart';

class SosFeatureSheet extends ConsumerWidget {
  const SosFeatureSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const SosFeatureSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sosState = ref.watch(sosStateProvider);
    return _SosSheetContent(sosState: sosState);
  }
}

class _SosSheetContent extends ConsumerStatefulWidget {
  final SosState sosState;
  const _SosSheetContent({required this.sosState});

  @override
  ConsumerState<_SosSheetContent> createState() => _SosSheetContentState();
}

class _SosSheetContentState extends ConsumerState<_SosSheetContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  StreamSubscription<Position>? _posSub;
  StreamSubscription<AccelerometerEvent>? _accSub;
  double _speedKmh = 0.0;
  double _g = 1.0;
  DateTime _lastTelemetryUi = DateTime.fromMillisecondsSinceEpoch(0);

  IncidentType? _optType;
  CrashSeverity? _optSeverity;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _startTelemetry();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _accSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _startTelemetry() {
    // Speed stream (km/h)
    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );
    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        final kmh = max(0.0, pos.speed * 3.6);
        final now = DateTime.now();
        if (now.difference(_lastTelemetryUi).inMilliseconds < 200) return;
        _lastTelemetryUi = now;
        if (!mounted) return;
        setState(() => _speedKmh = kmh);
      },
      onError: (_) {},
    );

    // G-force (instant magnitude in g)
    _accSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen(
      (e) {
        final g = sqrt(e.x * e.x + e.y * e.y + e.z * e.z) / 9.81;
        final now = DateTime.now();
        if (now.difference(_lastTelemetryUi).inMilliseconds < 200) return;
        _lastTelemetryUi = now;
        if (!mounted) return;
        setState(() => _g = g);
      },
      onError: (_) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    final sosState = ref.watch(sosStateProvider);
    final status = sosState.status;
    final isActive = status == SosStatus.active;
    final isAlert = status == SosStatus.preAlert;

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: isActive
                ? const Color(0xFFD32F2F).withValues(alpha: 0.35)
                : Colors.black.withValues(alpha: 0.18),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),

            // ── State indicator ─────────────────────────────────────────────
            if (isAlert)
              _buildCountdownRing(sosState.countdownSeconds)
            else
              _buildStatusCircle(isActive: isActive),

            const SizedBox(height: 20),

            // ── Title ───────────────────────────────────────────────────────
            _buildTitle(status, sosState),

            const SizedBox(height: 8),

            // ── Subtitle ────────────────────────────────────────────────────
            _buildSubtitle(status, sosState),

            const SizedBox(height: 28),

            // ── Optional incident selection (non-blocking) ───────────────────
            if (status == SosStatus.idle || status == SosStatus.received) ...[
              _buildOptionalSelectionRow(),
              const SizedBox(height: 14),
            ],

            if (sosState.statusText != null &&
                sosState.statusText!.trim().isNotEmpty) ...[
              Align(
                alignment: Alignment.center,
                child: Text(
                  sosState.statusText!.trim(),
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],

            // ── Action buttons ───────────────────────────────────────────────
            ..._buildActions(context, ref, status),

            const SizedBox(height: 16),

            // ── Bystander System ─────────────────────────────────────────────
            const BystanderListWidget(),
            const SizedBox(height: 16),

            // ── Live telemetry + Crash simulation ─────────────────────────────
            _buildTelemetryRow(),
            const SizedBox(height: 10),
            if (kDebugMode) _buildCrashSimulationButton(context),

            // ── Escape: Fake Call ────────────────────────────────────────────
            const SizedBox(height: 12),
            _buildFakeCallRow(context),
          ],
        ),
      ),
    );
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  Widget _buildCountdownRing(int seconds) {
    final frac = seconds / 10.0;
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 110,
          height: 110,
          child: CircularProgressIndicator(
            value: frac,
            strokeWidth: 7,
            backgroundColor: Colors.grey.shade200,
            valueColor: const AlwaysStoppedAnimation(Color(0xFFFF6F00)),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$seconds',
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                color: Color(0xFFFF6F00),
              ),
            ),
            const Text('sec',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusCircle({required bool isActive}) {
    return ScaleTransition(
      scale: isActive ? _pulseAnim : const AlwaysStoppedAnimation(1.0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive ? const Color(0xFFD32F2F) : const Color(0xFFF5F5F5),
          boxShadow: isActive
              ? [
                  BoxShadow(
                      color: const Color(0xFFD32F2F).withValues(alpha: 0.45),
                      blurRadius: 28,
                      spreadRadius: 6)
                ]
              : [],
        ),
        child: Icon(
          isActive ? Icons.crisis_alert : Icons.sos_outlined,
          size: 54,
          color: isActive ? Colors.white : const Color(0xFFD32F2F),
        ),
      ),
    );
  }

  Widget _buildTitle(SosStatus status, SosState sosState) {
    final (text, color) = switch (status) {
      SosStatus.preAlert => (
          'SOS IN ${sosState.countdownSeconds}s',
          const Color(0xFFFF6F00)
        ),
      SosStatus.active => ('SOS IS ACTIVE', const Color(0xFFD32F2F)),
      SosStatus.awaitingUserResponse => (
          'Crash Detected',
          const Color(0xFFFF6F00)
        ),
      _ => ('Emergency SOS', null),
    };
    return Text(
      text,
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w900,
        color: color,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildSubtitle(SosStatus status, SosState sosState) {
    String msg;
    if (status == SosStatus.preAlert) {
      final trigger = switch (sosState.trigger) {
        SosTrigger.suddenStop => '⚡ Sudden stop detected',
        SosTrigger.gForce => '💥 High G-force detected',
        SosTrigger.ble => '📡 BLE SOS trigger',
        _ => '🆘 Manual SOS triggered',
      };
      msg = '$trigger\nCancel if you are safe.';
    } else if (status == SosStatus.active) {
      msg = 'Broadcasting via BLE.\nEmergency contacts notified.';
    } else if (status == SosStatus.awaitingUserResponse) {
      msg = 'Awaiting your response\u2026';
    } else {
      msg =
          'Hold the SOS button to broadcast\nan emergency alert to nearby devices.';
    }
    return Text(
      msg,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.grey.shade600,
        height: 1.55,
        fontSize: 13.5,
      ),
    );
  }

  List<Widget> _buildActions(
    BuildContext context,
    WidgetRef ref,
    SosStatus status,
  ) {
    switch (status) {
      case SosStatus.preAlert:
        return [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text(
              'I\'M SAFE — CANCEL',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            onPressed: () {
              ref.read(sosStateProvider.notifier).cancelPreAlert();
              // Guard: only pop if this sheet is still on the navigator stack.
              if (mounted && Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            },
          ),
        ];

      case SosStatus.active:
        return [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey.shade800,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.cancel_outlined),
            label: const Text(
              'CANCEL SOS',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            onPressed: () async {
              await ref.read(sosStateProvider.notifier).cancelSos();
              if (!mounted) return;
              final incident = ref.read(sosStateProvider).lastResolvedIncident;
              // Guard: only pop if this sheet is still on the navigator stack.
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
              if (incident != null) {
                context.push(AppRoutes.incidentDetail, extra: incident);
              }
            },
          ),
        ];

      case SosStatus.awaitingUserResponse:
        return [
          const SizedBox(
            height: 52,
            child: Center(
              child: Text(
                'Respond to the crash alert above…',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
          ),
        ];

      case SosStatus.idle:
      case SosStatus.received:
        return [
          Semantics(
            label: 'Trigger SOS emergency alert',
            button: true,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD32F2F),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.sos),
              label: const Text(
                'TRIGGER SOS NOW',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              onPressed: () async {
                final notifier = ref.read(sosStateProvider.notifier);
                final currentState = ref.read(sosStateProvider);

                /// 🔥 KEY LOGIC
                if (currentState.status == SosStatus.active) {
                  // SECOND TAP → CANCEL
                  await notifier.cancelSos();

                  if (!context.mounted) return;

                  final incident =
                      ref.read(sosStateProvider).lastResolvedIncident;

                  if (incident != null) {
                    context.push(AppRoutes.incidentDetail, extra: incident);
                  }
                } else {
                  // FIRST TAP → TRIGGER
                  notifier.setOptionalPreselection(
                    type: _optType,
                    severity: _optSeverity,
                  );
                  await notifier.triggerSos();

                  if (!context.mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('SOS alert sent'),
                      backgroundColor: Color(0xFFD32F2F),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
          ),
        ];
    }
  }

  Widget _buildOptionalSelectionRow() {
    Widget chip<T>({
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            side: BorderSide(
              color: selected ? const Color(0xFF1565C0) : Colors.grey.shade300,
              width: selected ? 1.6 : 1.2,
            ),
            backgroundColor: selected
                ? const Color(0xFF1565C0).withValues(alpha: 0.08)
                : Colors.transparent,
            foregroundColor:
                selected ? const Color(0xFF1565C0) : Colors.grey.shade700,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          onPressed: onTap,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Optional: Type',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () {
                setState(() {
                  _optType = null;
                  _optSeverity = null;
                });
                ref.read(sosStateProvider.notifier).setOptionalPreselection();
              },
              child: const Text('Clear'),
            )
          ],
        ),
        Row(
          children: [
            chip(
              label: 'Individual',
              selected: _optType == IncidentType.individual,
              onTap: () => setState(() => _optType = IncidentType.individual),
            ),
            const SizedBox(width: 8),
            chip(
              label: 'Vehicular',
              selected: _optType == IncidentType.vehicular,
              onTap: () => setState(() => _optType = IncidentType.vehicular),
            ),
            const SizedBox(width: 8),
            chip(
              label: 'Fire',
              selected: _optType == IncidentType.fire,
              onTap: () => setState(() => _optType = IncidentType.fire),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Optional: Severity',
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            chip(
              label: 'Minor',
              selected: _optSeverity == CrashSeverity.minor,
              onTap: () => setState(() => _optSeverity = CrashSeverity.minor),
            ),
            const SizedBox(width: 8),
            chip(
              label: 'Serious',
              selected: _optSeverity == CrashSeverity.serious,
              onTap: () => setState(() => _optSeverity = CrashSeverity.serious),
            ),
            const SizedBox(width: 8),
            chip(
              label: 'Critical',
              selected: _optSeverity == CrashSeverity.critical,
              onTap: () =>
                  setState(() => _optSeverity = CrashSeverity.critical),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFakeCallRow(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.grey.shade600,
        side: BorderSide(color: Colors.grey.shade300),
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(Icons.phone_in_talk_outlined, size: 18),
      label: const Text('Fake Incoming Call (escape)',
          style: TextStyle(fontSize: 13)),
      onPressed: () {
        // Guard: only pop if this sheet is still on the navigator stack.
        if (Navigator.canPop(context)) Navigator.pop(context);
        context.push(AppRoutes.fakeCall);
      },
    );
  }

  Widget _buildTelemetryRow() {
    Widget chip(
        {required String label,
        required String value,
        required IconData icon}) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F7FB),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: Colors.grey.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade700)),
                    const SizedBox(height: 2),
                    Text(value,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(
          label: 'Speed',
          value: '${_speedKmh.toStringAsFixed(1)} km/h',
          icon: Icons.speed_outlined,
        ),
        const SizedBox(width: 10),
        chip(
          label: 'G-force',
          value: '${_g.toStringAsFixed(2)} g',
          icon: Icons.vibration,
        ),
      ],
    );
  }

  Widget _buildCrashSimulationButton(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: const Icon(Icons.bug_report_outlined),
      label: const Text(
        'CRASH SIMULATION (SMS primary contact)',
        style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.4),
      ),
      onPressed: () async {
        final last = ref.read(lastPositionProvider);
        final pos = last ??
            await ref.read(locationServiceProvider).getCurrentPosition();

        try {
          await ref.read(smsServiceProvider).sendSosToPrimaryContact(
                lat: pos?.latitude,
                lng: pos?.longitude,
                userName: null,
                throwOnFailure: true,
              );
        } catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('SMS failed: $e')),
          );
          return;
        }

        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Crash simulation SOS SMS sent (primary contact).')),
        );
      },
    );
  }
}
