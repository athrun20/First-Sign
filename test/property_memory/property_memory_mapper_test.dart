import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pillar_ai/models/analysis_models.dart';
import 'package:pillar_ai/models/capture_models.dart';
import 'package:pillar_ai/models/property_memory_enums.dart';
import 'package:pillar_ai/models/saved_report.dart';
import 'package:pillar_ai/models/twin_zone.dart';
import 'package:pillar_ai/services/property_memory_mapper.dart';

AnalysisIssue _issue({
  required String title,
  String location = 'Front elevation',
  String severity = 'High',
  int confidence = 90,
  bool needsCloserPhoto = false,
  int? photoIndex = 0,
  double? hl,
  double? ht,
  double? hw,
  double? hh,
}) {
  return AnalysisIssue(
    title: title,
    location: location,
    severity: severity,
    cost: '\$500',
    confidence: confidence,
    insight: 'Visible from photos only.',
    photoIndex: photoIndex,
    sourcePhotoLabel: location,
    needsCloserPhoto: needsCloserPhoto,
    highlightLeft: hl,
    highlightTop: ht,
    highlightWidth: hw,
    highlightHeight: hh,
  );
}

SavedReport _report({
  required List<AnalysisIssue> issues,
  required List<SavedPhoto> photos,
  String id = 'report_1',
}) {
  return SavedReport(
    id: id,
    createdAt: DateTime.utc(2026, 9, 10),
    report: AnalysisReport(
      overallScore: 72,
      conditionLabel: 'Mixed',
      issues: issues,
      estimatedRepairRange: '\$500–\$2,000',
      analysisSource: 'test',
      photoCount: photos.length,
    ),
    photos: photos,
  );
}

SavedPhoto _photo(int index, CaptureShotId? slot) {
  return SavedPhoto(
    index: index,
    label: slot?.name ?? 'Photo',
    slotId: slot,
    bytes: Uint8List.fromList([index, 1, 2, 3]),
  );
}

void main() {
  group('PropertyMemoryMapper', () {
    test('maps severity High/Medium/Low → urgent/attention/watch', () {
      final saved = _report(
        issues: [
          _issue(title: 'Roof shingle damage', severity: 'High', location: 'Roof'),
          _issue(title: 'Peeling paint', severity: 'Medium', location: 'Siding'),
          _issue(title: 'Minor wear', severity: 'Low', location: 'Siding'),
        ],
        photos: [_photo(0, CaptureShotId.front)],
      );
      final dets = PropertyMemoryMapper.mapSavedReportToDetections(saved);
      expect(dets.map((d) => d.severityBand), [
        SeverityBand.urgent,
        SeverityBand.attention,
        SeverityBand.watch,
      ]);
    });

    test('needsCloserPhoto → insufficient/low confidence + poor quality', () {
      final saved = _report(
        issues: [
          _issue(
            title: 'Possible crack',
            confidence: 92,
            needsCloserPhoto: true,
            location: 'Foundation',
          ),
        ],
        photos: [_photo(0, CaptureShotId.front)],
      );
      final d = PropertyMemoryMapper.mapSavedReportToDetections(saved).single;
      expect(d.confidence, ConfidenceBand.insufficient);
      expect(d.imageQuality, ImageQualityBand.poor);
    });

    test('highlights → region localization; twinZone → SurfaceType', () {
      final roof = _issue(
        title: 'Missing shingles on roof',
        location: 'Roof field',
        hl: 0.1,
        ht: 0.2,
        hw: 0.3,
        hh: 0.25,
      );
      expect(roof.twinZone, TwinZone.roof);
      expect(roof.hasLocalizedHighlight, isTrue);

      final saved = _report(
        issues: [roof],
        photos: [_photo(0, CaptureShotId.roof)],
      );
      final d = PropertyMemoryMapper.mapSavedReportToDetections(saved).single;
      expect(d.surfaceType, SurfaceType.roof);
      expect(d.localizationType, LocalizationType.region);
      expect(d.regionNorm, isNotNull);
      expect(d.category, ObservationCategory.missingMaterial);
    });

    test('AT-related coverage: meetsBaselineMinimum with 4 elevations', () {
      final photos = [
        _photo(0, CaptureShotId.front),
        _photo(1, CaptureShotId.left),
        _photo(2, CaptureShotId.right),
        _photo(3, CaptureShotId.rear),
      ];
      final saved = _report(issues: const [], photos: photos);
      final cov = PropertyMemoryMapper.buildCoverage(saved);
      expect(cov.meetsBaselineMinimum, isTrue);
      expect(cov.photoCount, 4);
    });

    test('Quick Scan single photo does not meet baseline minimum', () {
      final saved = _report(
        issues: [_issue(title: 'Stain on siding')],
        photos: [_photo(0, CaptureShotId.problemCloseup)],
      );
      expect(PropertyMemoryMapper.looksLikeQuickOrSingleShot(saved), isTrue);
      final cov = PropertyMemoryMapper.buildCoverage(saved);
      expect(cov.meetsBaselineMinimum, isFalse);
    });


    test('untagged 4 photos do not meet baseline minimum', () {
      final photos = [
        _photo(0, null),
        _photo(1, null),
        _photo(2, null),
        _photo(3, null),
      ];
      final saved = _report(issues: const [], photos: photos);
      final cov = PropertyMemoryMapper.buildCoverage(saved);
      expect(cov.meetsBaselineMinimum, isFalse);
      expect(PropertyMemoryMapper.looksLikeQuickOrSingleShot(saved), isTrue);
    });

    test('3 elevations + roof meet baseline minimum', () {
      final photos = [
        _photo(0, CaptureShotId.front),
        _photo(1, CaptureShotId.left),
        _photo(2, CaptureShotId.right),
        _photo(3, CaptureShotId.roof),
      ];
      final saved = _report(issues: const [], photos: photos);
      final cov = PropertyMemoryMapper.buildCoverage(saved);
      expect(cov.meetsBaselineMinimum, isTrue);
    });

    test('poor quality caps high/medium confidence to low', () {
      expect(
        PropertyMemoryMapper.capConfidenceByQuality(
          ConfidenceBand.high,
          ImageQualityBand.poor,
        ),
        ConfidenceBand.low,
      );
      expect(
        PropertyMemoryMapper.capConfidenceByQuality(
          ConfidenceBand.medium,
          ImageQualityBand.poor,
        ),
        ConfidenceBand.low,
      );
      expect(
        PropertyMemoryMapper.capConfidenceByQuality(
          ConfidenceBand.insufficient,
          ImageQualityBand.poor,
        ),
        ConfidenceBand.insufficient,
      );
    });

    test('enum storage maps fresh → new', () {
      expect(ObservationStatus.fresh.toStorage(), 'new');
      expect(ObservationStatus.fromStorage('new'), ObservationStatus.fresh);
      expect(ScanMode.checkIn.toStorage(), 'check_in');
    });
  });
}
