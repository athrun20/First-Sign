import 'package:flutter_test/flutter_test.dart';
import 'package:pillar_ai/models/analysis_models.dart';
import 'package:pillar_ai/models/capture_models.dart';
import 'package:pillar_ai/services/finding_retake_service.dart';

void main() {
  group('FindingRetakeService', () {
    test('maps roof findings to roof or close-up slot', () {
      const roof = AnalysisIssue(
        title: 'Missing / Damaged Shingles',
        location: 'Roof field',
        severity: 'Medium',
        cost: '\$1,000 – \$2,000',
        confidence: 80,
        insight: 'Screening note.',
      );
      expect(FindingRetakeService.preferredSlot(roof), CaptureShotId.roof);

      const weakRoof = AnalysisIssue(
        title: 'Missing / Damaged Shingles',
        location: 'Roof field',
        severity: 'Medium',
        cost: '\$1,000 – \$2,000',
        confidence: 62,
        insight: 'Screening note.',
        needsCloserPhoto: true,
      );
      expect(
        FindingRetakeService.preferredSlot(weakRoof),
        CaptureShotId.problemCloseup,
      );
    });

    test('maps paint and foundation to problem close-up', () {
      const paint = AnalysisIssue(
        title: 'Peeling / Failing Exterior Paint',
        location: 'Sun-exposed walls',
        severity: 'Medium',
        cost: '\$400 – \$1,200',
        confidence: 84,
        insight: 'Screening note.',
      );
      expect(
        FindingRetakeService.preferredSlot(paint),
        CaptureShotId.problemCloseup,
      );

      const foundation = AnalysisIssue(
        title: 'Foundation Crack / Settlement Signs',
        location: 'Grade line',
        severity: 'Medium',
        cost: '\$800 – \$2,400',
        confidence: 78,
        insight: 'Screening note.',
      );
      expect(
        FindingRetakeService.preferredSlot(foundation),
        CaptureShotId.problemCloseup,
      );
    });

    test('change summary reports score and severity deltas', () {
      const beforeIssue = AnalysisIssue(
        title: 'Missing / Damaged Shingles',
        location: 'Roof field',
        severity: 'High',
        cost: '\$2,000 – \$4,000',
        confidence: 70,
        insight: 'Weak evidence.',
        needsCloserPhoto: true,
      );
      const before = AnalysisReport(
        overallScore: 62,
        conditionLabel: 'Attention needed',
        issues: [beforeIssue],
        estimatedRepairRange: '\$2,000 – \$4,000',
        analysisSource: 'test',
        photoCount: 3,
      );
      const afterIssue = AnalysisIssue(
        title: 'Missing / Damaged Shingles',
        location: 'Roof field, ridges & valleys',
        severity: 'Medium',
        cost: '\$1,600 – \$3,800',
        confidence: 86,
        insight: 'Stronger cues.',
        needsCloserPhoto: false,
      );
      const after = AnalysisReport(
        overallScore: 74,
        conditionLabel: 'Fair',
        issues: [afterIssue],
        estimatedRepairRange: '\$1,600 – \$3,800',
        analysisSource: 'test',
        photoCount: 3,
      );

      final summary = FindingRetakeService.changeSummary(
        before: before,
        after: after,
        previousIssue: beforeIssue,
      );
      expect(summary.contains('62'), isTrue);
      expect(summary.contains('74'), isTrue);
      expect(summary.toLowerCase(), contains('medium'));
      expect(summary.toLowerCase(), contains('closer'));
    });

    test('matchFinding finds same system by title tokens', () {
      const previous = AnalysisIssue(
        title: 'Possible Gutter Overflow',
        location: 'Roof edge / gutters',
        severity: 'Medium',
        cost: '\$200 – \$800',
        confidence: 75,
        insight: 'Note',
      );
      const other = AnalysisIssue(
        title: 'Peeling / Failing Exterior Paint',
        location: 'Walls',
        severity: 'Low',
        cost: '\$400 – \$900',
        confidence: 70,
        insight: 'Note',
      );
      const gutter = AnalysisIssue(
        title: 'Gutter Overflow Risk',
        location: 'Downspout outlets',
        severity: 'Low',
        cost: '\$200 – \$600',
        confidence: 82,
        insight: 'Note',
      );
      final match = FindingRetakeService.matchFinding(previous, const [
        other,
        gutter,
      ]);
      expect(match?.title, contains('Gutter'));
    });
  });
}
