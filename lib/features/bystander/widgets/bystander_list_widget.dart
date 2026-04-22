import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/bystander_provider.dart';
import '../models/bystander_model.dart';
import 'package:accident_app/shared/utils/maps_launcher.dart';

class BystanderListWidget extends ConsumerWidget {
  const BystanderListWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bystanderProvider);

    if (!state.isActive || state.bystanders.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.people_alt, color: Colors.blueAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                'Active SOS (${state.bystanders.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.blueAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...state.bystanders.map((b) => _buildBystanderRow(context, b)),
        ],
      ),
    );
  }

  Widget _buildBystanderRow(BuildContext context, Bystander bystander) {
    Color roleColor;
    IconData roleIcon;
    String roleName;

    switch (bystander.role) {
      case BystanderRole.responder:
        roleColor = Colors.redAccent;
        roleIcon = Icons.medical_services;
        roleName = 'Responder';
        break;
      case BystanderRole.caller:
        roleColor = Colors.orangeAccent;
        roleIcon = Icons.phone_in_talk;
        roleName = 'Emergency Caller';
        break;
      case BystanderRole.coordinator:
        roleColor = Colors.purpleAccent;
        roleIcon = Icons.admin_panel_settings;
        roleName = 'Coordinator';
        break;
      case BystanderRole.support:
        roleColor = Colors.grey;
        roleIcon = Icons.volunteer_activism;
        roleName = 'Support';
        break;
    }

    /// 🔥 NEW: derive proximity from distance
    String proximity;
    Color proximityColor;

    if (bystander.distance <= 5) {
      proximity = "VERY CLOSE";
      proximityColor = Colors.red;
    } else if (bystander.distance <= 20) {
      proximity = "GETTING CLOSER";
      proximityColor = Colors.orange;
    } else {
      proximity = "FAR";
      proximityColor = Colors.green;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: roleColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(roleIcon, size: 16, color: roleColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      bystander.name,
                      style: TextStyle(
                        fontWeight: bystander.isCurrentUser
                            ? FontWeight.w900
                            : FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if (bystander.isCurrentUser) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'YOU',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold),
                        ),
                      )
                    ]
                  ],
                ),
                Text(
                  roleName,
                  style: TextStyle(
                      color: roleColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  bystander.lat != null && bystander.lng != null
                      ? 'Location: ${bystander.lat!.toStringAsFixed(5)}, ${bystander.lng!.toStringAsFixed(5)}'
                      : 'Location: Unknown',
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
                Text(
                  bystander.lastSeenAt != null
                      ? 'Time: ${DateFormat('HH:mm:ss').format(bystander.lastSeenAt!.toLocal())}'
                      : 'Time: --',
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
          ),

          /// 🔥 REPLACED DISTANCE WITH PROXIMITY
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                proximity,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: proximityColor,
                ),
              ),
              Text(
                '${bystander.distance.toStringAsFixed(0)}m',
                style: const TextStyle(fontSize: 10, color: Colors.black45),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: bystander.lat != null && bystander.lng != null
                    ? () => openInGoogleMaps(bystander.lat!, bystander.lng!)
                    : null,
                child: const Text('View in Google Maps'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
