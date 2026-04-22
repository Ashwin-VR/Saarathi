import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:accident_app/shared/providers/app_state.dart';
import 'package:accident_app/shared/models/emergency_service.dart';

/// Standalone MapFeature widget using flutter_map + OSM tiles.
/// Used if you want to embed the map outside the home screen.
class MapFeature extends ConsumerStatefulWidget {
  const MapFeature({super.key});

  @override
  ConsumerState<MapFeature> createState() => _MapFeatureState();
}

class _MapFeatureState extends ConsumerState<MapFeature> {
  final MapController _controller = MapController();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // Refresh POIs every 60 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _refreshPois();
    });
    // Initial load
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPois());
  }

  void _refreshPois() {
    final pos = ref.read(lastPositionProvider);
    if (pos != null) {
      print('[MapFeature] 🔄 Refreshing POIs @ ${pos.latitude}, ${pos.longitude}');
      ref
          .read(nearbyServicesProvider.notifier)
          .refresh(pos.latitude, pos.longitude);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(lastPositionProvider);
    final services = ref.watch(sortedServicesProvider);
    final sosState = ref.watch(sosStateProvider);

    final hasUserPos = position != null;
    final center = hasUserPos
        ? LatLng(position.latitude, position.longitude)
        : const LatLng(20.5937, 78.9629);
    final zoom = hasUserPos ? 15.0 : 4.5;

    // SOS origin (from incoming BLE SOS)
    final sosLat = sosState.incomingLat;
    final sosLng = sosState.incomingLng;
    final hasSosOrigin = sosLat != null && sosLng != null;

    // Auto-pan to SOS origin if available
    if (hasSosOrigin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _controller.move(LatLng(sosLat, sosLng), 15.0);
        } catch (_) {}
      });
    }

    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        minZoom: 3,
        maxZoom: 18,
      ),
      children: [
        // OSM raster tiles — free, no API key required
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.accident_app',
          maxZoom: 18,
          fallbackUrl: 'https://a.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
        ),

        // Emergency service POI markers
        if (services.isNotEmpty)
          MarkerLayer(
            markers: [
              for (final svc in services)
                Marker(
                  point: LatLng(svc.lat, svc.lng),
                  width: 36,
                  height: 36,
                  child: _serviceMarker(svc.type),
                ),
            ],
          ),

        // SOS origin marker (pulsing red pin)
        if (hasSosOrigin)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(sosLat, sosLng),
                width: 48,
                height: 48,
                child: _sosOriginMarker(),
              ),
            ],
          ),

        // User location marker
        if (hasUserPos)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(position.latitude, position.longitude),
                width: 48,
                height: 48,
                child: _userMarker(sosState.status),
              ),
            ],
          ),

        // Loading overlay while fetching POIs
        if (ref.watch(nearbyServicesProvider).isLoading)
          const Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.only(top: 8),
              child: _LoadingChip(),
            ),
          ),
      ],
    );
  }

  Widget _userMarker(SosStatus status) {
    final color = status == SosStatus.active
        ? const Color(0xFFD32F2F)
        : status == SosStatus.preAlert
            ? const Color(0xFFFF6F00)
            : const Color(0xFF1565C0);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: 10,
            spreadRadius: 3,
          ),
        ],
      ),
      child: const Icon(Icons.person_pin_circle, color: Colors.white, size: 22),
    );
  }

  Widget _sosOriginMarker() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFD32F2F),
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD32F2F).withValues(alpha: 0.6),
            blurRadius: 14,
            spreadRadius: 5,
          ),
        ],
      ),
      child: const Icon(Icons.crisis_alert, color: Colors.white, size: 24),
    );
  }

  Widget _serviceMarker(EmergencyServiceType type) {
    final (icon, color) = switch (type) {
      EmergencyServiceType.hospital    => (Icons.local_hospital,       const Color(0xFF43A047)),
      EmergencyServiceType.police      => (Icons.local_police,         const Color(0xFF1565C0)),
      EmergencyServiceType.fireStation => (Icons.local_fire_department, const Color(0xFFE53935)),
    };
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6, spreadRadius: 1),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

/// Small chip shown while POIs are loading.
class _LoadingChip extends StatelessWidget {
  const _LoadingChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          SizedBox(width: 8),
          Text('Loading services…', style: TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}
