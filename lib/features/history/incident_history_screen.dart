import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:accident_app/shared/services/incident_history_service.dart';

class IncidentHistoryScreen extends ConsumerWidget {
  const IncidentHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(incidentHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Incident history'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(incidentHistoryProvider),
          ),
        ],
      ),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history_toggle_off_outlined,
                      size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No incidents recorded',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          // Newest first
          final sorted = [...items]
            ..sort((a, b) => b.startTime.compareTo(a.startTime));

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: sorted.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _IncidentTile(entry: sorted[i]),
          );
        },
      ),
    );
  }
}

class _IncidentTile extends StatelessWidget {
  final IncidentHistoryEntry entry;
  const _IncidentTile({required this.entry});

  String _fmt(DateTime dt) =>
      DateFormat('dd MMM yyyy · HH:mm').format(dt.toLocal());

  String get _duration {
    final diff = entry.endTime.difference(entry.startTime);
    final m = diff.inMinutes;
    final s = diff.inSeconds % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }

  Future<void> _openMap(double lat, double lng) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final hasCoords = entry.lat != null && entry.lng != null;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date/time + duration
            Row(
              children: [
                const Icon(Icons.access_time, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _fmt(entry.startTime),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
                Text(
                  _duration,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Trigger + severity chips
            Wrap(
              spacing: 6,
              children: [
                _Chip(
                  label: entry.trigger,
                  color: const Color(0xFFD32F2F),
                ),
                if (entry.severity != null)
                  _Chip(
                    label: entry.severity!,
                    color: const Color(0xFFE65100),
                  ),
              ],
            ),

            // Map button
            if (hasCoords) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.map_outlined, size: 16),
                label: Text(
                  '${entry.lat!.toStringAsFixed(4)}, ${entry.lng!.toStringAsFixed(4)}',
                  style: const TextStyle(fontSize: 12),
                ),
                onPressed: () => _openMap(entry.lat!, entry.lng!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
