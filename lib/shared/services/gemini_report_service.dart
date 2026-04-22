import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

final class GeminiReportService {
  const GeminiReportService();

  // Gemini 2.0 Flash via v1beta endpoint.
  static const _apiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent';

  /// Generates a concise AI narrative for the incident report.
  ///
  /// Returns **empty string** on any failure (missing key, network error,
  /// 400/5xx, parse error) — the caller must treat '' as "no narrative".
  /// NEVER returns an error message string; those would pollute the PDF.
  Future<String> generateReport(Map<String, dynamic> data) async {
    // ── Guard: no key → skip silently ──────────────────────────────────────
    if (_apiKey.isEmpty) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[GeminiReportService] GEMINI_API_KEY not set — skipping AI narrative.');
      }
      return '';
    }

    try {
      // ── Strip nulls from payload to avoid Gemini 400 errors ───────────────
      final sanitized = _stripNulls(data);

      final response = await http
          .post(
            Uri.parse('$_endpoint?key=$_apiKey'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {
                      'text':
                          'Generate a short incident report with sections: '
                          'Summary, Sensor Signals, Location/Time, Actions Recommended. '
                          'No emojis. Plain ASCII text only. '
                          'Base it on this JSON:\n${jsonEncode(sanitized)}',
                    },
                  ],
                },
              ],
              'generationConfig': {
                'temperature': 0.2,
                'maxOutputTokens': 500,
              },
            }),
          )
          .timeout(const Duration(seconds: 10));

      // ── Non-2xx → silent skip ─────────────────────────────────────────────
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[GeminiReportService] HTTP ${response.statusCode} — skipping AI narrative.');
        }
        return '';
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final text = (json['candidates'] as List?)
          ?.firstOrNull?['content']?['parts']?[0]?['text']
          ?.toString()
          .trim();

      return (text != null && text.isNotEmpty) ? text : '';
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[GeminiReportService] generateReport error: $e');
      }
      return '';
    }
  }

  // ── Recursively remove null values from a JSON-like map ──────────────────
  // Gemini returns 400 if the request JSON contains null leaves.
  static Map<String, dynamic> _stripNulls(Map<String, dynamic> input) {
    final result = <String, dynamic>{};
    for (final entry in input.entries) {
      final v = entry.value;
      if (v == null) continue;
      if (v is Map<String, dynamic>) {
        final nested = _stripNulls(v);
        if (nested.isNotEmpty) result[entry.key] = nested;
      } else if (v is List) {
        final filtered = v
            .where((e) => e != null)
            .map((e) => e is Map<String, dynamic> ? _stripNulls(e) : e)
            .toList();
        if (filtered.isNotEmpty) result[entry.key] = filtered;
      } else {
        result[entry.key] = v;
      }
    }
    return result;
  }
}
