import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';

const _kVictimIdKey = 'victim_id_v1';

class VictimProfile {
  final String? name;
  final String? bloodGroup;
  final String? allergies;
  final String? conditions;
  final String? medications;
  final String? emergencyContact1;
  final String? emergencyContact1Phone;
  final String? emergencyContact2;
  final String? emergencyContact2Phone;
  final bool? organDonor;
  final String? healthInsurer;

  const VictimProfile({
    this.name,
    this.bloodGroup,
    this.allergies,
    this.conditions,
    this.medications,
    this.emergencyContact1,
    this.emergencyContact1Phone,
    this.emergencyContact2,
    this.emergencyContact2Phone,
    this.organDonor,
    this.healthInsurer,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'bloodGroup': bloodGroup,
    'allergies': allergies,
    'conditions': conditions,
    'medications': medications,
    'ec1Name': emergencyContact1,
    'ec1Phone': emergencyContact1Phone,
    'ec2Name': emergencyContact2,
    'ec2Phone': emergencyContact2Phone,
    'organDonor': organDonor,
    'healthInsurer': healthInsurer,
  };

  factory VictimProfile.fromJson(Map<String, dynamic> j) => VictimProfile(
    name: j['name'] as String?,
    bloodGroup: j['bloodGroup'] as String?,
    allergies: j['allergies'] as String?,
    conditions: j['conditions'] as String?,
    medications: j['medications'] as String?,
    emergencyContact1: j['ec1Name'] as String?,
    emergencyContact1Phone: j['ec1Phone'] as String?,
    emergencyContact2: j['ec2Name'] as String?,
    emergencyContact2Phone: j['ec2Phone'] as String?,
    organDonor: j['organDonor'] as bool?,
    healthInsurer: j['healthInsurer'] as String?,
  );

  /// Compact QR payload
  String toQrPayload() {
    final map = <String, dynamic>{};
    if (name != null && name!.isNotEmpty) map['n'] = name;
    if (bloodGroup != null) map['bg'] = bloodGroup;
    if (allergies != null && allergies!.isNotEmpty) map['al'] = allergies;
    if (conditions != null && conditions!.isNotEmpty) map['co'] = conditions;
    if (medications != null && medications!.isNotEmpty) map['me'] = medications;
    final ec1 = emergencyContact1Phone ?? emergencyContact1;
    if (ec1 != null && ec1.isNotEmpty) {
      map['ec'] = emergencyContact1 != null
          ? '${emergencyContact1}:$ec1'
          : ec1;
    }
    if (organDonor != null) map['od'] = organDonor;
    return jsonEncode(map);
  }
}

Future<VictimProfile?> loadVictimProfile() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_kVictimIdKey);
  if (raw == null) return null;
  try {
    return VictimProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

Future<void> saveVictimProfile(VictimProfile profile) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kVictimIdKey, jsonEncode(profile.toJson()));
}

class VictimIdScreen extends StatefulWidget {
  const VictimIdScreen({super.key});

  @override
  State<VictimIdScreen> createState() => _VictimIdScreenState();
}

