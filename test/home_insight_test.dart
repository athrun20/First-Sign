import 'package:flutter_test/flutter_test.dart';
import 'package:pillar_ai/models/analysis_models.dart';
import 'package:pillar_ai/services/home_insight.dart';
import 'package:pillar_ai/theme/app_lux.dart';

void main() {
  AnalysisReport report({
    int score = 80,
    String condition = 'Mixed exterior condition',
    List<AnalysisIssue> issues = const [],
    int photoCount = 4,
  }) {
    return AnalysisReport(
      overallScore: score,
      conditionLabel: condition,
      issues: issues,
      estimatedRepairRange: 'TBD',
      analysisSource: 'Local',
      photoCount: photoCount,
    );
  }

  AnalysisIssue issue({
    required String title,
    String severity = 'Medium',
    int confidence = 80,
  }) {
    return AnalysisIssue(
      title: title,
      location: 'Front',
      severity: severity,
      cost: 'TBD',
      confidence: confidence,
      insight: 'Screening note',
    );
  }

  group('homeStatusFromScore', () {
    test('maps score bands used across Home and history', () {
      const cases = <(int, String)>[
        (100, 'Good'),
        (91, 'Good'),
        (85, 'Good'),
        (84, 'Fair'),
        (70, 'Fair'),
        (69, 'Needs Attention'),
        (40, 'Needs Attention'),
        (0, 'Needs Attention'),
      ];
      for (final (score, label) in cases) {
        expect(
          homeStatusFromScore(score),
          label,
          reason: 'score $score should map to $label',
        );
      }
    });

    test('status colors match score bands', () {
      expect(homeStatusColor(90), AppLux.teal);
      expect(homeStatusColor(75), AppLux.warning);
      expect(homeStatusColor(50), AppLux.danger);
    });
  });

  group('latestInsightLine', () {
    test('empty findings → no high-priority message', () {
      expect(
        latestInsightLine(report(score: 92, condition: 'Strong condition')),
        'No high-priority issues in the latest scan.',
      );
    });

    test('high finding → main item to watch', () {
      final line = latestInsightLine(
        report(
          score: 62,
          issues: [
            issue(title: 'Window seal wear', severity: 'High', confidence: 88),
          ],
        ),
      );
      expect(line, 'Window seal wear is the main item to watch.');
    });

    test('medium finding → main item to plan', () {
      final line = latestInsightLine(
        report(
          score: 78,
          issues: [issue(title: 'Gutter overflow stains', severity: 'Medium')],
        ),
      );
      expect(line, 'Gutter overflow stains is the main item to plan.');
    });

    test('low-only findings → minor notes line', () {
      final line = latestInsightLine(
        report(
          score: 88,
          issues: [issue(title: 'Faded trim paint', severity: 'Low')],
        ),
      );
      expect(line, 'Minor notes only — Faded trim paint is worth a look.');
    });

    test('high finding wins over medium for wording and priority', () {
      final line = latestInsightLine(
        report(
          score: 55,
          issues: [
            issue(title: 'Gutter overflow stains', severity: 'Medium'),
            issue(title: 'Roof granule loss', severity: 'High', confidence: 91),
          ],
        ),
      );
      expect(line, 'Roof granule loss is the main item to watch.');
    });

    test('strips trailing period from finding title', () {
      final line = latestInsightLine(
        report(
          score: 70,
          issues: [
            issue(title: 'Siding paint wear.', severity: 'Medium'),
          ],
        ),
      );
      expect(line, 'Siding paint wear is the main item to plan.');
    });

    test('insufficient exterior stays honest', () {
      final line = latestInsightLine(
        report(
          score: 50,
          condition: 'Insufficient exterior evidence in photos',
        ),
      );
      expect(line, 'Latest scan needs clearer exterior photos.');
    });
  });

  group('homeGreeting', () {
    test('returning users get welcome back', () {
      expect(
        homeGreeting(now: DateTime(2026, 1, 1, 9), returning: true),
        'Welcome back',
      );
    });

    test('time-of-day greetings', () {
      expect(
        homeGreeting(now: DateTime(2026, 1, 1, 8), returning: false),
        'Good morning',
      );
      expect(
        homeGreeting(now: DateTime(2026, 1, 1, 14), returning: false),
        'Good afternoon',
      );
      expect(
        homeGreeting(now: DateTime(2026, 1, 1, 20), returning: false),
        'Good evening',
      );
    });
  });

  group('homeReassuranceLine', () {
    test('insufficient exterior', () {
      expect(
        homeReassuranceLine(
          report(condition: 'Insufficient exterior evidence in photos'),
        ),
        'Need clearer exterior photos',
      );
    });

    test('high findings', () {
      expect(
        homeReassuranceLine(
          report(
            score: 60,
            issues: [issue(title: 'Roof concern', severity: 'High')],
          ),
        ),
        'Worth a closer look soon',
      );
    });

    test('medium findings', () {
      expect(
        homeReassuranceLine(
          report(
            score: 78,
            issues: [issue(title: 'Gutter note', severity: 'Medium')],
          ),
        ),
        'A few items to plan',
      );
    });

    test('healthy empty or high score', () {
      expect(
        homeReassuranceLine(report(score: 92, issues: const [])),
        'Your home looks healthy',
      );
      expect(
        homeReassuranceLine(
          report(
            score: 86,
            issues: [issue(title: 'Light paint fade', severity: 'Low')],
          ),
        ),
        'Your home looks healthy',
      );
    });

    test('generally sound mid band with only lows', () {
      expect(
        homeReassuranceLine(
          report(
            score: 75,
            issues: [issue(title: 'Minor trim wear', severity: 'Low')],
          ),
        ),
        'Generally sound overall',
      );
    });
  });
}
