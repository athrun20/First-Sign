import '../models/analysis_models.dart';
import '../models/capture_models.dart';
import '../models/saved_report.dart';
import '../models/twin_zone.dart';
import 'finding_retake_service.dart';

/// Pairs a current finding with a *comparable* prior-scan photo.
///
/// Never falls back to a random history photo (e.g. portrait vs roof).
class EvidenceTimelinePairing {
  EvidenceTimelinePairing._();

  /// Exterior system this finding belongs to (finer than [TwinZone]).
  static String findingSystem(AnalysisIssue issue) {
    if (issue.isGroundDrainageFinding) return 'drainage';
    if (issue.isEaveGutterFinding) return 'gutters';
    switch (issue.twinZone) {
      case TwinZone.roof:
        return 'roof';
      case TwinZone.siding:
        return 'siding';
      case TwinZone.windows:
        return 'windows';
      case TwinZone.foundation:
        return 'foundation';
      case TwinZone.gutters:
        return 'gutters';
      case TwinZone.none:
        break;
    }
    final key = '${issue.title} ${issue.location}'.toLowerCase();
    if (key.contains('roof') ||
        key.contains('shingle') ||
        key.contains('granule')) {
      return 'roof';
    }
    if (key.contains('paint') || key.contains('peel')) return 'siding';
    if (key.contains('siding') || key.contains('cladding')) return 'siding';
    if (key.contains('foundation')) return 'foundation';
    if (key.contains('window')) return 'windows';
    return 'other';
  }

  /// Meaningful title tokens — drop hedging / filler that would match anything.
  static Set<String> titleTokens(AnalysisIssue issue) {
    final raw = '${issue.title} ${issue.location}'.toLowerCase();
    final parts = raw
        .split(RegExp('[^a-z0-9]+'))
        .where((t) => t.length >= 4)
        .toSet();
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
      'water',
      'near',
      'wear',
      'signs',
      'likely',
      'review',
      'watch',
    });
    return parts;
  }

  /// Prior finding that is the same system and plausibly the same area.
  static AnalysisIssue? matchPriorIssue(
    AnalysisIssue current,
    List<AnalysisIssue> priorIssues,
  ) {
    if (priorIssues.isEmpty) return null;
    final system = findingSystem(current);
    if (system == 'other') return null;

    AnalysisIssue? best;
    var bestScore = 0;
    final curTokens = titleTokens(current);

    for (final prior in priorIssues) {
      if (FindingRetakeService.looksNonExteriorIssue(prior)) continue;
      if (findingSystem(prior) != system) continue;
      var score = 10;
      if (current.twinZone != TwinZone.none &&
          prior.twinZone == current.twinZone) {
        score += 8;
      }
      var overlap = 0;
      final priorTokens = titleTokens(prior);
      for (final t in curTokens) {
        if (priorTokens.contains(t)) overlap++;
      }
      score += overlap * 4;
      if (score > bestScore) {
        bestScore = score;
        best = prior;
      }
    }

    // Require same system plus zone or a real token (not just "Possible").
    if (best == null) return null;
    if (bestScore < 14) return null;
    return best;
  }

  /// Photo bytes for [match] from [prior] — rematched, never photos.first.
  static SavedPhoto? priorEvidencePhoto({
    required AnalysisIssue match,
    required SavedReport prior,
  }) {
    final captures = prior.toCapturePhotos();
    if (captures.isEmpty) return null;

    final bound = FindingRetakeService.primaryEvidencePhoto(
      issue: match,
      photos: captures,
    );
    if (bound == null) return null;
    if (FindingRetakeService.looksNonExteriorPhoto(bound)) return null;

    for (final saved in prior.photos) {
      if (saved.index == bound.index && saved.bytes.isNotEmpty) {
        return saved;
      }
    }
    return null;
  }

  /// True when current and prior photos are the same exterior surface/slot.
  static bool isComparablePair({
    required AnalysisIssue current,
    required CapturePhoto? currentPhoto,
    required AnalysisIssue prior,
    required SavedPhoto priorPhoto,
  }) {
    if (findingSystem(current) != findingSystem(prior)) return false;
    if (FindingRetakeService.looksNonExteriorIssue(current) ||
        FindingRetakeService.looksNonExteriorIssue(prior)) {
      return false;
    }
    if (currentPhoto != null &&
        FindingRetakeService.looksNonExteriorPhoto(currentPhoto)) {
      return false;
    }
    final priorCapture = priorPhoto.toCapturePhoto();
    if (FindingRetakeService.looksNonExteriorPhoto(priorCapture)) {
      return false;
    }

    if (currentPhoto != null &&
        currentPhoto.slotId != null &&
        priorPhoto.slotId != null &&
        currentPhoto.slotId == priorPhoto.slotId) {
      return true;
    }
    if (current.twinZone != TwinZone.none &&
        current.twinZone == prior.twinZone) {
      return true;
    }
    // Same system + matching roof/grade captions.
    final a = '${currentPhoto?.label ?? ''} ${current.sourcePhotoLabel}'
        .toLowerCase();
    final b = '${priorPhoto.label} ${prior.sourcePhotoLabel}'.toLowerCase();
    if (_roofish(a) && _roofish(b)) return true;
    if (_gradeish(a) && _gradeish(b)) return true;
    return false;
  }

  static bool _roofish(String c) =>
      c.contains('roof') ||
      c.contains('shingle') ||
      c.contains('ridge') ||
      c.contains('eave');

  static bool _gradeish(String c) =>
      c.contains('soil') ||
      c.contains('outlet') ||
      c.contains('grade') ||
      c.contains('foundation') ||
      c.contains('downspout');
}
