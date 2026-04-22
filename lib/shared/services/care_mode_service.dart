import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:accident_app/shared/services/notification_service.dart';

// ── Care Mode State ────────────────────────────────────────────────────────────

enum CareModeStatus {
  inactive,      // Not running
  active,        // Timer is counting down
  checkPending,  // Wellness check notification shown, waiting for confirmation
}

class CareModeState {
  final CareModeStatus status;
  final int secondsRemaining;        // Seconds left in current timer interval
  final int missedChecks;            // Consecutive unconfirmed wellness checks
  final int intervalMinutes;         // Configurable interval (10 or 15)

  static const defaultInterval = 10; // minutes

  const CareModeState({
    this.status = CareModeStatus.inactive,
    this.secondsRemaining = 0,
    this.missedChecks = 0,
    this.intervalMinutes = defaultInterval,
  });

  CareModeState copyWith({
    CareModeStatus? status,
    int? secondsRemaining,
    int? missedChecks,
    int? intervalMinutes,
  }) {
    return CareModeState(
      status:           status           ?? this.status,
      secondsRemaining: secondsRemaining ?? this.secondsRemaining,
      missedChecks:     missedChecks     ?? this.missedChecks,
      intervalMinutes:  intervalMinutes  ?? this.intervalMinutes,
    );
  }

  String get timerDisplay {
    final m = secondsRemaining ~/ 60;
    final s = secondsRemaining % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  double get timerProgress {
    final total = intervalMinutes * 60;
    if (total <= 0) return 0;
    return secondsRemaining / total;
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final careModeProvider = NotifierProvider<CareModeNotifier, CareModeState>(
  CareModeNotifier.new,
);

/// Maximum consecutive missed checks before auto-SOS triggers.
const _maxMissedChecks = 2;

class CareModeNotifier extends Notifier<CareModeState> {
  Timer? _timer;

  @override
  CareModeState build() {
    ref.onDispose(_cleanup);
    return const CareModeState();
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Start Care Mode with [intervalMinutes] (10 or 15).
  void start({int intervalMinutes = CareModeState.defaultInterval}) {
    if (state.status != CareModeStatus.inactive) return;
    _cancelTimer();
    state = CareModeState(
      status:           CareModeStatus.active,
      secondsRemaining: intervalMinutes * 60,
      intervalMinutes:  intervalMinutes,
      missedChecks:     0,
    );
    _beginCountdown();
  }

  /// Stop Care Mode entirely.
  void stop() {
    _cleanup();
    state = const CareModeState(status: CareModeStatus.inactive);
  }

  /// User confirmed they are safe — reset the timer loop.
  Future<void> confirmSafe() async {
    if (state.status == CareModeStatus.inactive) return;
    await ref.read(notificationServiceProvider).cancelWellnessCheck();
    final interval = state.intervalMinutes;
    _cancelTimer();
    state = CareModeState(
      status:           CareModeStatus.active,
      secondsRemaining: interval * 60,
      intervalMinutes:  interval,
      missedChecks:     0,
    );
    _beginCountdown();
  }

  // ── Internal timer logic ──────────────────────────────────────────────────

  void _beginCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (state.status == CareModeStatus.inactive) return;

    final remaining = state.secondsRemaining - 1;

    if (remaining <= 0) {
      // Timer expired — issue wellness check
      _triggerWellnessCheck();
    } else {
      state = state.copyWith(secondsRemaining: remaining);
    }
  }

  Future<void> _triggerWellnessCheck() async {
    _cancelTimer();

    final newMissed = state.missedChecks;   // not incremented yet; this is a new check
    state = state.copyWith(
      status:           CareModeStatus.checkPending,
      secondsRemaining: 0,
    );

    // Show notification
    await ref.read(notificationServiceProvider)
        .showWellnessCheck(missedCount: newMissed);

    // Give user 60 seconds to respond before counting as missed
    _timer = Timer(const Duration(seconds: 60), _onCheckTimeout);
  }

  void _onCheckTimeout() {
    if (state.status != CareModeStatus.checkPending) return;

    final missed = state.missedChecks + 1;

    if (missed >= _maxMissedChecks) {
      // Auto-trigger SOS
      _cancelTimer();
      state = state.copyWith(missedChecks: missed);
      _autoTriggerSos();
    } else {
      // Another missed check — restart timer but track missed count
      final interval = state.intervalMinutes;
      _cancelTimer();
      state = CareModeState(
        status:           CareModeStatus.active,
        secondsRemaining: interval * 60,
        intervalMinutes:  interval,
        missedChecks:     missed,
      );
      _beginCountdown();
    }
  }

  void _autoTriggerSos() {
    // Delegate to SOS notifier via the registered callback
    try {
      ref.read(sosTriggerCallbackProvider)();
    } catch (_) {}
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _cleanup() {
    _cancelTimer();
    // cancelWellnessCheck is async; we fire it best-effort on dispose
    // (Future.ignore avoids an unhandled-promise lint without awaiting)
    ref.read(notificationServiceProvider).cancelWellnessCheck().ignore();
  }
}

// ── SOS trigger callback registered by SosNotifier in app_state.dart ─────────
// This provider holds the callback injected by SosNotifier to break the
// circular dependency between care_mode_service ↔ app_state.

typedef SosTriggerCallback = void Function();

final sosTriggerCallbackProvider =
    StateProvider<SosTriggerCallback>((ref) => () {});
