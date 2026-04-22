import 'package:accident_app/shared/services/sms_service.dart';
import 'package:accident_app/shared/services/sensor_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SMS message contains required fields and no emojis', () {
    final svc = SmsService();
    final msg = svc.buildSosMessageForTest(
      userName: 'Alex',
      profileAge: '29',
      profileBloodGroup: 'O+',
      lat: 12.971599,
      lng: 77.594566,
      severity: CrashSeverity.serious,
      structuredSelection: (type: 'Vehicular', severity: 'Critical'),
      triageSummary: 'High risk of severe injury; immediate dispatch recommended.',
      triageRiskPercent: 88,
    );

    expect(msg, contains('Lat/Lng: 12.971599, 77.594566'));
    expect(msg, contains('Type: Vehicular'));
    expect(msg, contains('Severity: Critical'));
    expect(msg, contains('Triage: High risk of severe injury'));
    expect(msg, contains('Risk: 88%'));
    expect(msg, contains('Profile: Alex, Age 29, Blood O+'));

    // Ensure message has no emoji markers we previously used.
    expect(msg, isNot(contains('🆘')));
    expect(msg, isNot(contains('🚑')));
    expect(msg, isNot(contains('🚔')));
    expect(msg, isNot(contains('🔥')));
  });

  test('SMS message still builds with missing location', () {
    final svc = SmsService();
    final msg = svc.buildSosMessageForTest(
      userName: 'Alex',
      lat: null,
      lng: null,
      severity: CrashSeverity.minor,
    );
    expect(msg, contains('Location: Location unavailable'));
  });
}

