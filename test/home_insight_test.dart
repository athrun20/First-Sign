import 'package:flutter_test/flutter_test.dart';
import 'package:pillar_ai/models/analysis_models.dart';
import 'package:pillar_ai/screens/analysis_report_screen.dart';
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
        (84, 'Good'),
        (80, 'Good'),
        (79, 'Stable'),
        (70, 'Stable'),
        (67, 'Needs Attention'),
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
      expect(homeStatusColor(75), AppLux.tealDeep);
      expect(homeStatusColor(50), AppLux.danger);
    });
  });

  group('latestInsightLine', () {
    test('empty findings → no high-priority message', () {
      expect(
        latestInsightLine(report(score: 92, condition: 'Strong condition')),
        'No high-priority issues from the latest scan.',
      );
    });

    test('high finding → natural closer-look wording', () {
      final line = latestInsightLine(
        report(
          score: 62,
          issues: [
            issue(title: 'Window seal wear', severity: 'High', confidence: 88),
          ],
        ),
      );
      expect(line, 'Window seal wear needs a closer look soon.');
    });

    test('medium finding → natural appear-to-need wording', () {
      final line = latestInsightLine(
        report(
          score: 78,
          issues: [issue(title: 'Gutter overflow stains', severity: 'Medium')],
        ),
      );
      expect(line, 'Gutter overflow stains appear to need attention.');
    });

    test('plural possible siding cracks is grammatical', () {
      // homeownerTitle softens to "Possible siding cracks".
      final line = latestInsightLine(
        report(
          score: 84,
          issues: [
            issue(
              title: 'Cracked / Damaged Siding',
              severity: 'Medium',
              confidence: 78,
            ),
          ],
        ),
      );
      expect(line.toLowerCase(), contains('siding crack'));
      expect(line, isNot(contains('is the main item')));
      expect(
        line,
        'Siding cracks appear to need attention.',
      );
    });

    test('singular medium finding uses appears', () {
      final line = latestInsightLine(
        report(
          score: 78,
          issues: [
            issue(title: 'Peeling / Failing Exterior Paint', severity: 'Medium'),
          ],
        ),
      );
      expect(line, 'Peeling / Failing Exterior Paint appears to need attention.');
    });

    test('low-only findings → minor notes line', () {
      final line = latestInsightLine(
        report(
          score: 88,
          issues: [issue(title: 'Faded trim paint', severity: 'Low')],
        ),
      );
      expect(line, 'Minor note — Faded trim paint is worth a look.');
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
      expect(line, 'Roof granule loss needs a closer look soon.');
    });

    test('strips trailing period from finding title', () {
      final line = latestInsightLine(
        report(
          score: 70,
          issues: [issue(title: 'Siding paint wear.', severity: 'Medium')],
        ),
      );
      expect(line, 'Siding paint wear appears to need attention.');
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

  group('firstSignAiCompanionNote', () {
    test('does not repeat the finding title from latestInsightLine', () {
      final r = report(
        score: 78,
        issues: [
          issue(title: 'Peeling / Failing Exterior Paint', severity: 'Medium'),
        ],
      );
      final whatMatters = latestInsightLine(r);
      final companion = firstSignAiCompanionNote(r);
      expect(whatMatters.toLowerCase(), contains('peeling'));
      expect(
        companion.toLowerCase().contains('peeling'),
        isFalse,
        reason: 'AI companion must not restate the primary finding title',
      );
      expect(companion, isNot(whatMatters));
      expect(companion.toLowerCase(), contains('manageable'));
    });

    test('high severity frames urgency without naming the defect', () {
      final r = report(
        score: 55,
        issues: [
          issue(title: 'Missing / Damaged Shingles', severity: 'High'),
        ],
      );
      final companion = firstSignAiCompanionNote(r);
      expect(companion.toLowerCase().contains('shingle'), isFalse);
      expect(companion.toLowerCase(), contains('closer look'));
    });

    test('empty findings stay calm and forward-looking', () {
      final companion = firstSignAiCompanionNote(
        report(score: 92, issues: const []),
      );
      expect(companion.toLowerCase(), contains('calm'));
    });

    test('single-photo medium mentions full-home scan', () {
      final companion = firstSignAiCompanionNote(
        report(
          score: 78,
          photoCount: 1,
          issues: [
            issue(title: 'Possible siding cracks', severity: 'Medium'),
          ],
        ),
      );
      expect(companion.toLowerCase(), contains('full-home'));
      expect(companion.toLowerCase(), contains('manageable'));
    });

    test('insufficient exterior asks for clearer angles', () {
      final companion = firstSignAiCompanionNote(
        report(
          score: 50,
          condition: 'Insufficient exterior evidence in photos',
        ),
      );
      expect(companion.toLowerCase(), contains('clearer'));
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

  group('Home Health presentation', () {
    test('81 is Good, not Fair', () {
      expect(reportHealthLabel(81), 'Good');
      expect(homeStatusFromScore(81), 'Good');
      expect(reportHealthLabel(75), 'Stable');
      expect(reportHealthLabel(60), 'Needs Attention');
    });

    test('rewrites technical roof classification titles', () {
      const issue = AnalysisIssue(
        title: 'Roof Surface Wear / Possible Impact',
        location: 'Roof field',
        severity: 'Medium',
        cost: r'$1,800 – $4,200',
        confidence: 82,
        insight: 'Surface wear cues on shingles.',
      );
      expect(issue.homeownerTitle, 'Possible roof surface damage');
      expect(issue.companionNextStep.toLowerCase(), isNot(contains('roof surface wear')));
      expect(issue.shortPlanningRange, contains(r'$'));
    });

    test('hero trust and monitor lines stay calm', () {
      final r = report(
        score: 81,
        issues: [
          issue(title: 'Gutter overflow stains', severity: 'Medium'),
          issue(title: 'Peeling paint', severity: 'Medium'),
        ],
      );
      expect(r.photoTrustLine, contains('No urgent concerns detected'));
      expect(r.photoTrustLine.toLowerCase(), contains('photos provided'));
      expect(r.monitorContextLine, contains('monitor'));
      expect(r.calmConditionLine.toLowerCase(), isNot(contains('fair')));
    });

    test('companion next step names a limitation without repeating the title', () {
      const weak = AnalysisIssue(
        title: 'Possible siding cracks',
        location: 'Left elevation',
        severity: 'Medium',
        cost: 'TBD',
        confidence: 62,
        insight: 'Linear marks, weak evidence.',
        needsCloserPhoto: true,
      );
      expect(weak.companionNextStep.toLowerCase(), contains('closer'));
      expect(
        weak.companionNextStep.toLowerCase(),
        isNot(contains('possible siding cracks')),
      );
    });
  });
}
