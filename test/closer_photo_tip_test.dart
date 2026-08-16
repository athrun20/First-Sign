import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pillar_ai/legal/privacy_copy.dart';
import 'package:pillar_ai/models/analysis_models.dart';
import 'package:pillar_ai/models/capture_models.dart';
import 'package:pillar_ai/screens/analysis_report_screen.dart';
import 'package:pillar_ai/screens/guided_capture_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

AnalysisIssue _issue({
  required String title,
  bool needsCloserPhoto = false,
  int confidence = 72,
}) {
  return AnalysisIssue(
    title: title,
    location: 'Front elevation',
    severity: 'Medium',
    cost: 'TBD',
    confidence: confidence,
    insight: 'Screening note.',
    needsCloserPhoto: needsCloserPhoto,
  );
}

AnalysisReport _report({
  required List<AnalysisIssue> issues,
  int photoCount = 1,
}) {
  return AnalysisReport(
    overallScore: 76,
    conditionLabel: 'Photo screening',
    issues: issues,
    estimatedRepairRange: '—',
    analysisSource: 'test',
    photoCount: photoCount,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('hasLimitedVisibility', () {
    test('true when needsCloserPhoto is set', () {
      final report = _report(
        issues: [_issue(title: 'Roof Surface Wear', needsCloserPhoto: true)],
      );
      expect(report.hasLimitedVisibility, isTrue);
    });

    test('true for limited-visibility title', () {
      final report = _report(
        issues: [
          _issue(title: 'Limited Visibility — Closer Photo Needed'),
        ],
      );
      expect(report.hasLimitedVisibility, isTrue);
    });

    test('false when findings are firm', () {
      final report = _report(
        issues: [
          _issue(title: 'Water May Be Dumping Near Foundation', confidence: 84),
        ],
        photoCount: 2,
      );
      expect(report.hasLimitedVisibility, isFalse);
    });
  });

  group('PhotoQualityResult.isDarkOrLowDetail', () {
    test('true for dark warning', () {
      const q = PhotoQualityResult(
        ok: true,
        warnings: ['A little dark — shade is fine, but more light helps.'],
        brightness: 0.16,
      );
      expect(q.isDarkOrLowDetail, isTrue);
    });

    test('false for a clean frame', () {
      const q = PhotoQualityResult(ok: true, brightness: 0.48);
      expect(q.isDarkOrLowDetail, isFalse);
    });
  });

  testWidgets('report shows closer-photo tip when flag is set', (tester) async {
    final report = _report(
      issues: [
        _issue(
          title: 'Limited Visibility — Closer Photo Needed',
          needsCloserPhoto: true,
          confidence: 58,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AnalysisReportScreen(photos: const [], report: report),
        onGenerateRoute: (settings) {
          if (settings.name == '/guided-capture') {
            return MaterialPageRoute<void>(
              builder: (_) => const GuidedCaptureScreen(singlePhotoMode: true),
              settings: settings,
            );
          }
          return null;
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.byKey(const Key('closer-photo-tip')), findsOneWidget);
    expect(find.text(PrivacyCopy.closerPhotoTitle), findsOneWidget);
    expect(find.text(PrivacyCopy.closerPhotoBody), findsOneWidget);
    expect(find.text(PrivacyCopy.closerPhotoAction), findsOneWidget);

    await tester.ensureVisible(find.text(PrivacyCopy.closerPhotoAction));
    await tester.tap(find.text(PrivacyCopy.closerPhotoAction));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(GuidedCaptureScreen), findsOneWidget);
  });

  testWidgets('report hides closer-photo tip when flag is off', (tester) async {
    final report = _report(
      issues: [
        _issue(
          title: 'Water May Be Dumping Near Foundation',
          confidence: 84,
        ),
      ],
      photoCount: 2,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AnalysisReportScreen(photos: const [], report: report),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.byKey(const Key('closer-photo-tip')), findsNothing);
    expect(find.text(PrivacyCopy.closerPhotoTitle), findsNothing);
  });
}
