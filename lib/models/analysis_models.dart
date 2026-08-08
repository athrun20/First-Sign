// Shared AI analysis models used by the report UI and PDF export.

import 'package:flutter/material.dart';

import '../legal/privacy_copy.dart';
import 'twin_zone.dart';

class AnalysisIssue {
  final String title;
  final String location;
  final String severity; // High | Medium | Low
  final String cost;
  final int confidence; // 0–100
  final String insight;

  /// Index into the capture photo list used for this finding.
  final int? photoIndex;

  /// e.g. "Front of home" — which guided shot supports this finding.
  final String sourcePhotoLabel;

  /// True when evidence is weak; UI should not over-claim certainty.
  final bool needsCloserPhoto;

  /// Optional Vision object-localization box (normalized 0–1 LTRB).
  /// When set, [surfaceHighlight] prefers this over generic zone estimates.
  final double? highlightLeft;
  final double? highlightTop;
  final double? highlightWidth;
  final double? highlightHeight;

  const AnalysisIssue({
    required this.title,
    required this.location,
    required this.severity,
    required this.cost,
    required this.confidence,
    required this.insight,
    this.photoIndex,
    this.sourcePhotoLabel = '',
    this.needsCloserPhoto = false,
    this.highlightLeft,
    this.highlightTop,
    this.highlightWidth,
    this.highlightHeight,
  });

  /// True when a usable Vision (or refined) box is stored.
  bool get hasLocalizedHighlight {
    final l = highlightLeft;
    final t = highlightTop;
    final w = highlightWidth;
    final h = highlightHeight;
    if (l == null || t == null || w == null || h == null) return false;
    if (w < 0.06 || h < 0.06) return false;
    if (l < -0.05 || t < -0.05 || l + w > 1.05 || t + h > 1.05) return false;
    return true;
  }

  /// Cost string with planning-range framing for UI.
  ///
  /// Weak-evidence findings withhold a dollar range so reports stay trustworthy.
  String get planningCostLabel {
    final c = cost.trim();
    if (c.isEmpty ||
        c.toUpperCase() == 'TBD' ||
        c.toLowerCase().startsWith('tbd')) {
      if (needsCloserPhoto || confidence < 70) {
        return 'Planning range withheld — weak photo evidence';
      }
      if (severity == 'Low') {
        return 'Planning range withheld — low-severity screening note';
      }
      return 'Planning range: TBD (confirm on-site)';
    }
    if (c.toLowerCase().contains('planning')) return c;
    return 'Planning range $c (screening estimate, not a bid)';
  }

  String get sourcePhotoDisplay {
    if (sourcePhotoLabel.trim().isNotEmpty) return sourcePhotoLabel.trim();
    if (photoIndex != null) return 'Photo ${photoIndex! + 1}';
    return 'Capture set';
  }

  double get severityLevel {
    switch (severity) {
      case 'High':
        return 0.9;
      case 'Medium':
        return 0.6;
      default:
        return 0.3;
    }
  }

  int get severityRank {
    switch (severity) {
      case 'High':
        return 3;
      case 'Medium':
        return 2;
      default:
        return 1;
    }
  }

  // ── Report storytelling (clearer narrative for UI + PDF) ─────────────────

  /// True when UI should avoid definitive high-impact wording.
  ///
  /// High + strong confidence + no closer-photo flag may keep the stored title.
  bool get shouldSoftenTitle {
    if (needsCloserPhoto) return true;
    if (severity == 'High' && confidence >= 90) return false;
    return true;
  }

  /// Homeowner-facing finding name (presentation only — does not change [title]).
  ///
  /// Softens crack/settlement/missing-shingle style claims when evidence is not
  /// extremely strong, so first impressions feel calmer and more honest.
  String get homeownerTitle {
    final t = title.trim();
    if (t.isEmpty) return 'Exterior screening note';
    final lower = t.toLowerCase();

    // Already hedged.
    if (lower.contains('possible') ||
        lower.contains('signs of') ||
        lower.contains('likely') ||
        lower.contains('may ') ||
        lower.contains('review') ||
        lower.contains('watch') ||
        lower.contains('risk')) {
      return t;
    }

    if (!shouldSoftenTitle) return t;

    if (lower.contains('foundation') &&
        (lower.contains('crack') || lower.contains('settlement'))) {
      return 'Possible foundation settlement signs';
    }
    if (lower.contains('missing') && lower.contains('shingle')) {
      return 'Possible missing or damaged shingles';
    }
    if (lower.contains('damaged shingle') ||
        (lower.contains('shingle') && lower.contains('damaged'))) {
      return 'Possible damaged shingles';
    }
    if ((lower.contains('cracked') || lower.contains('crack')) &&
        (lower.contains('siding') || lower.contains('cladding'))) {
      return 'Possible siding cracks';
    }
    if (lower.contains('structural')) {
      return 'Possible structural concern';
    }
    if (lower.startsWith('missing') ||
        lower.startsWith('damaged') ||
        lower.contains('failure')) {
      final rest = t[0].toLowerCase() + t.substring(1);
      return 'Possible $rest';
    }
    return t;
  }

  /// Plain-language finding name for story sentences.
  String get storyTitle {
    final t = title.trim();
    return t.isEmpty ? 'Exterior concern' : t;
  }

  /// What we found — short, homeowner-friendly (screening tone).
  String get storyWhat {
    final loc = location.trim().isEmpty ? 'the exterior' : location.trim();
    final photo = sourcePhotoDisplay;
    final base = '$storyTitle at $loc';
    final from = photo.isNotEmpty && photo != 'Capture set'
        ? ' (from $photo)'
        : '';
    if (needsCloserPhoto) {
      return '$base$from. Screening note only — confidence $confidence%; a sharper close-up would firm up this call.';
    }
    if (confidence >= 85) {
      return '$base$from. Photo cues support this screening finding (confidence $confidence%).';
    }
    if (confidence >= 70) {
      return '$base$from. Screening signals are usable for planning (confidence $confidence%), with normal photo limits.';
    }
    return '$base$from. Watch item only (confidence $confidence%) until a closer look confirms it.';
  }

  /// Ground-level downspout / outlet finding (not roof-edge gutter clogging).
  bool get isGroundDrainageFinding {
    final key = '${title.toLowerCase()} ${location.toLowerCase()}';
    if (key.contains('dumping near foundation') ||
        key.contains('near foundation') ||
        key.contains('soil at grade') ||
        key.contains('ground outlets') ||
        key.contains('water leaving near')) {
      return true;
    }
    final ground = key.contains('downspout') ||
        key.contains('outlet') ||
        key.contains('discharge') ||
        key.contains('at grade');
    final eave = key.contains('eave') ||
        key.contains('roof edge') ||
        key.contains('overflow') ||
        key.contains('clog');
    return ground && !eave;
  }

  /// Roof-edge gutter / overflow finding.
  bool get isEaveGutterFinding {
    final key = '${title.toLowerCase()} ${location.toLowerCase()}';
    if (isGroundDrainageFinding) return false;
    return key.contains('gutter') ||
        key.contains('eave') ||
        key.contains('overflow') ||
        key.contains('clog') ||
        key.contains('roof edge') ||
        (key.contains('drainage') && !key.contains('foundation'));
  }

