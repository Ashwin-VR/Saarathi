import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:accident_app/shared/models/emergency_service.dart';

/// Panel shown when SOS is ACTIVE (state == SosStatus.active).
/// Non-dismissible overlay at the bottom of the Home Screen.
/// Dismiss button hides the panel but does NOT cancel the alert.
class EmergencyResponsePanel extends StatefulWidget {
  final DateTime alertedAt;
  final List<String> notifiedContacts;
  final double? lat;
  final double? lng;
  final String? district;
  final EmergencyService? nearestHospital;
  final VoidCallback onDismiss;

  const EmergencyResponsePanel({
    super.key,
    required this.alertedAt,
    required this.notifiedContacts,
    this.lat,
    this.lng,
    this.district,
    this.nearestHospital,
    required this.onDismiss,
  });

  @override
  State<EmergencyResponsePanel> createState() => _EmergencyResponsePanelState();
}

class _EmergencyResponsePanelState extends State<EmergencyResponsePanel> {
  Future<void> _call112() async {
    final uri = Uri.parse('tel:112');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _shareLocation() async {
    final lat = widget.lat;
    final lng = widget.lng;
    final ts = DateFormat('dd MMM yyyy, HH:mm').format(widget.alertedAt);
    final hospital = widget.nearestHospital;
    final district = widget.district ?? 'Unknown location';

    String message;
    if (lat != null && lng != null) {
      final mapsLink = 'https://maps.google.com/?q=$lat,$lng';
      message = 'I\'ve been in a road accident.\n'
          'Location: $lat, $lng ($district)\n'
          'Maps: $mapsLink\n';
      if (hospital != null) {
        message += 'Nearest hospital: ${hospital.name}\n';
      }
      message += 'Time: $ts';
    } else {
      message = 'I\'ve been in a road accident.\nTime: $ts\n'
          'Location not available — call 112 for help.';
    }

    await Share.share(message, subject: 'EMERGENCY: Road accident');
  }

  void _showGoodSamaritanModal() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.gavel_rounded, color: Color(0xFF1565C0)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Good Samaritan Protection',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: const Text(
          'Section 134A of the Motor Vehicles (Amendment) Act 2019 grants '  
          'complete legal protection to any person who voluntarily provides '  
          'emergency assistance at a road accident scene in good faith.\n\n'  
          'You CANNOT be:\n'  
          '\u2022 Detained by police\n'  
          '\u2022 Forced to give your personal details\n'  
          '\u2022 Held civilly or criminally liable\n'  
          '\u2022 Required to accompany the victim to hospital\n\n'  
          'Help freely. The law is on your side.',
          style: TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ts = DateFormat('HH:mm').format(widget.alertedAt);
    final contacts = widget.notifiedContacts.isEmpty
        ? 'None'
        : widget.notifiedContacts.join(', ');
    final district = widget.district ?? 'Location unknown';

    return Material(
      elevation: 12,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1A0000),
              Color(0xFF2D0000),
            ],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: const Color(0xFFEF5350).withValues(alpha: 0.4)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  const _PulsingDot(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '\u26a0\ufe0f ALERT SENT \u00b7 $ts',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                    tooltip: 'Hide panel (alert still active)',
                    onPressed: widget.onDismiss,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 16),
              // Contacts row
              _InfoRow(
                icon: Icons.people_outline,
                label: 'Contacts notified',
                value: contacts,
              ),
              const SizedBox(height: 4),
              _InfoRow(
                icon: Icons.location_on_outlined,
                label: 'Location shared',
                value: district,
              ),
              const Divider(color: Colors.white12, height: 16),
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      label: 'CALL 112 NOW',
                      icon: Icons.phone_rounded,
                      color: const Color(0xFFD32F2F),
                      onTap: _call112,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionButton(
                      label: 'SHARE LOCATION',
                      icon: Icons.share_rounded,
                      color: const Color(0xFF1565C0),
                      onTap: _shareLocation,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Good Samaritan notice
              GestureDetector(
                onTap: _showGoodSamaritanModal,
                child: Text(
                  '\u00a7134A, MV Act 2019: You are legally protected for helping in good faith. Tap to learn more.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 11,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _opacity = Tween(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (_, __) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color.fromRGBO(239, 83, 80, _opacity.value),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.white38, size: 14),
        const SizedBox(width: 6),
        Text('$label: ', style: const TextStyle(color: Colors.white38, fontSize: 12)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
