import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pillar_ai/models/analysis_models.dart';
import 'package:pillar_ai/models/capture_models.dart';
import 'package:pillar_ai/services/analysis_feature_snapshot.dart';
import 'package:pillar_ai/services/exterior_analysis_service.dart';

void main() {
  group('Drainage findings — eave vs ground', () {
    final service = ExteriorAnalysisService(forceLocalOnly: true);

    test('eave overflow photos keep gutter/roof-edge language', () {
      final report = service.analyzeFeatureSnapshots(
        [
          ExteriorFeatureSnapshot.gutterOverflow(seed: 31, label: 'Eave'),
          ExteriorFeatureSnapshot.gutterOverflow(seed: 32, label: 'Side eave'),
        ],
        labels: const {
          'gutter': 0.86,
          'downspout': 0.70,
          'leaf': 0.62,
          'debris': 0.58,
          'roof': 0.50,
        },
        visionMode: true,
        source: 'eave overflow unit test',
      );

      final issue = _firstDrainageIssue(report);
      final blob = _issueBlob(issue);

      // Clear eave case should talk about gutters / roof edge, not ground pipes.
      expect(
        blob.contains('gutter') ||
            blob.contains('roof edge') ||
            blob.contains('overflow'),
        isTrue,
        reason: 'eave case should use gutter/overflow wording: $blob',
      );
      expect(
        issue.title.toLowerCase().contains('dumping near foundation'),
        isFalse,
        reason: 'eave overflow should not use pure ground-discharge title',
      );
    });

    test('ground-level discharge photos avoid clogged-gutter-at-eave copy', () {
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
          'downspout': 0.82,
          'pipe': 0.74,
          'drain': 0.68,
          'foundation': 0.60,
          'concrete': 0.52,
        },
        visionMode: true,
        source: 'ground discharge unit test',
      );

      final issue = _firstDrainageIssue(
        report,
        reason:
            'expected a drainage/outlet finding, got: '
            '${report.issues.map((i) => i.title).join(", ")}',
      );
      final blob = _issueBlob(issue);
      final cues = issue.forensicVisualCues.join(' ').toLowerCase();

      // Must not claim clogged gutter at eave when photo is pipes at grade.
      expect(
        blob.contains('clogging & overflow') ||
            blob.contains('eave lines') ||
            blob.contains('linear disruption along the eave'),
        isFalse,
        reason: 'must not reuse eave clogging wording on ground photo: $blob',
      );
      expect(
        cues.contains('linear disruption along the eave'),
        isFalse,
        reason: 'visual cues must not use eave jargon for ground discharge',
      );

      // Prefer ground / outlet language.
      final groundLanguage =
          blob.contains('foundation') ||
          blob.contains('outlet') ||
          blob.contains('downspout') ||
          blob.contains('dumping') ||
          blob.contains('grade') ||
          blob.contains('soil') ||
          blob.contains('ground');
      expect(
        groundLanguage || issue.isGroundDrainageFinding,
        isTrue,
        reason: 'ground discharge should use outlet/foundation language: $blob',
      );

      // Must not stay as pure eave overflow when evidence is grade pipes.
      expect(
        issue.title.toLowerCase().contains('possible gutter overflow'),
        isFalse,
        reason: 'ground primary evidence must not keep eave overflow title',
      );
      expect(issue.isGroundDrainageFinding, isTrue);
      expect(
        issue.forensicAffectedMaterial.toLowerCase(),
        isNot(contains('roof covering')),
      );

      // Confidence should not sound certain on zone-level ground estimates.
      expect(issue.confidence, lessThanOrEqualTo(84));
    });

    test('mixed set with grade-primary photo chooses ground discharge title', () {
      final report = service.analyzeFeatureSnapshots(
        [
          ExteriorFeatureSnapshot.groundDischarge(
            seed: 81,
            label: 'Discharge pipes wet soil',
          ),
          ExteriorFeatureSnapshot.healthyElevation(
            seed: 82,
            label: 'Front elevation',
          ),
        ],
        labels: const {
          'pipe': 0.80,
          'downspout': 0.76,
          'drain': 0.70,
          'foundation': 0.55,
        },
        visionMode: true,
        source: 'mixed grade-primary unit test',
      );

      final issue = _firstDrainageIssue(report);
      expect(
        issue.title.toLowerCase(),
        contains('dumping near foundation'),
        reason: 'got ${issue.title}',
      );
      expect(issue.location.toLowerCase(), contains('grade'));
    });

    test('homeowner copy stays plain for ground discharge findings', () {
      const issue = AnalysisIssue(
        title: 'Water May Be Dumping Near Foundation',
        location: 'Downspout outlets & soil at grade',
        severity: 'Medium',
        cost: r'$280 – $900',
        confidence: 78,
        insight:
            'Photos look more like water leaving near the foundation than a clogged gutter at the roof edge.',
      );

      expect(issue.isGroundDrainageFinding, isTrue);
      expect(issue.isEaveGutterFinding, isFalse);

      final cues = issue.forensicVisualCues.join(' ').toLowerCase();
      expect(cues.contains('linear disruption'), isFalse);
      expect(cues.contains('tab geometry'), isFalse);
      expect(cues.contains('elevation zone'), isFalse);
      expect(
        cues.contains('pipe') ||
            cues.contains('downspout') ||
            cues.contains('wet') ||
            cues.contains('soil') ||
            cues.contains('foundation'),
        isTrue,
      );

      final reasoning = issue.forensicAiReasoning.toLowerCase();
      expect(reasoning.contains('the model'), isFalse);
      expect(reasoning.contains('photo screening'), isTrue);

      // Zone-only → do not present as High Confidence.
      expect(issue.forensicConfidenceTitle, isNot(equals('High Confidence')));

      final steps = issue.surfaceRepairSteps.join(' ').toLowerCase();
      expect(steps.contains('extend'), isTrue);
      expect(steps.contains('foundation'), isTrue);
    });

    test('homeowner copy for eave overflow stays plain and eave-focused', () {
      const issue = AnalysisIssue(
        title: 'Possible Gutter Overflow',
        location: 'Roof edge / gutters',
        severity: 'Medium',
        cost: r'$450 – $1,200',
        confidence: 84,
        insight:
            'Photos suggest gutters may be clogged or overflowing at the roof edge.',
        highlightLeft: 0.1,
        highlightTop: 0.2,
        highlightWidth: 0.7,
        highlightHeight: 0.08,
      );

      expect(issue.isGroundDrainageFinding, isFalse);
      expect(issue.isEaveGutterFinding, isTrue);

      final cues = issue.forensicVisualCues.join(' ').toLowerCase();
      expect(cues.contains('linear disruption'), isFalse);
      expect(
        cues.contains('gutter') ||
            cues.contains('roof edge') ||
            cues.contains('overflow') ||
            cues.contains('debris'),
        isTrue,
      );
      expect(cues.contains('muddy soil'), isFalse);

      final zone = issue.surfaceZoneLabel.toLowerCase();
      expect(zone.contains('ground'), isFalse);
      expect(zone.contains('gutter') || zone.contains('roof'), isTrue);

      // "Roof edge / gutters" must not map material to roof covering.
      expect(
        issue.forensicAffectedMaterial.toLowerCase(),
        isNot(contains('roof covering')),
      );
      expect(
        issue.forensicAffectedMaterial.toLowerCase(),
        anyOf(contains('gutter'), contains('downspout')),
      );
      final steps = issue.surfaceRepairSteps.join(' ').toLowerCase();
      expect(
        steps.contains('clear leaves') || steps.contains('gutter'),
        isTrue,
      );
      expect(steps.contains('scrape loose paint'), isFalse);
    });

    test('paint finding does not get gutter-cleaning steps', () {
      const paint = AnalysisIssue(
        title: 'Peeling / Failing Exterior Paint',
        location: 'Front eaves & trim',
        severity: 'Medium',
        cost: r'$400 – $1,200',
        confidence: 80,
        insight: 'Paint film is separating on trim near the eaves.',
      );
      final steps = paint.surfaceRepairSteps.join(' ').toLowerCase();
      expect(steps.contains('scrape'), isTrue);
      expect(steps.contains('prime') || steps.contains('coat'), isTrue);
      expect(steps.contains('clear leaves'), isFalse);
      expect(steps.contains('gutter'), isFalse);
      expect(paint.storyRecommendation.toLowerCase(), contains('paint'));
      expect(
        paint.storyRecommendation.toLowerCase(),
        isNot(contains('clear leaves')),
      );
    });

    test('full-story What to do names each finding with matching steps', () {
      const report = AnalysisReport(
        overallScore: 72,
        conditionLabel: 'Attention needed — plan repairs (screening)',
        estimatedRepairRange: r'$700 – $2,000',
        analysisSource: 'test',
        photoCount: 3,
        issues: [
          AnalysisIssue(
            title: 'Possible Gutter Overflow',
            location: 'Roof edge / gutters',
            severity: 'Medium',
            cost: r'$450 – $1,200',
            confidence: 82,
            insight: 'Gutters may overflow at the roof edge.',
          ),
          AnalysisIssue(
            title: 'Peeling / Failing Exterior Paint',
            location: 'Front wall',
            severity: 'Medium',
            cost: r'$400 – $1,100',
            confidence: 80,
            insight: 'Paint is peeling on the wall face.',
          ),
        ],
      );

      final whatToDo = report.recommendationStory.toLowerCase();
      expect(whatToDo, contains('gutter'));
      expect(whatToDo, contains('paint'));
      // Paint block must mention paint care, not only gutter clean language.
      expect(whatToDo, contains('for peeling'));
      // Gutter recommendation should appear under gutter finding.
      expect(
        whatToDo.contains('clear leaves') ||
            whatToDo.contains('clean') ||
            whatToDo.contains('outlet') ||
            whatToDo.contains('gutter'),
        isTrue,
      );
    });

    test(
      'roof-only with vent-pipe / downspout labels still has no grade dumping',
      () {
        final photos = [
          CapturePhoto(
            file: XFile.fromData(
              Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xD9]),
              name: 'ridge_vent.jpg',
              mimeType: 'image/jpeg',
            ),
            label: 'Roof & eaves',
            index: 0,
            slotId: CaptureShotId.roof,
          ),
        ];
        final report = service.analyzeFeatureSnapshots(
          [
            ExteriorFeatureSnapshot.damagedRoof(
              seed: 24,
              label: 'Roof & eaves',
            ),
          ],
          labels: const {
            'roof': 0.92,
            'shingle': 0.86,
            'ridge': 0.74,
            'vent': 0.68,
            'pipe': 0.80,
            'downspout': 0.62,
            'chimney': 0.44,
          },
          visionMode: true,
          source: 'roof-only vent-pipe drainage gate',
          capturePhotos: photos,
        );

        final drainage = report.issues.where((i) => i.isGroundDrainageFinding);
        expect(
          drainage,
          isEmpty,
          reason:
              'roof-domain pipe/downspout labels must not mint grade dumping, '
              'got: ${report.issues.map((i) => '${i.title} @ ${i.location}').join("; ")}',
        );
      },
    );

    test(
      'mixed roof + grade binds dumping finding to the grade photo only',
      () {
        final photos = [
          CapturePhoto(
            file: XFile.fromData(
              Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xD9]),
              name: 'roof_field.jpg',
              mimeType: 'image/jpeg',
            ),
            label: 'Roof & eaves',
            index: 0,
            slotId: CaptureShotId.roof,
          ),
          CapturePhoto(
            file: XFile.fromData(
              Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xD9]),
              name: 'soil_outlet.jpg',
              mimeType: 'image/jpeg',
            ),
            label: 'Wet soil near downspout outlet',
            index: 1,
            slotId: CaptureShotId.problemCloseup,
          ),
        ];
        final report = service.analyzeFeatureSnapshots(
          [
            ExteriorFeatureSnapshot.damagedRoof(
              seed: 21,
              label: 'Roof & eaves',
            ),
            ExteriorFeatureSnapshot.groundDischarge(
              seed: 71,
              label: 'Wet soil near downspout outlet',
            ),
          ],
          labels: const {
            'roof': 0.84,
            'shingle': 0.78,
            'pipe': 0.80,
            'downspout': 0.72,
            'soil': 0.60,
            'outlet': 0.58,
            'foundation': 0.52,
          },
          visionMode: true,
          source: 'mixed roof+grade drainage primary',
          capturePhotos: photos,
        );

        final drainage = report.issues
            .where((i) => i.isGroundDrainageFinding)
            .toList();
        expect(
          drainage,
          isNotEmpty,
          reason:
              'grade photo should allow a drainage finding, got: '
              '${report.issues.map((i) => i.title).join("; ")}',
        );
        for (final d in drainage) {
          expect(
            d.photoIndex,
            1,
            reason:
                'primary evidence must be the grade/outlet photo, got '
                'index=${d.photoIndex} label=${d.sourcePhotoLabel}',
          );
          expect(d.sourcePhotoLabel.toLowerCase(), contains('soil'));
          expect(d.sourcePhotoLabel.toLowerCase(), isNot(contains('roof')));
          expect(
            d.location.toLowerCase(),
            isNot(contains('roof & eave')),
          );
        }
      },
    );

    test('roof-only scene does not mint Water May Be Dumping Near Foundation', () {
      final photos = [
        CapturePhoto(
          file: XFile.fromData(
            Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xD9]),
            name: 'roof_ridge.jpg',
            mimeType: 'image/jpeg',
          ),
          label: 'Roof & eaves',
          index: 0,
          slotId: CaptureShotId.roof,
        ),
      ];
      final report = service.analyzeFeatureSnapshots(
        [
          ExteriorFeatureSnapshot.damagedRoof(
            seed: 21,
            label: 'Roof & eaves',
          ),
        ],
        labels: const {
          'roof': 0.90,
          'shingle': 0.84,
          'ridge': 0.72,
          'tile': 0.40,
          'chimney': 0.48,
          'vent': 0.62,
          'pipe': 0.70,
        },
        visionMode: true,
        source: 'roof-only drainage gate',
        capturePhotos: photos,
      );

      final drainage = report.issues.where((i) {
        final t = '${i.title} ${i.location}'.toLowerCase();
        return t.contains('dumping') ||
            t.contains('soil at grade') ||
            t.contains('ground outlet') ||
            (t.contains('downspout') && t.contains('grade')) ||
            i.isGroundDrainageFinding;
      });
      expect(
        drainage,
        isEmpty,
        reason:
            'roof-only must not create drainage/grade findings, got: '
            '${report.issues.map((i) => '${i.title} @ ${i.location}').join("; ")}',
      );
    });

    test('soil-only scene does not invent roof-field damage', () {
      final report = service.analyzeFeatureSnapshots(
        [
          ExteriorFeatureSnapshot.groundDischarge(
            seed: 71,
            label: 'Wet soil near downspout outlet',
          ),
        ],
        labels: const {
          'pipe': 0.80,
          'downspout': 0.74,
          'soil': 0.60,
          'foundation': 0.55,
        },
        visionMode: true,
        source: 'soil-only roof gate',
      );

      final roof = report.issues.where((i) {
        final t = i.title.toLowerCase();
        return t.contains('roof surface') ||
            t.contains('shingle') ||
            t.contains('granule') ||
            t.contains('possible impact');
      });
      expect(
        roof,
        isEmpty,
        reason:
            'soil-only must not invent roof-field damage, got: '
            '${report.issues.map((i) => i.title).join("; ")}',
      );
    });

    test('refineBox ground drainage hugs grade, not eave strip', () {
      final eave = ExteriorAnalysisService.refineBoxForCategory(
        'gutter',
        0.1,
        0.1,
        0.8,
        0.8,
        objectIsExactMatch: false,
      );
      final ground = ExteriorAnalysisService.refineBoxForCategory(
        'gutter',
        0.1,
        0.1,
        0.8,
        0.8,
        objectIsExactMatch: false,
        groundDrainage: true,
      );

      expect(eave.h, lessThan(0.10));
      expect(eave.t, lessThan(0.40));
      expect(ground.t, greaterThan(0.55));
      expect(ground.h, greaterThan(eave.h));
    });
  });
}

/// First issue that looks like a drainage / gutter / outlet finding.
AnalysisIssue _firstDrainageIssue(
  AnalysisReport report, {
  String reason = 'expected a drainage finding',
}) {
  final drainage = report.issues.where((i) {
    final t = '${i.title} ${i.location}'.toLowerCase();
    return t.contains('gutter') ||
        t.contains('overflow') ||
        t.contains('drainage') ||
        t.contains('dumping') ||
        t.contains('downspout') ||
        t.contains('outlet') ||
        t.contains('foundation');
  }).toList();

  expect(drainage, isNotEmpty, reason: reason);
  return drainage.first;
}

String _issueBlob(AnalysisIssue issue) =>
    '${issue.title} ${issue.location} ${issue.insight}'.toLowerCase();