  /// Why it matters / impact if delayed.
  String get storyImpact {
    final key = '${title.toLowerCase()} ${location.toLowerCase()}';
    final system = () {
      if (isGroundDrainageFinding) {
        return 'Water that leaves too close to the house can wet the foundation, stain siding, and feed damp basements.';
      }
      if (isEaveGutterFinding ||
          key.contains('gutter') ||
          key.contains('downspout') ||
          key.contains('eave') ||
          key.contains('overflow')) {
        return 'Poor drainage can wet the foundation line, stain siding, and soften fascia.';
      }
      if (key.contains('roof') ||
          key.contains('shingle') ||
          key.contains('ridge')) {
        return 'Open roofing lets water reach underlayment and decking, then ceilings and attic framing.';
      }
      if (key.contains('foundation') ||
          key.contains('grade') ||
          key.contains('settlement')) {
        return 'Moisture at the base can widen cracks and invite basement or crawlspace dampness.';
      }
      if (key.contains('window') ||
          key.contains('seal') ||
          key.contains('caulk')) {
        return 'Failed seals invite drafts and hidden water at the rough opening.';
      }
      if (key.contains('paint') || key.contains('peel')) {
        return 'Failed coatings leave substrate open to UV and rain, accelerating future siding repairs.';
      }
      if (key.contains('mismatched') ||
          key.contains('patched') ||
          (key.contains('patch') && key.contains('siding'))) {
        return 'Mismatched or patched cladding often marks incomplete repairs; open board edges can still admit water behind the wall.';
      }
      if (key.contains('wiring') ||
          key.contains('cable clutter') ||
          (key.contains('cable') && key.contains('exterior'))) {
        return 'Surface cable runs clutter the elevation and can snag or hide unfinished exterior work that needs clean routing.';
      }
      if (key.contains('siding') || key.contains('cladding')) {
        return 'Damaged cladding can channel water behind the wall and grow the repair area.';
      }
      if (key.contains('chimney') || key.contains('flash')) {
        return 'Flashing gaps are a common leak path and often show later as interior stains.';
      }
      if (key.contains('fascia') ||
          key.contains('soffit') ||
          key.contains('rot')) {
        return 'Soft wood at the eaves usually means an active moisture source is still feeding it.';
      }
      if (key.contains('rust') || key.contains('corrosion')) {
        return 'Active corrosion weakens metal flashings and fasteners that protect openings.';
      }
      if (key.contains('vegetation')) {
        return 'Growth against the structure holds moisture on cladding and can lift roof edges over time.';
      }
      return 'Left alone, small exterior openings tend to grow with seasons and raise repair cost.';
    }();

    final urgency = switch (severity) {
      'High' =>
        'Acting within 1–2 weeks usually costs less than waiting for secondary damage.',
      'Medium' =>
        'Scheduling within 30–60 days helps keep wear from spreading to neighboring materials.',
      _ =>
        'Low urgency now; early fixes still protect curb appeal and avoid a larger future scope.',
    };
    return 'Impact if delayed: $system $urgency';
  }

  /// Clear recommended next step.
  String get storyRecommendation {
    if (needsCloserPhoto) {
      return 'Recommended: retake a sharp close-up of $storyTitle in good light, then re-run screening or show a pro.';
    }
    final steps = surfaceRepairSteps;
    if (steps.isNotEmpty) {
      final first = steps.first;
      return switch (severity) {
        'High' => 'Recommended this week for $storyTitle: $first',
        'Medium' => 'Recommended soon for $storyTitle: $first',
        _ =>
          'Recommended in the next maintenance cycle for $storyTitle: $first',
      };
    }
    return switch (severity) {
      'High' =>
        'Recommended: book a qualified exterior pro soon for $storyTitle and stop any active moisture source first.',
      'Medium' =>
        'Recommended: plan a repair window this season for $storyTitle and document the area with close-ups.',
      _ =>
        'Recommended: monitor $storyTitle and bundle with other exterior work when convenient.',
    };
  }

  /// Structured story body for cards (What → Impact → Next).
  String get storyNarrative {
    return '$storyWhat\n\n$storyImpact\n\n$storyRecommendation';
  }

  /// Single-paragraph insight for dense places (PDF lines, history).
  String get storyInsightParagraph {
    final showCost =
        cost.trim().isNotEmpty &&
        cost.toUpperCase() != 'TBD' &&
        !cost.toLowerCase().startsWith('tbd') &&
        cost.contains('\$') &&
        !needsCloserPhoto &&
        confidence >= 70;
    final parts = <String>[
      storyWhat,
      storyImpact,
      storyRecommendation,
      if (showCost) 'Planning cost range: $cost (not a contractor bid).',
      if (!showCost && (needsCloserPhoto || confidence < 70))
        'Planning cost withheld until photo evidence is stronger.',
    ];
    return parts.join(' ');
  }

  /// Map finding → digital twin zone for filtering / markers.
  TwinZone get twinZone {
    final key = '${title.toLowerCase()} ${location.toLowerCase()}';
    // Drainage before roof — "roof edge / gutters" is gutters, not shingles.
    if (isGroundDrainageFinding ||
        isEaveGutterFinding ||
        key.contains('gutter') ||
        key.contains('downspout') ||
        key.contains('eave') ||
        key.contains('fascia') ||
        key.contains('soffit') ||
        key.contains('overflow')) {
      return TwinZone.gutters;
    }
    if (key.contains('roof') ||
        key.contains('shingle') ||
        key.contains('ridge') ||
        key.contains('chimney') ||
        key.contains('flash')) {
      return TwinZone.roof;
    }
    if (key.contains('foundation') ||
        key.contains('grade') ||
        key.contains('settlement') ||
        key.contains('base')) {
      return TwinZone.foundation;
    }
    if (key.contains('window') ||
        key.contains('seal') ||
        key.contains('caulk') ||
        key.contains('door')) {
      return TwinZone.windows;
    }
    if (key.contains('siding') ||
        key.contains('paint') ||
        key.contains('cladding') ||
        key.contains('wall') ||
        key.contains('rust') ||
        key.contains('vegetation') ||
        key.contains('mismatched') ||
        key.contains('patched') ||
        key.contains('wiring') ||
        key.contains('cable')) {
      return TwinZone.siding;
    }
    return TwinZone.siding;
  }

  /// Prefer a readable story over a dense machine insight when showing UI copy.
  String get displayInsight {
    final raw = insight.trim();
    // Old dense insights with "Evidence:" / "Reasoning:" — replace with story form.
    if (raw.isEmpty ||
        raw.contains('Evidence:') ||
        raw.contains('Reasoning:') ||
        raw.contains('Why it matters:') ||
        raw.length > 420) {
      return storyNarrative;
    }
    // Already human-readable — still append impact + next if missing.
    final lower = raw.toLowerCase();
    final buf = StringBuffer(raw);
    if (!raw.endsWith('.') && !raw.endsWith('!')) buf.write('.');
    if (!lower.contains('impact') && !lower.contains('if delayed')) {
      buf.write('\n\n$storyImpact');
    }
    if (!lower.contains('recommend') && !lower.contains('next step')) {
      buf.write('\n\n$storyRecommendation');
    }
    return buf.toString();
  }

