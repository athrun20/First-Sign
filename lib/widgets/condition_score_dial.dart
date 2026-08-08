import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_lux.dart';

/// Good / Fair / Needs Attention from overall score bands used across the app.
String conditionStatusFromScore(int score) {
  if (score >= 85) return 'Good';
  if (score >= 70) return 'Fair';
  return 'Needs Attention';
}

/// Score-band accent: teal ≥85 · warm fair 70–84 · danger &lt;70.
Color conditionStatusColor(int score) {
  if (score >= 85) return AppLux.teal;
  if (score >= 70) return AppLux.warning;
  return AppLux.danger;
}

/// Circular condition gauge — ring + segmented dots + soft glow.
///
/// Mount only when a **real** report score exists (never a placeholder).
class ConditionScoreDial extends StatefulWidget {
  const ConditionScoreDial({
    super.key,
    required this.score,
    this.accent,
    this.size = 196,
  });

  /// Latest report overall score (0–100). Always real data.
  final int score;

  /// Defaults to [conditionStatusColor] for [score].
  final Color? accent;

  final double size;

  @override
  State<ConditionScoreDial> createState() => _ConditionScoreDialState();
}

class _ConditionScoreDialState extends State<ConditionScoreDial>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowPulse;
  double _fromProgress = 0;

  @override
  void initState() {
    super.initState();
    _glowPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    unawaited(_glowPulse.repeat(reverse: true));
  }

  @override
  void didUpdateWidget(covariant ConditionScoreDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.score != widget.score) {
      _fromProgress = oldWidget.score.clamp(0, 100) / 100.0;
    }
  }

  @override
  void dispose() {
    _glowPulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final score = widget.score;
    final accent = widget.accent ?? conditionStatusColor(score);
    final value = score.clamp(0, 100) / 100.0;

    final label = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$score',
            style: GoogleFonts.inter(
              fontSize: widget.size >= 180 ? 46 : 40,
              fontWeight: FontWeight.w700,
              color: AppLux.charcoal,
              height: 1,
              letterSpacing: -1.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Condition',
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: AppLux.muted,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: _fromProgress, end: value),
      duration: const Duration(milliseconds: 1280),
      curve: Curves.easeOutCubic,
      onEnd: () {
        _fromProgress = value;
      },
      builder: (context, animated, child) {
        return AnimatedBuilder(
          animation: _glowPulse,
          builder: (context, _) {
            final glow = Curves.easeInOut.transform(_glowPulse.value);
            return SizedBox(
              width: widget.size,
              height: widget.size,
              child: CustomPaint(
                painter: _ConditionScoreDialPainter(
                  progress: animated,
                  accent: accent,
                  glow: glow,
                ),
                child: child,
              ),
            );
          },
          child: child,
        );
      },
      child: label,
    );
  }
}

class _ConditionScoreDialPainter extends CustomPainter {
  _ConditionScoreDialPainter({
    required this.progress,
    required this.accent,
    required this.glow,
  });

  final double progress;
  final Color accent;
  final double glow;

  static const int _dotCount = 48;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final p = progress.clamp(0.0, 1.0);
    final g = glow.clamp(0.0, 1.0);

    final maxR = size.width / 2;
    final dotRadius = size.width * 0.0135;
    final dotsR = maxR - dotRadius - 2;
    final stroke = size.width * 0.058;
    final arcR = dotsR - dotRadius * 2.8 - stroke * 0.5;

    final lit = p * _dotCount;
    final inactivePaint = Paint()
      ..color = AppLux.muted.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;
    final activePaint = Paint()..style = PaintingStyle.fill;
    final glowPaint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.8 + 1.4 * g);

    for (var i = 0; i < _dotCount; i++) {
      final angle = -math.pi / 2 + (2 * math.pi * i / _dotCount);
      final pos = Offset(
        center.dx + dotsR * math.cos(angle),
        center.dy + dotsR * math.sin(angle),
      );

      final t = lit - i;
      if (t <= 0) {
        canvas.drawCircle(pos, dotRadius * 0.88, inactivePaint);
      } else {
        final strength = t >= 1 ? 1.0 : Curves.easeOut.transform(t);
        final r = dotRadius * (0.88 + 0.18 * strength);
        activePaint.color = Color.lerp(
          AppLux.muted.withValues(alpha: 0.22),
          accent,
          strength,
        )!;

        if (strength > 0.35) {
          final bloom = strength * (0.55 + 0.45 * g);
          glowPaint.color = accent.withValues(alpha: 0.10 + 0.14 * bloom);
          canvas.drawCircle(
            pos,
            r * (1.9 + 0.55 * g * strength),
            glowPaint,
          );
        }

        canvas.drawCircle(pos, r, activePaint);
      }
    }

    final haloPaint = Paint()
      ..color = accent.withValues(alpha: 0.045 + 0.035 * g * p)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke + 12 + 3 * g * p
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    canvas.drawCircle(center, arcR, haloPaint);

    final trackPaint = Paint()
      ..color = AppLux.border.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, arcR, trackPaint);

    final discPaint = Paint()
      ..color = AppLux.cardFill.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, arcR - stroke * 0.9, discPaint);

    if (p <= 0.001) return;

    final rect = Rect.fromCircle(center: center, radius: arcR);
    const start = -math.pi / 2;
    final sweep = 2 * math.pi * p;

    final arcGlow = Paint()
      ..color = accent.withValues(alpha: 0.08 + 0.07 * g)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke + 5 + 3 * g
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 + 2 * g);
    canvas.drawArc(rect, start, sweep, false, arcGlow);

    final progressPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          Color.lerp(accent, Colors.white, 0.2)!,
          accent,
          Color.lerp(accent, AppLux.charcoal, 0.1)!,
        ],
        stops: const [0.0, 0.48, 1.0],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep, false, progressPaint);
  }

  @override
  bool shouldRepaint(covariant _ConditionScoreDialPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.accent != accent ||
        oldDelegate.glow != glow;
  }
}