class _VictimIdScreenState extends State<VictimIdScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _name, _allergies, _conditions, _medications,
      _ec1Name, _ec1Phone, _ec2Name, _ec2Phone, _insurer;
  String? _bloodGroup;
  bool? _organDonor;
  bool _saving = false;
  bool _loaded = false;

  static const _bloodGroups = ['A+','A-','B+','B-','AB+','AB-','O+','O-','Unknown'];

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _allergies = TextEditingController();
    _conditions = TextEditingController();
    _medications = TextEditingController();
    _ec1Name = TextEditingController();
    _ec1Phone = TextEditingController();
    _ec2Name = TextEditingController();
    _ec2Phone = TextEditingController();
    _insurer = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _allergies, _conditions, _medications,
        _ec1Name, _ec1Phone, _ec2Name, _ec2Phone, _insurer]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final p = await loadVictimProfile();
    if (!mounted) return;
    if (p != null) {
      _name.text = p.name ?? '';
      _allergies.text = p.allergies ?? '';
      _conditions.text = p.conditions ?? '';
      _medications.text = p.medications ?? '';
      _ec1Name.text = p.emergencyContact1 ?? '';
      _ec1Phone.text = p.emergencyContact1Phone ?? '';
      _ec2Name.text = p.emergencyContact2 ?? '';
      _ec2Phone.text = p.emergencyContact2Phone ?? '';
      _insurer.text = p.healthInsurer ?? '';
      setState(() {
        _bloodGroup = p.bloodGroup;
        _organDonor = p.organDonor;
        _loaded = true;
      });
    } else {
      setState(() => _loaded = true);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final profile = VictimProfile(
      name: _name.text.trim(),
      bloodGroup: _bloodGroup,
      allergies: _allergies.text.trim().isEmpty ? null : _allergies.text.trim(),
      conditions: _conditions.text.trim().isEmpty ? null : _conditions.text.trim(),
      medications: _medications.text.trim().isEmpty ? null : _medications.text.trim(),
      emergencyContact1: _ec1Name.text.trim().isEmpty ? null : _ec1Name.text.trim(),
      emergencyContact1Phone: _ec1Phone.text.trim().isEmpty ? null : _ec1Phone.text.trim(),
      emergencyContact2: _ec2Name.text.trim().isEmpty ? null : _ec2Name.text.trim(),
      emergencyContact2Phone: _ec2Phone.text.trim().isEmpty ? null : _ec2Phone.text.trim(),
      organDonor: _organDonor,
      healthInsurer: _insurer.text.trim().isEmpty ? null : _insurer.text.trim(),
    );
    await saveVictimProfile(profile);
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Victim ID saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Victim ID Card'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.qr_code_2),
            label: const Text('View QR'),
            onPressed: () => context.push('/victim-id/qr'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Disclaimer
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Emergency reference only. Data stored only on this device and never transmitted.',
                        style: TextStyle(fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _SectionTitle('Personal'),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Full Name *',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Blood Group *',
                  prefixIcon: Icon(Icons.bloodtype_outlined),
                  border: OutlineInputBorder(),
                ),
                value: _bloodGroup,
                items: _bloodGroups
                    .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                    .toList(),
                onChanged: (v) => setState(() => _bloodGroup = v),
                validator: (v) => v == null ? 'Select blood group' : null,
              ),
              const SizedBox(height: 20),
              _SectionTitle('Medical'),
              TextFormField(
                controller: _allergies,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Known Allergies',
                  hintText: 'e.g. Penicillin, Peanuts',
                  prefixIcon: Icon(Icons.warning_amber_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _conditions,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Chronic Conditions',
                  hintText: 'e.g. Type 2 Diabetes, Hypertension',
                  prefixIcon: Icon(Icons.medical_services_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _medications,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Current Medications',
                  hintText: 'e.g. Metformin 500mg, Amlodipine 5mg',
                  prefixIcon: Icon(Icons.medication_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              _SectionTitle('Emergency Contacts'),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _ec1Name,
                      decoration: const InputDecoration(
                        labelText: 'Contact 1 Name *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Required'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _ec1Phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Required'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _ec2Name,
                      decoration: const InputDecoration(
                        labelText: 'Contact 2 Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _ec2Phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _SectionTitle('Other'),
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: SwitchListTile.adaptive(
                  title: const Text('Organ Donor'),
                  subtitle: const Text('In case of emergencies requiring transplant decision'),
                  value: _organDonor ?? false,
                  onChanged: (v) => setState(() => _organDonor = v),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _insurer,
                decoration: const InputDecoration(
                  labelText: 'Health Insurer',
                  hintText: 'e.g. Star Health, LIC',
                  prefixIcon: Icon(Icons.health_and_safety_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving...' : 'Save Victim ID'),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