  AnalysisIssue copyWith({
    String? title,
    String? location,
    String? severity,
    String? cost,
    int? confidence,
    String? insight,
    int? photoIndex,
    String? sourcePhotoLabel,
    bool? needsCloserPhoto,
    double? highlightLeft,
    double? highlightTop,
    double? highlightWidth,
    double? highlightHeight,
    bool clearHighlight = false,
  }) {
    return AnalysisIssue(
      title: title ?? this.title,
      location: location ?? this.location,
      severity: severity ?? this.severity,
      cost: cost ?? this.cost,
      confidence: confidence ?? this.confidence,
      insight: insight ?? this.insight,
      photoIndex: photoIndex ?? this.photoIndex,
      sourcePhotoLabel: sourcePhotoLabel ?? this.sourcePhotoLabel,
      needsCloserPhoto: needsCloserPhoto ?? this.needsCloserPhoto,
      highlightLeft: clearHighlight
          ? null
          : (highlightLeft ?? this.highlightLeft),
      highlightTop: clearHighlight ? null : (highlightTop ?? this.highlightTop),
      highlightWidth: clearHighlight
          ? null
          : (highlightWidth ?? this.highlightWidth),
      highlightHeight: clearHighlight
          ? null
          : (highlightHeight ?? this.highlightHeight),
    );
  }

  /// Short zone label for the photo callout.
  String get surfaceZoneLabel {
    final key = '${title.toLowerCase()} ${location.toLowerCase()}';
    if (isGroundDrainageFinding) {
      return 'Downspout / ground outlet';
    }
    if (isEaveGutterFinding ||
        key.contains('gutter') ||
        key.contains('downspout') ||
        key.contains('eave') ||
        key.contains('overflow')) {
      return 'Gutter / roof edge';
    }
    if (key.contains('roof') ||
        key.contains('shingle') ||
        key.contains('ridge')) {
      return 'Roof area';
    }
    if (key.contains('fascia') ||
        key.contains('soffit') ||
        key.contains('rot')) {
      return 'Fascia / soffit';
    }
    if (key.contains('foundation') ||
        key.contains('base') ||
        key.contains('grade')) {
      return 'Foundation';
    }
    if (key.contains('window') ||
        key.contains('seal') ||
        key.contains('caulk')) {
      return 'Window / seal';
    }
    if (key.contains('wiring') || key.contains('cable clutter')) {
      return 'Wall / wiring';
    }
    if (key.contains('siding') ||
        key.contains('paint') ||
        key.contains('wall') ||
        key.contains('mismatched') ||
        key.contains('patched')) {
      return 'Siding / wall';
    }
    if (key.contains('chimney') || key.contains('flash')) {
      return 'Chimney / flashing';
    }
    if (key.contains('rust') ||
        key.contains('metal') ||
        key.contains('corrosion')) {
      return 'Metal / corrosion';
    }
    return location;
  }

  /// Recommended timeline based on severity.
  String get surfaceTimeline {
    switch (severity) {
      case 'High':
        return 'Address within 1–2 weeks';
      case 'Medium':
        return 'Schedule within 30–60 days';
      default:
        return 'Plan into next maintenance cycle';
    }
  }

  /// Confidence band label for the surface-evidence meter (screening framing).
  String get surfaceConfidenceLabel {
    if (needsCloserPhoto || confidence < 70) return 'Needs closer photos';
    if (confidence >= 85) return 'Strong screening signal';
    if (confidence >= 70) return 'Solid screening signal';
    return 'Limited screening signal';
  }

  // ── Forensic Surface Evidence (premium analysis panel) ───────────────────

  /// Primary human-readable confidence (percent is secondary in UI).
  ///
  /// High Confidence · Moderate Confidence · Limited Visibility
  String get forensicConfidenceTitle {
    if (needsCloserPhoto || confidence < 65) return 'Limited Visibility';
    // Zone-only drainage estimates should not read as highly certain.
    if (!hasLocalizedHighlight &&
        (isGroundDrainageFinding || isEaveGutterFinding) &&
        confidence < 88) {
      return 'Moderate Confidence';
    }
    if (confidence < 80) return 'Moderate Confidence';
    return 'High Confidence';
  }

  /// One-line plain-English confidence framing.
  String get forensicConfidenceSubtitle {
    if (needsCloserPhoto || confidence < 65) {
      return 'The photo is hard to read — a closer shot would help.';
    }
    if (confidence < 80) {
      return 'Something shows up in the photo, but it is not crystal clear.';
    }
    if (hasLocalizedHighlight) {
      return 'Clear clues in a specific part of this photo.';
    }
    return 'Clues in this general area of the house (rough estimate only).';
  }

  /// Factors that can reduce model certainty (honest XAI).
  List<String> get forensicConfidenceLimiters {
    final out = <String>[];
    final key = '${title.toLowerCase()} ${location.toLowerCase()} ${insight.toLowerCase()}';
    if (needsCloserPhoto) {
      out.add('Too far away or soft focus — hard to see surface detail');
    }
    if (confidence < 80) {
      out.add('Mixed textures or something blocking the view');
    }
    if (key.contains('shadow') || key.contains('shade') || confidence < 75) {
      out.add('Shadows can look like stains or damage');
    }
    if (key.contains('tree') ||
        key.contains('vegetation') ||
        key.contains('plant') ||
        key.contains('leaf')) {
      out.add('Plants near the house can hide or look like surface damage');
    }
    if (key.contains('angle') || key.contains('oblique') || !hasLocalizedHighlight) {
      out.add('Camera angle — the marked area is an estimate, not a survey');
    }
    if (!hasLocalizedHighlight) {
      out.add('Rough area only — not a tight box around a clear object');
    }
    if (isGroundDrainageFinding &&
        (key.contains('eave') || key.contains('overflow') || key.contains('clog'))) {
      out.add('Ground-level photo — not proof of a clogged roof gutter');
    }
    if (out.isEmpty) {
      out.add('Photo screening only — not a full inspection');
    }
    // De-dupe, cap.
    final seen = <String>{};
    return out.where(seen.add).take(4).toList();
  }

  /// Short damage taxonomy for the forensic panel.
  String get forensicDamageType {
    final key = '${title.toLowerCase()} ${location.toLowerCase()}';
    if (key.contains('missing') && key.contains('shingle')) {
      return 'Missing or lifted shingles';
    }
    if (key.contains('granule') || key.contains('aging')) {
      return 'Worn shingles / granule loss';
    }
    if (key.contains('crack') && key.contains('foundation')) {
      return 'Possible foundation crack';
    }
    if (key.contains('crack') || key.contains('fracture')) {
      return 'Crack line';
    }
    if (key.contains('peel') || key.contains('paint')) {
      return 'Peeling paint';
    }
    if (isGroundDrainageFinding) {
      return 'Water near foundation / downspout outlet';
    }
    if (key.contains('gutter') ||
        key.contains('overflow') ||
        key.contains('drainage') ||
        key.contains('downspout')) {
      return 'Gutter / drainage issue';
    }
    if (key.contains('rot') || key.contains('soft')) {
      return 'Soft or rotting wood';
    }
    if (key.contains('stain') || key.contains('moisture') || key.contains('mold')) {
      return 'Moisture staining';
    }
    if (key.contains('rust') || key.contains('corrosion')) {
      return 'Corrosion / oxidation';
    }
    if (key.contains('seal') || key.contains('caulk') || key.contains('gap')) {
      return 'Seal failure / open joint';
    }
    if (key.contains('warp') || key.contains('buckl')) {
      return 'Warping / deformation';
    }
    if (key.contains('siding') || key.contains('cladding')) {
      return 'Cladding surface defect';
    }
    if (key.contains('roof') || key.contains('shingle')) {
      return 'Roof surface defect';
    }
    return homeownerTitle;
  }

