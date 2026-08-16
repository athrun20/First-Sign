import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pillar_ai/models/analysis_models.dart';
import 'package:pillar_ai/models/capture_models.dart';
import 'package:pillar_ai/services/analysis_feature_snapshot.dart';
import 'package:pillar_ai/services/exterior_analysis_service.dart';

void main() {
  final service = ExteriorAnalysisService(forceLocalOnly: true);

  CapturePhoto photo({
    required int index,
    required String label,
    CaptureShotId? slotId,
  }) {
    return CapturePhoto(
      file: XFile.fromData(
        Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xD9]),
        name: 'photo_$index.jpg',
        mimeType: 'image/jpeg',
      ),
      label: label,
      index: index,
      slotId: slotId,
    );
  }

  test('grade-only photos do not invent peeling exterior paint', () {
    final report = service.analyzeFeatureSnapshots(
      [
        ExteriorFeatureSnapshot.groundDischarge(
          seed: 71,
          label: 'White discharge pipes at grade',
        ),
        ExteriorFeatureSnapshot.groundDischarge(
          seed: 72,
          label: 'Wet soil near foundation outlet',
        ),
      ],
      labels: const {
        'pipe': 0.82,
        'downspout': 0.76,
        'drain': 0.70,
        'foundation': 0.62,
        'soil': 0.58,
        'house': 0.55,
        // Spurious paint-ish tags must not mint peel on grade-only set.
        'chip': 0.50,
        'trim': 0.40,
      },
      visionMode: true,
      source: 'grade-only paint false-positive unit test',
      capturePhotos: [
        photo(
          index: 0,
          label: 'White discharge pipes at grade',
          slotId: CaptureShotId.problemCloseup,
        ),
        photo(
          index: 1,
          label: 'Wet soil near foundation outlet',
          slotId: CaptureShotId.front,
        ),
      ],
    );

    final paintIssues = report.issues.where((i) {
      final t = i.title.toLowerCase();
      return t.contains('paint') || t.contains('peel') || t.contains('coating');
    });
    expect(
      paintIssues,
      isEmpty,
      reason:
          'grade-only set must not invent paint/peel findings, got: '
          '${report.issues.map((i) => i.title).join(", ")}',
    );

    // Drainage finding may still exist; confidence cap behavior is unchanged.
    final drainage = report.issues.where((i) => i.isGroundDrainageFinding);
    if (drainage.isNotEmpty) {
      expect(drainage.first.confidence, lessThanOrEqualTo(84));
    }
  });

  test('paint visual evidence chips are not gutter language', () {
    const issue = AnalysisIssue(
      title: 'Peeling / Failing Exterior Paint',
      location: 'Sun-exposed walls, trim & fascia',
      severity: 'Medium',
      cost: r'$1,100 – $2,900',
      confidence: 88,
      insight: 'Failing film on wall surfaces.',
    );

    final cues = issue.forensicVisualCues.join(' ').toLowerCase();
    expect(cues.contains('gutter'), isFalse, reason: cues);
    expect(cues.contains('roof edge'), isFalse, reason: cues);
    expect(cues.contains('leaves'), isFalse, reason: cues);
    expect(cues.contains('spilled over'), isFalse, reason: cues);
    expect(
      cues.contains('peel') ||
          cues.contains('flak') ||
          cues.contains('coating') ||
          cues.contains('bare wood') ||
          cues.contains('blister'),
      isTrue,
      reason: 'paint cues should describe coating failure: $cues',
    );

    // Legacy location wording with "eaves" must still not inherit gutter chips.
    const legacyLocation = AnalysisIssue(
      title: 'Peeling / Failing Exterior Paint',
      location: 'Sun-exposed walls, trim & eaves',
      severity: 'Medium',
      cost: r'$1,100 – $2,900',
      confidence: 88,
      insight: 'Failing film on wall surfaces.',
    );
    final legacyCues = legacyLocation.forensicVisualCues.join(' ').toLowerCase();
    expect(legacyCues.contains('gutter'), isFalse, reason: legacyCues);
    expect(legacyCues.contains('stained'), isFalse, reason: legacyCues);
    expect(legacyCues.contains('leaves'), isFalse, reason: legacyCues);
  });

  test('primary photo for paint is wall/trim, not ground outlet', () {
    final report = service.analyzeFeatureSnapshots(
      [
        ExteriorFeatureSnapshot.groundDischarge(
          seed: 81,
          label: 'Discharge pipes wet soil',
        ),
        ExteriorFeatureSnapshot.peelingPaint(
          seed: 51,
          label: 'Peeling white paint on clapboard',
        ),
        ExteriorFeatureSnapshot.peelingPaint(
          seed: 52,
          label: 'Paint peel wall close-up',
        ),
      ],
      labels: const {
        'paint': 0.82,
        'peel': 0.78,
        'flake': 0.62,
        'wall': 0.70,
        'house': 0.80,
        'siding': 0.60,
        'pipe': 0.55,
        'downspout': 0.50,
      },
      visionMode: true,
      source: 'paint primary photo unit test',
      capturePhotos: [
        photo(
          index: 0,
          label: 'Discharge pipes wet soil',
          slotId: CaptureShotId.problemCloseup,
        ),
        photo(
          index: 1,
          label: 'Peeling white paint on clapboard',
          slotId: CaptureShotId.front,
        ),
        photo(
          index: 2,
          label: 'Paint peel wall close-up',
          slotId: CaptureShotId.left,
        ),
      ],
    );

    final paint = report.issues.cast<AnalysisIssue?>().firstWhere(
      (i) {
        final t = i!.title.toLowerCase();
        return t.contains('paint') || t.contains('peel');
      },
      orElse: () => null,
    );
    expect(paint, isNotNull, reason: 'expected a paint finding with wall photos');
    final label = paint!.sourcePhotoLabel.toLowerCase();
    expect(
      label.contains('pipe') ||
          label.contains('soil') ||
          label.contains('discharge') ||
          label.contains('outlet') ||
          label.contains('grade'),
      isFalse,
      reason: 'paint must not bind to grade/outlet photo, got: $label',
    );
    expect(
      label.contains('paint') ||
          label.contains('peel') ||
          label.contains('wall') ||
          label.contains('clapboard'),
      isTrue,
      reason: 'paint primary should be wall/trim photo, got: $label',
    );

    final cues = paint.forensicVisualCues.join(' ').toLowerCase();
    expect(cues.contains('gutter'), isFalse, reason: cues);
  });

  test('real peeling paint snapshots still surface paint finding', () {
    final report = service.analyzeFeatureSnapshots(
      [
        ExteriorFeatureSnapshot.peelingPaint(
          seed: 51,
          label: 'Peeling white paint on clapboard',
        ),
        ExteriorFeatureSnapshot.peelingPaint(
          seed: 52,
          label: 'Paint peel close-up',
        ),
      ],
      labels: const {
        'paint': 0.80,
        'peel': 0.76,
        'flake': 0.60,
        'house': 0.70,
        'wall': 0.55,
      },
      visionMode: false,
      source: 'paint positive control unit test',
    );
    final titles = report.issues.map((i) => i.title.toLowerCase()).join(' | ');
    expect(
      titles.contains('paint') || titles.contains('peel'),
      isTrue,
      reason: 'expected paint/peel finding, got: $titles',
    );
  });

  /// Device regression: Problem close-up of dirt/plants/pipe must never own
  /// paint primary evidence — even when soil texture looks peel-like and the
  /// caption is the generic guided-slot title.
  test('high-peel grade problem close-up cannot own paint primary', () {
    // Soil / mulch / pipe frame with peel-like luminance variance (device bug).
    const gradeHighPeel = ExteriorFeatureSnapshot(
      brightness: 110,
      contrast: 48,
      edgeDensity: 0.18,
      topEdgeDensity: 0.06,
      midEdgeDensity: 0.10,
      botEdgeDensity: 0.30,
      horizontalBanding: 0.10,
      verticalBanding: 0.22,
      greenDominance: 0.16,
      greyDominance: 0.30,
      rustDominance: 0.03,
      darkPatchRatio: 0.24,
      darkTopBias: 0.06,
      lowerThirdDark: 0.58,
      midToneDominance: 0.40,
      highLuminanceVariance: 0.62,
      vegetationNear: 0.28,
      roofSignal: 0.10,
      wallSignal: 0.40,
      foundationSignal: 0.58,
      overallDistress: 0.36,
      crackLineScore: 0.10,
      peelingScore: 0.64, // soil texture masquerading as peel
      moistureStainScore: 0.40,
      gutterLineScore: 0.08,
      highTextureChaos: false,
      hashSeed: 91,
      label: 'Problem close-up',
    );

    final report = service.analyzeFeatureSnapshots(
      [
        gradeHighPeel,
        ExteriorFeatureSnapshot.peelingPaint(
          seed: 51,
          label: 'Front of home',
        ),
        ExteriorFeatureSnapshot.peelingPaint(
          seed: 52,
          label: 'Left side',
        ),
      ],
      labels: const {
        'paint': 0.82,
        'peel': 0.78,
        'flake': 0.62,
        'wall': 0.70,
        'house': 0.80,
        'siding': 0.55,
        'pipe': 0.70,
        'downspout': 0.60,
        'soil': 0.55,
        'plant': 0.50,
      },
      visionMode: true,
      source: 'grade problem close-up paint primary race unit test',
      capturePhotos: [
        photo(
          index: 0,
          label: 'Problem close-up',
          slotId: CaptureShotId.problemCloseup,
        ),
        photo(
          index: 1,
          label: 'Front of home',
          slotId: CaptureShotId.front,
        ),
        photo(
          index: 2,
          label: 'Left side',
          slotId: CaptureShotId.left,
        ),
      ],
    );

    final paint = report.issues.cast<AnalysisIssue?>().firstWhere(
      (i) {
        final t = i!.title.toLowerCase();
        return t.contains('paint') || t.contains('peel');
      },
      orElse: () => null,
    );
    expect(paint, isNotNull, reason: 'wall elevations should still yield paint');
    expect(
      paint!.photoIndex,
      isNotNull,
      reason: 'paint must bind a wall host photo, not unbound grade fallback',
    );
    expect(
      paint.photoIndex,
      isNot(0),
      reason:
          'paint must not use Problem close-up grade frame as primary '
          '(photoIndex=${paint.photoIndex}, label=${paint.sourcePhotoLabel})',
    );
    final label = paint.sourcePhotoLabel.toLowerCase();
    expect(
      label.contains('problem') ||
          label.contains('pipe') ||
          label.contains('soil') ||
          label.contains('discharge') ||
          label.contains('grade') ||
          label.contains('outlet'),
      isFalse,
      reason: 'paint primary must be wall/trim elevation, got: $label',
    );
    expect(
      label.contains('front') ||
          label.contains('left') ||
          label.contains('wall') ||
          label.contains('paint') ||
          label.contains('side'),
      isTrue,
      reason: 'paint primary should be wall elevation photo, got: $label',
    );

    // Drainage may still use the grade close-up if present.
    final drainage = report.issues.where((i) => i.isGroundDrainageFinding);
    for (final d in drainage) {
      // Not required to exist; if it does, grade photo is allowed.
      if (d.photoIndex != null) {
        expect(
          d.photoIndex == 0 ||
              d.sourcePhotoLabel.toLowerCase().contains('problem') ||
              d.sourcePhotoLabel.toLowerCase().contains('pipe') ||
              d.sourcePhotoLabel.toLowerCase().contains('soil') ||
              d.sourcePhotoLabel.toLowerCase().contains('front') ||
              d.sourcePhotoLabel.toLowerCase().contains('left'),
          isTrue,
        );
      }
    }
  });

  test('generic Problem close-up grade-only set cannot own paint primary', () {
    const gradeOnly = ExteriorFeatureSnapshot(
      brightness: 112,
      contrast: 44,
      edgeDensity: 0.16,
      topEdgeDensity: 0.06,
      midEdgeDensity: 0.10,
      botEdgeDensity: 0.28,
      horizontalBanding: 0.10,
      verticalBanding: 0.26,
      greenDominance: 0.14,
      greyDominance: 0.28,
      rustDominance: 0.03,
      darkPatchRatio: 0.22,
      darkTopBias: 0.06,
      lowerThirdDark: 0.56,
      midToneDominance: 0.42,
      highLuminanceVariance: 0.58,
      vegetationNear: 0.24,
      roofSignal: 0.10,
      wallSignal: 0.38,
      foundationSignal: 0.60,
      overallDistress: 0.34,
      crackLineScore: 0.10,
      peelingScore: 0.60,
      moistureStainScore: 0.38,
      gutterLineScore: 0.08,
      highTextureChaos: false,
      hashSeed: 93,
      label: 'Problem close-up',
    );

    final report = service.analyzeFeatureSnapshots(
      [gradeOnly, gradeOnly.copyWithSeed(94)],
      labels: const {
        // Spurious paint tags + structure — still no wall host photo.
        'paint': 0.70,
        'peel': 0.65,
        'chip': 0.50,
        'house': 0.55,
        'pipe': 0.80,
        'downspout': 0.72,
        'soil': 0.60,
        'plant': 0.55,
      },
      visionMode: true,
      source: 'grade-only generic close-up paint unit test',
      capturePhotos: [
        photo(
          index: 0,
          label: 'Problem close-up',
          slotId: CaptureShotId.problemCloseup,
        ),
        photo(
          index: 1,
          label: 'Problem close-up',
          slotId: CaptureShotId.problemCloseup,
        ),
      ],
    );

    final paintIssues = report.issues.where((i) {
      final t = i.title.toLowerCase();
      return t.contains('paint') || t.contains('peel') || t.contains('coating');
    }).toList();

    // Prefer drop; if any residual paint survives, it must not bind grade photo.
    for (final p in paintIssues) {
      expect(
        p.photoIndex,
        isNull,
        reason:
            'grade-only set must not own paint primary photo, got '
            'index=${p.photoIndex} label=${p.sourcePhotoLabel}',
      );
      final label = p.sourcePhotoLabel.toLowerCase();
      expect(
        label.contains('problem') ||
            label.contains('pipe') ||
            label.contains('soil') ||
            label.contains('grade'),
        isFalse,
        reason: 'paint sourcePhotoLabel must not be grade frame: $label',
      );
    }

    // Stronger preference: drop entirely when no wall host exists.
    expect(
      paintIssues,
      isEmpty,
      reason:
          'grade-only Problem close-up set should drop paint findings, got: '
          '${report.issues.map((i) => i.title).join(", ")}',
    );
  });
}

