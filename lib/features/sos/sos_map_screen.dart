import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:math' as _math;

import 'package:accident_app/shared/providers/app_state.dart';
import 'package:accident_app/shared/services/ble_sos_service.dart';
import 'package:accident_app/shared/services/role_assignment_service.dart';
import 'package:accident_app/shared/utils/maps_launcher.dart';
import 'package:url_launcher/url_launcher.dart';

/// Bystander mode screen shown when a BLE SOS is detected nearby.
/// - Asks quick triage questions.
/// - Shows basic first-aid instructions.
/// - Displays static nearby emergency services.
/// - Renders a simple radar using RSSI as signal strength.
class SosMapScreen extends ConsumerWidget {
  final String deviceId;
  final double? lat;
  final double? lng;
  final double? userLat;
  final double? userLng;

  const SosMapScreen({
    super.key,
    required this.deviceId,
    this.lat,
    this.lng,
    this.userLat,
    this.userLng,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proximity = ref.watch(proximityProvider);
    final rssi = proximity.rssi;
    final direction = proximity.direction;
    final isNavigator = proximity.isNavigator;
    print('RSSI used for UI: $rssi');
    print('RSSI used for role: $rssi');
    final role = assignRole(rssi ?? -100, deviceId);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.pop(),
        ),
        title: const Text('Nearby SOS — Bystander Help'),
        backgroundColor: const Color(0xFFB71C1C),
        actions: [
          // Navigator badge
          if (isNavigator)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                backgroundColor: Colors.amber.shade700,
                label: const Text(
                  '🧭 Navigator',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                backgroundColor: Colors.grey.shade700,
                label: const Text(
                  'Navigator active nearby',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headerSection(deviceId, lat, lng),
              const SizedBox(height: 12),
              _roleBanner(role),
              const SizedBox(height: 12),
              if (role == Role.CALL_AMBULANCE) ...[
                _callEmergencyButton(),
                const SizedBox(height: 12),
              ],
              // ── Ignore SOS button ──────────────────────────────────────────
              _ignoreButton(context, ref),
              const SizedBox(height: 16),
              if (role == Role.FIRST_AID) ...[
                _triageSection(),
                const SizedBox(height: 16),
                _firstAidSection(),
                const SizedBox(height: 16),
                _radarSection(rssi, direction, userLat, userLng, lat, lng),
                const SizedBox(height: 16),
                _nearbyStaticServices(),
              ] else if (role == Role.CALL_AMBULANCE) ...[
                _triageSection(),
                const SizedBox(height: 16),
                _radarSection(rssi, direction, userLat, userLng, lat, lng),
                const SizedBox(height: 16),
                _nearbyStaticServices(),
                const SizedBox(height: 16),
                _firstAidSection(),
              ] else ...[
                _supportSection(),
                const SizedBox(height: 16),
                _radarSection(rssi, direction, userLat, userLng, lat, lng),
                const SizedBox(height: 16),
                _nearbyStaticServices(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _roleLabel(Role role) {
    switch (role) {
      case Role.CALL_AMBULANCE:
        return 'CALL AMBULANCE';
      case Role.FIRST_AID:
        return 'FIRST AID';
      case Role.SUPPORT:
        return 'SUPPORT';
    }
  }

  Widget _roleBanner(Role role) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFB74D)),
      ),
      child: Text(
        '🚨 YOUR ROLE: ${_roleLabel(role)}',
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: Color(0xFFBF360C),
        ),
      ),
    );
  }

  Widget _supportSection() {
    return _TitledCard(
      title: 'Support Role',
      subtitle: 'Assist others / manage surroundings',
      child: const Text(
        'Assist others / manage surroundings',
        style: TextStyle(fontSize: 13),
      ),
    );
  }