  /// Primary exterior material inferred from finding context.
  String get forensicAffectedMaterial {
    final key = '${title.toLowerCase()} ${location.toLowerCase()}';
    if (key.contains('shingle') || key.contains('asphalt')) {
      return 'Asphalt shingle';
    }
    if (key.contains('metal roof') || key.contains('standing seam')) {
      return 'Metal roofing';
    }
    if (key.contains('roof')) return 'Roof covering';
    if (key.contains('vinyl')) return 'Vinyl siding';
    if (key.contains('fiber') || key.contains('cement')) {
      return 'Fiber-cement cladding';
    }
    if (key.contains('stucco')) return 'Stucco / EIFS';
    if (key.contains('brick') || key.contains('masonry')) {
      return 'Masonry / brick';
    }
    if (key.contains('wood') || key.contains('trim') || key.contains('fascia')) {
      return 'Wood trim / fascia';
    }
    if (key.contains('siding') || key.contains('paint') || key.contains('wall')) {
      return 'Exterior cladding';
    }
    if (isGroundDrainageFinding) {
      return 'Downspout outlet / grade';
    }
    if (key.contains('gutter') || key.contains('downspout')) {
      return 'Gutter / downspout';
    }
    if (key.contains('window') || key.contains('glass')) {
      return 'Window assembly';
    }
    if (key.contains('foundation') || key.contains('concrete')) {
      return 'Concrete / foundation';
    }
    if (key.contains('flash')) return 'Metal flashing';
    return 'Exterior surface';
  }

  /// Detection quality tier for forensic panel.
  String get forensicDetectionQuality {
    if (hasLocalizedHighlight && confidence >= 88 && !needsCloserPhoto) {
      return 'High — clear spot in the photo';
    }
    if (hasLocalizedHighlight && confidence >= 75) {
      return 'Good — area marked in the photo';
    }
    if (confidence >= 80 && !needsCloserPhoto) {
      return 'Solid — general area only (estimate)';
    }
    if (needsCloserPhoto || confidence < 70) {
      return 'Limited — needs closer photos';
    }
    return 'Moderate — photo screening only';
  }

  /// Approximate damaged area using highlight size + zone scale heuristics.
  ///
  /// Screening estimate only — not a surveyed measurement.
  String get forensicEstimatedSize {
    final r = surfaceHighlight;
    if (r == Rect.zero || !shouldShowSurfaceHighlight) {
      return 'Not measured — retake for scale';
    }
    final key = '${title.toLowerCase()} ${location.toLowerCase()}';
    // Assumed real-world span of the photo FOV (feet) by system.
    final double spanFt;
    if (key.contains('roof') || key.contains('shingle') || key.contains('ridge')) {
      spanFt = 32;
    } else if (key.contains('foundation') || key.contains('grade')) {
      spanFt = 28;
    } else if (isGroundDrainageFinding) {
      spanFt = 22;
    } else if (key.contains('gutter') || key.contains('eave')) {
      spanFt = 36;
    } else if (key.contains('window')) {
      spanFt = 18;
    } else {
      spanFt = 26;
    }
    final wFt = r.width * spanFt;
    final hFt = r.height * spanFt * 0.75;
    final area = wFt * hFt;
    if (area < 0.8) {
      final wIn = (wFt * 12).clamp(2.0, 48.0);
      final hIn = (hFt * 12).clamp(2.0, 48.0);
      return '~${wIn.toStringAsFixed(0)}×${hIn.toStringAsFixed(0)} in (est.)';
    }
    if (area < 12) {
      return '~${wFt.toStringAsFixed(1)}×${hFt.toStringAsFixed(1)} ft (est.)';
    }
    return '~${area.toStringAsFixed(0)} sq ft surface (est.)';
  }

  /// Suggested next capture angle when confidence is weak.
  String get forensicRetakeAngleHint {
    final key = '${title.toLowerCase()} ${location.toLowerCase()}';
    if (isGroundDrainageFinding) {
      return 'Photograph the downspout end at ground level, plus the wet soil or splash zone after rain.';
    }
    if (isEaveGutterFinding ||
        key.contains('gutter') ||
        key.contains('eave') ||
        key.contains('fascia') ||
        key.contains('overflow')) {
      return 'Stand closer to the roof edge and shoot along the gutter so hangers and any overflow stains show.';
    }
    if (key.contains('roof') || key.contains('shingle')) {
      return 'Take a closer shot of the worn area in even daylight. Stay on the ground — no climbing.';
    }
    if (key.contains('foundation') || key.contains('crack')) {
      return 'Take a tight close-up of the crack with a coin for scale, plus a wider shot of the wall base.';
    }
    if (key.contains('window') || key.contains('seal')) {
      return 'Fill the frame with the sill and corner seals; avoid heavy backlight.';
    }
    if (key.contains('siding') || key.contains('paint')) {
      return 'Shoot a straight-on close-up of the worst board, then a wider wall shot for context.';
    }
    return 'Retake a sharp, well-lit close-up from a straight-on angle.';
  }

  /// Visual cues the AI is responding to (plain-English “why detected”).
  ///
  /// Phrased as observable photo evidence — not internal model claims.
  List<String> get forensicVisualCues {
    final key = '${title.toLowerCase()} ${location.toLowerCase()}';
    final cues = <String>[];
    // Drainage first — "roof edge / gutters" must not fall into roof-shingle cues.
    if (isGroundDrainageFinding) {
      cues.addAll(const [
        'Pipes or downspout ends near the ground',
        'Wet or muddy soil near the foundation',
        'Water leaving close to the house wall',
        'Splash or staining at the outlet area',
      ]);
    } else if (isEaveGutterFinding ||
        key.contains('gutter') ||
        key.contains('downspout') ||
        key.contains('eave') ||
        key.contains('overflow') ||
        key.contains('drainage')) {
      cues.addAll(const [
        'Uneven or stained spots along the gutter line',
        'Marks that may mean water spilled over the edge',
        'Gutter that looks out of line with the wall',
        'Leaves or debris near the roof edge',
      ]);
    } else if (key.contains('roof') || key.contains('shingle')) {
      cues.addAll(const [
        'Worn or uneven spots in the shingles',
        'Edges that look lifted, missing, or broken',
        'Color that does not match nearby shingles',
        'Darker patches that may mean wear or exposure',
      ]);
    } else if (key.contains('siding') || key.contains('paint') || key.contains('peel')) {
      cues.addAll(const [
        'Paint that is peeling or flaking',
        'Color that does not match nearby boards',
        'Boards that look warped or lifted at the edge',
        'Discolored patches on the wall',
      ]);
    } else if (key.contains('foundation') || key.contains('crack')) {
      cues.addAll(const [
        'A crack line near the base of the wall',
        'Shadow that follows a crack path',
        'Broken texture in concrete or masonry',
        'Damp-looking stains near the ground',
      ]);
    } else if (key.contains('window') || key.contains('seal')) {
      cues.addAll(const [
        'Gaps in the seal around the window',
        'Stains under the sill or at the corners',
        'Uneven gap along the frame',
        'Caulk that looks cracked or missing',
      ]);
    } else if (key.contains('rust') || key.contains('corrosion')) {
      cues.addAll(const [
        'Orange or brown rust color on metal',
        'Flaking or pitted metal surface',
        'Stains running onto nearby materials',
      ]);
    } else {
      cues.addAll(const [
        'A worn or uneven spot on the surface',
        'Color that does not match nearby material',
        'Edges that look broken or out of place',
        'Wear focused in one area of the photo',
      ]);
    }
    return cues;
  }

