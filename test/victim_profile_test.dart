import 'package:flutter_test/flutter_test.dart';
import 'package:accident_app/features/victim_id/victim_id_screen.dart';

void main() {
  group('VictimProfile', () {
    test('toJson and fromJson work correctly', () {
      final profile = VictimProfile(
        name: 'John Doe',
        bloodGroup: 'O+',
        allergies: 'Peanuts',
        conditions: 'Asthma',
        medications: 'Inhaler',
        emergencyContact1: 'Jane Doe',
        emergencyContact1Phone: '1234567890',
        emergencyContact2: '',
        emergencyContact2Phone: '',
        organDonor: true,
        healthInsurer: 'HealthCare Inc',
      );

      final json = profile.toJson();
      expect(json['name'], 'John Doe');
      expect(json['bloodGroup'], 'O+');

      final reconstructed = VictimProfile.fromJson(json);
      expect(reconstructed.name, profile.name);
      expect(reconstructed.bloodGroup, profile.bloodGroup);
      expect(reconstructed.allergies, profile.allergies);
      expect(reconstructed.organDonor, profile.organDonor);
    });

    test('toQrPayload generates compact JSON string', () {
      final profile = VictimProfile(
        name: 'John Doe',
        bloodGroup: 'O+',
        allergies: 'Peanuts',
        conditions: 'Asthma',
        medications: 'Inhaler',
        emergencyContact1: 'Jane Doe',
        emergencyContact1Phone: '1234567890',
        emergencyContact2: '',
        emergencyContact2Phone: '',
        organDonor: true,
        healthInsurer: 'HealthCare Inc',
      );

      final payload = profile.toQrPayload();
      // Should not contain full keys, but compact keys like 'n', 'bg'
      expect(payload.contains('"n":"John Doe"'), true);
      expect(payload.contains('"bg":"O+"'), true);
      expect(payload.contains('"al":"Peanuts"'), true);
      expect(payload.contains('"co":"Asthma"'), true);
      expect(payload.contains('"od":true'), true);
    });

    test('empty profile handles null values gracefully', () {
      final json = <String, dynamic>{};
      final profile = VictimProfile.fromJson(json);

      expect(profile.name, isNull);
      expect(profile.bloodGroup, isNull);
      expect(profile.organDonor, isNull);
      expect(profile.toQrPayload(), isNotNull);
    });
  });
}
