import 'package:flutter_test/flutter_test.dart';
import 'package:pillar_ai/services/photo_calibration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PhotoCalibrationHarness (pixel pipeline)', () {
    late PhotoCalibrationHarness harness;

    setUp(() {
      harness = PhotoCalibrationHarness();
    });

    for (final scenario in PhotoCalibrationHarness.scenarios) {
      test(scenario.id, () async {
        final result = await harness.runScenario(scenario);
        expect(result.passed, isTrue, reason: result.summary);
        expect(result.report.photoCount, greaterThan(0));
        // Prefer labeled photos from assets/calibration when present.
        expect(
          result.usedRealPhotos,
          isTrue,
          reason:
              '${scenario.id} should load real assets (usedReal=${result.usedRealPhotos})',
        );
        // Screening framing should remain.
        expect(
          result.report.conditionLabel.toLowerCase().contains('screening') ||
              result.report.analysisSource.toLowerCase().contains(
                'screening',
              ) ||
              result.report.analysisSource.toLowerCase().contains('local'),
          isTrue,
        );
        // Labeled primary defect (when defined) must appear in findings.
        final primary = scenario.expect.primaryDefect;
        if (primary != null) {
          final blob = result.report.issues
              .map((i) => '${i.title} ${i.location} ${i.insight}')
              .join(' ')
              .toLowerCase();
          final hints = [
            primary,
            ...scenario.expect.primaryDefectHints,
          ].map((h) => h.toLowerCase());
          expect(
            hints.any(blob.contains),
            isTrue,
            reason:
                '${scenario.id}: expected primary "$primary" in findings: $blob',
          );
        }
      }, timeout: const Timeout(Duration(seconds: 120)));
    }

    test('healthy scores higher than severe roof on labeled sets', () async {
      final healthy = await harness.runScenario(
        PhotoCalibrationHarness.scenarios.firstWhere(
          (s) => s.id == 'healthy_multi_angle',
        ),
      );
      final roof = await harness.runScenario(
        PhotoCalibrationHarness.scenarios.firstWhere(
          (s) => s.id == 'severe_roof_damage',
        ),
      );
      expect(healthy.passed, isTrue, reason: healthy.summary);
      expect(roof.passed, isTrue, reason: roof.summary);
      expect(healthy.usedRealPhotos, isTrue);
      expect(roof.usedRealPhotos, isTrue);
      expect(healthy.report.highCount, 0);
      // Healthy control should not score worse than labeled roof damage.
      expect(
        healthy.report.overallScore,
        greaterThanOrEqualTo(roof.report.overallScore),
        reason:
            'healthy=${healthy.report.overallScore} severe=${roof.report.overallScore}',
      );
      expect(roof.report.overallScore, lessThan(88));
      final roofBlob = roof.report.issues
          .map((i) => '${i.title} ${i.location}')
          .join(' ')
          .toLowerCase();
      expect(
        roofBlob.contains('roof') ||
            roofBlob.contains('shingle') ||
            roofBlob.contains('granule'),
        isTrue,
        reason: 'severe roof must surface roof finding: $roofBlob',
      );
    });

    test('runAll returns one result per scenario', () async {
      final all = await harness.runAll();
      expect(all.length, PhotoCalibrationHarness.scenarios.length);
      final failed = all.where((r) => !r.passed).map((r) => r.summary);
      expect(failed, isEmpty, reason: failed.join('\n'));
    });
  });
}