  /// Plain-English AI reasoning for the forensic panel (grounded claims only).
  String get forensicAiReasoning {
    final cues = forensicVisualCues.take(2).join(', and ').toLowerCase();
    final region = hasLocalizedHighlight
        ? 'This photo shows a specific area'
        : 'This photo shows a general area of the house (rough estimate)';
    final kind = forensicDamageType.toLowerCase();
    final material = forensicAffectedMaterial.toLowerCase();
    return '$region that may relate to $kind on $material. '
        'What stood out: $cues. '
        'This is photo screening only — it cannot see inside walls or measure depth. '
        '${forensicConfidenceTitle == 'Limited Visibility' ? forensicRetakeAngleHint : storyRecommendation}';
  }

  /// Stable organic mask seed for contour generation (not a crude box).
  int get forensicMaskSeed =>
      Object.hash(title, location, highlightLeft, highlightTop, photoIndex);

  /// Extra cost context for the surface-evidence cost card.
  String get surfaceCostNote {
    const disclaimer =
        'Planning estimate only from photo screening — not a contractor bid. '
        'Real cost depends on access, materials, and local labor.';
    if (needsCloserPhoto ||
        confidence < 70 ||
        cost.trim().isEmpty ||
        cost.toUpperCase() == 'TBD' ||
        cost.toLowerCase().startsWith('tbd')) {
      return 'No dollar range until photos are clearer. Retake a close-up or confirm on-site. $disclaimer';
    }
    switch (severity) {
      case 'High':
        return 'Fixing sooner often costs less than waiting for more water damage. $disclaimer';
      case 'Medium':
        return 'Mid-range planning estimate for scheduling — not a bid. $disclaimer';
      default:
        return 'Optional preventive range — easy to bundle with other exterior work. $disclaimer';
    }
  }

  /// Why this finding matters — multi-part detail for surface evidence.
  List<String> get surfaceWhyItMattersPoints {
    final points = <String>[storyWhat];

    final key = '${title.toLowerCase()} ${location.toLowerCase()}';
    if (isGroundDrainageFinding) {
      points.add(
        'Water that leaves too close to the house can wet the foundation and stain the lower wall.',
      );
    } else if (isEaveGutterFinding ||
        key.contains('gutter') ||
        key.contains('downspout') ||
        key.contains('eave') ||
        key.contains('overflow') ||
        key.contains('drainage')) {
      points.add(
        'Clogged or overflowing gutters can soak fascia boards and send water down the wall or toward the foundation.',
      );
    } else if (key.contains('roof') || key.contains('shingle')) {
      points.add(
        'Roof openings let water reach underlayment and decking, which can lead to leaks in ceilings and attic mold.',
      );
    } else if (key.contains('siding') ||
        key.contains('paint') ||
        key.contains('peel')) {
      points.add(
        'Failed coatings expose substrate to UV and moisture, accelerating rot and reducing insulation performance.',
      );
    } else if (key.contains('window') ||
        key.contains('seal') ||
        key.contains('caulk')) {
      points.add(
        'Failed seals invite drafts and water at the rough opening — a common source of hidden wall damage.',
      );
    } else if (key.contains('foundation') || key.contains('crack')) {
      points.add(
        'Foundation movement or water paths can worsen seasonally; early sealing and drainage fixes limit structural risk.',
      );
    } else if (key.contains('chimney') || key.contains('flash')) {
      points.add(
        'Flashing failures are a top exterior leak source and often show first as interior stains near the chimney.',
      );
    } else if (key.contains('rust') ||
        key.contains('metal') ||
        key.contains('corrosion')) {
      points.add(
        'Active corrosion weakens fasteners and flashings; staining can also mask underlying moisture issues.',
      );
    } else if (key.contains('fascia') ||
        key.contains('soffit') ||
        key.contains('rot')) {
      points.add(
        'Soft wood at the eaves is often fed by gutter leaks; replace material only after the water source is fixed.',
      );
    } else {
      points.add(
        'Exterior defects compound over seasons — small openings become larger repair scopes if water keeps entering.',
      );
    }

    points.add(switch (severity) {
      'High' =>
        'Priority is high: delay raises the chance of interior damage and a much larger invoice.',
      'Medium' =>
        'Worth scheduling soon so wear does not spread to neighboring materials.',
      _ =>
        'Low urgency, but documenting and fixing early protects curb appeal and resale readiness.',
    });

    // De-dupe while preserving order.
    final seen = <String>{};
    return points.where(seen.add).toList();
  }

  /// Practical repair checklist for the surface-evidence sheet.
  List<String> get surfaceRepairSteps {
    final t = '${title.toLowerCase()} ${location.toLowerCase()}';
    if (isGroundDrainageFinding ||
        (t.contains('downspout') &&
            (t.contains('outlet') ||
                t.contains('grade') ||
                t.contains('foundation') ||
                t.contains('dumping')))) {
      return const [
        'After rain, check where water leaves the downspout or pipe.',
        'Extend outlets 4–6 ft from the foundation where practical.',
        'Clear mud, leaves, or splash blocks that trap water at the wall.',
        'Make sure soil slopes away from the house so water does not pool.',
      ];
    }
    if (isEaveGutterFinding ||
        t.contains('gutter') ||
        t.contains('downspout') ||
        t.contains('eave') ||
        t.contains('overflow')) {
      return const [
        'Clear leaves and sediment from gutters, hangers, and downspout elbows.',
        'Confirm the gutter slopes toward the outlets; re-secure loose hangers.',
        'Extend downspouts 4–6 ft from the foundation where practical.',
        'Add guards or schedule seasonal cleans if overflow keeps returning.',
      ];
    }
    if (t.contains('roof') || t.contains('shingle') || t.contains('ridge')) {
      return const [
        'Walk (or drone) ridges, valleys, and windward slopes; note missing tabs and soft spots.',
        'Replace damaged shingles and inspect underlayment where wet or dark.',
        'Clear debris from valleys; reseal pipe boots and step flashing as needed.',
        'If decking feels soft, stop DIY patches and book a licensed roofer.',
      ];
    }
    if (t.contains('wiring') ||
        t.contains('cable clutter') ||
        (t.contains('cable') && t.contains('exterior'))) {
      return const [
        'Do not cut or disconnect unknown exterior cables.',
        'Photograph entry points, junctions, and where runs enter the wall.',
        'Have a licensed electrician secure, consolidate, or conduit-route surface runs.',
        'After re-routing, reseal wall penetrations against water intrusion.',
      ];
    }
    if (t.contains('mismatched') ||
        t.contains('patched') ||
        (t.contains('patch') && t.contains('siding'))) {
      return const [
        'Map the full color-block / replacement board area on that elevation.',
        'Match course height, profile, and finish to the surrounding cladding where practical.',
        'Seal board edges, butt joints, and penetrations after replacement.',
        'Re-check the elevation after the next heavy rain for open seams.',
      ];
    }
    if (t.contains('siding') || t.contains('paint') || t.contains('peel')) {
      return const [
        'Scrape loose paint and sand to a firm feathered edge.',
        'Wash the surface; spot-prime bare wood or fiber cement.',
        'Apply two coats of exterior-grade finish matched to the elevation.',
        'Caulk butt joints and trim so moisture cannot re-enter behind the coating.',
      ];
    }
    if (t.contains('window') || t.contains('seal') || t.contains('caulk')) {
      return const [
        'Cut out failed caulk and clean dust/oil from the joint.',
        'Apply backer rod if the gap is deep, then exterior-grade sealant.',
        'Tool a smooth fillet; keep weep holes open at the sill.',
        'After the next rain, check for dampness at interior reveals.',
      ];
    }
    if (t.contains('foundation') || t.contains('crack') || t.contains('base')) {
      return const [
        'Measure and photo crack width/length for a monitoring baseline.',
        'Seal hairline cracks with masonry-compatible sealant or epoxy.',
        'Improve grade and downspout discharge so water flows away from the wall.',
        'Call a structural pro for wide, stepped, or rapidly growing cracks.',
      ];
    }
    if (t.contains('chimney') || t.contains('flash')) {
      return const [
        'Inspect step flashing and counter-flashing for gaps or rust.',
        'Repoint loose mortar; seal or recast a cracked crown.',
        'Confirm cricket/saddle drainage on the uphill roof side if present.',
        'Have a roofer water-test after repairs if interior stains exist.',
      ];
    }
    if (t.contains('rust') || t.contains('metal') || t.contains('corrosion')) {
      return const [
        'Wire-brush loose rust to sound metal; wipe clean.',
        'Treat remaining oxide with a rust converter if recommended.',
        'Prime and topcoat with metal-rated exterior paint.',
        'Replace heavily corroded fasteners, vents, or flashings.',
      ];
    }
    if (t.contains('fascia') || t.contains('soffit') || t.contains('rot')) {
      return const [
        'Probe soft boards with a screwdriver; mark full extent of rot.',
        'Fix the water source (gutter leak, missing drip edge) first.',
        'Replace rotten sections with primed exterior stock.',
        'Paint to match; verify ventilation openings remain clear.',
      ];
    }
    return const [
      'Document the area with clear, well-lit close-up photos.',
      'Stop active moisture sources (gutters, seals, grading) first.',
      'Repair or replace damaged material with exterior-rated products.',
      'Refinish and reseal; re-check after the next heavy rain.',
    ];
  }

