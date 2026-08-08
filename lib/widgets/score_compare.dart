import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/score_comparison.dart';
import '../theme/app_lux.dart';

/// Compact delta chip: icon + points (+9 / −4 / No change).
class ScoreDeltaChip extends StatelessWidget {
  const ScoreDeltaChip({
    super.key,
    required this.comparison,
    this.compact = false,
  });

  final ScoreComparison comparison;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = comparison.accentColor;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: comparison.softFill,
        borderRadius: BorderRadius.circular(AppLux.radiusPill),
        border: Border.all(
          color: c.withValues(alpha: comparison.unchanged ? 0.12 : 0.2),
          width: AppLux.borderWidth,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(comparison.trendIcon, size: compact ? 14 : 15, color: c),
          SizedBox(width: compact ? 4 : 5),
          Text(
            comparison.unchanged
                ? (compact ? 'Even' : 'No change')
                : '${comparison.pointsChip} pts',
            style: GoogleFonts.inter(
              fontSize: compact ? 11.5 : 12.5,
              fontWeight: FontWeight.w700,
              color: c,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Home score history: previous → latest, one calm delta line.
class ScoreHistoryPanel extends StatelessWidget {
  const ScoreHistoryPanel({
    super.key,
    required this.comparison,
    this.onOpenLatest,
    this.onOpenHistory,
  });

  final ScoreComparison comparison;
  final VoidCallback? onOpenLatest;
  final VoidCallback? onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final accent = comparison.accentColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpenHistory,
        borderRadius: BorderRadius.circular(AppLux.radius3xl),
        splashColor: AppLux.teal.withValues(alpha: 0.04),
        child: Ink(
          decoration: AppLux.card(radius: AppLux.radius3xl),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Score history',
                      style: GoogleFonts.inter(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppLux.charcoal,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const Spacer(),
                    ScoreDeltaChip(comparison: comparison, compact: true),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _ScoreSide(
                        label: comparison.fromLabel,
                        score: comparison.fromScore,
                        date: comparison.fromDateLabel,
                        emphasize: false,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                        color: accent.withValues(alpha: 0.75),
                      ),
                    ),
                    Expanded(
                      child: _ScoreSide(
                        label: comparison.toLabel,
                        score: comparison.toScore,
                        date: comparison.toDateLabel,
                        emphasize: true,
                        onTap: onOpenLatest,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  comparison.narrative,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: accent,
                    letterSpacing: -0.1,
                  ),
                ),
                if (onOpenHistory != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Tap for all reports',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: AppLux.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Report screen: this score vs last / latest — calm, no chart.
class ScoreCompareStrip extends StatelessWidget {
  const ScoreCompareStrip({
    super.key,
    required this.comparison,
    this.onOpenOther,
    this.otherActionLabel,
  });

  final ScoreComparison comparison;
  final VoidCallback? onOpenOther;
  final String? otherActionLabel;

  @override
  Widget build(BuildContext context) {
    final accent = comparison.accentColor;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppLux.surface,
        borderRadius: BorderRadius.circular(AppLux.radius2xl),
        border: Border.all(color: AppLux.border, width: AppLux.borderWidth),
        boxShadow: AppLux.cardShadow(intensity: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  comparison.headline,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppLux.muted,
                    letterSpacing: 0.05,
                  ),
                ),
              ),
              ScoreDeltaChip(comparison: comparison, compact: true),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _InlineScore(
                  label: comparison.fromLabel,
                  score: comparison.fromScore,
                  date: comparison.fromDateLabel,
                  muted: true,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: accent.withValues(alpha: 0.8),
                ),
              ),
              Expanded(
                child: _InlineScore(
                  label: comparison.toLabel,
                  score: comparison.toScore,
                  date: comparison.toDateLabel,
                  muted: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            comparison.narrative,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: accent,
              letterSpacing: -0.1,
            ),
          ),
          if (onOpenOther != null && otherActionLabel != null) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: onOpenOther,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    otherActionLabel!,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppLux.teal,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppLux.teal,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One-line delta for compact cards (home latest report).
class ScoreDeltaLine extends StatelessWidget {
  const ScoreDeltaLine({super.key, required this.comparison});

  final ScoreComparison comparison;

  @override
  Widget build(BuildContext context) {
    final c = comparison.accentColor;
    return Row(
      children: [
        Icon(comparison.trendIcon, size: 14, color: c),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            comparison.unchanged
                ? 'Unchanged vs last scan'
                : '${comparison.pointsLabel} vs last scan',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: c,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Private pieces ───────────────────────────────────────────────────────────

class _ScoreSide extends StatelessWidget {
  const _ScoreSide({
    required this.label,
    required this.score,
    required this.emphasize,
    this.date,
    this.onTap,
  });

  final String label;
  final int score;
  final String? date;
  final bool emphasize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: emphasize ? AppLux.tealMist : AppLux.cardFill,
        borderRadius: BorderRadius.circular(AppLux.radiusLg),
        border: Border.all(
          color: emphasize
              ? AppLux.teal.withValues(alpha: 0.18)
              : AppLux.border,
          width: AppLux.borderWidth,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: emphasize ? AppLux.tealDeep : AppLux.muted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$score',
            style: GoogleFonts.inter(
              fontSize: emphasize ? 28 : 24,
              fontWeight: FontWeight.w700,
              color: emphasize ? AppLux.tealDeep : AppLux.charcoal,
              height: 1,
              letterSpacing: -0.5,
            ),
          ),
          if (date != null) ...[
            const SizedBox(height: 5),
            Text(
              date!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppLux.body,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppLux.radiusLg),
        child: child,
      ),
    );
  }
}

class _InlineScore extends StatelessWidget {
  const _InlineScore({
    required this.label,
    required this.score,
    required this.muted,
    this.date,
  });

  final String label;
  final int score;
  final String? date;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: muted ? AppLux.cardFill : AppLux.tealMist,
        borderRadius: BorderRadius.circular(AppLux.radiusMd),
        border: Border.all(
          color: muted ? AppLux.border : AppLux.teal.withValues(alpha: 0.14),
          width: AppLux.borderWidth,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppLux.muted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$score',
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: muted ? AppLux.charcoal : AppLux.tealDeep,
              height: 1,
              letterSpacing: -0.4,
            ),
          ),
          if (date != null) ...[
            const SizedBox(height: 4),
            Text(
              date!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: AppLux.body,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