extension on ExteriorFeatureSnapshot {
  ExteriorFeatureSnapshot copyWithSeed(int seed) {
    return ExteriorFeatureSnapshot(
      brightness: brightness,
      contrast: contrast,
      edgeDensity: edgeDensity,
      topEdgeDensity: topEdgeDensity,
      midEdgeDensity: midEdgeDensity,
      botEdgeDensity: botEdgeDensity,
      horizontalBanding: horizontalBanding,
      verticalBanding: verticalBanding,
      greenDominance: greenDominance,
      greyDominance: greyDominance,
      rustDominance: rustDominance,
      darkPatchRatio: darkPatchRatio,
      darkTopBias: darkTopBias,
      lowerThirdDark: lowerThirdDark,
      midToneDominance: midToneDominance,
      highLuminanceVariance: highLuminanceVariance,
      vegetationNear: vegetationNear,
      roofSignal: roofSignal,
      wallSignal: wallSignal,
      foundationSignal: foundationSignal,
      overallDistress: overallDistress,
      crackLineScore: crackLineScore,
      peelingScore: peelingScore,
      moistureStainScore: moistureStainScore,
      gutterLineScore: gutterLineScore,
      highTextureChaos: highTextureChaos,
      hashSeed: seed,
      label: label,
    );
  }
}
