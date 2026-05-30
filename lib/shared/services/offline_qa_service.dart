import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:accident_app/shared/models/emergency_service.dart';

final offlineQaServiceProvider = Provider<OfflineQaService>((ref) {
  return OfflineQaService();
});

class _QaEntry {
  final List<String> keywords;
  final String answer;
  const _QaEntry({required this.keywords, required this.answer});
}

class OfflineQaService {
  List<_QaEntry> _entries = [];
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final raw = await rootBundle.loadString('assets/data/offline_qa.json');
      final list = (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
      _entries = list.map((e) => _QaEntry(
        keywords: (e['keywords'] as List<dynamic>).cast<String>(),
        answer: e['answer'] as String,
      )).toList();
      _loaded = true;
      print('[OfflineQA] Loaded ${_entries.length} entries');
    } catch (e) {
      print('[OfflineQA] Load error: $e');
      _entries = [];
    }
  }

  /// Find the best matching answer for [query].
  /// Falls back to [nearestHospital] info if no match found.
  String answer(String query, {EmergencyService? nearestHospital}) {
    if (!_loaded || _entries.isEmpty) {
      return _fallback(nearestHospital);
    }

    final tokens = _tokenize(query);
    if (tokens.isEmpty) return _fallback(nearestHospital);

    int bestScore = 0;
    _QaEntry? bestEntry;

    for (final entry in _entries) {
      int score = 0;
      for (final kw in entry.keywords) {
        if (tokens.any((t) => t.contains(kw) || kw.contains(t))) {
          score++;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        bestEntry = entry;
      }
    }

    if (bestEntry != null && bestScore > 0) {
      return bestEntry.answer;
    }
    return _fallback(nearestHospital);
  }

  String _fallback(EmergencyService? hospital) {
    if (hospital != null) {
      return "I can't answer that without internet. Call 112 for immediate help. "
          "The nearest hospital on the map is ${hospital.name} — "
          "${hospital.distanceKm(0, 0).toStringAsFixed(1)} km away. "
          "Tap it on the map to call directly.";
    }
    return "I can't answer that without internet. Call 112 for immediate help.";
  }

  List<String> _tokenize(String query) {
    return query
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .split(' ')
        .where((t) => t.length > 2)
        .toList();
  }
}
