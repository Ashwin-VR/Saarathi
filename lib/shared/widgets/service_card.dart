import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:accident_app/shared/models/emergency_service.dart';

class ServiceCard extends StatelessWidget {
  final EmergencyService service;
  final double userLat;
  final double userLng;

  const ServiceCard({
    super.key,
    required this.service,
    required this.userLat,
    required this.userLng,
  });

  Future<void> _openNavigation() async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${service.lat},${service.lng}'
      '&travelmode=driving',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dist = service.distanceLabel(userLat, userLng);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _openNavigation,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: _TypeIcon(type: service.type),
          title: Text(
            service.name,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            service.type.label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                dist,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Icon(Icons.navigation_outlined,
                  size: 16, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeIcon extends StatelessWidget {
  final EmergencyServiceType type;
  const _TypeIcon({required this.type});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (type) {
      EmergencyServiceType.hospital =>
        (Icons.local_hospital, const Color(0xFFD32F2F)),
      EmergencyServiceType.police =>
        (Icons.local_police, const Color(0xFF1565C0)),
      EmergencyServiceType.fireStation =>
        (Icons.local_fire_department, const Color(0xFFE65100)),
    };

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }
}
