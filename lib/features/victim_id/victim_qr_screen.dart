import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:accident_app/features/victim_id/victim_id_screen.dart';

class VictimQrScreen extends StatefulWidget {
  const VictimQrScreen({super.key});

  @override
  State<VictimQrScreen> createState() => _VictimQrScreenState();
}

class _VictimQrScreenState extends State<VictimQrScreen> {
  VictimProfile? _profile;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    loadVictimProfile().then((p) {
      if (mounted) setState(() { _profile = p; _loaded = true; });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final profile = _profile;
    if (profile == null || (profile.name == null && profile.bloodGroup == null)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Medical QR Code')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.qr_code_2, size: 80, color: Colors.white24),
              const SizedBox(height: 16),
              const Text('No Victim ID set up yet.'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Set up Victim ID'),
              ),
            ],
          ),
        ),
      );
    }

    final payload = profile.toQrPayload();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Medical QR Code',
            style: TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: QrImageView(
                data: payload,
                version: QrVersions.auto,
                size: 260,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.black,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (profile.name != null)
              Text(
                profile.name!,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800),
              ),
            if (profile.bloodGroup != null) ...
              [
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD32F2F),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Blood Group: ${profile.bloodGroup}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16),
                  ),
                ),
              ],
            const SizedBox(height: 20),
            Text(
              'Show this QR to emergency responders.',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              'Contains: name, blood group, allergies, conditions, emergency contact',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
