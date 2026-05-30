import 'package:flutter_test/flutter_test.dart';
import 'package:accident_app/shared/providers/app_state.dart';

void main() {
  group('SosState Transitions', () {
    test('initial state is idle with 10s countdown', () {
      const state = SosState();
      expect(state.status, SosStatus.idle);
      expect(state.countdownSeconds, 10);
      expect(state.alertedAt, isNull);
    });

    test('copyWith updates status and alertedAt correctly', () {
      const state = SosState();
      final now = DateTime.now();

      final activeState = state.copyWith(
        status: SosStatus.active,
        alertedAt: now,
      );

      expect(activeState.status, SosStatus.active);
      expect(activeState.alertedAt, now);
      expect(activeState.countdownSeconds, 10); // remains unchanged
    });

    test('copyWith updates countdown correctly for preAlert', () {
      const state = SosState(status: SosStatus.preAlert, countdownSeconds: 10);

      final tickState = state.copyWith(countdownSeconds: 9);

      expect(tickState.status, SosStatus.preAlert);
      expect(tickState.countdownSeconds, 9);
    });
  });
}
