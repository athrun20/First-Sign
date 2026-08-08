import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/capture_models.dart';
import '../services/capture_assistant_service.dart';
import '../theme/app_lux.dart';

/// Live coach panel for guided capture: tips, quality feedback, suggestions.
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
    // Prefer fresh post-capture flash, else coach for current slot.
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
      decoration: AppLux.card(radius: AppLux.radius2xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppLux.teal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    size: 18,
                    color: AppLux.teal,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Smart Capture Assistant',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppLux.charcoal,
                          letterSpacing: -0.2,
                        ),
                      ),
                      Text(
                        widget.filled
                            ? 'Quality check · ${widget.shot.shortLabel}'
                            : 'Live tips · ${widget.shot.shortLabel}',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: AppLux.body,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: widget.filled
                        ? AppLux.teal.withValues(alpha: 0.12)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    widget.filled
                        ? 'Done'
                        : '${widget.shotNumber}/${widget.totalShots}',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: widget.filled
                          ? AppLux.teal
                          : AppLux.body,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Main advice (quality feedback) — extra air for a calmer read
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
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

          // Rotating live tip
          if (tip != null && !widget.filled) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Material(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: tips.length > 1 ? _nextTip : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.lightbulb_outline_rounded,
                          size: 18,
                          color: Color(0xFFD97706),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: Text(
                              tip,
                              key: ValueKey(tip),
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                height: 1.35,
                                color: AppLux.charcoal,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        if (tips.length > 1)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.touch_app_outlined,
                              size: 16,
                              color: AppLux.muted.withValues(alpha: 0.8),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],

          // Quick tip chips when empty
          if (!widget.filled && advice.quickTips.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in advice.quickTips.take(3))
                    _MiniChip(label: t, compact: true),
                ],
              ),
            ),

          // Session suggestion
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.tips_and_updates_outlined,
                  size: 16,
                  color: AppLux.charcoal.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.sessionSuggestion,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      height: 1.35,
                      color: AppLux.body,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Capture actions — Retake/Camera primary; Replace/Gallery soft secondary
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Row(
              children: [
                Expanded(
                  flex: 6,
                  child: FilledButton.icon(
                    onPressed: widget.onCamera,
                    icon: const Icon(Icons.photo_camera_rounded, size: 18),
                    label: Text(widget.filled ? 'Retake' : 'Camera'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppLux.teal,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppLux.radiusMd),
                      ),
                      textStyle: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 5,
                  child: OutlinedButton.icon(
                    onPressed: widget.onGallery,
                    icon: Icon(
                      Icons.photo_library_outlined,
                      size: 17,
                      color: AppLux.muted.withValues(alpha: 0.95),
                    ),
                    label: Text(widget.filled ? 'Replace' : 'Gallery'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppLux.body,
                      backgroundColor: AppLux.cardFill,
                      side: BorderSide(
                        color: AppLux.border.withValues(alpha: 0.95),
                        width: 0.85,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppLux.radiusMd),
                      ),
                      textStyle: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        letterSpacing: 0.05,
                      ),
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(advice.icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        advice.headline,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppLux.charcoal,
                          letterSpacing: -0.2,
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
                  const SizedBox(height: 5),
                  Text(
                    badge!,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
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
                  ),
                ),
                if (advice.quickTips.isNotEmpty &&
                    (advice.tone == AssistantTone.warning ||
                        advice.tone == AssistantTone.caution)) ...[
                  const SizedBox(height: 8),
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
                                color: AppLux.charcoal,
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
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$score',
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, this.compact = false});
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = compact && label.length > 42
        ? '${label.substring(0, 40)}…'
        : label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppLux.border),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: AppLux.body,
        ),
      ),
    );
  }
}
