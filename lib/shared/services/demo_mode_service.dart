import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kDemoModeKey = 'demo_mode_enabled_v1';

class DemoModeNotifier extends StateNotifier<bool> {
  DemoModeNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_kDemoModeKey) ?? false;
  }

  Future<void> toggle(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDemoModeKey, value);
  }
}

final demoModeProvider = StateNotifierProvider<DemoModeNotifier, bool>(
  (_) => DemoModeNotifier(),
);
