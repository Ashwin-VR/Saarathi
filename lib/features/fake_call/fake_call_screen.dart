import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Full-screen fake incoming call UI.
/// "Answer" → transitions to an in-call screen with timer, waveform, mute & end-call.
class FakeCallScreen extends StatefulWidget {
  final String callerName;
  final String callerNumber;

  const FakeCallScreen({
    super.key,
    this.callerName = 'Mom',
    this.callerNumber = '+91 98765 43210',
  });

  @override
  State<FakeCallScreen> createState() => _FakeCallScreenState();
}

class _FakeCallScreenState extends State<FakeCallScreen>
    with TickerProviderStateMixin {
  late AnimationController _ringController;
  Timer? _autoDeclineTimer;
  int _ringsElapsed = 0;
  bool _answered = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    HapticFeedback.heavyImpact();

    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _autoDeclineTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && !_answered) _decline();
    });

    _ringController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _ringsElapsed++;
        if (_ringsElapsed % 3 == 0) HapticFeedback.mediumImpact();
      }
    });
  }

  @override
  void dispose() {
    _ringController.dispose();
    _autoDeclineTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _answer() {
    _ringController.stop();
    _autoDeclineTimer?.cancel();
    setState(() => _answered = true);
  }

  void _decline() {
    _ringController.stop();
    _autoDeclineTimer?.cancel();
    // Guard: the auto-decline timer can fire after the route has already been
    // removed from the navigator stack (e.g. user navigated away manually).
    // Calling pop() on an empty stack causes a black-screen crash.
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_answered) {
      return _InCallScreen(
        callerName: widget.callerName,
        callerNumber: widget.callerNumber,
        onEndCall: () {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        },
      );
    }

    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1A1A2E), Color(0xFF0D0D0D)],
              ),
            ),
          ),

          // Animated ring waves
          Center(
            child: AnimatedBuilder(
              animation: _ringController,
              builder: (_, __) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    for (int i = 0; i < 3; i++) _buildRingWave(i),
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF1565C0),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1565C0).withValues(alpha: 0.4),
                            blurRadius: 24,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          widget.callerName.isNotEmpty
                              ? widget.callerName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontSize: 46,
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // Top caller info
          Positioned(
            top: size.height * 0.12,
            left: 24,
            right: 24,
            child: Column(
              children: [
                const Text(
                  'incoming call',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.callerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.callerNumber,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),

          // Bottom action row
          Positioned(
            bottom: size.height * 0.1,
            left: 40,
            right: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _CallActionButton(
                  icon: Icons.call_end,
                  color: const Color(0xFFD32F2F),
                  label: 'Decline',
                  onPressed: _decline,
                ),
                _CallActionButton(
                  icon: Icons.call,
                  color: const Color(0xFF2E7D32),
                  label: 'Answer',
                  onPressed: _answer,
                ),
              ],
            ),
          ),

          Positioned(
            bottom: size.height * 0.06,
            left: 0,
            right: 0,
            child: const Center(
              child: Text(
                'Slide to answer',
                style: TextStyle(color: Colors.white30, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRingWave(int index) {
    final delay = index / 3.0;
    final value = ((_ringController.value + delay) % 1.0);
    final scale = 1.0 + value * 1.2;
    final opacity = (1.0 - value) * 0.4;
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFF1565C0).withValues(alpha: opacity),
            width: 2,
          ),
        ),
      ),
    );
  }
}

// ── In-call screen ────────────────────────────────────────────────────────────

class _InCallScreen extends StatefulWidget {
  final String callerName;
  final String callerNumber;
  final VoidCallback onEndCall;

  const _InCallScreen({
    required this.callerName,
    required this.callerNumber,
    required this.onEndCall,
  });

  @override
  State<_InCallScreen> createState() => _InCallScreenState();
}

class _InCallScreenState extends State<_InCallScreen>
    with SingleTickerProviderStateMixin {
  late Timer _callTimer;
  int _secondsElapsed = 0;
  bool _muted = false;
  bool _speakerOn = false;

  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _secondsElapsed++);
    });
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _callTimer.cancel();
    _waveController.dispose();
    super.dispose();
  }

  String get _timerLabel {
    final m = (_secondsElapsed ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsElapsed % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),

            // Caller info
            Text(
              widget.callerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.callerNumber,
              style: const TextStyle(color: Colors.white54, fontSize: 15),
            ),
            const SizedBox(height: 12),
            Text(
              _timerLabel,
              style: const TextStyle(
                color: Color(0xFF4CAF50),
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 40),

            // Avatar
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1565C0),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1565C0).withValues(alpha: 0.4),
                    blurRadius: 24,
                    spreadRadius: 6,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  widget.callerName.isNotEmpty
                      ? widget.callerName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    fontSize: 42,
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 36),

            // Waveform
            AnimatedBuilder(
              animation: _waveController,
              builder: (_, __) => _buildWaveform(),
            ),
            const SizedBox(height: 40),

            // Controls row (mute, speaker)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _InCallControl(
                  icon: _muted ? Icons.mic_off : Icons.mic,
                  label: _muted ? 'Unmute' : 'Mute',
                  active: _muted,
                  onTap: () => setState(() => _muted = !_muted),
                ),
                const SizedBox(width: 32),
                _InCallControl(
                  icon: _speakerOn ? Icons.volume_up : Icons.volume_down,
                  label: 'Speaker',
                  active: _speakerOn,
                  onTap: () => setState(() => _speakerOn = !_speakerOn),
                ),
                const SizedBox(width: 32),
                _InCallControl(
                  icon: Icons.dialpad,
                  label: 'Keypad',
                  active: false,
                  onTap: () {},
                ),
              ],
            ),
            const Spacer(),

            // End call button
            GestureDetector(
              onTap: () {
                HapticFeedback.heavyImpact();
                widget.onEndCall();
              },
              child: Container(
                width: 72,
                height: 72,
                margin: const EdgeInsets.only(bottom: 40),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFD32F2F),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFD32F2F).withValues(alpha: 0.5),
                      blurRadius: 20,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(Icons.call_end, color: Colors.white, size: 32),
              ),
            ),
            const Text(
              'End Call',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildWaveform() {
    final rng = Random(42);
    final bars = List.generate(28, (i) {
      final base = rng.nextDouble() * 0.5 + 0.2;
      final anim = (_waveController.value + i / 28.0) % 1.0;
      final height = base + sin(anim * pi * 2) * 0.25;
      return height.clamp(0.1, 1.0);
    });

    return SizedBox(
      height: 48,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: bars.map((h) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 4,
            height: 48 * h,
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _InCallControl extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _InCallControl({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? const Color(0xFF2196F3).withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.08),
              border: Border.all(
                color: active
                    ? const Color(0xFF2196F3)
                    : Colors.white.withValues(alpha: 0.15),
                width: 1.5,
              ),
            ),
            child: Icon(
              icon,
              color: active ? const Color(0xFF2196F3) : Colors.white70,
              size: 26,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onPressed;

  const _CallActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onPressed,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    );
  }
}
