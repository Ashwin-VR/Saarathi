import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:accident_app/shared/models/emergency_service.dart';

final geminiServiceProvider = Provider<GeminiService>((ref) {
  return GeminiService();
});

class GeminiService {
  static const _modelName = 'gemini-2.0-flash';
  static const _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  /// Generate an AI response for the given user message.
  /// [lat], [lng], [district], [countryName] provide location context.
  /// [nearbyPois] provides up to 5 nearest hospitals/services.
  /// Returns null on any error (caller should use offline fallback).
  Future<String?> generateResponse({
    required String userMessage,
    double? lat,
    double? lng,
    String? district,
    String? countryName,
    List<EmergencyService>? nearbyPois,
  }) async {
    if (_apiKey.isEmpty) {
      print('[GeminiService] No API key — using offline fallback');
      return null;
    }

    try {
      final model = GenerativeModel(
        model: _modelName,
        apiKey: _apiKey,
        systemInstruction: Content.system(_buildSystemPrompt(
          lat: lat,
          lng: lng,
          district: district,
          countryName: countryName,
          nearbyPois: nearbyPois,
        )),
        generationConfig: GenerationConfig(
          maxOutputTokens: 200,
          temperature: 0.2,
        ),
      );

      final response = await model
          .generateContent([Content.text(userMessage)])
          .timeout(const Duration(seconds: 10));

      final text = response.text;
      if (text == null || text.trim().isEmpty) return null;
      return text.trim();
    } on TimeoutException {
      print('[GeminiService] Request timed out');
      return null;
    } catch (e) {
      print('[GeminiService] Error: $e');
      return null;
    }
  }

  String _buildSystemPrompt({
    double? lat,
    double? lng,
    String? district,
    String? countryName,
    List<EmergencyService>? nearbyPois,
  }) {
    final locationStr = lat != null && lng != null
        ? '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'
        : 'Unknown';

    final districtStr = district ?? 'Unknown';
    final countryStr = countryName ?? 'India';

    final hospitals = nearbyPois
            ?.where((p) => p.type == EmergencyServiceType.hospital)
            .take(5)
            .map((p) => '- ${p.name}')
            .join('\n') ??
        'None found nearby';

    final police = nearbyPois
            ?.where((p) => p.type == EmergencyServiceType.police)
            .take(3)
            .map((p) => '- ${p.name}')
            .join('\n') ??
        'None found nearby';

    return '''
You are the emergency assistant in RoadSoS, a road accident response app.
You help bystanders and accident victims at the scene of road accidents in India and nearby countries.

Context for this session:
- User GPS: $locationStr
- District: $districtStr, $countryStr
- Emergency numbers: Ambulance 108, Police 100, General Emergency 112
- Nearby hospitals:\n$hospitals
- Nearby police:\n$police

Your role:
1. Help find and contact nearby emergency services — reference them by name.
2. Provide bystander first aid guidance aligned with WHO/Indian Red Cross untrained bystander protocols. Never exceed this scope.
3. Inform bystanders of their legal protection under Section 134A, MV Act 2019 when relevant.
4. Help bystanders describe their location to dispatchers.
5. Provide emergency numbers for other countries if the user is outside India.

Hard constraints — never break:
- Never diagnose specific injuries.
- Never recommend specific medications, dosages, or clinical procedures.
- Never claim that nearby facilities are definitely open or equipped — always say "call ahead to confirm".
- Never say you are an AI, a chatbot, or a language model. Just answer.
- Maximum 3 sentences per response unless the user asks for more detail.
- If unsure, default to: "Call 112 and stay on the line with the operator."

When asked about stopping bleeding:
"Apply firm, direct pressure with any clean cloth. Hold continuously — do not lift to check. If cloth soaks through, add more on top. Keep pressure until help arrives."

When asked about an unconscious victim:
"Check for breathing — look, listen, feel. If breathing: recovery position (on their side, top knee bent forward). If not breathing and you know CPR, begin. Call 112 immediately if not already done."

When asked about the Good Samaritan law:
"Under Section 134A of India's Motor Vehicles Act, you are legally protected from civil and criminal liability for helping a road accident victim in good faith. You cannot be detained, forced to give personal information, or charged for any outcome if you acted with good intent."
''';
  }
}