  /// True when a highlight should be drawn (localized or strong zone fallback).
  ///
  /// Weak / closer-photo findings without Vision boxes skip the overlay so
  /// surface evidence does not invent a generic zone estimate. Zone estimates
  /// are reserved for High-severity, high-confidence calls only.
  bool get shouldShowSurfaceHighlight {
    if (hasLocalizedHighlight) return true;
    if (needsCloserPhoto) return false;
    if (severity != 'High') return false;
    if (confidence < 86) return false;
    return true;
  }

  /// Normalized highlight rect (0–1) for the surface-evidence photo overlay.
  ///
  /// Prefers Vision object localization when available. Zone estimates only
  /// when evidence is solid enough to justify a callout; otherwise empty.
  Rect get surfaceHighlight {
    if (hasLocalizedHighlight) {
      return Rect.fromLTWH(
        highlightLeft!.clamp(0.0, 0.94),
        highlightTop!.clamp(0.0, 0.94),
        // Prefer compact Vision boxes — avoid full-elevation blobs on phones.
        highlightWidth!.clamp(0.04, 0.58),
        highlightHeight!.clamp(0.04, 0.44),
      );
    }
    if (!shouldShowSurfaceHighlight) {
      return Rect.zero;
    }
    return zoneFallbackHighlight;
  }

  /// Generic zone estimate when no reliable Vision box is stored.
  /// Tight category bands only — last resort when evidence is solid.
  Rect get zoneFallbackHighlight {
    final key = '${title.toLowerCase()} ${location.toLowerCase()}';
    if (key.contains('chimney')) {
      return const Rect.fromLTWH(0.56, 0.04, 0.22, 0.20);
    }
    if (key.contains('roof') ||
        key.contains('ridge') ||
        key.contains('shingle')) {
      return const Rect.fromLTWH(0.22, 0.04, 0.56, 0.18);
    }
    if (key.contains('gutter') ||
        key.contains('eave') ||
        key.contains('fascia') ||
        key.contains('soffit')) {
      return const Rect.fromLTWH(0.12, 0.20, 0.76, 0.08);
    }
    if (key.contains('foundation') ||
        key.contains('base') ||
        key.contains('grade')) {
      return const Rect.fromLTWH(0.16, 0.80, 0.68, 0.12);
    }
    if (key.contains('window')) {
      return const Rect.fromLTWH(0.34, 0.34, 0.28, 0.26);
    }
    if (key.contains('siding') ||
        key.contains('wall') ||
        key.contains('paint')) {
      return const Rect.fromLTWH(0.14, 0.34, 0.30, 0.32);
    }
    // Stable pseudo-random box from title hash so each issue feels distinct.
    final h = title.hashCode.abs();
    final left = 0.16 + (h % 20) / 100;
    final top = 0.22 + ((h ~/ 20) % 18) / 100;
    return Rect.fromLTWH(left, top, 0.28, 0.24);
  }

