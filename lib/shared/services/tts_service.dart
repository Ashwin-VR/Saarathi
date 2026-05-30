import 'package:flutter_riverpod/flutter_riverpod.dart';

final ttsServiceProvider = Provider<TtsService>((ref) {
  final svc = TtsService();
  ref.onDispose(svc.dispose);
  return svc;
});

/// Text-to-speech is out of scope for RoadSoS (PRD §17).
/// Crash scene ambient noise exceeds 80dB — TTS is unreliable.
/// This stub preserves the API surface without the flutter_tts dependency.
class TtsService {
  String? _lastSpoken;

  Future<void> speakOnChange(String phrase) async {
    if (phrase == _lastSpoken) return;
    _lastSpoken = phrase;
    // No-op: TTS removed per PRD §17 (flutter_tts out of scope)
    print('[TtsService] (stub) Would speak: "$phrase"');
  }

  Future<void> stop() async {
    _lastSpoken = null;
  }

  void resetLastSpoken() => _lastSpoken = null;

  Future<void> dispose() async {
    await stop();
  }
}
