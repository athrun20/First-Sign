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

    // Title + location only — a poisoned sourcePhotoLabel must not pick the slot.
    final key = '${issue.title} ${issue.location}'.toLowerCase();

    if (key.contains('roof') ||
        key.contains('shingle') ||
        key.contains('ridge') ||
        key.contains('granule') ||
        key.contains('asphalt') ||
        key.contains('impact')) {
      return CaptureShotId.roof;
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

  /// Rewrite each finding onto the photo that actually supports it.
  ///
  /// Category-matched slot / caption wins over a mismatched Vision box or
  /// stored `photoIndex`. Used by the report so every evidence surface agrees.
  /// Ground-drainage findings with only roof-domain photos are dropped.
  static List<AnalysisIssue> rebindIssues({
    required List<AnalysisIssue> issues,
    required List<CapturePhoto> photos,
  }) {
    if (photos.isEmpty) return issues;
    final kept = <AnalysisIssue>[];
    for (final issue in issues) {
      if (_isDrainageFinding(issue) &&
          !photos.any((p) => photoSupportsIssue(issue, p))) {
        continue;
      }
      kept.add(rebindIssue(issue: issue, photos: photos));
    }
    return kept;
  }

  /// Whether [photo] can serve as evidence for [issue].
  ///
  /// Drainage / foundation-water never treats a pure roof-field frame as
  /// support. Roof / shingle findings never treat a soil / outlet close-up
  /// as support.
  static bool photoSupportsIssue(AnalysisIssue issue, CapturePhoto photo) {
    if (looksNonExteriorPhoto(photo)) return false;
    if (_isDrainageFinding(issue)) {
      return !_isRoofOnlyPhoto(photo);
    }
    if (_isRoofFinding(issue)) {
      if (_looksGradeCaption(photo)) return false;
      return _isRoofOnlyPhoto(photo) || photo.slotId == CaptureShotId.roof;
    }
    return true;
  }

  /// Finding this photo should open — never a drainage claim on a roof frame.
  static AnalysisIssue? bestIssueForPhoto({
    required CapturePhoto photo,
    required List<AnalysisIssue> issues,
  }) {
    if (looksNonExteriorPhoto(photo) || issues.isEmpty) return null;

    for (final issue in issues) {
      if (issue.photoIndex == photo.index &&
          photoSupportsIssue(issue, photo)) {
        return issue;
      }
    }

    final label = photo.label.trim().toLowerCase();
    if (label.isNotEmpty) {
      for (final issue in issues) {
        if (issue.sourcePhotoLabel.trim().toLowerCase() == label &&
            photoSupportsIssue(issue, photo)) {
          return issue;
        }
      }
    }

    AnalysisIssue? best;
    var bestScore = -1;
    for (final issue in issues) {
      if (!photoSupportsIssue(issue, photo)) continue;
      var score = 1;
      if (_isRoofOnlyPhoto(photo) && _isRoofFinding(issue)) score = 3;
      if (_looksGradeCaption(photo) && _isDrainageFinding(issue)) score = 3;
      if (score > bestScore) {
        bestScore = score;
        best = issue;
      }
    }
    return best;
  }

  /// Subtitle for Surface Evidence — never mix grade location with a roof label.
  static String evidenceCaption({
    required AnalysisIssue issue,
    required String photoLabel,
    required bool photoSupportsFinding,
  }) {
    final photo = photoLabel.trim();
    if (!photoSupportsFinding) {
      return photo.isEmpty
          ? 'Related context — not proof of this finding'
          : 'Related context · $photo';
    }
    final loc = issue.shortLocation.trim();
    if (photo.isEmpty) return loc;
    if (loc.isEmpty || loc.toLowerCase() == photo.toLowerCase()) return photo;
    if (_locationConflictsWithPhoto(loc, photo)) return loc;
    return '$loc  ·  $photo';
  }

  /// Calm note when the selected angle is not the finding's evidence.
  static String relatedContextNote(AnalysisIssue issue) {
    if (_isDrainageFinding(issue)) {
      return 'This angle is related context — it does not show soil, grade, '
          'or an outlet, so it is not proof of this finding.';
    }
    if (_isRoofFinding(issue)) {
      return 'This angle is related context — it is not the roof surface '
          'this finding is about.';
    }
    return 'This angle is related context — it does not show the area '
        'this finding is about.';
  }

  static bool _locationConflictsWithPhoto(String location, String photoLabel) {
    final loc = location.toLowerCase();
    final photo = photoLabel.toLowerCase();
    final locGrade = loc.contains('grade') ||
        loc.contains('outlet') ||
        loc.contains('soil') ||
        loc.contains('foundation') ||
        loc.contains('downspout');
    final locRoof = (loc.contains('roof') || loc.contains('shingle')) &&
        !loc.contains('grade');
    final photoRoof = photo.contains('roof') ||
        photo.contains('shingle') ||
        photo.contains('ridge') ||
        photo.contains('eave');
    final photoGrade = photo.contains('soil') ||
        photo.contains('outlet') ||
        photo.contains('grade') ||
        photo.contains('discharge');
    return (locGrade && photoRoof) || (locRoof && photoGrade);
  }

  static AnalysisIssue rebindIssue({
    required AnalysisIssue issue,
    required List<CapturePhoto> photos,
  }) {
    final bound = primaryEvidencePhoto(issue: issue, photos: photos);
    if (bound == null) {
      if (_isDrainageFinding(issue) || _isRoofFinding(issue)) {
        return issue.copyWith(clearHighlight: true);
      }
      return issue;
    }
    final moved = issue.photoIndex != bound.index;
    return issue.copyWith(
      photoIndex: bound.index,
      sourcePhotoLabel: bound.label,
      clearHighlight: moved,
    );
  }

  /// Primary evidence photo for a finding.
  ///
  /// Drainage / foundation-water never returns a pure roof-field shot.
  /// Roof / shingle / impact never returns a soil / outlet close-up.
  /// Category-matched slot wins over a mismatched stored Vision box.
  static CapturePhoto? primaryEvidencePhoto({
    required AnalysisIssue issue,
    required List<CapturePhoto> photos,
    int? fallbackIndex,
  }) {
    if (photos.isEmpty) return null;

    photos = [
      for (final p in photos)
        if (!looksNonExteriorPhoto(p)) p,
    ];
    if (photos.isEmpty) return null;

    final drainFinding = _isDrainageFinding(issue);
    final roofFinding = _isRoofFinding(issue);

    if (drainFinding) {
      final grade = photos.where(_looksGradeCaption).toList();
      if (grade.isNotEmpty) {
        return _preferStoredIfEligible(issue, grade, fallbackIndex);
      }
      final notRoof = photos.where((p) => !_isRoofOnlyPhoto(p)).toList();
      if (notRoof.isNotEmpty) {
        return _preferStoredIfEligible(issue, notRoof, fallbackIndex);
      }
      return null;
    }

    if (roofFinding) {
      final roof = photos.where(_isRoofOnlyPhoto).toList();
      if (roof.isNotEmpty) {
        return _preferStoredIfEligible(issue, roof, fallbackIndex);
      }
      final notSoil = photos.where((p) => !_looksGradeCaption(p)).toList();
      if (notSoil.isNotEmpty) {
        return _preferStoredIfEligible(issue, notSoil, fallbackIndex);
      }
      return null;
    }

    return _preferStoredIfEligible(issue, photos, fallbackIndex);
  }

  static CapturePhoto _preferStoredIfEligible(
    AnalysisIssue issue,
    List<CapturePhoto> candidates,
    int? fallbackIndex,
  ) {
    CapturePhoto? byIndex(int? i) {
      if (i == null) return null;
      for (final p in candidates) {
        if (p.index == i) return p;
      }
      return null;
    }

    final stored = byIndex(issue.photoIndex);
    if (stored != null) return stored;

    final label = issue.sourcePhotoLabel.trim().toLowerCase();
    if (label.isNotEmpty) {
      for (final p in candidates) {
        if (p.label.toLowerCase() == label) return p;
      }
    }

    final fallback = byIndex(fallbackIndex);
    if (fallback != null) return fallback;

    final preferred = preferredSlot(issue);
    for (final p in candidates) {
      if (p.slotId == preferred) return p;
    }
    return candidates.first;
  }

  static bool _isDrainageFinding(AnalysisIssue issue) {
    if (issue.isGroundDrainageFinding) return true;
    if (issue.isEaveGutterFinding) return false;
    final key = '${issue.title} ${issue.location}'.toLowerCase();
    return key.contains('dumping') ||
        key.contains('soil at grade') ||
        key.contains('ground outlet') ||
        key.contains('near foundation') ||
        (key.contains('downspout') &&
            (key.contains('outlet') ||
                key.contains('grade') ||
                key.contains('foundation'))) ||
        (key.contains('foundation') &&
            (key.contains('water') ||
                key.contains('wet') ||
                key.contains('drain')));
  }

  static bool _isRoofFinding(AnalysisIssue issue) {
    if (_isDrainageFinding(issue) || issue.isEaveGutterFinding) {
      return false;
    }
    final key = '${issue.title} ${issue.location}'.toLowerCase();
    return key.contains('roof') ||
        key.contains('shingle') ||
        key.contains('ridge') ||
        key.contains('granule') ||
        key.contains('asphalt') ||
        (key.contains('impact') && key.contains('roof'));
  }

  /// Pure roof-field / ridge / "Roof & eaves" slot — not grade evidence.
  static bool _isRoofOnlyPhoto(CapturePhoto photo) {
    if (_looksGradeCaption(photo)) return false;
    if (photo.slotId == CaptureShotId.roof) return true;
    final c = '${photo.label} ${photo.file.name}'.toLowerCase();
    if (c.contains('roof & eave') || c.contains('roof and eave')) return true;
    if (c.contains('ridge') ||
        c.contains('shingle') ||
        c.contains('granule') ||
        c.contains('asphalt')) {
      return true;
    }
    if (c.contains('roof') &&
        !c.contains('gutter') &&
        !c.contains('outlet')) {
      return true;
    }
    if (c.contains('eave') && !c.contains('grade')) return true;
    return false;
  }

  /// Portrait / selfie / indoor captions must never be evidence.
  static bool looksNonExteriorCaption(String raw) {
    final c = raw.toLowerCase();
    if (c.trim().isEmpty) return false;
    final tokens = c.split(RegExp('[^a-z0-9]+')).where((t) => t.isNotEmpty);
    const blocked = {
      'person',
      'people',
      'human',
      'selfie',
      'portrait',
      'headshot',
      'mugshot',
      'face',
      'indoor',
      'interior',
      'kitchen',
      'bedroom',
      'bathroom',
      'livingroom',
    };
    return tokens.any(blocked.contains);
  }

  static bool looksNonExteriorPhoto(CapturePhoto photo) {
    return looksNonExteriorCaption('${photo.label} ${photo.file.name}');
  }

  static bool looksNonExteriorIssue(AnalysisIssue issue) {
    return looksNonExteriorCaption(
      '${issue.title} ${issue.location} ${issue.sourcePhotoLabel}',
    );
  }

  static bool _looksGradeCaption(CapturePhoto photo) {
    final c = '${photo.label} ${photo.file.name}'.toLowerCase();
    return c.contains('soil') ||
        c.contains('outlet') ||
        c.contains('discharge') ||
        c.contains('pipe') ||
        c.contains('grade') ||
        c.contains('mulch') ||
        c.contains('gravel') ||
        c.contains('dirt') ||
        (c.contains('downspout') &&
            (c.contains('ground') ||
                c.contains('base') ||
                c.contains('foundation') ||
                c.contains('end'))) ||
        (c.contains('foundation') &&
            (c.contains('wet') ||
                c.contains('soil') ||
                c.contains('outlet') ||
                c.contains('dumping')));
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