  factory AnalysisIssue.fromJson(Map<String, dynamic> json) {
    return AnalysisIssue(
      title: json['title'] as String? ?? 'Detected issue',
      location: json['location'] as String? ?? 'Exterior surface',
      severity: json['severity'] as String? ?? 'Medium',
      cost: json['cost'] as String? ?? 'TBD',
      confidence: (json['confidence'] as num?)?.round() ?? 75,
      insight: json['insight'] as String? ?? '',
      photoIndex: (json['photoIndex'] as num?)?.round(),
      sourcePhotoLabel: json['sourcePhotoLabel'] as String? ?? '',
      needsCloserPhoto: json['needsCloserPhoto'] as bool? ?? false,
      highlightLeft: (json['highlightLeft'] as num?)?.toDouble(),
      highlightTop: (json['highlightTop'] as num?)?.toDouble(),
      highlightWidth: (json['highlightWidth'] as num?)?.toDouble(),
      highlightHeight: (json['highlightHeight'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'location': location,
    'severity': severity,
    'cost': cost,
    'confidence': confidence,
    'insight': insight,
    'photoIndex': photoIndex,
    'sourcePhotoLabel': sourcePhotoLabel,
    'needsCloserPhoto': needsCloserPhoto,
    if (highlightLeft != null) 'highlightLeft': highlightLeft,
    if (highlightTop != null) 'highlightTop': highlightTop,
    if (highlightWidth != null) 'highlightWidth': highlightWidth,
    if (highlightHeight != null) 'highlightHeight': highlightHeight,
  };
}

class AnalysisReport {
  final int overallScore;
  final String conditionLabel;
  final List<AnalysisIssue> issues;
  final String estimatedRepairRange;
  final String analysisSource; // e.g. Google Vision, Local placeholder
  final int photoCount;

  const AnalysisReport({
    required this.overallScore,
    required this.conditionLabel,
    required this.issues,
    required this.estimatedRepairRange,
    required this.analysisSource,
    required this.photoCount,
  });

  int get highCount => issues.where((i) => i.severity == 'High').length;
  int get mediumCount => issues.where((i) => i.severity == 'Medium').length;
  int get lowCount => issues.where((i) => i.severity == 'Low').length;

  /// Findings ordered for storytelling: High → Medium → Low, then confidence.
  List<AnalysisIssue> get issuesByPriority {
    final list = [...issues];
    list.sort((a, b) {
      final s = b.severityRank - a.severityRank;
      if (s != 0) return s;
      final c = b.confidence.compareTo(a.confidence);
      if (c != 0) return c;
      return a.title.compareTo(b.title);
    });
    return list;
  }

  AnalysisIssue? get topPriorityIssue =>
      issuesByPriority.isEmpty ? null : issuesByPriority.first;

  /// Score meaning in plain language (overall condition chapter).
  String get scoreMeaning {
    final s = overallScore;
    final engine = usedCloudVision
        ? 'Cloud Vision + local features'
        : 'on-device multi-feature screening';
    final coverage = photoCount <= 1
        ? 'single-photo coverage only'
        : photoCount <= 3
        ? '$photoCount-photo coverage (partial elevations)'
        : '$photoCount-photo multi-angle coverage';
    if (s >= 92) {
      return 'This $engine pass scores in the strong range with $coverage. Visible systems look serviceable from the angles provided — still not a licensed inspection.';
    }
    if (s >= 84) {
      return 'Screening looks generally sound ($engine, $coverage), with limited items worth planning — not an emergency picture from these photos.';
    }
    if (s >= 72) {
      return 'Screening condition is mixed ($engine, $coverage). Targeted repairs would improve weather protection; confirm scope on-site.';
    }
    if (s >= 58) {
      return 'Attention is warranted on this $engine pass ($coverage). One or more items should move up the priority list before the next season.';
    }
    return 'Multiple screening concerns are pulling the score down ($engine, $coverage). Focus on high-severity items first, then verify with a pro.';
  }

  /// Chapter 1 — overall condition narrative.
  String get conditionStory {
    final base = conditionLabel.trim().isEmpty
        ? 'Exterior photo screening completed.'
        : conditionLabel.trim();
    final lower = base.toLowerCase();

    // Honest empty path when Vision rejected non-exterior / weak evidence photos.
    if (lower.contains('insufficient exterior')) {
      final photoBit = photoCount == 1
          ? ' Based on a single photo.'
          : photoCount > 1
          ? ' Based on $photoCount photos.'
          : '';
      return '$base$photoBit No findings were generated because the set does not clearly show home exterior surfaces (roof, siding, foundation, gutters, etc.). '
          'Upload clear elevations of the house rather than people, indoor rooms, or unrelated objects.';
    }

    final photoBit = photoCount <= 0
        ? ''
        : photoCount == 1
        ? (usedCloudVision
              ? ' Based on a single photo with Google Cloud Vision — AI scene '
                    'labels can strengthen this one angle, but other elevations remain uncovered (lower confidence than a multi-shot set).'
              : ' Based on a single photo (Quick Scan) — one angle limits certainty, '
                    'so treat findings as a focused first look rather than a full home picture.')
        : (usedCloudVision
              ? ' Based on $photoCount photos with Google Cloud Vision + local features — multi-angle agreement raises trust vs a single shot.'
              : ' Based on $photoCount photos (on-device multi-feature screening) — multi-angle coverage improves confidence.');
    if (issues.isEmpty) {
      return photoCount == 1
          ? '$base$photoBit $scoreMeaning No significant exterior defects were flagged from this angle.'
          : '$base$photoBit $scoreMeaning No significant exterior defects were flagged in this screening pass.';
    }

    final lead = issuesByPriority.take(3).map((i) => i.storyTitle).toList();
    final leadText = lead.isEmpty
        ? 'exterior concerns'
        : lead.length == 1
        ? lead.first
        : '${lead.take(lead.length - 1).join(', ')} and ${lead.last}';

    final mix = <String>[];
    if (highCount > 0) mix.add('$highCount high');
    if (mediumCount > 0) mix.add('$mediumCount medium');
    if (lowCount > 0) mix.add('$lowCount low');
    final mixText = mix.isEmpty
        ? 'findings'
        : '${mix.join(', ')} priority finding${issues.length == 1 ? '' : 's'}';

    if (photoCount == 1) {
      return '$base$photoBit $scoreMeaning From this photo we flagged $mixText, led by $leadText. '
          'A full multi-angle set can raise confidence across the rest of the exterior.';
    }
    return '$base$photoBit $scoreMeaning We flagged $mixText, led by $leadText.';
  }

  /// True when this report came from a single-photo / Quick Scan capture.
  bool get isSinglePhotoScan => photoCount == 1;

  /// True when the report source indicates Google Cloud Vision was used.
  bool get usedCloudVision {
    final s = analysisSource.toLowerCase();
    return s.contains('vision') || s.contains('google cloud');
  }

  /// True when analysis fell back to local multi-feature (no key / Vision error).
  bool get usedLocalFallback {
    final s = analysisSource.toLowerCase();
    return s.contains('local') || s.contains('offline fallback');
  }

  /// Short badge for UI / PDF when [isSinglePhotoScan].
  static const singlePhotoBadge = 'Quick Scan · single photo';

  /// One calm, plain-language first impression for the score hero.
  ///
  /// Presentation only — does not change scoring or finding detection.
  String get calmHeadline {
    final lower = conditionLabel.toLowerCase();
    if (lower.contains('insufficient exterior')) {
      return 'These photos may not show a clear home exterior. '
          'Try roof, wall, and foundation angles in good light.';
    }
    if (issues.isEmpty) {
      return photoCount <= 1
          ? 'Looking solid from this angle — nothing elevated to chase right now.'
          : 'Looking solid overall — no high-priority exterior concerns from these photos.';
    }
    final top = topPriorityIssue;
    final focus = top == null ? 'the priority item' : top.homeownerTitle;
    if (highCount > 0) {
      return 'Worth a closer look soon. Start with $focus.';
    }
    if (mediumCount > 0) {
      return mediumCount == 1
          ? 'One item to plan: $focus. Nothing looks like an emergency from these photos.'
          : 'A few items to plan, starting with $focus. Nothing looks like an emergency from these photos.';
    }
    return 'Minor notes only. Overall condition looks fine from this screening.';
  }

  /// Short condition line under the score (no engine jargon).
  String get calmConditionLine {
    final lower = conditionLabel.toLowerCase();
    if (lower.contains('insufficient exterior')) {
      return 'Need clearer exterior photos';
    }
    if (issues.isEmpty) {
      return overallScore >= 90
          ? 'Strong exterior condition'
          : 'Solid exterior condition';
    }
    if (highCount > 0) return 'Needs attention this season';
    if (mediumCount >= 2) return 'Fair — plan some exterior work';
    if (mediumCount == 1) return 'Generally sound · one item to plan';
    return 'Generally sound · minor notes only';
  }

  /// Chapter 2 — highest priority focus.
  String get priorityStory {
    final top = topPriorityIssue;
    if (top == null) {
      if (conditionLabel.toLowerCase().contains('insufficient exterior')) {
        return 'Highest priority: none — capture clear exterior elevations before screening for defects.';
      }
      return photoCount == 1
          ? 'Highest priority: none — this single-angle scan did not elevate defects.'
          : 'Highest priority: none — no defects were elevated in this assessment.';
    }
    final n = issuesByPriority.where((i) => i.severity == top.severity).length;
    final confBit = 'confidence ${top.confidence}%';
    final photoBit = top.sourcePhotoDisplay.isNotEmpty
        ? ' · evidence: ${top.sourcePhotoDisplay}'
        : '';
    final closerBit = top.needsCloserPhoto
        ? ' Treat as a screening note until a closer photo is available.'
        : '';
    if (top.severity == 'High') {
      return 'Highest priority: ${top.storyTitle} at ${top.location} ($confBit$photoBit). '
          'Start here — high-severity items protect the rest of the home when fixed first.'
          '${n > 1 ? ' You have $n high-priority items total; tackle them before cosmetic work.' : ''}'
          '$closerBit';
    }
    if (top.severity == 'Medium') {
      return 'Highest priority: ${top.storyTitle} at ${top.location} ($confBit$photoBit). '
          'No high-severity alarms, so this is your lead repair to schedule this season.$closerBit';
    }
    return 'Highest priority: ${top.storyTitle} at ${top.location} ($confBit$photoBit). '
        'Only low-severity notes — optional maintenance when convenient.$closerBit';
  }

  /// Chapter 3 — recommendations / action plan.
  String get recommendationStory {
    if (issues.isEmpty) {
      if (conditionLabel.toLowerCase().contains('insufficient exterior')) {
        return 'Recommendations: re-capture front, side, rear, and roof/eave shots of the home in daylight, then re-run screening.';
      }
      return photoCount == 1
          ? 'Recommendations: keep seasonal maintenance and add more exterior angles after storms for a fuller screening picture.'
          : 'Recommendations: keep seasonal maintenance (gutters, seals, paint touch-ups) and re-scan after storms or if something new appears.';
    }
    final ranked = issuesByPriority;
    final buf = StringBuffer('Recommendations: ');
    // Concrete, finding-specific next steps for the top 1–2 items.
    for (var i = 0; i < ranked.length && i < 2; i++) {
      final issue = ranked[i];
      if (i > 0) buf.write(' Next: ');
      buf.write(
        issue.storyRecommendation
            .replaceFirst('Recommended: ', '')
            .replaceFirst('Recommended ', ''),
      );
      if (!buf.toString().trimRight().endsWith('.')) buf.write('.');
    }
    final closer = issues.where((i) => i.needsCloserPhoto).length;
    final more = issues.length > 2 ? issues.length - 2 : 0;
    if (more > 0) {
      buf.write(
        ' Then continue down the list by severity — $more other finding${more == 1 ? '' : 's'} remain.',
      );
    }
    if (closer > 0) {
      buf.write(
        ' $closer item${closer == 1 ? '' : 's'} need closer photos before treating them as firm diagnoses.',
      );
    }
    if (photoCount == 1) {
      buf.write(
        ' Because this is a single-photo scan, re-check uncovered elevations before large repairs.',
      );
    } else if (highCount == 0 && mediumCount > 0) {
      buf.write(' Bundle medium items with one contractor visit when you can.');
    }
    return buf.toString();
  }

  /// Chapter 4 — impact (risk + planning cost).
  String get impactStory {
    final range = estimatedRepairRange.trim().isEmpty
        ? 'TBD'
        : estimatedRepairRange.trim();
    if (conditionLabel.toLowerCase().contains('insufficient exterior')) {
      return 'Impact: no exterior repair scope from this set. Planning range not estimated. Capture true exterior elevations first.';
    }
    if (issues.isEmpty) {
      return photoCount == 1
          ? 'Impact: no elevated repair scope from this single angle. Planning range $range. Reassess with more elevations if weather events or new symptoms appear.'
          : 'Impact: no elevated repair scope from this scan. Planning range $range. Reassess if weather events or new symptoms appear.';
    }

    final systems = <String>{};
    for (final i in issuesByPriority.take(4)) {
      final t = i.title.toLowerCase();
      if (t.contains('roof') || t.contains('shingle')) {
        systems.add('roof weatherproofing');
      } else if (t.contains('gutter') || t.contains('downspout')) {
        systems.add('drainage');
      } else if (t.contains('foundation')) {
        systems.add('foundation moisture control');
      } else if (t.contains('wiring') || t.contains('cable')) {
        systems.add('exterior wiring / penetrations');
      } else if (t.contains('siding') ||
          t.contains('paint') ||
          t.contains('mismatched') ||
          t.contains('patched')) {
        systems.add('cladding / coatings');
      } else if (t.contains('window') || t.contains('seal')) {
        systems.add('openings / seals');
      } else if (t.contains('chimney') || t.contains('flash')) {
        systems.add('flashing');
      }
    }
    final systemBit = systems.isEmpty
        ? 'listed exterior systems'
        : systems.join(', ');

    final risk = highCount > 0
        ? 'Leaving high-priority defects open (especially $systemBit) raises the chance of interior water damage and a larger invoice.'
        : mediumCount > 0
        ? 'Medium issues on $systemBit rarely fail overnight, but they quietly expand repair scope over a season or two.'
        : 'Impact stays limited on $systemBit if you maintain coatings, seals, and drainage on a normal cycle.';

    final costBit = range.toUpperCase().startsWith('TBD')
        ? 'Combined planning range is withheld or TBD until stronger photo evidence supports dollar estimates ($range).'
        : 'Combined planning range for confidence-qualified findings is $range (not a bid — access, materials, and local labor set the real price).';

    final coverageBit = photoCount == 1
        ? ' Single-photo confidence is limited to this angle.'
        : ' Multi-photo coverage supports a broader exterior picture.';

    return 'Impact: $risk $costBit$coverageBit';
  }

  /// Ordered story beats for UI / PDF sections.
  List<({String title, String body})> get storyChapters => [
    (title: 'Overall condition', body: conditionStory),
    (title: 'Highest priority', body: priorityStory),
    (title: 'Recommendations', body: recommendationStory),
    (title: 'Impact', body: impactStory),
  ];

  /// Compact executive summary (one block).
  String get executiveSummary {
    return storyChapters.map((c) => '${c.title}: ${c.body}').join('\n\n');
  }

  /// Screening disclaimer for UI + PDF (not a licensed inspection).
  /// Canonical text lives in [PrivacyCopy] so all surfaces stay aligned.
  static const screeningDisclaimer = PrivacyCopy.screeningDisclaimer;

  /// Short chip/badge text for report headers.
  static const screeningBadge = PrivacyCopy.screeningBadge;

  /// Twin zones that currently have at least one finding.
  Set<TwinZone> get markedTwinZones => {for (final i in issues) i.twinZone};

  factory AnalysisReport.fromJson(Map<String, dynamic> json) {
    final rawIssues = json['issues'] as List<dynamic>? ?? const [];
    return AnalysisReport(
      overallScore: (json['overallScore'] as num?)?.round() ?? 0,
      conditionLabel: json['conditionLabel'] as String? ?? '',
      issues: rawIssues
          .map((e) => AnalysisIssue.fromJson(e as Map<String, dynamic>))
          .toList(),
      estimatedRepairRange: json['estimatedRepairRange'] as String? ?? 'TBD',
      analysisSource: json['analysisSource'] as String? ?? '',
      photoCount: (json['photoCount'] as num?)?.round() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'overallScore': overallScore,
    'conditionLabel': conditionLabel,
    'issues': issues.map((i) => i.toJson()).toList(),
    'estimatedRepairRange': estimatedRepairRange,
    'analysisSource': analysisSource,
    'photoCount': photoCount,
  };
}