  Widget _callEmergencyButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFD32F2F),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () async {
          final uri = Uri.parse('tel:112');
          await launchUrl(uri);
        },
        icon: const Icon(Icons.call),
        label: const Text(
          'Call Emergency',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _headerSection(String deviceId, double? lat, double? lng) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Someone nearby may need help',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Device: $deviceId',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              lat != null && lng != null
                  ? 'Approx. location: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'
                  : 'Beacon did not include GPS coordinates.',
              style: const TextStyle(fontSize: 13),
            ),
            if (lat != null && lng != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => openInGoogleMaps(lat, lng),
                icon: const Icon(Icons.map_outlined),
                label: const Text('View Location'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _triageSection() {
    return _TitledCard(
      title: 'Quick Check',
      subtitle: 'Answer these questions if it\'s safe to approach.',
      child: const _TriageQuestions(),
    );
  }

  Widget _firstAidSection() {
    return _TitledCard(
      title: 'Basic First Aid',
      subtitle: 'Simple, high-level guidance based on common emergencies.',
      child: const _FirstAidTips(),
    );
  }

  Widget _radarSection(
    int? rssi,
    FollowDirection? direction,
    double? userLat,
    double? userLng,
    double? targetLat,
    double? targetLng,
  ) {
    // Compute bearing from user to SOS caller (radians) for the radar dot.
    double? bearing;
    if (userLat != null &&
        userLng != null &&
        targetLat != null &&
        targetLng != null) {
      final dLng = (targetLng - userLng) * (_math.pi / 180);
      final lat1 = userLat * (_math.pi / 180);
      final lat2 = targetLat * (_math.pi / 180);
      bearing = _math.atan2(
        _math.sin(dLng) * _math.cos(lat2),
        _math.cos(lat1) * _math.sin(lat2) -
            _math.sin(lat1) * _math.cos(lat2) * _math.cos(dLng),
      );
    }

    return _TitledCard(
      title: 'Signal Direction (Approx.)',
      subtitle:
          'Turn slowly and move until the signal gets stronger. This is an approximation only.',
      child: _RadarWithBars(rssi: rssi, direction: direction, bearing: bearing),
    );
  }

  Widget _ignoreButton(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.grey.shade700,
          side: BorderSide(color: Colors.grey.shade400),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.do_not_disturb_on_outlined, size: 18),
        label: const Text('Ignore this SOS', style: TextStyle(fontSize: 13)),
        onPressed: () async {
          await ref.read(sosStateProvider.notifier).ignoreSos(deviceId);
          if (context.mounted) context.pop();
        },
      ),
    );
  }

  Widget _nearbyStaticServices() {
    const services = [
      ('City General Hospital', '1.2 km · Emergency'),
      ('Central Police Station', '0.9 km · 24x7'),
      ('Fire & Rescue HQ', '1.5 km · Fire/Rescue'),
    ];
    return _TitledCard(
      title: 'Nearest Emergency Services',
      subtitle: 'Nearby services that may be able to respond.',
      child: Column(
        children: [
          for (final (name, detail) in services)
            ListTile(
              leading: const Icon(Icons.location_city),
              title: Text(name),
              subtitle: Text(detail),
            ),
        ],
      ),
    );
  }
}

class _TitledCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _TitledCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _TriageQuestions extends StatefulWidget {
  const _TriageQuestions();

  @override
  State<_TriageQuestions> createState() => _TriageQuestionsState();
}

