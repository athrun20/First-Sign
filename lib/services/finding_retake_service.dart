import '../models/analysis_models.dart';
import '../models/capture_models.dart';

/// Maps a screening finding to the best guided shot to retake, and summarizes
/// how a re-analysis changed that finding.
class FindingRetakeService {
  FindingRetakeService._();

  /// Preferred checklist slot for a closer / replacement shot.
  static CaptureShotId preferredSlot(
    AnalysisIssue issue, {
    CapturePhoto? boundPhoto,
  }) {
    final boundSlot = boundPhoto?.slotId;
    if (boundSlot != null) {
      // Prefer problem close-up when the bound shot was already a full elevation
      // and evidence is weak — closer frames raise confidence fastest.
      if (issue.needsCloserPhoto &&
          boundSlot != CaptureShotId.problemCloseup &&
          boundSlot != CaptureShotId.roof) {
        return CaptureShotId.problemCloseup;
      }
      return boundSlot;
    }

    final key = '${issue.title} ${issue.location} ${issue.sourcePhotoLabel}'
        .toLowerCase();

    if (key.contains('roof') ||
        key.contains('shingle') ||
        key.contains('ridge') ||
        key.contains('granule') ||
        key.contains('asphalt')) {
      return issue.needsCloserPhoto
          ? CaptureShotId.problemCloseup
          : CaptureShotId.roof;
    }
    // Ground outlets / wet soil → grade-level retake, not roof eave.
    if (key.contains('dumping near foundation') ||
        key.contains('soil at grade') ||
        key.contains('ground outlets') ||
        (key.contains('downspout') &&
            (key.contains('outlet') ||
                key.contains('foundation') ||
                key.contains('grade')) &&
            !key.contains('eave') &&
            !key.contains('overflow'))) {
      return CaptureShotId.problemCloseup;
    }
    if (key.contains('gutter') ||
        key.contains('eave') ||
        key.contains('fascia') ||
        key.contains('downspout') ||
        key.contains('overflow')) {
      return CaptureShotId.roof;
    }
    if (key.contains('foundation') ||
        key.contains('settlement') ||
        key.contains('grade') ||
        key.contains('base')) {
      return CaptureShotId.problemCloseup;
    }
    if (key.contains('paint') ||
        key.contains('peel') ||
        key.contains('siding') ||
        key.contains('cladding') ||
        key.contains('crack') ||
        key.contains('masonry') ||
        key.contains('brick')) {
      return CaptureShotId.problemCloseup;
    }
    if (key.contains('window') || key.contains('seal')) {
      return CaptureShotId.front;
    }
    if (key.contains('chimney') || key.contains('flash')) {
      return CaptureShotId.roof;
    }
    return CaptureShotId.problemCloseup;
  }

  /// Human label for the retake banner.
  static String slotCoachLabel(CaptureShotId slot) {
    for (final def in kGuidedShotChecklist) {
      if (def.id == slot) return def.title;
    }
    return 'this area';
  }

  /// Short summary of score + matched finding change after re-analysis.
  static String changeSummary({
    required AnalysisReport before,
    required AnalysisReport after,
    required AnalysisIssue previousIssue,
  }) {
    final scoreDelta = after.overallScore - before.overallScore;
    final scorePart = scoreDelta == 0
        ? 'Score stayed ${after.overallScore}'
        : scoreDelta > 0
        ? 'Score improved ${before.overallScore} → ${after.overallScore} (+$scoreDelta)'
        : 'Score ${before.overallScore} → ${after.overallScore} ($scoreDelta)';

    final next = matchFinding(previousIssue, after.issues);
    if (next == null) {
      return '$scorePart. “${previousIssue.storyTitle}” is no longer listed — re-check or confirm on-site.';
    }

    final confDelta = next.confidence - previousIssue.confidence;
    final confPart = confDelta == 0
        ? 'confidence ${next.confidence}%'
        : confDelta > 0
        ? 'confidence ${previousIssue.confidence}% → ${next.confidence}%'
        : 'confidence ${previousIssue.confidence}% → ${next.confidence}%';

    final sevPart = next.severity == previousIssue.severity
        ? 'still ${next.severity}'
        : '${previousIssue.severity} → ${next.severity}';

    final closer = previousIssue.needsCloserPhoto && !next.needsCloserPhoto
        ? ' Closer photo cleared the “needs closer” flag.'
        : next.needsCloserPhoto
        ? ' Still flagged for a closer shot if you can.'
        : '';

    return '$scorePart. “${next.storyTitle}” is $sevPart ($confPart).$closer';
  }

  /// Best matching issue in a new report for a prior finding.
  static AnalysisIssue? matchFinding(
    AnalysisIssue previous,
    List<AnalysisIssue> nextIssues,
  ) {
    if (nextIssues.isEmpty) return null;

    final prevTokens = _tokens(previous);
    AnalysisIssue? best;
    var bestScore = -1;

    for (final issue in nextIssues) {
      final tokens = _tokens(issue);
      var hit = 0;
      for (final t in prevTokens) {
        if (tokens.contains(t)) hit++;
      }
      // Prefer title token overlap, then severity rank proximity.
      final score =
          hit * 10 - (issue.severityRank - previous.severityRank).abs();
      if (score > bestScore) {
        bestScore = score;
        best = issue;
      }
    }

    // Require at least one meaningful token match.
    if (bestScore < 10) {
      // Fall back to same twin zone if available.
      for (final issue in nextIssues) {
        if (issue.twinZone == previous.twinZone &&
            issue.twinZone.toString() != 'TwinZone.none') {
          return issue;
        }
      }
      return null;
    }
    return best;
  }

  static Set<String> _tokens(AnalysisIssue issue) {
    final raw = '${issue.title} ${issue.location}'.toLowerCase();
    final parts = raw
        .split(RegExp('[^a-z0-9]+'))
        .where((t) => t.length >= 4)
        .toSet();
    // Drop ultra-common filler.
    parts.removeAll(const {
      'with',
      'from',
      'this',
      'that',
      'area',
      'home',
      'exterior',
      'possible',
      'surface',
    });
    return parts;
  }
}
