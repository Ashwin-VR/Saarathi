import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Wraps a child widget and shows a permission request UI if needed.
class PermissionGate extends StatefulWidget {
  final Widget child;
  final List<Permission> permissions;

  const PermissionGate({
    super.key,
    required this.child,
    required this.permissions,
  });

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate> {
  bool _checking = true;
  bool _granted = false;
  bool _permanentlyDenied = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    setState(() => _checking = true);

    final statuses = await widget.permissions.request();
    final allGranted = statuses.values.every(
      (s) => s == PermissionStatus.granted || s == PermissionStatus.limited,
    );
    final anyPermanent = statuses.values
        .any((s) => s == PermissionStatus.permanentlyDenied);

    setState(() {
      _checking = false;
      _granted = allGranted;
      _permanentlyDenied = anyPermanent && !allGranted;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_granted) return widget.child;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_off, size: 72, color: Colors.red),
              const SizedBox(height: 24),
              const Text(
                'Permissions Required',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'This app needs Location and Bluetooth permissions to relay SOS signals and include your location in alerts.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, height: 1.5),
              ),
              const SizedBox(height: 32),
              if (_permanentlyDenied) ...[
                ElevatedButton.icon(
                  icon: const Icon(Icons.settings),
                  label: const Text('Open App Settings'),
                  onPressed: openAppSettings,
                ),
              ] else ...[
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Grant Permissions'),
                  onPressed: _checkPermissions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
