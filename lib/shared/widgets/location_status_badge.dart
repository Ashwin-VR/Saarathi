import 'package:flutter/material.dart';
import '../models/safe_location.dart';

/// Small status badge that renders next to any location-aware widget.
///
/// Shows:
///   • green  "Live location"            — fresh GPS fix
///   • amber  "Using last known location (X min ago)"  — cached
///   • red    "Using last known location (X hrs ago)"  — stale cache
///
/// Usage:
/// ```dart
/// LocationStatusBadge(location: safeLocation)
/// ```
class LocationStatusBadge extends StatelessWidget {
  final SafeLocation? location;

  const LocationStatusBadge({super.key, required this.location});

  @override
  Widget build(BuildContext context) {
    if (location == null) {
      return _Badge(
        icon: Icons.location_off_outlined,
        label: 'Location unavailable',
        color: Colors.red.shade700,
      );
    }

    if (!location!.isFromCache) {
      return _Badge(
        icon: Icons.my_location,
        label: 'Live location',
        color: Colors.green.shade700,
      );
    }

    final color =
        location!.isStale ? Colors.red.shade700 : Colors.orange.shade800;

    return _Badge(
      icon: Icons.history_toggle_off,
      label: location!.freshnessLabel,
      color: color,
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Badge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
