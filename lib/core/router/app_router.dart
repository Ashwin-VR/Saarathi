import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:accident_app/shared/services/profile_service.dart';
import 'package:accident_app/shared/services/demo_mode_service.dart';

import 'package:accident_app/screens/home_screen.dart';
import 'package:accident_app/features/nearby/nearby_screen.dart';
import 'package:accident_app/features/fake_call/fake_call_screen.dart';
import 'package:accident_app/features/logs/logs_screen.dart';
import 'package:accident_app/features/sos/sos_map_screen.dart';
import 'package:accident_app/features/sos/incident_detail_screen.dart';
import 'package:accident_app/features/onboarding/onboarding_screen.dart';
import 'package:accident_app/features/history/incident_history_screen.dart';
import 'package:accident_app/shared/models/incident_record.dart';
import 'package:accident_app/shared/providers/app_state.dart';
import 'package:accident_app/shared/services/sms_service.dart';
import 'package:accident_app/features/victim_id/victim_id_screen.dart';
import 'package:accident_app/features/victim_id/victim_qr_screen.dart';

// ── Route path constants ─────────────────────────────────────────────────────
abstract class AppRoutes {
  static const home = '/';
  static const sosAlert = '/sos-alert';
  static const sosMap = '/sos-map';
  static const nearbyList = '/nearby';
  static const settings = '/settings';
  static const fakeCall = '/fake-call';
  static const incidentDetail = '/incident-detail';
  static const onboarding = '/onboarding';
  static const history = '/history';
  static const victimId = '/victim-id';
  static const victimIdQr = '/victim-id/qr';
  static const aiCopilot = '/ai';
}

// ── Router provider ──────────────────────────────────────────────────────────
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.home,
    debugLogDiagnostics: false,
    redirect: (context, state) async {
      // Show onboarding on very first launch
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getBool('onboarding_done_v1') ?? false;
      if (!done && state.matchedLocation != AppRoutes.onboarding) {
        return AppRoutes.onboarding;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.onboarding,
        name: 'onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        name: 'home',
        builder: (_, __) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.sosAlert,
        name: 'sosAlert',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return SosAlertPage(
            deviceId: extra['deviceId'] as String? ?? 'Unknown',
            lat: extra['lat'] as double?,
            lng: extra['lng'] as double?,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.sosMap,
        name: 'sosMap',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return SosMapScreen(
            deviceId: extra['deviceId'] as String? ?? 'Unknown',
            lat: extra['lat'] as double?,
            lng: extra['lng'] as double?,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.nearbyList,
        name: 'nearbyList',
        builder: (_, __) => const NearbyServicesFullScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        name: 'settings',
        builder: (_, __) => const SettingsPage(),
      ),
      GoRoute(
        path: AppRoutes.history,
        name: 'history',
        builder: (_, __) => const IncidentHistoryScreen(),
      ),
      GoRoute(
        path: AppRoutes.incidentDetail,
        name: 'incidentDetail',
        builder: (context, state) {
          final incident = state.extra as IncidentRecord;
          return IncidentDetailScreen(incident: incident);
        },
      ),
      GoRoute(
        path: AppRoutes.fakeCall,
        name: 'fakeCall',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return FakeCallScreen(
            callerName: extra['name'] as String? ?? 'Mom',
            callerNumber: extra['number'] as String? ?? '+91 98765 43210',
          );
        },
      ),
      GoRoute(
        path: AppRoutes.victimId,
        name: 'victimId',
        builder: (_, __) => const VictimIdScreen(),
      ),
      GoRoute(
        path: AppRoutes.victimIdQr,
        name: 'victimIdQr',
        builder: (_, __) => const VictimQrScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Not Found')),
      body: Center(child: Text('Route not found: ${state.uri}')),
    ),
  );
});

// ── SOS Alert full-screen page ───────────────────────────────────────────────
class SosAlertPage extends StatelessWidget {
  final String deviceId;
  final double? lat;
  final double? lng;

