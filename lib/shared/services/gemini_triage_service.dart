import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

final geminiTriageServiceProvider = Provider<GeminiTriageService>((ref) {
  return const GeminiTriageService();
});

final class GeminiTriageResult {
  final String summaryLine;
  final int injuryRiskPercent;

  const GeminiTriageResult({
    required this.summaryLine,
    required this.injuryRiskPercent,
  });
}

final class GeminiTriageService {
  const GeminiTriageService();

  // NOTE: Using Gemini 2.0 Flash (latest) via v1beta endpoint.
  static const String _model = 'gemini-2.0-flash';
  static const String _endpointBase =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  static const _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  Future<GeminiTriageResult?> triage({
    required Map<String, dynamic> sosPayload,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (_apiKey.isEmpty) return null;

    final prompt = _buildPrompt(sosPayload);

    try {
      final res = await http
          .post(
            Uri.parse('$_endpointBase?key=$_apiKey'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {'text': prompt},
                  ],
                },
              ],
              // Keep responses deterministic and short.
              'generationConfig': {
                'temperature': 0.2,
                'maxOutputTokens': 120,
              },
            }),
          )
          .timeout(timeout);

      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      return parseTriageResponse(res.body);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[GeminiTriageService] triage failed: $e');
      }
      return null;
    }
  }

  /// Exposed for unit tests.
  @visibleForTesting
  GeminiTriageResult? parseTriageResponse(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final candidates = (json['candidates'] as List?) ?? const [];
      if (candidates.isEmpty) return null;

      final content = candidates.first['content'] as Map<String, dynamic>?;
      final parts = (content?['parts'] as List?) ?? const [];
      final text = parts.isNotEmpty ? parts.first['text']?.toString() : null;
      if (text == null || text.trim().isEmpty) return null;

      // Expect a compact two-line response:
      // SUMMARY: ...
      // RISK_PERCENT: 42
      final lines = text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      String? summary;
      int? risk;
      for (final l in lines) {
        if (l.toUpperCase().startsWith('SUMMARY:')) {
          summary = l.substring('SUMMARY:'.length).trim();
        } else if (l.toUpperCase().startsWith('RISK_PERCENT:')) {
          final raw = l.substring('RISK_PERCENT:'.length).trim();
          final p = int.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), ''));
          if (p != null) risk = p.clamp(0, 100);
        }
      }

      if (summary == null || summary.isEmpty) return null;
      return GeminiTriageResult(
        summaryLine: summary,
        injuryRiskPercent: risk ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  String _buildPrompt(Map<String, dynamic> sosPayload) {
    final jsonStr = jsonEncode(sosPayload);
    return [
      'You are an emergency triage assistant.',
      'Given the following SOS JSON, output EXACTLY two lines:',
      'SUMMARY: <one short line, no emojis>',
      'RISK_PERCENT: <integer 0-100>',
      '',
      'SOS_JSON:',
      jsonStr,
    ].join('\n');
  }
}

