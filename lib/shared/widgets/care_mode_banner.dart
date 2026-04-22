import 'package:flutter/material.dart';
import 'package:accident_app/shared/services/care_mode_service.dart';

/// Persistent banner displayed at the top of the home screen showing the
/// Care Mode countdown timer and wellness-check status.
class CareModeBanner extends StatelessWidget {
  final CareModeState state;
  final VoidCallback onConfirmSafe;
  final VoidCallback onStop;

  const CareModeBanner({
    super.key,
    required this.state,
    required this.onConfirmSafe,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final isCheckPending = state.status == CareModeStatus.checkPending;
    final missedBadge    = state.missedChecks > 0;

    final bgColor = isCheckPending
        ? const Color(0xFFE65100)
        : const Color(0xFF1565C0);

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(16),
      elevation: 6,
      shadowColor: bgColor.withValues(alpha: 0.45),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // ── Icon ─────────────────────────────────────────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Icon(
                isCheckPending
                    ? Icons.warning_amber_rounded
                    : Icons.health_and_safety,
                key: ValueKey(isCheckPending),
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),

            // ── Info ─────────────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        isCheckPending
                            ? 'Wellness Check!'
                            : 'Care Mode',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          letterSpacing: 0.3,
                        ),
                      ),
                      if (missedBadge) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${state.missedChecks} missed',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (!isCheckPending)
                    _TimerRow(
                      display: state.timerDisplay,
                      progress: state.timerProgress,
                      intervalMinutes: state.intervalMinutes,
                    )
                  else
                    const Text(
                      'Tap to confirm you\'re safe',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // ── Action buttons ────────────────────────────────────────────────
            if (isCheckPending)
              _ActionBtn(
                label: 'I\'m Safe',
                icon: Icons.check_circle_outline,
                onTap: onConfirmSafe,
              )
            else
              _ActionBtn(
                label: 'Stop',
                icon: Icons.stop_circle_outlined,
                onTap: onStop,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Timer display row ─────────────────────────────────────────────────────────

class _TimerRow extends StatelessWidget {
  final String display;
  final double progress;
  final int intervalMinutes;

  const _TimerRow({
    required this.display,
    required this.progress,
    required this.intervalMinutes,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Circular mini progress
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 2.5,
            backgroundColor: Colors.white.withValues(alpha: 0.25),
            valueColor:
                const AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          '$display / ${intervalMinutes.toString().padLeft(2, '0')}:00',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ── Small inline action button ────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.35), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
