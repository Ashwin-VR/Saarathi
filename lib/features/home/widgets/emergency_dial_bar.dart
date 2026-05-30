import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Fixed emergency dial bar — always visible at top of Home Screen.
/// Reads numbers from assets/data/emergency_numbers.json.
/// Defaults to India (IN) if country unknown.
class EmergencyDialBar extends StatefulWidget {
  final String? countryCode;
  const EmergencyDialBar({super.key, this.countryCode});

  @override
  State<EmergencyDialBar> createState() => _EmergencyDialBarState();
}

class _EmergencyDialBarState extends State<EmergencyDialBar> {
  Map<String, dynamic>? _numbers;

  @override
  void initState() {
    super.initState();
    _loadNumbers();
  }

  Future<void> _loadNumbers() async {
    try {
      final raw = await rootBundle.loadString('assets/data/emergency_numbers.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final code = widget.countryCode ?? 'IN';
      final entry = (data[code] ?? data['IN'] ?? data['DEFAULT'])
          as Map<String, dynamic>;
      if (mounted) setState(() => _numbers = entry);
    } catch (e) {
      if (mounted) {
        setState(() => _numbers = {
          'ambulance': {'number': '108', 'label': 'Ambulance'},
          'police': {'number': '100', 'label': 'Police'},
          'emergency': {'number': '112', 'label': 'Emergency'},
        });
      }
    }
  }

  Future<void> _dial(String number) async {
    final uri = Uri.parse('tel:$number');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nums = _numbers;
    if (nums == null) {
      return Container(
        color: const Color(0xFF0D0D0D),
        height: 72,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
        ),
      );
    }

    final amb = nums['ambulance'] as Map<String, dynamic>? ?? {'number': '108', 'label': 'Ambulance'};
    final pol = nums['police'] as Map<String, dynamic>? ?? {'number': '100', 'label': 'Police'};
    final emg = nums['emergency'] as Map<String, dynamic>? ?? {'number': '112', 'label': 'Emergency'};

    return Container(
      color: const Color(0xFF0D0D0D),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: _DialButton(
                      label: amb['label'] as String,
                      number: amb['number'] as String,
                      color: const Color(0xFFD32F2F),
                      icon: Icons.local_hospital_rounded,
                      onTap: () => _dial(amb['number'] as String),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _DialButton(
                      label: pol['label'] as String,
                      number: pol['number'] as String,
                      color: const Color(0xFF1565C0),
                      icon: Icons.local_police_rounded,
                      onTap: () => _dial(pol['number'] as String),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _DialButton(
                      label: emg['label'] as String,
                      number: emg['number'] as String,
                      color: const Color(0xFF7B1818),
                      icon: Icons.emergency_rounded,
                      onTap: () => _dial(emg['number'] as String),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Numbers may change \u2014 verify locally if unsure.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 9.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialButton extends StatelessWidget {
  final String label;
  final String number;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _DialButton({
    required this.label,
    required this.number,
    required this.color,
    required this.icon,
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
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    number,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
