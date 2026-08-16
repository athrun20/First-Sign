import 'package:flutter_test/flutter_test.dart';
import 'package:pillar_ai/models/analysis_models.dart';
import 'package:pillar_ai/services/analysis_feature_snapshot.dart';
import 'package:pillar_ai/services/exterior_analysis_service.dart';

void main() {
  final service = ExteriorAnalysisService();

  group('AnalysisGoldenSet credibility', () {
    for (final scenario in AnalysisGoldenSet.scenarios) {
      test(scenario.id, () {
        final report = service.analyzeFeatureSnapshots(
          scenario.photos,
          labels: scenario.labels,
          visionMode: scenario.labels.isNotEmpty,
          source: 'Golden-set test · ${scenario.id}',
        );

        final exp = scenario.expect;
        final high = report.highCount;
        final titles = report.issues
            .map((i) => i.title.toLowerCase())
            .join(' ');
        final locations = report.issues
            .map((i) => i.location.toLowerCase())
            .join(' ');
        final blob =
            '$titles $locations ${report.conditionLabel.toLowerCase()}';
        final maxConf = report.issues.isEmpty
            ? 0
            : report.issues
                  .map((i) => i.confidence)
                  .reduce((a, b) => a > b ? a : b);

        expect(
          report.overallScore,
          inInclusiveRange(exp.minScore, exp.maxScore),
          reason:
              '${exp.id}: score ${report.overallScore} outside ${exp.minScore}-${exp.maxScore}. '
              'Issues: ${report.issues.map((i) => '${i.severity} ${i.title} (${i.confidence}%)').join('; ')}',
        );

        expect(
          high,
          lessThanOrEqualTo(exp.maxHighCount),
          reason: '${exp.id}: too many High findings ($high)',
        );
        expect(
          high,
          greaterThanOrEqualTo(exp.minHighCount),
          reason:
              '${exp.id}: expected at least ${exp.minHighCount} High findings',
        );

        if (exp.allowOnlyLowOrEmpty) {
          expect(
            report.issues.every((i) => i.severity == 'Low') ||
                report.issues.isEmpty,
            isTrue,
            reason:
                '${exp.id}: expected only Low/empty, got ${report.issues.map((i) => i.severity).join(",")}',
          );
        }

        for (final hint in exp.mustIncludeCategoryHints) {
          final h = hint.toLowerCase();
          final hit = blob.contains(h);
          // At least one of the must-include hints for multi-hint lists is OK
          // when list length > 1 is handled below as OR groups — here require each.
          // Foundation scenario uses OR-style list: check any match once outside.
          expect(
            hit || exp.mustIncludeCategoryHints.length > 1,
            isTrue,
            reason: '${exp.id}: missing category hint "$hint" in "$blob"',
          );
        }
        if (exp.mustIncludeCategoryHints.length > 1) {
          final any = exp.mustIncludeCategoryHints.any(
            (h) => blob.contains(h.toLowerCase()),
          );
          expect(
            any,
            isTrue,
            reason:
                '${exp.id}: expected one of ${exp.mustIncludeCategoryHints} in "$blob"',
          );
        } else if (exp.mustIncludeCategoryHints.length == 1) {
          expect(
            blob.contains(exp.mustIncludeCategoryHints.first.toLowerCase()),
            isTrue,
          );
        }

        for (final hint in exp.mustNotIncludeCategoryHints) {
          expect(
            blob.contains(hint.toLowerCase()),
            isFalse,
            reason: '${exp.id}: unexpected category "$hint"',
          );
        }

        if (report.issues.isNotEmpty) {
          expect(
            maxConf,
            lessThanOrEqualTo(exp.maxConfidence),
            reason: '${exp.id}: max confidence $maxConf > ${exp.maxConfidence}',
          );
        }

        if (exp.requireNeedsCloserWhenWeak) {
          // Weak single-photo: either only Low/empty, or any finding flags closer photos,
          // and never High with high certainty language.
          expect(high, 0);
          if (report.issues.isNotEmpty) {
            final weakHonest = report.issues.every(
              (i) =>
                  i.needsCloserPhoto ||
                  i.confidence <= 78 ||
                  i.severity == 'Low',
            );
            expect(
              weakHonest,
              isTrue,
              reason: '${exp.id}: weak photo over-claimed certainty',
            );
          }
        }

        // Screening language present on every report path.
        expect(
          report.conditionLabel.toLowerCase().contains('screening') ||
              report.analysisSource.toLowerCase().contains('screening') ||
              report.scoreMeaning.toLowerCase().contains('screening'),
          isTrue,
          reason: '${exp.id}: missing screening language',
        );

        // Costs framed as planning ranges (when present).
        for (final issue in report.issues) {
          expect(issue.planningCostLabel.toLowerCase(), contains('planning'));
          expect(issue.confidence, lessThanOrEqualTo(94));
        }
      });
    }
  });

  group('Consistency & honesty', () {
    test('same golden input yields same score and issue titles', () {
      final photos = [
        ExteriorFeatureSnapshot.damagedRoof(),
        ExteriorFeatureSnapshot.damagedRoof(seed: 22),
      ];
      final labels = {'roof': 0.94, 'shingle': 0.88, 'damage': 0.82};
      final a = service.analyzeFeatureSnapshots(
        photos,
        labels: labels,
        visionMode: true,
      );
      final b = service.analyzeFeatureSnapshots(
        photos,
        labels: labels,
        visionMode: true,
      );
      expect(a.overallScore, b.overallScore);
      expect(
        a.issues.map((i) => i.title).toList(),
        b.issues.map((i) => i.title).toList(),
      );
      expect(
        a.issues.map((i) => i.confidence).toList(),
        b.issues.map((i) => i.confidence).toList(),
      );
    });

    test('healthy home scores higher than severe roof', () {
      final healthy = AnalysisGoldenSet.scenarios.firstWhere(
        (s) => s.id == 'healthy_multi_angle',
      );
      final roof = AnalysisGoldenSet.scenarios.firstWhere(
        (s) => s.id == 'severe_roof_damage',
      );
      final h = service.analyzeFeatureSnapshots(
        healthy.photos,
        labels: healthy.labels,
        visionMode: true,
      );
      final r = service.analyzeFeatureSnapshots(
        roof.photos,
        labels: roof.labels,
        visionMode: true,
      );
      expect(h.overallScore, greaterThan(r.overallScore + 8));
    });

    test('disclaimer constants are strong screening language', () {
      expect(
        AnalysisReport.screeningDisclaimer.toLowerCase(),
        contains('not a licensed'),
      );
      expect(
        AnalysisReport.screeningDisclaimer.toLowerCase(),
        contains('screening'),
      );
      expect(
        AnalysisReport.screeningBadge.toLowerCase(),
        contains('not an inspection'),
      );
    });

    test('High severity never appears with very low confidence', () {
      for (final scenario in AnalysisGoldenSet.scenarios) {
        final report = service.analyzeFeatureSnapshots(
          scenario.photos,
          labels: scenario.labels,
          visionMode: scenario.labels.isNotEmpty,
        );
        for (final issue in report.issues) {
          if (issue.severity == 'High') {
            expect(
              issue.confidence,
              greaterThanOrEqualTo(70),
              reason: '${scenario.id}: High with conf ${issue.confidence}',
            );
            expect(issue.needsCloserPhoto, isFalse);
          }
        }
      }
    });
  });
}
