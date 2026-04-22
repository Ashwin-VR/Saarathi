import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:accident_app/shared/providers/app_state.dart';
import 'package:accident_app/shared/widgets/service_card.dart';
import 'package:accident_app/shared/widgets/filter_chip_row.dart';

class NearbyServicesFullScreen extends ConsumerWidget {
  const NearbyServicesFullScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(nearbyServicesProvider);
    final activeFilter = ref.watch(activeFilterProvider);
    final position = ref.watch(lastPositionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Services'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: position == null
                ? null
                : () => ref
                    .read(nearbyServicesProvider.notifier)
                    .refresh(position.latitude, position.longitude),
          ),
        ],
      ),
      body: Column(
        children: [
          FilterChipRow(
            activeFilters: activeFilter,
            onChanged: (types) =>
                ref.read(activeFilterProvider.notifier).state = types,
          ),
          Expanded(
            child: servicesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text('$e', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: position == null
                          ? null
                          : () => ref
                              .read(nearbyServicesProvider.notifier)
                              .refresh(position.latitude, position.longitude),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (services) {
                final filtered = services
                    .where((s) => activeFilter.contains(s.type))
                    .toList();

                if (filtered.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_off, size: 48, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('No services found in this area.',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }

                // Sort by distance
                if (position != null) {
                  filtered.sort((a, b) => a
                      .distanceKm(position.latitude, position.longitude)
                      .compareTo(
                          b.distanceKm(position.latitude, position.longitude)));
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    return ServiceCard(
                      service: filtered[i],
                      userLat: position?.latitude ?? 0,
                      userLng: position?.longitude ?? 0,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
