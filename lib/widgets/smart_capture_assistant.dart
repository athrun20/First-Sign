import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/capture_models.dart';
import '../services/capture_assistant_service.dart';
import '../theme/app_lux.dart';

/// Live coach panel for guided capture — calm, singular, luxury.
///
/// Hierarchy: shot goal → one tip → capture actions.
/// No redundant tip chips or repeated session copy.
class SmartCaptureAssistant extends StatefulWidget {
  const SmartCaptureAssistant({
    super.key,
    required this.shot,
    required this.shotNumber,
    required this.totalShots,
    required this.filled,
    required this.sessionSuggestion,
    this.quality,
    this.acceptedWithWarnings = false,
    this.flashFeedback,
    this.onCamera,
    this.onGallery,
  });

  final CaptureShotDef shot;
  final int shotNumber;
  final int totalShots;
  final bool filled;
  final String sessionSuggestion;
  final PhotoQualityResult? quality;
  final bool acceptedWithWarnings;

  /// Short-lived message after a capture (e.g. quality result).
  final AssistantAdvice? flashFeedback;

  final VoidCallback? onCamera;
  final VoidCallback? onGallery;

  @override
  State<SmartCaptureAssistant> createState() => _SmartCaptureAssistantState();
}

class _SmartCaptureAssistantState extends State<SmartCaptureAssistant> {
  int _tipIndex = 0;

  @override
  void didUpdateWidget(covariant SmartCaptureAssistant oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shot.id != widget.shot.id) {
      _tipIndex = 0;
    }
  }

  AssistantAdvice get _advice {
    final flash = widget.flashFeedback;
    if (flash != null) return flash;
    return CaptureAssistantService.adviceForShot(
      widget.shot,
      filled: widget.filled,
      quality: widget.quality,
      acceptedWithWarnings: widget.acceptedWithWarnings,
    );
  }

  List<String> get _rotatingTips {
    final tips = CaptureAssistantService.quickTipsFor(widget.shot.id);
    if (tips.isEmpty) return const [];
    return tips;
  }

  void _nextTip() {
    final tips = _rotatingTips;
    if (tips.length < 2) return;
    setState(() => _tipIndex = (_tipIndex + 1) % tips.length);
  }

  /// Session strip only after progress — avoids “front elevation” twice on shot 1.
  bool get _showSessionNote {
    if (widget.sessionSuggestion.trim().isEmpty) return false;
    if (widget.filled) return true;
    return widget.shotNumber > 1;
  }

  @override
  Widget build(BuildContext context) {
    final advice = _advice;
    final tips = _rotatingTips;
    final tip = tips.isEmpty ? null : tips[_tipIndex % tips.length];
    final score = widget.quality != null
        ? CaptureAssistantService.qualityScore(widget.quality!)
        : null;
    final badge = widget.quality != null
        ? CaptureAssistantService.qualityBadge(
            widget.quality,
            accepted: widget.acceptedWithWarnings || widget.filled,
          )
        : null;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppLux.surface,
        borderRadius: BorderRadius.circular(AppLux.radiusHero),
        border: Border.all(color: AppLux.border, width: AppLux.borderWidth),
        boxShadow: AppLux.softShadow(intensity: 0.85),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 16, 0),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppLux.tealMist,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: AppLux.teal.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 15,
                    color: AppLux.tealDeep.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Capture coach',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppLux.charcoal,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        widget.filled
                            ? 'Quality · ${widget.shot.shortLabel}'
                            : '${widget.shot.shortLabel} · shot ${widget.shotNumber} of ${widget.totalShots}',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: AppLux.muted,
                          letterSpacing: -0.05,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.filled)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppLux.teal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Done',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppLux.tealDeep,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Primary shot goal / quality feedback ──────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _AdviceBlock(
                key: ValueKey(
                  '${widget.shot.id}-${advice.headline}-${advice.tone}-'
                  '${widget.quality?.summary ?? ''}',
                ),
                advice: advice,
                score: widget.filled ? score : null,
                badge: widget.filled ? badge : null,
              ),
            ),
          ),

          // ── Single rotating tip (no chips) ────────────────────────────
          if (tip != null && !widget.filled)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 16, 0),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: tips.length > 1 ? _nextTip : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.lightbulb_outline_rounded,
                          size: 16,
                          color: AppLux.gold.withValues(alpha: 0.85),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Text(
                              tip,
                              key: ValueKey(tip),
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                height: 1.4,
                                color: AppLux.charcoalMid,
                                fontWeight: FontWeight.w500,
                                letterSpacing: -0.1,
                              ),
                            ),
                          ),
                        ),
                        if (tips.length > 1) ...[
                          const SizedBox(width: 6),
                          Text(
                            'Tip ${_tipIndex + 1}/${tips.length}',
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AppLux.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── Session note (progress only — not first empty shot) ────────
          if (_showSessionNote)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: Text(
                widget.sessionSuggestion,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  height: 1.4,
                  color: AppLux.muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

          // ── Actions ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Row(
              children: [
                Expanded(
                  flex: 6,
                  child: SizedBox(
                    height: 50,
                    child: FilledButton(
                      onPressed: widget.onCamera,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppLux.tealDeep,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          letterSpacing: -0.15,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            widget.filled
                                ? Icons.refresh_rounded
                                : Icons.photo_camera_rounded,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(widget.filled ? 'Retake' : 'Camera'),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 5,
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      onPressed: widget.onGallery,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppLux.charcoalMid,
                        backgroundColor: AppLux.cardFill,
                        side: BorderSide(
                          color: AppLux.border.withValues(alpha: 0.95),
                          width: 0.85,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                          letterSpacing: -0.05,
                        ),
                      ),
                      child: Text(widget.filled ? 'Replace' : 'Gallery'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdviceBlock extends StatelessWidget {
  const _AdviceBlock({super.key, required this.advice, this.score, this.badge});

  final AssistantAdvice advice;
  final int? score;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final color = advice.accentColor;
    final isTip = advice.tone == AssistantTone.tip;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: isTip
            ? AppLux.tealMist.withValues(alpha: 0.65)
            : color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isTip
              ? AppLux.teal.withValues(alpha: 0.12)
              : color.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isTip
                  ? AppLux.surface.withValues(alpha: 0.9)
                  : color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              advice.icon,
              size: 19,
              color: isTip ? AppLux.tealDeep : color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        advice.headline,
                        style: GoogleFonts.inter(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: AppLux.charcoal,
                          letterSpacing: -0.25,
                          height: 1.2,
                        ),
                      ),
                    ),
                    if (score != null) ...[
                      const SizedBox(width: 8),
                      _ScorePill(score: score!, color: color),
                    ],
                  ],
                ),
                if (badge != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    badge!,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  advice.body,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    height: 1.45,
                    color: AppLux.body,
                    fontWeight: FontWeight.w400,
                    letterSpacing: -0.05,
                  ),
                ),
                // Only list fix tips when quality is weak — not for empty slots.
                if (advice.quickTips.isNotEmpty &&
                    (advice.tone == AssistantTone.warning ||
                        advice.tone == AssistantTone.caution)) ...[
                  const SizedBox(height: 10),
                  for (final t in advice.quickTips.take(2))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '→  ',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              t,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                height: 1.35,
                                color: AppLux.charcoalMid,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.score, required this.color});
  final int score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$score',
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
