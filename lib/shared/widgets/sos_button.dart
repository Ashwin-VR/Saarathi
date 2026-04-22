import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// SOS button with press-and-hold (1.5 s) circular progress indicator.
/// - Hold 1.5 s → trigger (onPressed callback fires)
/// - Release before 1.5 s → cancels
/// - Long-press alternative via [onLongPress] (bottom-sheet)
class SosButton extends StatefulWidget {
  final bool isActive;
  final bool isPreAlert;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;

  const SosButton({
    super.key,
    required this.isActive,
    this.isPreAlert = false,
    required this.onPressed,
    this.onLongPress,
  });

  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton>
    with TickerProviderStateMixin {
  // ── Pulse animation (when active / pre-alert) ─────────────────────────────
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // ── Hold-to-trigger progress ──────────────────────────────────────────────
  static const Duration _holdDuration = Duration(milliseconds: 1500);
  late AnimationController _holdController;
  bool _holding = false;
  Timer? _triggerTimer;

  @override
  void initState() {
    super.initState();

    // Pulse animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.30).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (widget.isActive || widget.isPreAlert) {
      _pulseController.repeat(reverse: true);
    }

    // Hold-progress animation
    _holdController = AnimationController(
      vsync: this,
      duration: _holdDuration,
    );
  }

  @override
  void didUpdateWidget(SosButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shouldPulse = widget.isActive || widget.isPreAlert;
    final wasPulsing = oldWidget.isActive || oldWidget.isPreAlert;

    if (shouldPulse && !wasPulsing) {
      _pulseController.repeat(reverse: true);
    } else if (!shouldPulse && wasPulsing) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _holdController.dispose();
    _triggerTimer?.cancel();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    // Active / pre-alert: single tap is enough (cancel/sheet)
    if (widget.isActive || widget.isPreAlert) return;

    setState(() => _holding = true);
    _holdController.forward(from: 0);
    HapticFeedback.lightImpact();

    _triggerTimer = Timer(_holdDuration, () {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      // Let the ring complete visually (reach 1.0) before resetting.
      Future.microtask(() {
        if (!mounted) return;
        _resetHold();
        widget.onPressed();
      });
    });
  }

  void _onTapUp(TapUpDetails _) {
    if (widget.isActive || widget.isPreAlert) {
      HapticFeedback.heavyImpact();
      widget.onPressed();
      return;
    }
    _resetHold();
  }

  void _onTapCancel() {
    _resetHold();
  }

  void _resetHold() {
    _triggerTimer?.cancel();
    _triggerTimer = null;
    if (!mounted) return;
    setState(() => _holding = false);
    _holdController.stop();
    _holdController.reset();
  }

  Color get _buttonColor {
    if (widget.isActive) return const Color(0xFF7B0000);
    if (widget.isPreAlert) return const Color(0xFFE65100);
    return const Color(0xFFD32F2F);
  }

  Color get _glowColor {
    if (widget.isActive) return const Color(0xFFD32F2F);
    if (widget.isPreAlert) return const Color(0xFFFF6F00);
    return const Color(0xFFD32F2F);
  }

  IconData get _icon {
    if (widget.isActive) return Icons.cancel_outlined;
    if (widget.isPreAlert) return Icons.warning_amber_rounded;
    return Icons.sos;
  }

  String get _label {
    if (widget.isActive) return 'CANCEL';
    if (widget.isPreAlert) return 'SOS!';
    if (_holding) return 'HOLD…';
    return 'SOS';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onLongPress: () {
        _resetHold();
        HapticFeedback.heavyImpact();
        widget.onLongPress?.call();
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseAnimation, _holdController]),
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              // Outer pulsing halo (active / pre-alert)
              if (widget.isActive || widget.isPreAlert)
                Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _glowColor.withValues(alpha: 0.25),
                    ),
                  ),
                ),
              if (widget.isActive || widget.isPreAlert)
                Transform.scale(
                  scale: (_pulseAnimation.value - 1) * 0.5 + 1,
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _glowColor.withValues(alpha: 0.15),
                    ),
                  ),
                ),

              // Hold progress ring (idle state only)
              if (_holding && !widget.isActive && !widget.isPreAlert)
                SizedBox(
                  width: 86,
                  height: 86,
                  child: CustomPaint(
                    painter: _HoldRingPainter(
                      progress: _holdController.value,
                      color: _glowColor,
                    ),
                  ),
                ),

              // Main button body
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _buttonColor,
                  boxShadow: [
                    BoxShadow(
                      color: _glowColor.withValues(alpha: 0.55),
                      blurRadius: 20,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_icon, color: Colors.white, size: 28),
                    Text(
                      _label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Custom ring painter for the hold-to-trigger progress arc.
/// Always starts at the top (-90°) and sweeps clockwise to 360°.
class _HoldRingPainter extends CustomPainter {
  final double progress; // 0.0 → 1.0
  final Color color;

  const _HoldRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 6) / 2; // 3 px padding each side

    // Background track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withOpacity(0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );

    // Foreground arc (0° = top, sweeps clockwise)
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,           // start at the top
        2 * math.pi * progress, // sweep proportional to hold time
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_HoldRingPainter old) =>
      old.progress != progress || old.color != color;
}
