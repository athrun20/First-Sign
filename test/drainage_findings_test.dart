import 'package:flutter_test/flutter_test.dart';
import 'package:pillar_ai/models/analysis_models.dart';
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

      final drainage = report.issues.where((i) {
        final t = i.title.toLowerCase();
        return t.contains('gutter') ||
            t.contains('overflow') ||
            t.contains('drainage') ||
            t.contains('dumping');
      }).toList();

      expect(drainage, isNotEmpty, reason: 'expected a drainage finding');
      final issue = drainage.first;
      final blob =
          '${issue.title} ${issue.location} ${issue.insight}'.toLowerCase();

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

      final drainage = report.issues.where((i) {
        final t = '${i.title} ${i.location}'.toLowerCase();
        return t.contains('drainage') ||
            t.contains('downspout') ||
            t.contains('dumping') ||
            t.contains('foundation') ||
            t.contains('outlet') ||
            t.contains('gutter') ||
            t.contains('overflow');
      }).toList();

      expect(
        drainage,
        isNotEmpty,
        reason:
            'expected a drainage/outlet finding, got: '
            '${report.issues.map((i) => i.title).join(", ")}',
      );

      final issue = drainage.first;
      final blob =
          '${issue.title} ${issue.location} ${issue.insight}'.toLowerCase();
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
      final groundLanguage = blob.contains('foundation') ||
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

      // Confidence should not sound certain on zone-level ground estimates.
      expect(issue.confidence, lessThanOrEqualTo(84));
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
      expect(issue.forensicConfidenceTitle, isNot('High Confidence'));

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
        insight: 'Photos suggest gutters may be clogged or overflowing at the roof edge.',
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
      expect(
        zone.contains('gutter') || zone.contains('roof'),
        isTrue,
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
        groundDrainage: false,
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