  const SosAlertPage({
    super.key,
    required this.deviceId,
    this.lat,
    this.lng,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFB71C1C),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.9, end: 1.1),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeInOut,
                builder: (_, val, child) =>
                    Transform.scale(scale: val, child: child),
                child: const Icon(Icons.warning_amber_rounded,
                    size: 96, color: Colors.white),
              ),
              const SizedBox(height: 24),
              const Text(
                '⚠ SOS RECEIVED',
                style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 2),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Nearby person needs urgent help',
                style: TextStyle(color: Colors.white70, fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              _infoRow('Device', deviceId),
              if (lat != null && lng != null)
                _infoRow('Location',
                    '${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}'),
              const SizedBox(height: 48),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFFB71C1C),
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.check),
                label: const Text('ACKNOWLEDGE',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                onPressed: () => context.pop(),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.pop(),
                child: const Text('Dismiss',
                    style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('$label: ',
              style: const TextStyle(color: Colors.white60, fontSize: 14)),
          Flexible(
            child: Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

// ── Settings page ─────────────────────────────────────────────────────────────
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  // ── Profile state ─────────────────────────────────────────
  final _profileService = ProfileService();

  // Profile field controllers
  late TextEditingController _nameCtrl;
  late TextEditingController _ageCtrl;
  late TextEditingController _sos1Ctrl;
  late TextEditingController _sos2Ctrl;
  String? _selectedGender;
  String? _selectedBloodGroup;

  static const _genders = ['Male', 'Female', 'Other', 'Prefer not to say'];
  static const _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  // ── Existing state ─────────────────────────────────────────
  List<String> _contacts = [];
  String? _primary;
  bool _suddenStopEnabled = true;
  bool _gForceEnabled = true;
  bool _passiveBleEnabled = true;
  bool _advancedExpanded = false;

  static const _suddenStopKey = 'settings_sudden_stop_enabled';
  static const _gForceKey = 'settings_g_force_enabled';
  static const _passiveBleKey = 'settings_passive_ble_enabled';

  bool get _allSystemsActive =>
      _passiveBleEnabled && _suddenStopEnabled && _gForceEnabled;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _ageCtrl  = TextEditingController();
    _sos1Ctrl = TextEditingController();
    _sos2Ctrl = TextEditingController();
    _loadProfile();
    _loadContacts();
    _loadToggleSettings();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _sos1Ctrl.dispose();
    _sos2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final p = await _profileService.load();
    if (!mounted) return;
    setState(() {
      _nameCtrl.text = p.name ?? '';
      _ageCtrl.text  = p.age  ?? '';
      _sos1Ctrl.text = p.sos1 ?? '';
      _sos2Ctrl.text = p.sos2 ?? '';
      _selectedGender     = p.gender;
      _selectedBloodGroup = p.bloodGroup;
    });
  }

  Future<void> _saveProfile() async {
    final p = UserProfile(
      name:       _nameCtrl.text.trim(),
      gender:     _selectedGender,
      age:        _ageCtrl.text.trim(),
      bloodGroup: _selectedBloodGroup,
      sos1:       _sos1Ctrl.text.trim(),
      sos2:       _sos2Ctrl.text.trim(),
    );
    await _profileService.save(p);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved')),
      );
    }
  }

  Future<void> _loadContacts() async {
    final contacts = await SmsService.getContacts();
    final primary = await SmsService.getPrimaryContact();
    if (mounted) {
      setState(() {
        _contacts = contacts;
        _primary = primary;
      });
    }
  }

  Future<void> _loadToggleSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _suddenStopEnabled = prefs.getBool(_suddenStopKey) ?? true;
      _gForceEnabled = prefs.getBool(_gForceKey) ?? true;
      _passiveBleEnabled = prefs.getBool(_passiveBleKey) ?? true;
    });
  }

  Future<void> _setSuddenStopEnabled(bool value) async {
    setState(() => _suddenStopEnabled = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_suddenStopKey, value);
    _applySuddenStopDetection(value);
  }

  Future<void> _setGForceEnabled(bool value) async {
    setState(() => _gForceEnabled = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_gForceKey, value);
    _applyGForceDetection(value);
  }

  Future<void> _setPassiveBleEnabled(bool value) async {
    setState(() => _passiveBleEnabled = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_passiveBleKey, value);
    _applyPassiveBleScan(value);
  }

  // Preserve existing toggle behavior while persisting UI state.
  void _applySuddenStopDetection(bool value) {}

  void _applyGForceDetection(bool value) {}

  void _applyPassiveBleScan(bool value) {}

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Safety Control Center')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ── Status card ─────────────────────────────────────────────────
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      _allSystemsActive
                          ? Icons.verified_user_outlined
                          : Icons.warning_amber_rounded,
                      color: _allSystemsActive
                          ? Colors.greenAccent.shade400
                          : colorScheme.error,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _allSystemsActive
                            ? '🟢 All systems active'
                            : '🔴 Some features disabled',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Profile card ────────────────────────────────────────────────
            _buildSectionCard(
              context,
              icon: Icons.person_outline,
              title: 'PROFILE',
              subtitle: 'Included in your SOS PDF report',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: Icon(Icons.badge_outlined),
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Gender',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                          ),
                          value: _selectedGender,
                          items: _genders
                              .map((g) => DropdownMenuItem(
                                    value: g,
                                    child: Text(
                                      g,
                                      style: const TextStyle(fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _selectedGender = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _ageCtrl,
                          keyboardType: TextInputType.number,
                          maxLines: 1,
                          decoration: const InputDecoration(
                            labelText: 'Age',
                            prefixIcon: Icon(Icons.cake_outlined),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Blood Group',
                      prefixIcon: Icon(Icons.bloodtype_outlined),
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    value: _selectedBloodGroup,
                    items: _bloodGroups
                        .map((b) => DropdownMenuItem(
                              value: b,
                              child: Text(
                                b,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _selectedBloodGroup = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _sos1Ctrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'SOS Contact 1',
                      prefixIcon: Icon(Icons.emergency_outlined),
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _sos2Ctrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'SOS Contact 2',
                      prefixIcon: Icon(Icons.emergency_outlined),
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 46),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _saveProfile,
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('Save Profile',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildSectionCard(
              context,
              icon: Icons.emergency_outlined,
              title: 'EMERGENCY READINESS',
              subtitle: 'Used during SOS alerts',
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.star_outline),
                    title: const Text('Primary Contact'),
                    subtitle: Text(_primary ?? 'Not set'),
                  ),
                  const Divider(height: 8),
                  ..._contacts.map(
                    (c) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_outline),
                      title: Text(c),
                      subtitle: Text(
                        c == _primary
                            ? 'Primary contact (used for crash simulation)'
                            : 'Emergency contact',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              c == _primary ? Icons.star : Icons.star_border,
                              color: c == _primary
                                  ? Colors.amber.shade700
                                  : Colors.grey,
                            ),
                            tooltip: 'Set as primary',
                            onPressed: () async {
                              await SmsService.setPrimaryContact(c);
                              await _loadContacts();
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            tooltip: 'Remove contact',
                            onPressed: () async {
                              await SmsService.removeContact(c);
                              await _loadContacts();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_add_outlined),
                    title: const Text('Add emergency contact'),
                    subtitle: const Text('Receives SMS when SOS is triggered'),
                    trailing: const Icon(Icons.add_circle_outline),
                    onTap: () => _showAddContactDialog(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildSectionCard(
              context,
              icon: Icons.psychology_alt_outlined,
              title: 'SMART DETECTION',
              subtitle: 'Auto-detect accidents using sensors',
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.speed_outlined),
                    title: const Text('Sudden Stop Detection'),
                    subtitle: const Text(
                        'Alert when speed drops from ≥25 to ≈0 km/h'),
                    value: _suddenStopEnabled,
                    onChanged: _setSuddenStopEnabled,
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.vibration),
                    title: const Text('G-force Impact Detection'),
                    subtitle: const Text('Alert on high-impact events (>2.5G)'),
                    value: _gForceEnabled,
                    onChanged: _setGForceEnabled,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildSectionCard(
              context,
              icon: Icons.bluetooth_searching,
              title: 'NEARBY EMERGENCY NETWORK',
              subtitle: 'Detect SOS nearby without internet',
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.radar_outlined),
                title: const Text('Passive BLE Scan'),
                subtitle: const Text('Alert when nearby SOS detected'),
                value: _passiveBleEnabled,
                onChanged: _setPassiveBleEnabled,
              ),
            ),
            const SizedBox(height: 12),

            // ── VICTIM ID ───────────────────────────────────────────────────
            _buildSectionCard(
              context,
              icon: Icons.badge_outlined,
              title: 'VICTIM ID CARD',
              subtitle: 'Medical info QR for emergency responders',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.qr_code_2),
                title: const Text('Set up Victim ID'),
                subtitle: const Text('Blood group, allergies, conditions, emergency contacts'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.victimId),
              ),
            ),
            const SizedBox(height: 12),

            // ── DEMO MODE ────────────────────────────────────────────────────
            _buildSectionCard(
              context,
              icon: Icons.science_outlined,
              title: 'DEMO MODE',
              subtitle: 'Safe testing without real alerts',
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.warning_amber_outlined),
                title: const Text('Demo mode'),
                subtitle: const Text('Test without sending real alerts'),
                value: ref.watch(demoModeProvider),
                onChanged: (v) =>
                    ref.read(demoModeProvider.notifier).toggle(v),
              ),
            ),
            const SizedBox(height: 12),

            // ── INCIDENT HISTORY ────────────────────────────────────────────
            _buildSectionCard(
              context,
              icon: Icons.history,
              title: 'INCIDENT HISTORY',
              subtitle: 'Review past emergency events',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history_outlined),
                title: const Text('Incident history'),
                subtitle: const Text('View all recorded SOS incidents'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.history),
              ),
            ),
            const SizedBox(height: 12),

            // ── SAFETY TOOLS ───────────────────────────────────────────────
            _buildSectionCard(
              context,
              icon: Icons.security_outlined,
              title: 'SAFETY TOOLS',
              subtitle: 'Quick access tools in high-risk situations',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.phone_in_talk_outlined),
                title: const Text('Fake Incoming Call'),
                subtitle:
                    const Text('Simulate a call to exit unsafe situation'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.fakeCall),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: ExpansionTile(
                initiallyExpanded: _advancedExpanded,
                onExpansionChanged: (value) {
                  setState(() => _advancedExpanded = value);
                },
                leading: const Icon(Icons.tune),
                title: const Text('ADVANCED'),
                subtitle: const Text('Diagnostics and test controls'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final notifier =
                            ProviderScope.containerOf(context, listen: false)
                                .read(sosStateProvider.notifier);
                        await notifier.triggerSos(testMode: true);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Test SOS triggered'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.sos_outlined),
                      label: const Text('Test SOS'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LogsScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('View Logs'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── PRIVACY / DPDPA ─────────────────────────────────────────────
            _buildSectionCard(
              context,
              icon: Icons.privacy_tip_outlined,
              title: 'PRIVACY',
              subtitle: 'Your data rights under DPDPA 2023',
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.delete_forever_outlined, color: Colors.red),
                    title: const Text('Clear all my data'),
                    subtitle: const Text('Removes profile, contacts, victim ID, and all cached data'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _confirmClearData(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClearData(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all data?'),
        content: const Text(
          'This will permanently delete your profile, emergency contacts, Victim ID, '
          'and all cached data from this device. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All data cleared')),
        );
      }
    }
  }

  void _showAddContactDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Emergency Contact'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Phone number',
            hintText: '+91 98765 43210',
            prefixIcon: Icon(Icons.phone),
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final number = controller.text.trim();
              if (number.isNotEmpty) {
                await SmsService.addContact(number);
                await _loadContacts();
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
