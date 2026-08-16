import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pillar_ai/models/analysis_models.dart';
import 'package:pillar_ai/models/twin_zone.dart';
import 'package:pillar_ai/screens/analysis_report_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  AnalysisIssue issue({
    required String title,
    String location = 'Capture set',
    String severity = 'Medium',
  }) {
    return AnalysisIssue(
      title: title,
      location: location,
      severity: severity,
      cost: 'TBD',
      confidence: 78,
      insight: 'Screening note.',
    );
  }

  AnalysisReport reportWith(List<AnalysisIssue> issues) {
    return AnalysisReport(
      overallScore: 74,
      conditionLabel: 'Attention needed — plan repairs (screening)',
      estimatedRepairRange: 'TBD',
      analysisSource: 'test',
      photoCount: 2,
      issues: issues,
    );
  }

  group('twin zone mapping', () {
    test('drainage finding maps to Gutters, not Foundation or Roof', () {
      final drain = issue(
        title: 'Water May Be Dumping Near Foundation',
        location: 'Downspout outlets & soil at grade',
      );
      expect(drain.isGroundDrainageFinding, isTrue);
      expect(drain.twinZone, TwinZone.gutters);
    });

    test('eave overflow maps to Gutters', () {
      final gutter = issue(
        title: 'Possible Gutter Overflow',
        location: 'Roof edge / gutters',
      );
      expect(gutter.twinZone, TwinZone.gutters);
    });

    test('roof wear maps to Roof', () {
      final roof = issue(
        title: 'Roof Surface Wear / Possible Impact',
        location: 'Roof field',
      );
      expect(roof.twinZone, TwinZone.roof);
    });

    test('paint / siding map to Siding', () {
      expect(
        issue(
          title: 'Peeling / Failing Exterior Paint',
          location: 'Front wall',
        ).twinZone,
        TwinZone.siding,
      );
      expect(
        issue(
          title: 'Cracked / Damaged Siding',
          location: 'Left elevation',
        ).twinZone,
        TwinZone.siding,
      );
    });

    test('foundation crack maps to Foundation', () {
      expect(
        issue(
          title: 'Foundation Crack / Settlement Signs',
          location: 'Foundation wall',
        ).twinZone,
        TwinZone.foundation,
      );
    });
  });

  group('twin tap copy', () {
    test('helper and empty lines are screening-toned', () {
      expect(
        TwinZoneCopy.tapHelper,
        'Tap a surface to see findings for that area.',
      );
      expect(
        TwinZoneCopy.noIssuesLine(TwinZone.roof),
        'No issues flagged on Roof from these photos.',
      );
      expect(
        TwinZoneCopy.noIssuesLine(TwinZone.gutters),
        'No issues flagged on Gutters from these photos.',
      );
    });
  });

  group('twin tap on report', () {
    testWidgets('helper is visible on first open', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AnalysisReportScreen(
            photos: const [],
            report: reportWith([
              issue(
                title: 'Water May Be Dumping Near Foundation',
                location: 'Downspout outlets & soil at grade',
              ),
            ]),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      expect(find.byKey(const Key('twin-tap-helper')), findsOneWidget);
      expect(find.text(TwinZoneCopy.tapHelper), findsOneWidget);
    });

    testWidgets('tap Gutters focuses the drainage finding', (tester) async {
      final drain = issue(
        title: 'Water May Be Dumping Near Foundation',
        location: 'Downspout outlets & soil at grade',
        severity: 'Medium',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AnalysisReportScreen(
            photos: const [],
            report: reportWith([drain]),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      await tester.tap(find.widgetWithText(InkWell, 'Gutters'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));

      expect(find.byKey(const Key('twin-tap-helper')), findsNothing);
      expect(find.byKey(const Key('twin-zone-summary')), findsOneWidget);
      expect(find.text('Medium'), findsWidgets);
      expect(find.text(drain.homeownerTitle), findsWidgets);
      expect(find.text('View evidence →'), findsWidgets);
    });

    testWidgets('tap Roof with no roof finding is a calm empty', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AnalysisReportScreen(
            photos: const [],
            report: reportWith([
              issue(
                title: 'Water May Be Dumping Near Foundation',
                location: 'Downspout outlets & soil at grade',
              ),
            ]),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      await tester.tap(find.widgetWithText(InkWell, 'Roof'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));

      expect(
        find.text(TwinZoneCopy.noIssuesLine(TwinZone.roof)),
        findsWidgets,
      );
      expect(find.byKey(const Key('twin-zone-empty')), findsOneWidget);
      expect(find.byKey(const Key('twin-zone-summary')), findsNothing);
    });
  });
}