class _TriageQuestionsState extends State<_TriageQuestions> {
  bool? breathing;
  bool? conscious;
  bool? bleeding;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _question(
          label: 'Is the person breathing?',
          value: breathing,
          onChanged: (v) => setState(() => breathing = v),
        ),
        _question(
          label: 'Are they conscious?',
          value: conscious,
          onChanged: (v) => setState(() => conscious = v),
        ),
        _question(
          label: 'Is there visible bleeding?',
          value: bleeding,
          onChanged: (v) => setState(() => bleeding = v),
        ),
      ],
    );
  }

  Widget _question({
    required String label,
    required bool? value,
    required ValueChanged<bool?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          ToggleButtons(
            isSelected: [
              value == true,
              value == false,
            ],
            borderRadius: BorderRadius.circular(12),
            onPressed: (index) => onChanged(index == 0),
            children: const [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('Yes'),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('No'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FirstAidTips extends StatelessWidget {
  const _FirstAidTips();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text(
          'If not breathing or unconscious:',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 4),
        Text(
          '• Call local emergency number immediately.\n'
          '• If trained, begin CPR: 30 chest compressions then 2 rescue breaths.\n'
          '• Do not move the person unless there is immediate danger (fire, traffic, etc.).',
          style: TextStyle(fontSize: 13),
        ),
        SizedBox(height: 8),
        Text(
          'If there is severe bleeding:',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 4),
        Text(
          '• Apply firm, direct pressure with a clean cloth or your hand.\n'
          '• If possible, raise the injured area above heart level.\n'
          '• Do not remove objects stuck in the wound; pad around them.',
          style: TextStyle(fontSize: 13),
        ),
      ],
    );
  }
}

class _RadarWithBars extends StatelessWidget {
  final int? rssi;
  final FollowDirection? direction;
  final double? bearing; // radians; null → default straight ahead

  const _RadarWithBars({required this.rssi, this.direction, this.bearing});

  double _signalPercent() {
    if (rssi == null) return 0;
    // Map RSSI (~ -90 dBm weak, -40 dBm strong) to 0–1.
    final clamped = rssi!.clamp(-90, -40);
    return ((clamped + 90) / 50).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final percent = _signalPercent();

    // Direction label (no numeric RSSI shown)
    final directionLabel = switch (direction) {
      FollowDirection.forward => '↑ Move forward',
      FollowDirection.wrongDirection => '↓ Wrong direction — turn back',
      FollowDirection.turnSlightly => '→ Turn slightly',
      FollowDirection.lostSignal => '⚠️ Signal lost',
      null => rssi == null ? 'Scanning…' : 'Tracking signal',
    };

    final directionColor = switch (direction) {
      FollowDirection.forward => const Color(0xFF43A047),
      FollowDirection.wrongDirection => const Color(0xFFD32F2F),
      FollowDirection.lostSignal => Colors.grey,
      _ => const Color(0xFFFF6F00),
    };

    return Column(
      children: [
        SizedBox(
          width: 180,
          height: 180,
          child: CustomPaint(
            painter: _RadarPainter(strength: percent, bearing: bearing ?? 0.0),
          ),
        ),
        const SizedBox(height: 8),
        // Direction label instead of numeric RSSI
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: directionColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: directionColor.withValues(alpha: 0.4)),
          ),
          child: Text(
            directionLabel,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: directionColor,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _signalBars(percent),
      ],
    );
  }

  Widget _signalBars(double percent) {
    final bars = 5;
    final activeBars = (percent * bars).round();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(bars, (i) {
        final active = i < activeBars;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 8,
          height: 10 + i * 6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            color: active ? const Color(0xFF4CAF50) : Colors.grey.shade300,
          ),
        );
      }),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double strength;
  final double bearing; // radians

  _RadarPainter({required this.strength, required this.bearing});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2 - 8;
    final bgPaint = Paint()
      ..color = const Color(0xFFE3F2FD)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, maxRadius, bgPaint);

    final ringPaint = Paint()
      ..color = const Color(0xFFBBDEFB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(center, maxRadius * (i / 3), ringPaint);
    }

    final dotRadius = 8.0;
    final distanceFactor = 1.0 - (0.7 * strength);
    final dotDistance = maxRadius * distanceFactor;
    // Use real bearing computed from GPS coordinates.
    final dotOffset = Offset(
      center.dx + dotDistance * Math.sin(bearing),
      center.dy - dotDistance * Math.cos(bearing),
    );

    final dotPaint = Paint()
      ..color = const Color(0xFFD32F2F)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(dotOffset, dotRadius, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.strength != strength || oldDelegate.bearing != bearing;
}

// Simple math helpers without importing dart:math in multiple places.
class Math {
  static double cos(double x) => _math.cos(x);
  static double sin(double x) => _math.sin(x);
}
