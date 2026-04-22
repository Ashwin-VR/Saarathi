import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlng;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:accident_app/core/router/app_router.dart';
import 'package:accident_app/shared/providers/app_state.dart';
import 'package:accident_app/shared/models/emergency_service.dart';
import 'package:accident_app/shared/widgets/sos_button.dart';
import 'package:accident_app/shared/widgets/service_card.dart';
import 'package:accident_app/shared/widgets/filter_chip_row.dart';
import 'package:accident_app/shared/widgets/permission_gate.dart';
import 'package:accident_app/features/sos/sos_screen.dart';
import 'package:accident_app/shared/services/care_mode_service.dart';
import 'package:accident_app/shared/services/notification_service.dart';
import 'package:accident_app/shared/widgets/care_mode_banner.dart';
import 'package:accident_app/shared/services/sensor_service.dart';
import 'package:accident_app/shared/services/safe_location_service.dart';
import 'package:accident_app/features/bystander/providers/bystander_provider.dart';
// ADDED
import 'package:accident_app/shared/services/proximity_helper_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  bool _panelExpanded = false;
  bool _followUser = true;
  late AnimationController _sosAnimController;
  late Animation<double> _sosScale;
  final ProximityFeedback _proximityFeedback = ProximityFeedback();
  Timer? _locationRefreshTimer;

  @override
  void initState() {
    super.initState();
    _sosAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationServiceProvider).onNotificationTap =
          _handleNotificationTap;
    });
    _sosScale = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _sosAnimController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _setupListeners());

    // Auto-refresh location every 60 seconds
    _locationRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      final notifier = ref.read(nearbyServicesProvider.notifier);
      final pos = ref.read(lastPositionProvider);
      if (pos != null) {
        notifier.refresh(pos.latitude, pos.longitude);
      }
    });
  }

  @override
  void dispose() {
    _locationRefreshTimer?.cancel();
    _sosAnimController.dispose();
    _proximityFeedback.dispose();
    super.dispose();
  }

  void _setupListeners() {
    // Navigate to SOS MAP screen (with pin) when BLE SOS received
    ref.listenManual(sosStateProvider, (prev, next) {
      if (next.status == SosStatus.received &&
          prev?.status != SosStatus.received) {
        if (!mounted) return;
        final incomingDeviceId = next.incomingDeviceId ?? 'Unknown';
        context.push(AppRoutes.sosMap, extra: {
          'deviceId': incomingDeviceId,
          'lat': next.incomingLat,
          'lng': next.incomingLng,
        });
      }

      // Show pre-alert bottom sheet automatically on motion trigger
      if (next.status == SosStatus.preAlert && prev?.status == SosStatus.idle) {
        if (!mounted) return;
        SosFeatureSheet.show(context);
      }

      // Show MINOR response sheet when detector opens the response window
      if (next.status == SosStatus.awaitingUserResponse &&
          prev?.status != SosStatus.awaitingUserResponse) {
        _showMinorResponseSheet(next.responseCountdownSeconds);
      }

      if (next.status == SosStatus.active && mounted) {
        final user = ref.read(lastPositionProvider);
        final helperLat = next.incomingLat;
        final helperLng = next.incomingLng;
        if (user != null && helperLat != null && helperLng != null) {
          try {
            _mapController.fitCamera(
              CameraFit.bounds(
                bounds: LatLngBounds.fromPoints([
                  latlng.LatLng(user.latitude, user.longitude),
                  latlng.LatLng(helperLat, helperLng),
                ]),
                padding: const EdgeInsets.all(80),
              ),
            );
          } catch (_) {
            _mapController.move(
                latlng.LatLng(user.latitude, user.longitude), 15.0);
          }
        } else if (user != null) {
          _mapController.move(
              latlng.LatLng(user.latitude, user.longitude), 15.0);
        }
      }
    });
    // ADDED — drive proximity haptic feedback whenever RSSI updates
    ref.listenManual(proximityProvider, (prev, next) {
      if (next.rssi != null) {
        _proximityFeedback.update(next.proximity);
      } else {
        _proximityFeedback.dispose();
      }
    });

    // Care Mode: show wellness check dialog when check is pending
    ref.listenManual(careModeProvider, (prev, next) {
      if (next.status == CareModeStatus.checkPending &&
          prev?.status == CareModeStatus.active) {
        _showWellnessCheckDialog();
      }
    });

    // Fetch POIs on first GPS fix
    ref.listenManual(lastPositionProvider, (prev, next) {
      if (next != null && prev == null) {
        ref
            .read(nearbyServicesProvider.notifier)
            .refresh(next.latitude, next.longitude);
      }
      // Animate map to user location if following
      if (next != null && _followUser) {
        _mapController.move(latlng.LatLng(next.latitude, next.longitude), 15.0);
      }
    });
  }


  // ── Notification tap handler ─────────────────────────────────────────────

  void _handleNotificationTap(NotificationResponse response) async {
    final payload = response.payload ?? '';
    if (payload == 'wellness_check' || response.actionId == 'confirm_safe') {
      ref.read(careModeProvider.notifier).confirmSafe();
      return;
    }
    if (response.actionId == 'view_map' || payload.contains(',')) {
      final parts = payload.split(',');
      if (parts.length < 2) return;

      final lat = double.tryParse(parts[0].trim());
      final lng = double.tryParse(parts[1].trim());
      if (lat == null || lng == null) return;

      final url = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=walking',
      );
      await launchUrl(url, mode: LaunchMode.externalApplication);
      return;
    }
  }

  // ── MINOR response sheet ──────────────────────────────────────────────────

  void _showMinorResponseSheet(int initialSeconds) {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false, // user must explicitly respond or wait
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MinorResponseSheet(
        initialSeconds: initialSeconds,
        onResponse: (response) {
          if (ctx.mounted) {
            Navigator.of(ctx).pop();
          }
          ref.read(sosStateProvider.notifier).setUserResponse(response);
        },
      ),
    );
  }



  // ── Wellness check in-app dialog ──────────────────────────────────────────

  void _showWellnessCheckDialog() {
    if (!mounted) return;
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.health_and_safety, color: Color(0xFF1565C0)),
            SizedBox(width: 10),
            Text('Wellness Check',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        content: const Text(
          'Are you safe?\n\nTap \'I\'m Safe\' to continue. Ignoring this will trigger SOS.',
          style: TextStyle(fontSize: 14, height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Dismissed = treated as missed (timeout callback handles it)
            },
            child: const Text('Dismiss', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('I\'m Safe',
                style: TextStyle(fontWeight: FontWeight.w700)),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(careModeProvider.notifier).confirmSafe();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permissions: const [
        Permission.location,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ],
      child: _buildMain(context),
    );
  }

  Widget _buildMain(BuildContext context) {
    final sosState = ref.watch(sosStateProvider);
    final position = ref.watch(lastPositionProvider);
    final services = ref.watch(sortedServicesProvider);
    final filter = ref.watch(activeFilterProvider);
    final filtered = services.where((s) => filter.contains(s.type)).toList();

    final panelHeight = _panelExpanded ? 360.0 : 170.0;
    final isPreAlert = sosState.status == SosStatus.preAlert;

    final careModeState = ref.watch(careModeProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(sosState),
      body: Stack(
        children: [
          // ── Map ────────────────────────────────────────────────────────────
          Positioned.fill(
            child: _buildMap(
              position?.latitude,
              position?.longitude,
              filtered,
              sosState,
            ),
          ),

          // ── Location status banner — anchored below AppBar, non-floating ──
          // A non-Positioned Column inside the Stack inherits the full stack
          // width. The SizedBox spacer equals the AppBar + status-bar height,
          // so the banner renders immediately below the AppBar without
          // overlapping the map or any other overlay element.
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: MediaQuery.of(context).padding.top + kToolbarHeight,
              ),
              Consumer(
                builder: (context, ref, _) {
                  final safeLocationService =
                      ref.watch(safeLocationServiceProvider);
                  return FutureBuilder(
                    future: safeLocationService.getSafeLocation(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return _buildLocationBanner(
                          '📡 Getting location...',
                          Colors.grey.shade800,
                        );
                      }
                      final location = snapshot.data;
                      if (location == null) {
                        return _buildLocationBanner(
                          '❌ Location unavailable',
                          Colors.red.shade800,
                        );
                      }
                      if (location.isFromCache) {
                        return _buildLocationBanner(
                          '⚠️ Last known location',
                          Colors.orange.shade800,
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  );
                },
              ),
            ],
          ),

          // ── Top gradient fade ──────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 120,
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCC000000), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),

          // ── Stacked banners (Care Mode → Pre-alert/BLE, no overlap) ───────
          Positioned(
            top: MediaQuery.of(context).padding.top + 56,
            left: 12,
            right: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (sosState.status == SosStatus.active &&
                    sosState.activeEmergencyType != null)
                  _buildCallNowBanner(sosState.activeEmergencyType!),
                if (sosState.statusText != null &&
                    sosState.statusText!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildStatusTextBanner(sosState.statusText!.trim()),
                ],
                if (careModeState.status != CareModeStatus.inactive) ...[
                  CareModeBanner(
                    state: careModeState,
                    onConfirmSafe: () =>
                        ref.read(careModeProvider.notifier).confirmSafe(),
                    onStop: () => ref.read(careModeProvider.notifier).stop(),
                  ),
                  const SizedBox(height: 8),
                ],
                if (isPreAlert)
                  _buildPreAlertBanner(sosState)
                else if (sosState.status == SosStatus.received)
                  _buildBleBanner(sosState),
              ],
            ),
          ),

          // ── Re-centre / follow button ──────────────────────────────────────
          // ── Re-centre button (top-right, fixed) ─────────────────────────
          if (position != null)
            Positioned(
              right: 16,
              top: MediaQuery.of(context).padding.top + 64,
              child: _buildRecenterFab(position.latitude, position.longitude),
            ),

          // ── SOS button ────────────────────────────────────────────────────
          Positioned(
            right: 16,
            bottom: panelHeight + 88,
            child: _buildSosButton(sosState, ref),
          ),

          // ── Emergency type buttons (FIRE / AMBULANCE / POLICE) ────────────
          Positioned(
            left: 16,
            bottom: panelHeight + 88,
            child: _buildEmergencyButtons(sosState, ref),
          ),

          // ── Filter chips ───────────────────────────────────────────────────
          Positioned(
            left: 0,
            right: 80,
            bottom: panelHeight + 4,
            child: FilterChipRow(
              activeFilters: filter,
              onChanged: (v) =>
                  ref.read(activeFilterProvider.notifier).state = v,
            ),
          ),

          // ── Bottom panel ───────────────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomPanel(
              services: filtered,
              userLat: position?.latitude ?? 0,
              userLng: position?.longitude ?? 0,
              expanded: _panelExpanded,
              onToggle: () => setState(() => _panelExpanded = !_panelExpanded),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallNowBanner(EmergencyType type) {
    final label = switch (type) {
      EmergencyType.fire    => 'Fire department',
      EmergencyType.medical => 'Ambulance',
      EmergencyType.police  => 'Police',
    };
    return Material(
      color: const Color(0xFF0F3460),
      borderRadius: BorderRadius.circular(14),
      elevation: 8,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _attemptEmergencyCall(context, number: '112'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.phone_in_talk, color: Colors.white, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Call $label now (112)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusTextBanner(String text) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white70, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── App bar ───────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(SosState sosState) {
    final careModeState = ref.watch(careModeProvider);
    final Color barColor = switch (sosState.status) {
      SosStatus.active => const Color(0xFFB71C1C),
      SosStatus.preAlert => const Color(0xFFE65100),
      _ => Colors.transparent,
    };

    return AppBar(
      backgroundColor: barColor,
      elevation: 0,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingDot(
            active: sosState.status == SosStatus.active ||
                sosState.status == SosStatus.preAlert,
            color: sosState.status == SosStatus.active
                ? const Color(0xFFEF5350)
                : sosState.status == SosStatus.preAlert
                    ? const Color(0xFFFFB74D)
                    : const Color(0xFF4CAF50),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              sosState.status == SosStatus.active
                  ? 'SOS ACTIVE'
                  : sosState.status == SosStatus.preAlert
                      ? 'SOS in ${sosState.countdownSeconds}s'
                      : 'Emergency SOS',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5),
            ),
          ),
        ],
      ),
      actions: [
        // Care Mode toggle
        IconButton(
          icon: Icon(
            careModeState.status != CareModeStatus.inactive
                ? Icons.health_and_safety
                : Icons.health_and_safety_outlined,
            color: careModeState.status != CareModeStatus.inactive
                ? const Color(0xFF4CAF50)
                : Colors.white,
          ),
          tooltip: careModeState.status != CareModeStatus.inactive
              ? 'Car Mode Active — tap to stop'
              : 'Start Car Mode',
          onPressed: () {
            if (careModeState.status != CareModeStatus.inactive) {
              ref.read(careModeProvider.notifier).stop();
            } else {
              _showCareModeStartDialog();
            }
          },
        ),
        IconButton(
          icon: const Icon(Icons.phone_in_talk_outlined, color: Colors.white),
          tooltip: 'Fake call',
          onPressed: () => context.push(AppRoutes.fakeCall),
        ),
        IconButton(
          icon: const Icon(Icons.list_alt_rounded, color: Colors.white),
          tooltip: 'Nearby list',
          onPressed: () => context.push(AppRoutes.nearbyList),
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: Colors.white),
          tooltip: 'Settings',
          onPressed: () => context.push(AppRoutes.settings),
        ),
      ],
    );
  }

  // ── Care Mode start dialog ────────────────────────────────────────────────

  void _showCareModeStartDialog() {
    int selectedMinutes = CareModeState.defaultInterval;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.health_and_safety, color: Color(0xFF1565C0)),
              SizedBox(width: 10),
              Text('Start Care Mode',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'A wellness check will be sent periodically.\n'
                'Missing 2 checks in a row triggers SOS automatically.',
                style: TextStyle(fontSize: 13, height: 1.55),
              ),
              const SizedBox(height: 20),
              const Text('Check interval:',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [10, 15].map((min) {
                  final selected = selectedMinutes == min;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: ChoiceChip(
                      label: Text('$min min'),
                      selected: selected,
                      selectedColor:
                          const Color(0xFF1565C0).withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? const Color(0xFF1565C0)
                            : Colors.grey.shade700,
                      ),
                      onSelected: (_) =>
                          setDialogState(() => selectedMinutes = min),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('Start',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              onPressed: () {
                Navigator.pop(ctx);
                ref
                    .read(careModeProvider.notifier)
                    .start(intervalMinutes: selectedMinutes);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Flutter Map ───────────────────────────────────────────────────────────

  Widget _buildMap(
    double? lat,
    double? lng,
    List<EmergencyService> services,
    SosState sosState,
  ) {
    final center = latlng.LatLng(lat ?? 20.5937, lng ?? 78.9629);
    final zoom = lat != null ? 15.0 : 4.5;
    final bystanderState = ref.watch(bystanderProvider);
    final bystanders = bystanderState.bystanders
        .where((b) => b.lat != null && b.lng != null)
        .toList();

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        minZoom: 3,
        maxZoom: 18,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all,
        ),
        onPositionChanged: (pos, hasGesture) {
          if (hasGesture && _followUser) {
            setState(() => _followUser = false);
          }
        },
      ),
      children: [
        // OSM raster tiles — free, no API key
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.accident_app',
          maxZoom: 18,
          fallbackUrl: 'https://a.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
        ),

        // POI markers for nearby services
        MarkerLayer(
          markers: [
            for (final svc in services)
              Marker(
                point: latlng.LatLng(svc.lat, svc.lng),
                width: 36,
                height: 36,
                child: _ServiceMarker(type: svc.type),
              ),
          ],
        ),

        // SOS caller location marker (incoming BLE SOS with coordinates)
        if (sosState.incomingLat != null && sosState.incomingLng != null)
          MarkerLayer(
            markers: [
              Marker(
                point:
                    latlng.LatLng(sosState.incomingLat!, sosState.incomingLng!),
                width: 48,
                height: 48,
                child: const _SosCallerMarker(),
              ),
            ],
          ),

        // User location marker — anchor at bottom-center of the icon
        if (lat != null && lng != null)
          MarkerLayer(
            markers: [
              Marker(
                point: latlng.LatLng(lat, lng),
                width: 56,
                height: 56,
                // Align the bottom-center of the marker widget to the GPS point
                // so the icon circle sits ON the coordinate, not above it.
                alignment: Alignment.bottomCenter,
                child: _UserLocationMarker(
                  isActive: sosState.status == SosStatus.active,
                  isPreAlert: sosState.status == SosStatus.preAlert,
                  animation: _sosScale,
                ),
              ),
            ],
          ),

        // Nearby bystanders (only while SOS is active)
        // Pinned to bottom-center so label appears ABOVE the bystander's
        // GPS point — prevents overlap with the user location icon.
        if (sosState.status == SosStatus.active && bystanders.isNotEmpty)
          MarkerLayer(
            markers: [
              for (final b in bystanders)
                Marker(
                  point: latlng.LatLng(b.lat!, b.lng!),
                  width: 130,
                  height: 54,
                  alignment: Alignment.bottomCenter,
                  child: _BystanderPin(
                    label: '${b.distance.toStringAsFixed(0)}m away',
                  ),
                ),
            ],
          ),
      ],
    );
  }

  // ── Banners ───────────────────────────────────────────────────────────────

  Widget _buildPreAlertBanner(SosState sosState) {
    return Material(
      color: const Color(0xFFE65100),
      borderRadius: BorderRadius.circular(14),
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'SOS in ${sosState.countdownSeconds}s — tap to cancel',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () =>
                  ref.read(sosStateProvider.notifier).cancelPreAlert(),
              child: const Text("CANCEL"),
            ),
          ],
        ),
      ),
    );
  }

  // MODIFIED — extended to show live proximity badge; all original layout preserved
  Widget _buildBleBanner(SosState sosState) {
    // ADDED — watch proximity state; zero extra BLE logic
    final proximityState = ref.watch(proximityProvider);
    final proximity = proximityState.proximity;
    final proximityColor = Color(getProximityColor(proximity));
    final proximityEmoji = getProximityEmoji(proximity);

    return Material(
      color: const Color(0xFFB71C1C),
      borderRadius: BorderRadius.circular(14),
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          // ADDED — column wraps original row + badge
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Original row (unchanged content) ──────────────────────────
            Row(
              children: [
                const Icon(Icons.bluetooth_searching,
                    color: Colors.white, size: 24),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '⚠ Nearby person needs help!',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  onPressed: () =>
                      ref.read(sosStateProvider.notifier).dismissIncoming(),
                  child: const Text("OK"),
                ),
              ],
            ),

            // ADDED — proximity badge row (only shown when RSSI is available)
            if (proximityState.rssi != null) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: proximityColor.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: proximityColor, width: 1.2),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Flexible prevents overflow when proximity label is long.
                    Flexible(
                      child: Text(
                        '$proximityEmoji  $proximity',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: proximityColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${proximityState.rssi} dBm',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Full-width status banner anchored directly below the AppBar.
  Widget _buildLocationBanner(String text, Color color) {
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.location_searching,
            size: 14,
            color: Colors.white70,
          ),
          const SizedBox(width: 8),
          // Flexible prevents overflow when text is long on narrow screens.
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── FABs ──────────────────────────────────────────────────────────────────

  Widget _buildRecenterFab(double lat, double lng) {
    return FloatingActionButton.small(
      heroTag: 'recenter',
      backgroundColor: _followUser ? const Color(0xFF1565C0) : Colors.white,
      foregroundColor: _followUser ? Colors.white : const Color(0xFF1565C0),
      elevation: 4,
      onPressed: () {
        setState(() => _followUser = true);
        _mapController.move(latlng.LatLng(lat, lng), 15.0);
      },
      child: Icon(_followUser ? Icons.my_location : Icons.location_searching),
    );
  }

  Widget _buildSosButton(SosState sosState, WidgetRef ref) {
    final semanticLabel = switch (sosState.status) {
      SosStatus.active => 'Cancel active SOS',
      SosStatus.preAlert => 'View SOS pre-alert countdown',
      _ => 'Trigger SOS emergency alert',
    };

    return Semantics(
      label: semanticLabel,
      button: true,
      child: SosButton(
        isActive: sosState.status == SosStatus.active,
        isPreAlert: sosState.status == SosStatus.preAlert,
        onPressed: () async {
          if (sosState.status == SosStatus.active) {
            // Cancel SOS and navigate to incident detail screen
            await ref.read(sosStateProvider.notifier).cancelSos();
            if (!context.mounted) return;
            final incident = ref.read(sosStateProvider).lastResolvedIncident;
            if (incident != null) {
              context.push(AppRoutes.incidentDetail, extra: incident);
            }
          } else if (sosState.status == SosStatus.preAlert) {
            SosFeatureSheet.show(context);
          } else {
            final success =
                await ref.read(sosStateProvider.notifier).triggerSos();

            if (!context.mounted) return;

            if (success) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('SOS alert sent'),
                  backgroundColor: Color(0xFFD32F2F),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          }
        },
        onLongPress: () => SosFeatureSheet.show(context),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Emergency type quick-buttons: FIRE / AMBULANCE / POLICE
  // Each calls the existing SOS pipeline with the EmergencyType set.
  // Disabled while SOS is already active to avoid re-entrance.
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildEmergencyButtons(SosState sosState, WidgetRef ref) {
    final disabled = sosState.status == SosStatus.active ||
        sosState.status == SosStatus.preAlert;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EmergencyTypeButton(
          emoji: '🔥',
          label: 'FIRE',
          color: const Color(0xFFD32F2F),
          onTap: disabled
              ? null
              : () => _triggerEmergency(
                  ref, EmergencyType.fire, 'FIRE'),
        ),
        const SizedBox(height: 8),
        _EmergencyTypeButton(
          emoji: '🚑',
          label: 'AMBULANCE',
          color: const Color(0xFF2E7D32),
          onTap: disabled
              ? null
              : () => _triggerEmergency(
                  ref, EmergencyType.medical, 'AMBULANCE'),
        ),
        const SizedBox(height: 8),
        _EmergencyTypeButton(
          emoji: '🚔',
          label: 'POLICE',
          color: const Color(0xFF1565C0),
          onTap: disabled
              ? null
              : () => _triggerEmergency(
                  ref, EmergencyType.police, 'POLICE'),
        ),
      ],
    );
  }

  Future<void> _triggerEmergency(
    WidgetRef ref,
    EmergencyType type,
    String label,
  ) async {
    final success = await ref
        .read(sosStateProvider.notifier)
        .triggerSos(emergencyType: type);
    if (!mounted) return;
    if (success) {
      if (type == EmergencyType.medical || type == EmergencyType.police) {
        await _attemptEmergencyCall(context, number: '112');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label emergency alert sent'),
          backgroundColor: const Color(0xFFD32F2F),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _attemptEmergencyCall(
    BuildContext context, {
    required String number,
  }) async {
    try {
      final uri = Uri.parse('tel:$number');
      final ok = await launchUrl(uri);
      if (ok) return;
    } catch (_) {}

    if (!context.mounted) return;
    final retry = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Call failed',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text('Could not start a call to $number. Try again?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
    if (retry == true && context.mounted) {
      await _attemptEmergencyCall(context, number: number);
    }
  }

  // (manual SOS FAB removed — options are available in the SOS long-press sheet)
}

// ── Emergency type button widget ──────────────────────────────────────────────

class _EmergencyTypeButton extends StatelessWidget {
  final String emoji;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _EmergencyTypeButton({
    required this.emoji,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onTap == null;
    return Opacity(
      opacity: isDisabled ? 0.45 : 1.0,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Map marker widgets ────────────────────────────────────────────────────────

class _UserLocationMarker extends StatelessWidget {
  final bool isActive;
  final bool isPreAlert;
  final Animation<double> animation;

  const _UserLocationMarker({
    required this.isActive,
    required this.isPreAlert,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? const Color(0xFFD32F2F)
        : isPreAlert
            ? const Color(0xFFFF6F00)
            : const Color(0xFF1565C0);

    return ScaleTransition(
      scale: (isActive || isPreAlert)
          ? animation
          : const AlwaysStoppedAnimation(1.0),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.5),
              blurRadius: 12,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Icon(
          isActive ? Icons.crisis_alert : Icons.person_pin_circle,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }
}

/// Red pulsing pin shown at the SOS caller's GPS location.
class _SosCallerMarker extends StatelessWidget {
  const _SosCallerMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFD32F2F),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80D32F2F),
            blurRadius: 16,
            spreadRadius: 6,
          ),
        ],
      ),
      child: const Icon(Icons.sos, color: Colors.white, size: 22),
    );
  }
}

class _ServiceMarker extends StatelessWidget {
  final EmergencyServiceType type;
  const _ServiceMarker({required this.type});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (type) {
      EmergencyServiceType.hospital => (
          Icons.local_hospital,
          const Color(0xFF43A047)
        ),
      EmergencyServiceType.police => (
          Icons.local_police,
          const Color(0xFF1565C0)
        ),
      EmergencyServiceType.fireStation => (
          Icons.local_fire_department,
          const Color(0xFFE53935)
        ),
    };

    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 6,
              spreadRadius: 1),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

class _BystanderPin extends StatelessWidget {
  final String label;
  const _BystanderPin({required this.label});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1565C0), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_pin_circle,
                size: 18, color: Color(0xFF1565C0)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1565C0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bottom panel ──────────────────────────────────────────────────────────────

class _BottomPanel extends StatelessWidget {
  final List<EmergencyService> services;
  final double userLat;
  final double userLng;
  final bool expanded;
  final VoidCallback onToggle;

  const _BottomPanel({
    required this.services,
    required this.userLat,
    required this.userLng,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      height: expanded ? 360 : 170,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              child: Center(
                child: AnimatedRotation(
                  turns: expanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 280),
                  child: Icon(
                    Icons.keyboard_arrow_up_rounded,
                    size: 26,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Expanded prevents overflow when service count label is wide.
                Expanded(
                  child: Text(
                    'Nearby Services',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${services.length} found',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onPrimaryContainer)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: services.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_searching,
                            size: 32, color: theme.colorScheme.outline),
                        const SizedBox(height: 8),
                        Text('Fetching nearby services…',
                            style: TextStyle(
                                color: theme.colorScheme.outline,
                                fontSize: 13)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: services.length,
                    itemBuilder: (_, i) => ServiceCard(
                      service: services[i],
                      userLat: userLat,
                      userLng: userLng,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── MINOR crash response sheet ────────────────────────────────────────────────
//
// Shown for 5 seconds when a MINOR crash is detected.
// Two-layer predefined selection:
// 1) Type: Individual / Vehicular / Fire
// 2) Severity: Minor / Serious / Critical
// Auto-closes when the response window expires (escalation is in SosNotifier).

class _MinorResponseSheet extends ConsumerStatefulWidget {
  final int initialSeconds;
  final void Function(String response) onResponse;

  const _MinorResponseSheet({
    required this.initialSeconds,
    required this.onResponse,
  });

  @override
  ConsumerState<_MinorResponseSheet> createState() =>
      _MinorResponseSheetState();
}

class _MinorResponseSheetState extends ConsumerState<_MinorResponseSheet> {
  late int _seconds;
  Timer? _ticker;
  IncidentType? _selectedType;
  CrashSeverity? _selectedSeverity;

  static const _typeOptions = [
    (label: 'Individual', value: IncidentType.individual),
    (label: 'Vehicular', value: IncidentType.vehicular),
    (label: 'Fire', value: IncidentType.fire),
  ];

  static const _severityOptions = [
    (label: 'Minor', value: CrashSeverity.minor),
    (label: 'Serious', value: CrashSeverity.serious),
    (label: 'Critical', value: CrashSeverity.critical),
  ];

  @override
  void initState() {
    super.initState();
    _seconds = widget.initialSeconds;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final remaining = _seconds - 1;
      if (remaining <= 0) {
        _ticker?.cancel();
        // Escalation fires automatically in SosNotifier; just close the sheet.
        // Guard: sheet may already have been closed by the notifier listener.
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      } else {
        setState(() => _seconds = remaining);
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Auto-dismiss if SosNotifier left the awaitingUserResponse state
    ref.listen(sosStateProvider, (_, next) {
      if (next.status != SosStatus.awaitingUserResponse && mounted) {
        // Guard: ticker may have already popped this route — only pop once.
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    });

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Row(
              children: [
                const Text('🟡', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Minor crash detected — Are you okay?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                // Live countdown badge
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _seconds <= 2
                        ? const Color(0xFFD32F2F)
                        : const Color(0xFFE65100),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$_seconds',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'No response in $_seconds s → severity escalates',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
            ),
            const SizedBox(height: 16),

            const Text(
              'Step 1: Select type',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: _typeOptions.map((opt) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedType == opt.value
                            ? const Color(0xFF0F3460)
                            : const Color(0xFF16213E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                        side: const BorderSide(
                            color: Color(0xFF0F3460), width: 1),
                      ),
                      onPressed: () =>
                          setState(() => _selectedType = opt.value),
                      child: Text(
                        opt.label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            const Text(
              'Step 2: Select severity',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: _severityOptions.map((opt) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedSeverity == opt.value
                            ? const Color(0xFF0F3460)
                            : const Color(0xFF16213E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                        side: const BorderSide(
                            color: Color(0xFF0F3460), width: 1),
                      ),
                      onPressed: () =>
                          setState(() => _selectedSeverity = opt.value),
                      child: Text(
                        opt.label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 46),
                backgroundColor: const Color(0xFFD32F2F),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF5A5A5A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _selectedType != null && _selectedSeverity != null
                  ? () => widget.onResponse(
                        '${_selectedType!.name}|${_selectedSeverity!.name}',
                      )
                  : null,
              child: const Text(
                'Send Selection',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualSosSheet extends StatefulWidget {
  final Future<void> Function(IncidentType type, CrashSeverity severity)
      onSubmit;

  const _ManualSosSheet({required this.onSubmit});

  @override
  State<_ManualSosSheet> createState() => _ManualSosSheetState();
}

class _ManualSosSheetState extends State<_ManualSosSheet> {
  IncidentType? _selectedType;
  CrashSeverity? _selectedSeverity;
  bool _submitting = false;

  static const _typeOptions = [
    (label: 'Individual', value: IncidentType.individual),
    (label: 'Vehicular', value: IncidentType.vehicular),
    (label: 'Fire', value: IncidentType.fire),
  ];

  static const _severityOptions = [
    (label: 'Minor', value: CrashSeverity.minor),
    (label: 'Serious', value: CrashSeverity.serious),
    (label: 'Critical', value: CrashSeverity.critical),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _SosBroadcastIcon(size: 24, color: Color(0xFFFF3B30)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Manual SOS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Step 1: Select type',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: _typeOptions.map((opt) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedType == opt.value
                            ? const Color(0xFF0F3460)
                            : const Color(0xFF16213E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        side: const BorderSide(
                            color: Color(0xFF0F3460), width: 1),
                      ),
                      onPressed: _submitting
                          ? null
                          : () => setState(() => _selectedType = opt.value),
                      child: Text(opt.label, textAlign: TextAlign.center),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            const Text(
              'Step 2: Select severity',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: _severityOptions.map((opt) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedSeverity == opt.value
                            ? const Color(0xFF0F3460)
                            : const Color(0xFF16213E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        side: const BorderSide(
                            color: Color(0xFF0F3460), width: 1),
                      ),
                      onPressed: _submitting
                          ? null
                          : () => setState(() => _selectedSeverity = opt.value),
                      child: Text(opt.label, textAlign: TextAlign.center),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                backgroundColor: const Color(0xFFD32F2F),
                foregroundColor: Colors.white,
              ),
              onPressed: _submitting ||
                      _selectedType == null ||
                      _selectedSeverity == null
                  ? null
                  : () async {
                      setState(() => _submitting = true);
                      await widget.onSubmit(_selectedType!, _selectedSeverity!);
                      if (!mounted) return;
                      setState(() => _submitting = false);
                    },
              icon: const Icon(Icons.send),
              label: Text(_submitting ? 'Sending...' : 'Trigger Manual SOS'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SosBroadcastIcon extends StatelessWidget {
  final double size;
  final Color color;

  const _SosBroadcastIcon({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _SosBroadcastPainter(color),
    );
  }
}

class _SosBroadcastPainter extends CustomPainter {
  final Color color;

  _SosBroadcastPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.09
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final ui.Path pinPath = ui.Path()
      ..moveTo(size.width * 0.5, size.height * 0.92)
      ..quadraticBezierTo(size.width * 0.18, size.height * 0.52,
          size.width * 0.5, size.height * 0.16)
      ..quadraticBezierTo(size.width * 0.82, size.height * 0.52,
          size.width * 0.5, size.height * 0.92)
      ..close();
    canvas.drawPath(pinPath, fill..color = color.withValues(alpha: 0.25));

    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.46),
      size.width * 0.12,
      fill..color = color,
    );

    final center = Offset(size.width * 0.5, size.height * 0.44);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: size.width * 0.28),
      -0.75,
      1.5,
      false,
      stroke,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: size.width * 0.38),
      -0.68,
      1.36,
      false,
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _SosBroadcastPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ── Pulsing dot for AppBar status indicator ───────────────────────────────────

class _PulsingDot extends StatefulWidget {
  final Color color;
  final bool active;
  const _PulsingDot({required this.color, this.active = true});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _a = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _c, curve: Curves.easeInOut),
    );
    if (widget.active) {
      _c.repeat(reverse: true);
    } else {
      _c.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(_PulsingDot old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _c.repeat(reverse: true);
    } else if (!widget.active && old.active) {
      _c.stop();
      _c.value = 1.0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (_, __) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: _a.value),
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: _a.value * 0.6),
              blurRadius: 6,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }
}
