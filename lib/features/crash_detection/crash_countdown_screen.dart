import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:accident_app/shared/providers/app_state.dart';

/// Full-screen 15-second crash countdown.
/// Plays alarm audio. Countdown controlled by SosNotifier.
/// Shown as a full-screen overlay (not a route — pushed as modal).
class CrashCountdownOverlay extends ConsumerStatefulWidget {
  const CrashCountdownOverlay({super.key});

  static Future<void> show(BuildContext context) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => const CrashCountdownOverlay(),
    );
  }

  @override
  ConsumerState<CrashCountdownOverlay> createState() =>
      _CrashCountdownOverlayState();
}

class _CrashCountdownOverlayState
    extends ConsumerState<CrashCountdownOverlay>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _pulse = Tween(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _playAlarm();
  }

  Future<void> _playAlarm() async {
    try {
      await _player.play(AssetSource('audio/alarm.mp3'), volume: 1.0);
    } catch (e) {
      debugPrint('[CrashCountdown] Alarm error: $e');
    }
  }

  Future<void> _stopAlarm() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  @override
  void dispose() {
    _stopAlarm();
    _player.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _cancel() {
    ref.read(sosStateProvider.notifier).cancelPreAlert();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final sosState = ref.watch(sosStateProvider);
    final seconds = sosState.countdownSeconds;
    final trigger = sosState.trigger;

    // Auto-dismiss when state moves to active or idle
    ref.listen(sosStateProvider, (prev, next) {
      if (next.status == SosStatus.active ||
          next.status == SosStatus.idle) {
        _stopAlarm();
        if (mounted) Navigator.of(context).pop();
      }
    });

    final triggerLabel = trigger == SosTrigger.manual
        ? 'Manual SOS activated'
        : 'Crash detected';

    return Scaffold(
      backgroundColor: const Color(0xFFB71C1C),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                triggerLabel.toUpperCase(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 32),
              // Countdown circle
              ScaleTransition(
                scale: _pulse,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white30, width: 4),
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$seconds',
                    style: const TextStyle(
                      fontSize: 96,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'SOS alert will be sent in $seconds seconds.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 15,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFB71C1C),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _cancel,
                  child: const Text(
                    'CANCEL — I\'m OK',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
