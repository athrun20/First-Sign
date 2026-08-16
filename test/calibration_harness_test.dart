import 'package:flutter_test/flutter_test.dart';
import 'package:pillar_ai/models/analysis_models.dart';
import 'package:pillar_ai/services/field_calibration_harness.dart';

/// Field fixture pack (A1) — manifest-driven local analysis bands.
///
/// ```bash
/// flutter test test/calibration_harness_test.dart
/// ```
///
/// Scenarios with no photos / unloadable files are **skipped** (not failed).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FieldCalibrationHarness', () {
    late FieldCalibrationHarness harness;

    setUp(() {
      harness = FieldCalibrationHarness();
    });

    test('scenario registry is non-empty', () {
      expect(FieldCalibrationHarness.scenarioIds, isNotEmpty);
    });

    for (final id in FieldCalibrationHarness.scenarioIds) {
      test('scenario $id', () async {
        final result = await harness.runScenario(id);
        // Always print a short line so CI logs show pack status.
        // ignore: avoid_print
        print(result.summary);

        if (result.skipped) {
          // Placeholder folders without photos are OK for A1.
          expect(
            result.skipReason,
            isNotNull,
            reason: '${result.scenarioId} skipped without reason',
          );
          return;
        }

        expect(
          result.passed,
          isTrue,
          reason: result.summary,
        );
        expect(result.report, isNotNull);
        expect(result.photoCount, greaterThan(0));
        expect(result.report!.photoCount, greaterThan(0));
      }, timeout: const Timeout(Duration(seconds: 120)));
    }

    test('runAll covers every registered scenario', () async {
      final all = await harness.runAll();
      expect(all.length, FieldCalibrationHarness.scenarioIds.length);

      final failed = all.where((r) => !r.skipped && !r.passed).toList();
      if (failed.isNotEmpty) {
        final lines = failed.map((r) => r.summary).join('\n');
        // ignore: avoid_print
        print('Field pack failures:\n$lines');
      }
      expect(
        failed,
        isEmpty,
        reason: failed.map((r) => r.summary).join('\n'),
      );

      final ran = all.where((r) => !r.skipped).length;
      final skipped = all.where((r) => r.skipped).length;
      // ignore: avoid_print
      print('Field pack: $ran ran, $skipped skipped, ${failed.length} failed');
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('evaluate: score out of range fails', () {
      final report = _scoreOnly(40);
      final failures = FieldCalibrationHarness.evaluate(
        report,
        const FieldCalibrationExpected(scoreMin: 55, scoreMax: 98),
      );
      expect(failures.any((f) => f.contains('score')), isTrue);
    });

    test('evaluate: forbidden category fails', () {
      final report = _withIssue(
        title: 'Foundation crack near grade',
        severity: 'Low',
      );
      final failures = FieldCalibrationHarness.evaluate(
        report,
        const FieldCalibrationExpected(
          forbiddenCategories: ['foundation'],
          maxFindings: 10,
          scoreMin: 0,
          scoreMax: 100,
        ),
      );
      expect(failures.any((f) => f.contains('forbidden')), isTrue);
    });

    test('evaluate: severity above max fails', () {
      final report = _withIssue(
        title: 'Paint film peeling',
        severity: 'High',
      );
      final failures = FieldCalibrationHarness.evaluate(
        report,
        const FieldCalibrationExpected(
          maxSeverity: 'Medium',
          maxFindings: 10,
          scoreMin: 0,
          scoreMax: 100,
        ),
      );
      expect(failures.any((f) => f.contains('severity')), isTrue);
    });

    test('inferCategory maps paint and roof titles', () {
      expect(
        FieldCalibrationHarness.inferCategory(
          _issue(title: 'Peeling paint on siding'),
        ),
        anyOf('paint', 'siding'),
      );
      expect(
        FieldCalibrationHarness.inferCategory(
          _issue(title: 'Missing asphalt shingles'),
        ),
        'roof',
      );
    });

    test('evaluate: requiredCategories fails when missing', () {
      final report = _scoreOnly(70);
      final failures = FieldCalibrationHarness.evaluate(
        report,
        const FieldCalibrationExpected(
          requiredCategories: ['drainage'],
          scoreMin: 0,
          scoreMax: 100,
        ),
      );
      expect(failures.any((f) => f.contains('required category')), isTrue);
    });

    test('evaluate: requireNeedsCloserPhoto fails when absent', () {
      final report = _withIssue(title: 'Soft note', severity: 'Low');
      final failures = FieldCalibrationHarness.evaluate(
        report,
        const FieldCalibrationExpected(
          requireNeedsCloserPhoto: true,
          scoreMin: 0,
          scoreMax: 100,
        ),
      );
      expect(
        failures.any((f) => f.contains('requireNeedsCloserPhoto')),
        isTrue,
      );
    });

    /// A2 under-call: drainage_grade must fire drainage; limited_dark demoted.
    test('A2: drainage_grade finds drainage; limited_dark demoted vs healthy',
        () async {
      final healthy = await harness.runScenario('healthy_multi');
      final drainage = await harness.runScenario('drainage_grade');
      final dark = await harness.runScenario('limited_dark');

      // ignore: avoid_print
      print(healthy.summary);
      // ignore: avoid_print
      print(drainage.summary);
      // ignore: avoid_print
      print(dark.summary);

      expect(healthy.skipped, isFalse, reason: healthy.summary);
      expect(drainage.skipped, isFalse, reason: drainage.summary);
      expect(dark.skipped, isFalse, reason: dark.summary);
      expect(healthy.passed, isTrue, reason: healthy.summary);
      expect(drainage.passed, isTrue, reason: drainage.summary);
      expect(dark.passed, isTrue, reason: dark.summary);

      final h = healthy.report!;
      final d = drainage.report!;
      final lim = dark.report!;

      // Outlet + wet/eroded soil → drainage-related finding (not empty clean).
      final drainageCats =
          d.issues.map(FieldCalibrationHarness.inferCategory).toList();
      expect(
        drainageCats,
        contains('drainage'),
        reason: 'drainage_grade must produce a drainage finding, got: '
            '${d.issues.map((i) => i.title).join("; ")}',
      );
      expect(d.issues, isNotEmpty);
      expect(d.overallScore, lessThan(95));

      // Dark / low-detail: retake path + clearly below healthy multi-angle.
      expect(
        lim.issues.any(
          (i) =>
              i.needsCloserPhoto ||
              i.title.toLowerCase().contains('limited visibility'),
        ),
        isTrue,
        reason: 'limited_dark should demote confidence / needsCloserPhoto',
      );
      expect(
        lim.overallScore,
        lessThan(h.overallScore - 8),
        reason:
            'limited_dark score ${lim.overallScore} should be clearly below '
            'healthy_multi ${h.overallScore}',
      );
      // Control stays clean — do not invent findings on healthy multi-angle.
      expect(h.overallScore, greaterThanOrEqualTo(91));
    }, timeout: const Timeout(Duration(seconds: 180)));
  });
}

AnalysisIssue _issue({
  required String title,
  String severity = 'Low',
  bool needsCloserPhoto = false,
}) {
  return AnalysisIssue(
    title: title,
    location: 'Test location',
    severity: severity,
    cost: 'TBD',
    confidence: 70,
    insight: 'Harness unit check',
    needsCloserPhoto: needsCloserPhoto,
  );
}

AnalysisReport _withIssue({
  required String title,
  String severity = 'Low',
  int score = 70,
}) {
  return AnalysisReport(
    overallScore: score,
    conditionLabel: 'Screening',
    issues: [_issue(title: title, severity: severity)],
    estimatedRepairRange: '\$0',
    analysisSource: 'Test',
    photoCount: 1,
  );
}

AnalysisReport _scoreOnly(int score) {
  return AnalysisReport(
    overallScore: score,
    conditionLabel: 'Screening',
    issues: const [],
    estimatedRepairRange: '\$0',
    analysisSource: 'Test',
    photoCount: 0,
  );
}
