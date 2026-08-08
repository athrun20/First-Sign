import 'package:flutter_test/flutter_test.dart';
import 'package:pillar_ai/services/analysis_feature_snapshot.dart';
import 'package:pillar_ai/services/exterior_analysis_service.dart';

void main() {
  test('caption-like paint labels surface peeling paint finding', () {
    final service = ExteriorAnalysisService(forceLocalOnly: true);
    final report = service.analyzeFeatureSnapshots(
      [
        ExteriorFeatureSnapshot.peelingPaint(
          seed: 51,
          label: 'Peeling white paint on clapboard',
        ),
        ExteriorFeatureSnapshot.peelingPaint(
          seed: 52,
          label: 'Paint peel close-up',
        ),
      ],
      labels: const {
        'paint': 0.80,
        'peel': 0.76,
        'flake': 0.60,
        'house': 0.70,
        'wall': 0.55,
      },
      visionMode: false,
      source: 'paint soft label unit test',
    );
    final titles = report.issues.map((i) => i.title.toLowerCase()).join(' | ');
    expect(
      titles.contains('paint') || titles.contains('peel'),
      isTrue,
      reason:
          'expected paint/peel finding, got score=${report.overallScore} issues=$titles',
    );
  });
}
