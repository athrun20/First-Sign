import 'package:flutter/material.dart';

import '../theme/app_lux.dart';
import 'saved_report.dart';

/// Direction of a score change between two scans.
enum ScoreTrend { improved, declined, unchanged }

/// Pure comparison between two exterior condition scores.
///
/// [fromScore] is the baseline (older / other scan).
/// [toScore] is the focus score (newer, or the one the user is viewing).
class ScoreComparison {
  const ScoreComparison({
    required this.fromScore,
    required this.toScore,
    required this.fromLabel,
    required this.toLabel,
    this.fromDateLabel,
    this.toDateLabel,
    this.headline = 'Score change',
  });

  final int fromScore;
  final int toScore;
  final String fromLabel;
  final String toLabel;
  final String? fromDateLabel;
  final String? toDateLabel;

  /// Short header, e.g. "Compared to last scan".
  final String headline;

  int get delta => toScore - fromScore;
  int get absDelta => delta.abs();

  ScoreTrend get trend {
    if (delta > 0) return ScoreTrend.improved;
    if (delta < 0) return ScoreTrend.declined;
    return ScoreTrend.unchanged;
  }

  bool get improved => trend == ScoreTrend.improved;
  bool get declined => trend == ScoreTrend.declined;
  bool get unchanged => trend == ScoreTrend.unchanged;

  /// Signed points chip: `+9`, `−4`, `0`.
  String get pointsChip {
    if (unchanged) return '0';
    if (improved) return '+$delta';
    return '−$absDelta';
  }

  /// Compact: `+9 pts`, `−4 pts`, `No change`.
  String get pointsLabel {
    if (unchanged) return 'No change';
    if (improved) return '+$delta pts';
    return '−$absDelta pts';
  }

  /// Full narrative for cards.
  String get narrative {
    if (unchanged) return 'Score unchanged';
    final unit = absDelta == 1 ? 'point' : 'points';
    if (improved) return 'Improved by $absDelta $unit';
    return 'Down $absDelta $unit';
  }

  /// Direction word for accessibility / captions.
  String get directionWord {
    switch (trend) {
      case ScoreTrend.improved:
        return 'improved';
      case ScoreTrend.declined:
        return 'declined';
      case ScoreTrend.unchanged:
        return 'unchanged';
    }
  }

  Color get accentColor {
    switch (trend) {
      case ScoreTrend.improved:
        return AppLux.teal;
      case ScoreTrend.declined:
        return AppLux.danger;
      case ScoreTrend.unchanged:
        return AppLux.body;
    }
  }

  Color get softFill {
    switch (trend) {
      case ScoreTrend.improved:
        return AppLux.tealMist;
      case ScoreTrend.declined:
        return AppLux.dangerSoft;
      case ScoreTrend.unchanged:
        return AppLux.cardFill;
    }
  }

  IconData get trendIcon {
    switch (trend) {
      case ScoreTrend.improved:
        return Icons.trending_up_rounded;
      case ScoreTrend.declined:
        return Icons.trending_down_rounded;
      case ScoreTrend.unchanged:
        return Icons.horizontal_rule_rounded;
    }
  }

  /// Latest vs previous scan (home / newest report).
  factory ScoreComparison.latestVsPrevious({
    required SavedReport latest,
    required SavedReport previous,
  }) {
    return ScoreComparison(
      fromScore: previous.score,
      toScore: latest.score,
      fromLabel: 'Previous',
      toLabel: 'Latest',
      fromDateLabel: previous.relativeDateLabel,
      toDateLabel: latest.relativeDateLabel,
      headline: 'Compared to last scan',
    );
  }

  /// Viewing a past report — anchor against the most recent scan.
  factory ScoreComparison.pastVsLatest({
    required SavedReport past,
    required SavedReport latest,
  }) {
    return ScoreComparison(
      fromScore: past.score,
      toScore: latest.score,
      fromLabel: 'This report',
      toLabel: 'Latest scan',
      fromDateLabel: past.relativeDateLabel,
      toDateLabel: latest.relativeDateLabel,
      headline: 'Compared to latest scan',
    );
  }

  /// Resolve a useful comparison for [reportId], or null if none.
  ///
  /// Read-only over existing [reports] — does not touch storage.
  static ScoreComparison? forSavedReport({
    required String reportId,
    required List<SavedReport> reports,
    int? liveScore,
  }) {
    if (reports.length < 2) return null;
    final latest = reports.first;
    final idx = reports.indexWhere((r) => r.id == reportId);
    if (idx < 0) return null;

    if (idx == 0) {
      final previous = reports[1];
      final score = liveScore ?? latest.score;
      return ScoreComparison(
        fromScore: previous.score,
        toScore: score,
        fromLabel: 'Last scan',
        toLabel: 'This report',
        fromDateLabel: previous.relativeDateLabel,
        toDateLabel: 'Latest',
        headline: 'Compared to last scan',
      );
    }

    final past = reports[idx];
    final score = liveScore ?? past.score;
    return ScoreComparison(
      fromScore: score,
      toScore: latest.score,
      fromLabel: 'This report',
      toLabel: 'Latest scan',
      fromDateLabel: past.relativeDateLabel,
      toDateLabel: latest.relativeDateLabel,
      headline: 'Compared to latest scan',
    );
  }
}
