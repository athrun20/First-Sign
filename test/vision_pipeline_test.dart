import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pillar_ai/models/analysis_models.dart';
import 'package:pillar_ai/services/analysis_feature_snapshot.dart';
import 'package:pillar_ai/services/exterior_analysis_service.dart';

void main() {
  AnalysisReport report({
    int score = 80,
    String condition = 'Good',
    List<AnalysisIssue> issues = const [],
    String range = r'$0',
    String source = 'AI exterior screening · local multi-feature',
    int photoCount = 4,
  }) {
    return AnalysisReport(
      overallScore: score,
      conditionLabel: condition,
      issues: issues,
      estimatedRepairRange: range,
      analysisSource: source,
      photoCount: photoCount,
    );
  }

  AnalysisIssue issue({
    required String title,
    String location = 'Front elevation',
    String severity = 'Medium',
    String cost = 'TBD',
    int confidence = 80,
    String insight = 'Screening note',
    bool needsCloserPhoto = false,
    String sourcePhotoLabel = '',
    double? highlightLeft,
    double? highlightTop,
    double? highlightWidth,
    double? highlightHeight,
  }) {
    return AnalysisIssue(
      title: title,
      location: location,
      severity: severity,
      cost: cost,
      confidence: confidence,
      insight: insight,
      needsCloserPhoto: needsCloserPhoto,
      sourcePhotoLabel: sourcePhotoLabel,
      highlightLeft: highlightLeft,
      highlightTop: highlightTop,
      highlightWidth: highlightWidth,
      highlightHeight: highlightHeight,
    );
  }

  /// Full-elevation structure box used by refineBoxForCategory cases.
  const houseL = 0.10;
  const houseT = 0.20;
  const houseW = 0.70;
  const houseH = 0.70;

  group('Vision API key resolution', () {
    test('sanitize strips quotes and whitespace', () {
      expect(
        ExteriorAnalysisService.resolveVisionApiKey('  "abc123"  '),
        'abc123',
      );
      expect(ExteriorAnalysisService.resolveVisionApiKey("'xyz'"), 'xyz');
    });

    test('rejects placeholder keys so local fallback stays clean', () {
      for (final key in ['your_key', 'your_key_here', 'null']) {
        expect(
          ExteriorAnalysisService.resolveVisionApiKey(key),
          isEmpty,
          reason: 'placeholder "$key" should resolve empty',
        );
      }
    });

    test('constructor override enables hasVisionKey', () {
      final on = ExteriorAnalysisService(
        visionApiKey: 'test-key-not-placeholder',
      );
      expect(on.hasVisionKey, isTrue);

      final forceLocal = ExteriorAnalysisService(
        visionApiKey: 'test-key-not-placeholder',
        forceLocalOnly: true,
      );
      expect(forceLocal.hasVisionKey, isFalse);

      // Empty override falls through to compile-time defines (usually empty).
      final empty = ExteriorAnalysisService(visionApiKey: '');
      expect(empty.visionApiKey, isNot(contains('your_key')));
    });
  });

  group('Vision label expansion', () {
    test('maps roof / shingle labels into exterior domain keys', () {
      final expanded = ExteriorAnalysisService.expandVisionLabels({
        'Roof': 0.92,
        'Asphalt': 0.81,
        'House': 0.7,
      });
      expect(expanded['roof'], greaterThan(0.7));
      expect(expanded['shingle'], greaterThan(0.4));
      expect(
        expanded.containsKey('exterior') || expanded.containsKey('wall'),
        isTrue,
      );
    });

    test('damage and vegetation need structure context', () {
      final alone = ExteriorAnalysisService.expandVisionLabels({
        'plant': 0.8,
        'moss': 0.75,
        'rust': 0.66,
        'crack': 0.7,
      });
      expect(alone['vegetation'] ?? 0, lessThan(0.2));
      expect(alone['damage'] ?? 0, lessThan(0.2));

      final withStructure = ExteriorAnalysisService.expandVisionLabels({
        'house': 0.9,
        'roof': 0.85,
        'plant': 0.8,
        'moss': 0.75,
        'rust': 0.66,
        'crack': 0.7,
        'foundation': 0.6,
      });
      expect(withStructure['vegetation'], greaterThan(0.5));
      expect(withStructure['moisture'] ?? 0, greaterThan(0.4));
      expect(
        withStructure['rust stain'] ?? withStructure['damage'] ?? 0,
        greaterThan(0.5),
      );
      expect(withStructure['crack'], greaterThan(0.5));
    });

    test('patched siding and wiring need structure context', () {
      final alone = ExteriorAnalysisService.expandVisionLabels({
        'cable': 0.9,
        'discoloration': 0.8,
        'patch': 0.75,
      });
      expect(alone['wiring'] ?? 0, lessThan(0.2));
      expect(alone['patch'] ?? 0, lessThan(0.2));

      final withStructure = ExteriorAnalysisService.expandVisionLabels({
        'house': 0.9,
        'siding': 0.84,
        'wall': 0.7,
        'discoloration': 0.78,
        'patch': 0.72,
        'cable': 0.86,
        'electrical wiring': 0.70,
      });
      expect(withStructure['siding'] ?? 0, greaterThan(0.6));
      expect(withStructure['patch'] ?? 0, greaterThan(0.5));
      expect(withStructure['discoloration'] ?? 0, greaterThan(0.5));
      expect(
        withStructure['wiring'] ?? withStructure['cable'] ?? 0,
        greaterThan(0.5),
      );
    });

    test('drops people and indoor labels aggressively', () {
      final expanded = ExteriorAnalysisService.expandVisionLabels({
        'Person': 0.97,
        'Face': 0.91,
        'Living room': 0.88,
        'Sofa': 0.8,
        'Laptop': 0.7,
      });
      expect(expanded, isEmpty);
      expect(
        ExteriorAnalysisService.isClearlyNonExteriorScene({
          'Person': 0.97,
          'Living room': 0.88,
        }),
        isTrue,
      );
      expect(ExteriorAnalysisService.hasExteriorEvidence(expanded), isFalse);
    });

    test('filterExteriorVisionLabels keeps roof cues only', () {
      // Indoor-dominant scene with only a weak stray roof tag → drop all.
      final dominated = ExteriorAnalysisService.filterExteriorVisionLabels({
        'Kitchen': 0.95,
        'Person': 0.90,
        'Cabinet': 0.88,
        'Stove': 0.84,
        'Roof': 0.28,
      });
      expect(dominated, isEmpty);

      // True exterior roof photo: keep structure cues, drop indoor noise.
      final filtered = ExteriorAnalysisService.filterExteriorVisionLabels({
        'Roof': 0.92,
        'Shingle': 0.88,
        'House': 0.80,
        'Person': 0.20,
      });
      expect(filtered.keys, containsAll(['roof', 'shingle']));
      expect(filtered.containsKey('person'), isFalse);
    });

    test('kitchen indoor scene is clearly non-exterior', () {
      final kitchen = <String, double>{
        'Kitchen': 0.96,
        'Cabinet': 0.91,
        'Countertop': 0.88,
        'Stove': 0.86,
        'Appliance': 0.82,
        'Indoor': 0.90,
        'Room': 0.78,
        'Tile': 0.70,
        'Floor': 0.65,
      };
      expect(
        ExteriorAnalysisService.isClearlyNonExteriorScene(kitchen),
        isTrue,
      );
      expect(
        ExteriorAnalysisService.filterExteriorVisionLabels(kitchen),
        isEmpty,
      );
      expect(ExteriorAnalysisService.expandVisionLabels(kitchen), isEmpty);
      expect(
        ExteriorAnalysisService.hasExteriorEvidence(
          ExteriorAnalysisService.expandVisionLabels(kitchen),
        ),
        isFalse,
      );
    });

    test('bare tile/wall/paint do not count as exterior evidence', () {
      expect(
        ExteriorAnalysisService.hasExteriorEvidence({
          'tile': 0.95,
          'wall': 0.9,
          'paint': 0.88,
          'window': 0.8,
          'concrete': 0.75,
        }),
        isFalse,
      );
      expect(ExteriorAnalysisService.isExteriorRelevantLabel('tile'), isFalse);
      expect(
        ExteriorAnalysisService.isExteriorRelevantLabel('tile roof'),
        isTrue,
      );
    });

    test('kitchen labels never mint roof findings (snapshot path)', () {
      final service = ExteriorAnalysisService(forceLocalOnly: true);
      // Intentionally roof-like features + kitchen Vision labels: labels win.
      final report = service.analyzeFeatureSnapshots(
        [
          ExteriorFeatureSnapshot.damagedRoof(
            seed: 99,
            label: 'Kitchen interior',
          ),
        ],
        labels: {
          'Kitchen': 0.95,
          'Cabinet': 0.90,
          'Stove': 0.88,
          'Countertop': 0.86,
          'Appliance': 0.84,
          'Indoor': 0.92,
          'Room': 0.80,
        },
        visionMode: true,
        source:
            'AI exterior screening · Google Cloud Vision (single photo) + local features',
      );

      expect(
        report.conditionLabel.toLowerCase(),
        contains('insufficient exterior'),
      );
      expect(report.issues, isEmpty);
      expect(
        report.estimatedRepairRange.toLowerCase(),
        anyOf(contains('tbd'), contains('no exterior')),
      );
      final blob = report.issues
          .map((i) => '${i.title} ${i.insight} ${i.cost}')
          .join(' ')
          .toLowerCase();
      expect(blob.contains('shingle'), isFalse);
      expect(blob.contains('roof'), isFalse);
    });

    test('real roof labels still produce shingle findings', () {
      final service = ExteriorAnalysisService(forceLocalOnly: true);
      final scenario = AnalysisGoldenSet.scenarios.firstWhere(
        (s) => s.id == 'severe_roof_damage',
      );
      final report = service.analyzeFeatureSnapshots(
        scenario.photos,
        labels: scenario.labels,
        visionMode: true,
        source: 'AI exterior screening · Google Cloud Vision + local features',
      );

      expect(
        report.conditionLabel.toLowerCase(),
        isNot(contains('insufficient exterior')),
      );
      expect(report.issues, isNotEmpty);
      final titles = report.issues.map((i) => i.title.toLowerCase()).join(' ');
      expect(
        titles.contains('roof') ||
            titles.contains('shingle') ||
            titles.contains('granule'),
        isTrue,
        reason: 'expected roof-related finding, got: $titles',
      );
    });

    test('vision-mode snapshot still produces credible findings', () {
      final service = ExteriorAnalysisService(forceLocalOnly: true);
      final scenario = AnalysisGoldenSet.scenarios.firstWhere(
        (s) => s.id == 'severe_roof_damage',
        orElse: () => AnalysisGoldenSet.scenarios.firstWhere(
          (s) => s.labels.isNotEmpty,
          orElse: () => AnalysisGoldenSet.scenarios.first,
        ),
      );

      final expanded = ExteriorAnalysisService.expandVisionLabels({
        ...scenario.labels,
        'roof': 0.94,
        'shingle': 0.90,
        'damage': 0.86,
        'house': 0.88,
      });

      final result = service.analyzeFeatureSnapshots(
        scenario.photos,
        labels: expanded.isNotEmpty ? expanded : scenario.labels,
        visionMode: true,
        source: 'AI exterior screening · Google Cloud Vision + local features',
      );

      expect(result.photoCount, greaterThan(0));
      expect(result.usedCloudVision, isTrue);
      expect(result.overallScore, inInclusiveRange(34, 98));
      expect(result.issues, isNotEmpty);
      expect(result.issues.length, lessThanOrEqualTo(3));

      for (final finding in result.issues) {
        expect(finding.confidence, inInclusiveRange(48, 94));
        expect(finding.insight, isNotEmpty);
        expect(finding.severity, anyOf('High', 'Medium', 'Low'));
      }

      final titles = result.issues.map((i) => i.title.toLowerCase()).join(' ');
      expect(
        titles.contains('roof') ||
            titles.contains('shingle') ||
            titles.contains('granule'),
        isTrue,
        reason: 'expected roof-related finding, got: $titles',
      );
    });
  });

  group('Report messaging', () {
    const localSource = 'AI exterior screening · local multi-feature';
    const visionSingleSource =
        'AI exterior screening · Google Cloud Vision (single photo) + local features';

    test('single-photo local vs vision copy differs', () {
      final local = report(source: localSource, photoCount: 1);
      final vision = report(source: visionSingleSource, photoCount: 1);

      expect(local.usedCloudVision, isFalse);
      expect(vision.usedCloudVision, isTrue);
      expect(local.conditionStory.toLowerCase(), contains('quick scan'));
      expect(vision.conditionStory.toLowerCase(), contains('vision'));
      expect(vision.scoreMeaning.toLowerCase(), contains('vision'));
      expect(local.scoreMeaning.toLowerCase(), contains('single-photo'));
    });

    test('insufficient exterior story does not invent defects', () {
      final insufficient = report(
        score: 88,
        condition:
            'Insufficient exterior evidence — photos may not show a home exterior (screening)',
        range: 'TBD — no exterior findings',
        source: visionSingleSource,
        photoCount: 1,
      );

      final story = insufficient.conditionStory.toLowerCase();
      expect(story, contains('insufficient'));
      expect(story, isNot(contains('serviceable')));
      expect(insufficient.priorityStory.toLowerCase(), contains('none'));
      expect(
        insufficient.recommendationStory.toLowerCase(),
        contains('re-capture'),
      );
      expect(insufficient.impactStory.toLowerCase(), contains('no exterior'));
    });

    test('planning cost withheld on weak evidence findings', () {
      final weak = issue(
        title: 'Possible surface wear',
        severity: 'Low',
        confidence: 62,
        needsCloserPhoto: true,
      );
      expect(weak.planningCostLabel.toLowerCase(), contains('withheld'));
      expect(weak.storyInsightParagraph.toLowerCase(), contains('withheld'));

      final strong = issue(
        title: 'Missing / Damaged Shingles',
        location: 'Roof field',
        severity: 'High',
        cost: r'$1,800 – $4,000',
        confidence: 88,
        insight: 'Roof damage supported',
      );
      expect(strong.planningCostLabel, contains(r'$1,800'));
      expect(
        strong.storyWhat.toLowerCase(),
        contains('photo cues support'),
      );
      expect(
        strong.storyWhat.toLowerCase().contains('confidence 88'),
        isFalse,
        reason: 'findings card storyWhat stays short — no raw confidence echo',
      );
    });

    test('stories name actual findings rather than only generic counts', () {
      final detailed = report(
        score: 64,
        condition:
            'Attention needed — Prioritize Missing / Damaged Shingles (screening)',
        issues: [
          issue(
            title: 'Missing / Damaged Shingles',
            location: 'Primary roof plane',
            severity: 'High',
            cost: r'$1,600 – $3,600',
            confidence: 86,
            insight: 'Roof openings',
            sourcePhotoLabel: 'Roof',
          ),
          issue(
            title: 'Possible Gutter Overflow',
            location: 'Roof edge / gutters',
            severity: 'Medium',
            cost: r'$200 – $500',
            confidence: 80,
            insight: 'Drainage',
            sourcePhotoLabel: 'Front of home',
          ),
        ],
        range: r'$1,800 – $4,100',
        source: localSource,
        photoCount: 4,
      );

      expect(detailed.conditionStory, contains('Missing / Damaged Shingles'));
      expect(detailed.priorityStory, contains('Missing / Damaged Shingles'));
      expect(detailed.priorityStory, contains('86%'));
      expect(detailed.recommendationStory.toLowerCase(), contains('shingle'));
      expect(detailed.impactStory.toLowerCase(), contains('roof'));
      expect(detailed.scoreMeaning.toLowerCase(), contains('4-photo'));
    });
  });

  group('Vision bounding boxes for surface evidence', () {
    test('parseVisionBoundingBox reads normalizedVertices', () {
      final box = ExteriorAnalysisService.parseVisionBoundingBox({
        'name': 'House',
        'score': 0.9,
        'boundingPoly': {
          'normalizedVertices': [
            {'x': 0.10, 'y': 0.20},
            {'x': 0.80, 'y': 0.20},
            {'x': 0.80, 'y': 0.90},
            {'x': 0.10, 'y': 0.90},
          ],
        },
      });

      expect(box, isNotNull);
      expect(box!.l, closeTo(0.10, 0.001));
      expect(box.t, closeTo(0.20, 0.001));
      expect(box.w, closeTo(0.70, 0.001));
      expect(box.h, closeTo(0.70, 0.001));
    });

    test('refineBoxForCategory tightens house box for roof band', () {
      final roof = ExteriorAnalysisService.refineBoxForCategory(
        'roof',
        houseL,
        houseT,
        houseW,
        houseH,
        objectIsExactMatch: false,
      );
      expect(roof.t, lessThan(0.28));
      expect(roof.h, lessThan(0.20));
      expect(roof.w, greaterThan(0.40));
      expect(roof.w, lessThan(0.64));
    });

    test('refineBoxForCategory gutter band is thin at eave', () {
      final gutter = ExteriorAnalysisService.refineBoxForCategory(
        'gutter',
        houseL,
        houseT,
        houseW,
        houseH,
        objectIsExactMatch: false,
      );
      expect(gutter.h, lessThan(0.09));
      expect(gutter.w, greaterThan(0.50));
      expect(gutter.t, greaterThan(0.24));
      expect(gutter.t, lessThan(0.46));
    });

    test('refineBoxForCategory foundation band hugs grade line', () {
      final foundation = ExteriorAnalysisService.refineBoxForCategory(
        'foundation',
        houseL,
        houseT,
        houseW,
        houseH,
        objectIsExactMatch: false,
      );
      expect(foundation.t, greaterThan(0.72));
      expect(foundation.h, lessThan(0.14));
      expect(foundation.w, lessThan(0.82));
    });

    test('refineBoxForCategory exact window insets, never grows', () {
      final win = ExteriorAnalysisService.refineBoxForCategory(
        'window',
        0.30,
        0.35,
        0.22,
        0.28,
        objectIsExactMatch: true,
      );
      expect(win.w, lessThanOrEqualTo(0.22));
      expect(win.h, lessThanOrEqualTo(0.28));
      expect(win.l, greaterThanOrEqualTo(0.30));
      expect(win.t, greaterThanOrEqualTo(0.35));
    });

    test('specific objects preferred over large structure names', () {
      expect(
        ExteriorAnalysisService.isSpecificObjectForCategory('window', 'window'),
        isTrue,
      );
      expect(ExteriorAnalysisService.isLargeStructureObject('house'), isTrue);
      expect(
        ExteriorAnalysisService.isSpecificObjectForCategory('house', 'window'),
        isFalse,
      );
    });

    test('surfaceHighlight prefers stored Vision box over zone fallback', () {
      final withBox = issue(
        title: 'Missing / Damaged Shingles',
        location: 'Primary roof plane',
        severity: 'High',
        cost: r'$1,500 – $3,200',
        confidence: 88,
        insight: 'Roof damage',
        highlightLeft: 0.12,
        highlightTop: 0.08,
        highlightWidth: 0.55,
        highlightHeight: 0.28,
      );
      expect(withBox.hasLocalizedHighlight, isTrue);
      expect(withBox.surfaceHighlight.left, closeTo(0.12, 0.001));
      expect(withBox.surfaceHighlight.top, closeTo(0.08, 0.001));
      expect(withBox.surfaceHighlight.width, closeTo(0.55, 0.001));

      final zoneFallback = issue(
        title: 'Missing / Damaged Shingles',
        location: 'Primary roof plane',
        severity: 'High',
        confidence: 88,
        insight: 'Roof damage',
      );
      expect(zoneFallback.hasLocalizedHighlight, isFalse);
      expect(zoneFallback.shouldShowSurfaceHighlight, isTrue);
      expect(zoneFallback.surfaceHighlight.top, lessThan(0.10));
      expect(zoneFallback.surfaceHighlight.height, lessThan(0.22));
      expect(zoneFallback.surfaceHighlight.width, lessThan(0.60));

      final weak = issue(
        title: 'Siding Condition Review',
        location: 'Exterior wall',
        severity: 'Low',
        confidence: 72,
        insight: 'Weak note',
        needsCloserPhoto: true,
      );
      expect(weak.shouldShowSurfaceHighlight, isFalse);
      expect(weak.surfaceHighlight, equals(Rect.zero));
    });

    test('highlight survives json round-trip', () {
      final original = issue(
        title: 'Window Seal Failure Risk',
        confidence: 81,
        insight: 'Seal wear',
        cost: r'$300 – $900',
        highlightLeft: 0.30,
        highlightTop: 0.35,
        highlightWidth: 0.22,
        highlightHeight: 0.28,
      );
      final restored = AnalysisIssue.fromJson(original.toJson());
      expect(restored.hasLocalizedHighlight, isTrue);
      expect(restored.surfaceHighlight.width, closeTo(0.22, 0.001));
      expect(restored.surfaceHighlight.height, closeTo(0.28, 0.001));
      expect(restored.highlightLeft, closeTo(0.30, 0.001));
    });

    test('Confidence prefers pipeline attention over region fallback', () {
      const pipeline = [
        SurfaceAttentionSample(x: 0.40, y: 0.30, weight: 0.9),
        SurfaceAttentionSample(x: 0.46, y: 0.36, weight: 0.6),
      ];
      final withMap = issue(
        title: 'Missing / Damaged Shingles',
        location: 'Primary roof plane',
        severity: 'High',
        confidence: 88,
        insight: 'Roof damage',
        highlightLeft: 0.12,
        highlightTop: 0.08,
        highlightWidth: 0.55,
        highlightHeight: 0.28,
      ).copyWith(attentionSamples: pipeline);

      final field = withMap.attentionField();
      expect(field.isPipeline, isTrue);
      expect(field.isApproximate, isFalse);
      expect(field.samples, hasLength(2));
      expect(field.samples.first.x, closeTo(0.40, 0.001));

      final restored = AnalysisIssue.fromJson(withMap.toJson());
      expect(restored.attentionSamples, isNotNull);
      expect(restored.attentionField().isPipeline, isTrue);
    });

    test('Confidence fallback stays inside the evidence region', () {
      final boxed = issue(
        title: 'Missing / Damaged Shingles',
        location: 'Primary roof plane',
        severity: 'High',
        confidence: 88,
        insight: 'Roof damage',
        highlightLeft: 0.20,
        highlightTop: 0.10,
        highlightWidth: 0.30,
        highlightHeight: 0.20,
      );
      final field = boxed.attentionField();
      expect(field.isApproximate, isTrue);
      expect(field.isEmpty, isFalse);
      final r = boxed.surfaceHighlight.inflate(0.02);
      for (final s in field.samples) {
        expect(s.x, inInclusiveRange(r.left, r.right));
        expect(s.y, inInclusiveRange(r.top, r.bottom));
      }

      final weak = issue(
        title: 'Siding Condition Review',
        location: 'Exterior wall',
        severity: 'Low',
        confidence: 72,
        insight: 'Weak note',
        needsCloserPhoto: true,
      );
      expect(weak.attentionField().isEmpty, isTrue);
    });
  });
}
