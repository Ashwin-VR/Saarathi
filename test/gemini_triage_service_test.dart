import 'package:accident_app/shared/services/gemini_triage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Gemini triage parsing extracts summary and risk', () {
    const body = r'''
{
  "candidates": [
    {
      "content": {
        "parts": [
          { "text": "SUMMARY: Possible head/torso trauma; immediate evaluation advised.\nRISK_PERCENT: 62\n" }
        ]
      }
    }
  ]
}
''';

    const svc = GeminiTriageService();
    final res = svc.parseTriageResponse(body);
    expect(res, isNotNull);
    expect(res!.summaryLine, contains('Possible'));
    expect(res.injuryRiskPercent, 62);
  });

  test('Gemini triage parsing tolerates missing risk', () {
    const body = r'''
{
  "candidates": [
    {
      "content": { "parts": [ { "text": "SUMMARY: Unknown severity." } ] }
    }
  ]
}
''';

    const svc = GeminiTriageService();
    final res = svc.parseTriageResponse(body);
    expect(res, isNotNull);
    expect(res!.summaryLine, 'Unknown severity.');
    expect(res.injuryRiskPercent, 0);
  });
}

