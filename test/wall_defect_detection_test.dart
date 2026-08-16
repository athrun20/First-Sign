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

  bool isSidingOrCladdingFinding(AnalysisIssue i) {
    final t = i.title.toLowerCase();
    return t.contains('siding') ||
        t.contains('cladding') ||
        (t.contains('crack') && !t.contains('foundation'));
  }

  test('window glass / shatter scene does not invent siding cracks', () {
    final report = service.analyzeFeatureSnapshots(
      [
        ExteriorFeatureSnapshot.healthyElevation(
          seed: 41,
          label: 'Broken window close-up',
        ),
      ],
      labels: const {
        'window': 0.90,
        'glass': 0.86,
        'brick': 0.72,
        'house': 0.70,
        'broken': 0.78,
        'damage': 0.62,
        'crack': 0.58,
      },
      visionMode: true,
      source: 'window glass not siding unit test',
      capturePhotos: [
        photo(
          index: 0,
          label: 'Broken window glass',
          slotId: CaptureShotId.problemCloseup,
        ),
      ],
    );

    final siding = report.issues.where(isSidingOrCladdingFinding);
    expect(
      siding,
      isEmpty,
      reason:
          'glass/window shatter must not mint siding cracks, got: '
          '${report.issues.map((i) => i.title).join(", ")}',
    );

    final windows = report.issues.where((i) {
      final t = i.title.toLowerCase();
      return t.contains('window') || t.contains('glass') || t.contains('glazing');
    });
    expect(
      windows,
      isNotEmpty,
      reason:
          'expected a window/glass finding, got: '
          '${report.issues.map((i) => i.title).join(", ")}',
    );
    expect(
      windows.first.title.toLowerCase(),
      anyOf(contains('broken'), contains('glass'), contains('window')),
    );
  });

  test('mismatched / patched siding surfaces as Medium lead finding', () {
    final report = service.analyzeFeatureSnapshots(
      [
        ExteriorFeatureSnapshot.mismatchedSiding(
          seed: 91,
          label: 'Front wall patch',
        ),
        ExteriorFeatureSnapshot.mismatchedSiding(
          seed: 92,
          label: 'Side elevation',
        ),
      ],
      labels: const {
        'siding': 0.86,
        'house': 0.90,
        'wall': 0.78,
        'discoloration': 0.72,
        'patch': 0.68,
        'window': 0.55,
      },
      visionMode: true,
      source: 'mismatched siding unit test',
    );

    final titles = report.issues.map((i) => i.title.toLowerCase()).join(' | ');
    final blob = '$titles ${report.conditionLabel.toLowerCase()}';

    expect(
      blob.contains('patch') ||
          blob.contains('mismatched') ||
          blob.contains('siding'),
      isTrue,
      reason: 'expected patched/mismatched siding, got: $titles',
    );
    expect(
      report.issues.any((i) => i.severity == 'Medium' || i.severity == 'High'),
      isTrue,
      reason:
          'expected Medium+ severity for clear patch work, got: '
          '${report.issues.map((i) => '${i.severity} ${i.title}').join('; ')}',
    );
    // Should not bury the wall defect under a lone window seal note.
    if (report.issues.isNotEmpty) {
      final lead = report.issues.first.title.toLowerCase();
      expect(
        lead.contains('siding') ||
            lead.contains('patch') ||
            lead.contains('mismatched'),
        isTrue,
        reason: 'lead finding should be siding patch, got: $lead',
      );
    }
  });

  test('exterior wiring clutter surfaces when labels support it', () {
    final report = service.analyzeFeatureSnapshots(
      [
        ExteriorFeatureSnapshot.exteriorWiringClutter(
          seed: 101,
          label: 'Wall cables',
        ),
        ExteriorFeatureSnapshot.exteriorWiringClutter(
          seed: 102,
          label: 'Side cables',
        ),
      ],
      labels: const {
        'house': 0.88,
        'siding': 0.74,
        'wall': 0.70,
        'cable': 0.82,
        'wiring': 0.78,
        'electrical': 0.60,
      },
      visionMode: true,
      source: 'wiring clutter unit test',
    );

    final titles = report.issues.map((i) => i.title.toLowerCase()).join(' | ');
    expect(
      titles.contains('wiring') || titles.contains('cable'),
      isTrue,
      reason: 'expected exterior wiring/cable finding, got: $titles',
    );
    expect(
      report.issues.any((i) => i.severity == 'Medium' || i.severity == 'High'),
      isTrue,
      reason: 'expected Medium+ for heavy cable clutter',
    );
  });

  test('weak indoor-like scenes still do not invent wall patch findings', () {
    final report = service.analyzeFeatureSnapshots(
      [ExteriorFeatureSnapshot.weakAmbiguous(seed: 61, label: 'Ambiguous')],
      labels: const {'house': 0.55, 'building': 0.48},
      visionMode: false,
      source: 'weak scene honesty unit test',
    );

    expect(report.highCount, 0);
    final titles = report.issues.map((i) => i.title.toLowerCase()).join(' | ');
    expect(
      titles.contains('mismatched') || titles.contains('patched siding'),
      isFalse,
      reason: 'weak scene must not invent patched siding: $titles',
    );
    expect(
      titles.contains('wiring') || titles.contains('cable clutter'),
      isFalse,
      reason: 'weak scene must not invent wiring clutter: $titles',
    );
  });

  test('healthy multi-angle still avoids false patch / wiring Mediums', () {
    final report = service.analyzeFeatureSnapshots(
      [
        ExteriorFeatureSnapshot.healthyElevation(seed: 11, label: 'Front'),
        ExteriorFeatureSnapshot.healthyElevation(seed: 12, label: 'Left'),
        ExteriorFeatureSnapshot.healthyElevation(seed: 13, label: 'Right'),
      ],
      labels: const {
        'house': 0.92,
        'building': 0.88,
        'siding': 0.70,
        'roof': 0.55,
        'window': 0.60,
      },
      visionMode: false,
      source: 'healthy honesty unit test',
    );

    expect(report.overallScore, greaterThanOrEqualTo(88));
    expect(report.highCount, 0);
    final mediumTitles = report.issues
        .where((i) => i.severity == 'Medium' || i.severity == 'High')
        .map((i) => i.title.toLowerCase())
        .toList();
    expect(
      mediumTitles.any(
        (t) => t.contains('mismatched') || t.contains('patched'),
      ),
      isFalse,
      reason: 'healthy home must not invent patched siding: $mediumTitles',
    );
    expect(
      mediumTitles.any((t) => t.contains('wiring') || t.contains('cable')),
      isFalse,
      reason: 'healthy home must not invent wiring clutter: $mediumTitles',
    );
  });

  test('grade-only pipe/soil photo does not invent siding cracks', () {
    final report = service.analyzeFeatureSnapshots(
      [
        ExteriorFeatureSnapshot.groundDischarge(
          seed: 71,
          label: 'White discharge pipes at grade',
        ),
      ],
      labels: const {
        'pipe': 0.82,
        'downspout': 0.74,
        'soil': 0.62,
        'mulch': 0.55,
        'foundation': 0.58,
        // Spurious wall/crack tags from Vision must not mint cladding cracks.
        'house': 0.72,
        'building': 0.65,
        'wall': 0.55,
        'crack': 0.62,
        'chip': 0.50,
        'damage': 0.48,
      },
      visionMode: true,
      source: 'grade-only siding false-positive unit test',
      capturePhotos: [
        photo(
          index: 0,
          label: 'White discharge pipes at grade',
          slotId: CaptureShotId.problemCloseup,
        ),
      ],
    );

    final sidingIssues = report.issues.where(isSidingOrCladdingFinding);
    expect(
      sidingIssues,
      isEmpty,
      reason:
          'grade-only pipe/soil must not invent siding/cladding cracks, got: '
          '${report.issues.map((i) => i.title).join(", ")}',
    );

    // Prefer drainage when outlet cues support it; otherwise empty/insufficient.
    final drainage = report.issues.where((i) => i.isGroundDrainageFinding);
    if (drainage.isNotEmpty) {
      expect(drainage.first.confidence, lessThanOrEqualTo(84));
      final steps = drainage.first.surfaceRepairSteps.join(' ').toLowerCase();
      expect(steps.contains('scrape loose paint'), isFalse);
      expect(
        steps.contains('extend') || steps.contains('foundation'),
        isTrue,
        reason: 'drainage steps expected, got: $steps',
      );
    }

    // Quick Scan honesty / single-photo limits remain.
    expect(report.isSinglePhotoScan, isTrue);
  });

  test('grade-only set maps to drainage or insufficient, not cladding', () {
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
        'pipe': 0.80,
        'downspout': 0.76,
        'drain': 0.70,
        'foundation': 0.60,
        'soil': 0.58,
        'house': 0.55,
        'wall': 0.48,
        'crack': 0.58,
      },
      visionMode: true,
      source: 'grade-only drainage-not-cladding unit test',
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

    final titles = report.issues.map((i) => i.title.toLowerCase()).join(' | ');
    expect(
      report.issues.any(isSidingOrCladdingFinding),
      isFalse,
      reason: 'grade-only must not produce cladding findings: $titles',
    );
    expect(
      titles.contains('paint') || titles.contains('peel'),
      isFalse,
      reason: 'grade-only must keep paint suppression: $titles',
    );

    final drainage = report.issues.where((i) => i.isGroundDrainageFinding);
    if (report.issues.isNotEmpty) {
      expect(
        drainage,
        isNotEmpty,
        reason:
            'if findings exist they should be drainage, not cladding: $titles',
      );
      expect(drainage.first.confidence, lessThanOrEqualTo(84));
    }
  });

  test('siding finding primary photo is wall/siding, not grade', () {
    final report = service.analyzeFeatureSnapshots(
      [
        ExteriorFeatureSnapshot.groundDischarge(
          seed: 81,
          label: 'Discharge pipes wet soil',
        ),
        ExteriorFeatureSnapshot.crackedSiding(
          seed: 71,
          label: 'Cracked clapboard wall',
        ),
        ExteriorFeatureSnapshot.crackedSiding(
          seed: 72,
          label: 'Siding corner crack close-up',
        ),
      ],
      labels: const {
        'siding': 0.88,
        'wall': 0.80,
        'crack': 0.80,
        'house': 0.90,
        'pipe': 0.55,
        'downspout': 0.50,
        'soil': 0.45,
      },
      visionMode: true,
      source: 'siding primary photo unit test',
      capturePhotos: [
        photo(
          index: 0,
          label: 'Discharge pipes wet soil',
          slotId: CaptureShotId.problemCloseup,
        ),
        photo(
          index: 1,
          label: 'Cracked clapboard wall',
          slotId: CaptureShotId.front,
        ),
        photo(
          index: 2,
          label: 'Siding corner crack close-up',
          slotId: CaptureShotId.left,
        ),
      ],
    );

    final siding = report.issues.cast<AnalysisIssue?>().firstWhere(
      (i) {
        final t = i!.title.toLowerCase();
        return t.contains('siding') ||
            t.contains('cladding') ||
            (t.contains('crack') && !t.contains('foundation'));
      },
      orElse: () => null,
    );
    expect(siding, isNotNull, reason: 'expected a siding/crack finding');
    final label = siding!.sourcePhotoLabel.toLowerCase();
    expect(
      label.contains('pipe') ||
          label.contains('soil') ||
          label.contains('discharge') ||
          label.contains('outlet') ||
          label.contains('grade'),
      isFalse,
      reason: 'siding must not bind to grade/outlet photo, got: $label',
    );
    expect(
      label.contains('siding') ||
          label.contains('wall') ||
          label.contains('clapboard') ||
          label.contains('crack'),
      isTrue,
      reason: 'siding primary should be wall/cladding photo, got: $label',
    );

    // Crack repair steps — not paint scrape.
    final steps = siding.surfaceRepairSteps.join(' ').toLowerCase();
    expect(steps.contains('scrape loose paint'), isFalse, reason: steps);
    expect(
      steps.contains('replace') ||
          steps.contains('crack') ||
          steps.contains('board') ||
          steps.contains('course'),
      isTrue,
      reason: 'crack findings need cladding repair steps: $steps',
    );
  });

  test('cracked siding repair steps are not paint scrape', () {
    const issue = AnalysisIssue(
      title: 'Cracked / Damaged Siding',
      location: 'Wall faces, corners & butt joints',
      severity: 'Medium',
      cost: r'$1,200 – $3,200',
      confidence: 86,
      insight: 'Cladding damage is supported by fracture-like linear structure.',
    );
    expect(issue.homeownerTitle.toLowerCase(), contains('siding crack'));
    final steps = issue.surfaceRepairSteps.join(' ').toLowerCase();
    expect(steps.contains('scrape loose paint'), isFalse);
    expect(steps.contains('replace'), isTrue);
    expect(steps.contains('crack') || steps.contains('board'), isTrue);
  });
}
