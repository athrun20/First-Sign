import 'package:flutter_test/flutter_test.dart';
import 'package:pillar_ai/services/analysis_feature_snapshot.dart';
import 'package:pillar_ai/services/exterior_analysis_service.dart';

void main() {
  final service = ExteriorAnalysisService(forceLocalOnly: true);

  test('mismatched / patched siding surfaces as Medium lead finding', () {
    final report = service.analyzeFeatureSnapshots(
      [
        ExteriorFeatureSnapshot.mismatchedSiding(
          seed: 91,
          label: 'Front wall patch',
        ),
        ExteriorFeatureSnapshot.mismatchedSiding(
          seed: 92,
          label: 'Side elevation',
        ),
      ],
      labels: const {
        'siding': 0.86,
        'house': 0.90,
        'wall': 0.78,
        'discoloration': 0.72,
        'patch': 0.68,
        'window': 0.55,
      },
      visionMode: true,
      source: 'mismatched siding unit test',
    );

    final titles = report.issues.map((i) => i.title.toLowerCase()).join(' | ');
    final blob =
        '$titles ${report.conditionLabel.toLowerCase()}';

    expect(
      blob.contains('patch') ||
          blob.contains('mismatched') ||
          blob.contains('siding'),
      isTrue,
      reason: 'expected patched/mismatched siding, got: $titles',
    );
    expect(
      report.issues.any(
        (i) =>
            i.severity == 'Medium' ||
            i.severity == 'High',
      ),
      isTrue,
      reason: 'expected Medium+ severity for clear patch work, got: '
          '${report.issues.map((i) => '${i.severity} ${i.title}').join('; ')}',
    );
    // Should not bury the wall defect under a lone window seal note.
    if (report.issues.isNotEmpty) {
      final lead = report.issues.first.title.toLowerCase();
      expect(
        lead.contains('siding') ||
            lead.contains('patch') ||
            lead.contains('mismatched'),
        isTrue,
        reason: 'lead finding should be siding patch, got: $lead',
      );
    }
  });

  test('exterior wiring clutter surfaces when labels support it', () {
    final report = service.analyzeFeatureSnapshots(
      [
        ExteriorFeatureSnapshot.exteriorWiringClutter(
          seed: 101,
          label: 'Wall cables',
        ),
        ExteriorFeatureSnapshot.exteriorWiringClutter(
          seed: 102,
          label: 'Side cables',
        ),
      ],
      labels: const {
        'house': 0.88,
        'siding': 0.74,
        'wall': 0.70,
        'cable': 0.82,
        'wiring': 0.78,
        'electrical': 0.60,
      },
      visionMode: true,
      source: 'wiring clutter unit test',
    );

    final titles = report.issues.map((i) => i.title.toLowerCase()).join(' | ');
    expect(
      titles.contains('wiring') || titles.contains('cable'),
      isTrue,
      reason: 'expected exterior wiring/cable finding, got: $titles',
    );
    expect(
      report.issues.any((i) => i.severity == 'Medium' || i.severity == 'High'),
      isTrue,
      reason: 'expected Medium+ for heavy cable clutter',
    );
  });

  test('weak indoor-like scenes still do not invent wall patch findings', () {
    final report = service.analyzeFeatureSnapshots(
      [
        ExteriorFeatureSnapshot.weakAmbiguous(seed: 61, label: 'Ambiguous'),
      ],
      labels: const {'house': 0.55, 'building': 0.48},
      visionMode: false,
      source: 'weak scene honesty unit test',
    );

    expect(report.highCount, 0);
    final titles = report.issues.map((i) => i.title.toLowerCase()).join(' | ');
    expect(
      titles.contains('mismatched') || titles.contains('patched siding'),
      isFalse,
      reason: 'weak scene must not invent patched siding: $titles',
    );
    expect(
      titles.contains('wiring') || titles.contains('cable clutter'),
      isFalse,
      reason: 'weak scene must not invent wiring clutter: $titles',
    );
  });

  test('healthy multi-angle still avoids false patch / wiring Mediums', () {
    final report = service.analyzeFeatureSnapshots(
      [
        ExteriorFeatureSnapshot.healthyElevation(seed: 11, label: 'Front'),
        ExteriorFeatureSnapshot.healthyElevation(seed: 12, label: 'Left'),
        ExteriorFeatureSnapshot.healthyElevation(seed: 13, label: 'Right'),
      ],
      labels: const {
        'house': 0.92,
        'building': 0.88,
        'siding': 0.70,
        'roof': 0.55,
        'window': 0.60,
      },
      visionMode: false,
      source: 'healthy honesty unit test',
    );

    expect(report.overallScore, greaterThanOrEqualTo(88));
    expect(report.highCount, 0);
    final mediumTitles = report.issues
        .where((i) => i.severity == 'Medium' || i.severity == 'High')
        .map((i) => i.title.toLowerCase())
        .toList();
    expect(
      mediumTitles.any(
        (t) => t.contains('mismatched') || t.contains('patched'),
      ),
      isFalse,
      reason: 'healthy home must not invent patched siding: $mediumTitles',
    );
    expect(
      mediumTitles.any((t) => t.contains('wiring') || t.contains('cable')),
      isFalse,
      reason: 'healthy home must not invent wiring clutter: $mediumTitles',
    );
  });
}
