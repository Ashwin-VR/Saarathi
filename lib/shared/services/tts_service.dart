import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

final ttsServiceProvider = Provider<TtsService>((ref) {
  final svc = TtsService();
  ref.onDispose(svc.dispose);
  return svc;
});

class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  String? _lastSpoken; // track last phrase to avoid repetition

  Future<void> _init() async {
    if (_initialized) return;
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      _initialized = true;
      print('[TtsService] ✅ TTS initialized');
    } catch (e) {
      print('[TtsService] ❌ TTS init error: $e');
    }
  }

  /// Speak [phrase] only if it differs from the last spoken phrase.
  Future<void> speakOnChange(String phrase) async {
    if (!_isMobile) return;
    if (phrase == _lastSpoken) return;
    _lastSpoken = phrase;
    await _init();
    try {
      await _tts.stop();
      await _tts.speak(phrase);
      print('[TtsService] 🔊 Speaking: "$phrase"');
    } catch (e) {
      print('[TtsService] ❌ speak error: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
    _lastSpoken = null;
  }

  void resetLastSpoken() => _lastSpoken = null;

  Future<void> dispose() async {
    await stop();
  }

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;
}
