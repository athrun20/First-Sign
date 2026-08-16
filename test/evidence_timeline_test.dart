import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pillar_ai/models/analysis_models.dart';
import 'package:pillar_ai/models/capture_models.dart';
import 'package:pillar_ai/models/saved_report.dart';
import 'package:pillar_ai/services/analysis_feature_snapshot.dart';
import 'package:pillar_ai/services/evidence_timeline.dart';
import 'package:pillar_ai/services/exterior_analysis_service.dart';
import 'package:pillar_ai/services/finding_retake_service.dart';

void main() {
  AnalysisIssue issue({
    required String title,
    String location = 'Front',
    int? photoIndex,
    String sourcePhotoLabel = '',
  }) {
    return AnalysisIssue(
      title: title,
      location: location,
      severity: 'Medium',
      cost: 'TBD',
      confidence: 80,
      insight: 'Screening note.',
      photoIndex: photoIndex,
      sourcePhotoLabel: sourcePhotoLabel,
    );
  }

  CapturePhoto cap({
    required int index,
    required String label,
    CaptureShotId? slotId,
  }) {
    return CapturePhoto(
      file: XFile.fromData(
        Uint8List.fromList(const [1, 2, 3]),
        name: '$label.jpg',
        mimeType: 'image/jpeg',
      ),
      label: label,
      index: index,
      slotId: slotId,
    );
  }

  SavedPhoto saved({
    required int index,
    required String label,
    CaptureShotId? slotId,
  }) {
    return SavedPhoto(
      index: index,
      label: label,
      slotId: slotId,
      bytes: Uint8List.fromList([index + 1, 9, 9, 9]),
    );
  }

  group('non-exterior scene gate', () {
    test('person / selfie / portrait short-circuit even with a house behind', () {
      expect(
        ExteriorAnalysisService.isClearlyNonExteriorScene({
          'Person': 0.94,
          'Face': 0.88,
          'Portrait': 0.80,
        }),
        isTrue,
      );
      expect(
        ExteriorAnalysisService.isClearlyNonExteriorScene({
          'Selfie': 0.90,
          'House': 0.52,
          'Building': 0.48,
        }),
        isTrue,
      );
      expect(
        ExteriorAnalysisService.filterExteriorVisionLabels({
          'Person': 0.93,
          'Face': 0.86,
          'House': 0.50,
        }),
        isEmpty,
      );
    });

    test('roof field with a small person tag still counts as exterior', () {
      expect(
        ExteriorAnalysisService.isClearlyNonExteriorScene({
          'Roof': 0.92,
          'Shingle': 0.86,
          'Person': 0.22,
        }),
        isFalse,
      );
    });

    test('portrait in front of a house is still non-exterior', () {
      expect(
        ExteriorAnalysisService.isClearlyNonExteriorScene({
          'Person': 0.88,
          'Face': 0.80,
          'House': 0.78,
          'Building': 0.70,
        }),
        isTrue,
      );
      expect(
        ExteriorAnalysisService.filterExteriorVisionLabels({
          'Person': 0.88,
          'Face': 0.80,
          'House': 0.78,
        }),
        isEmpty,
      );
    });

    test('incidental person on a roof field stays exterior', () {
      expect(
        ExteriorAnalysisService.isClearlyNonExteriorScene({
          'Roof': 0.90,
          'Shingle': 0.82,
          'Person': 0.50,
        }),
        isFalse,
      );
    });

    test('person snapshot produces no exterior finding', () {
      final report =
          ExteriorAnalysisService(forceLocalOnly: true).analyzeFeatureSnapshots(
            [ExteriorFeatureSnapshot.healthyElevation(seed: 3, label: 'Selfie')],
            labels: const {
              'Person': 0.96,
              'Face': 0.91,
              'Portrait': 0.84,
            },
            visionMode: true,
            source: 'person fixture',
          );
      expect(report.issues, isEmpty);
      expect(
        report.conditionLabel.toLowerCase(),
        contains('insufficient exterior'),
      );
    });
  });

  group('EvidenceTimelinePairing', () {
    test('does not pair a roof finding with a portrait prior', () {
      final current = issue(
        title: 'Roof Surface Wear / Possible Impact',
        location: 'Roof field',
        photoIndex: 0,
        sourcePhotoLabel: 'Roof & eaves',
      );
      final priorPortrait = issue(
        title: 'Limited Visibility — Closer Photo Needed',
        location: 'Capture set',
        photoIndex: 0,
        sourcePhotoLabel: 'Portrait',
      );
      expect(
        EvidenceTimelinePairing.matchPriorIssue(current, [priorPortrait]),
        isNull,
      );
    });

    test('pairs roof with a prior roof-like finding and photo', () {
      final current = issue(
        title: 'Roof Surface Wear / Possible Impact',
        location: 'Roof field',
        photoIndex: 0,
        sourcePhotoLabel: 'Roof & eaves',
      );
      final priorRoof = issue(
        title: 'Possible roof granule loss',
        location: 'Roof field',
        photoIndex: 0,
        sourcePhotoLabel: 'Roof & eaves',
      );
      expect(
        EvidenceTimelinePairing.matchPriorIssue(current, [priorRoof]),
        isNotNull,
      );

      final prior = SavedReport(
        id: 'old',
        createdAt: DateTime(2026, 1, 1),
        report: AnalysisReport(
          overallScore: 80,
          conditionLabel: 'Good',
          issues: [priorRoof],
          estimatedRepairRange: 'TBD',
          analysisSource: 'test',
          photoCount: 1,
        ),
        photos: [
          saved(index: 0, label: 'Roof & eaves', slotId: CaptureShotId.roof),
        ],
      );
      final priorPhoto = EvidenceTimelinePairing.priorEvidencePhoto(
        match: priorRoof,
        prior: prior,
      );
      expect(priorPhoto, isNotNull);
      expect(priorPhoto!.label.toLowerCase(), contains('roof'));
      expect(
        EvidenceTimelinePairing.isComparablePair(
          current: current,
          currentPhoto: cap(
            index: 0,
            label: 'Roof & eaves',
            slotId: CaptureShotId.roof,
          ),
          prior: priorRoof,
          priorPhoto: priorPhoto,
        ),
        isTrue,
      );
    });

    test('never uses a face photo as the prior timeline side', () {
      final roofIssue = issue(
        title: 'Roof Surface Wear / Possible Impact',
        location: 'Roof field',
        photoIndex: 0,
        sourcePhotoLabel: 'Portrait',
      );
      final prior = SavedReport(
        id: 'old',
        createdAt: DateTime(2026, 1, 1),
        report: AnalysisReport(
          overallScore: 70,
          conditionLabel: 'Mixed',
          issues: [roofIssue],
          estimatedRepairRange: 'TBD',
          analysisSource: 'test',
          photoCount: 2,
        ),
        photos: [
          saved(index: 0, label: 'Portrait', slotId: CaptureShotId.front),
          saved(index: 1, label: 'Roof & eaves', slotId: CaptureShotId.roof),
        ],
      );
      final bound = EvidenceTimelinePairing.priorEvidencePhoto(
        match: roofIssue,
        prior: prior,
      );
      expect(bound, isNotNull);
      expect(bound!.label.toLowerCase(), isNot(contains('portrait')));
      expect(bound.slotId, CaptureShotId.roof);
    });

    test('does not fall back to photos.first when no comparable photo exists', () {
      final drain = issue(
        title: 'Water May Be Dumping Near Foundation',
        location: 'Downspout outlets & soil at grade',
        photoIndex: 0,
        sourcePhotoLabel: 'Portrait',
      );
      final prior = SavedReport(
        id: 'old',
        createdAt: DateTime(2026, 1, 1),
        report: AnalysisReport(
          overallScore: 70,
          conditionLabel: 'Mixed',
          issues: [drain],
          estimatedRepairRange: 'TBD',
          analysisSource: 'test',
          photoCount: 1,
        ),
        photos: [
          saved(index: 0, label: 'Portrait', slotId: CaptureShotId.front),
        ],
      );
      expect(
        EvidenceTimelinePairing.priorEvidencePhoto(match: drain, prior: prior),
        isNull,
      );
    });

    test('does not pair roof with a foundation prior', () {
      final roof = issue(
        title: 'Roof Surface Wear / Possible Impact',
        location: 'Roof field',
        photoIndex: 0,
        sourcePhotoLabel: 'Roof & eaves',
      );
      final foundation = issue(
        title: 'Possible foundation settlement',
        location: 'Base of wall at grade',
        photoIndex: 0,
        sourcePhotoLabel: 'Foundation close-up',
      );
      expect(
        EvidenceTimelinePairing.matchPriorIssue(roof, [foundation]),
        isNull,
      );
      expect(
        EvidenceTimelinePairing.isComparablePair(
          current: roof,
          currentPhoto: cap(
            index: 0,
            label: 'Roof & eaves',
            slotId: CaptureShotId.roof,
          ),
          prior: foundation,
          priorPhoto: saved(
            index: 0,
            label: 'Foundation close-up',
            slotId: CaptureShotId.problemCloseup,
          ),
        ),
        isFalse,
      );
    });

    test('mixed portrait + roof set keeps roof finding off the face photo', () {
      final photos = [
        cap(index: 0, label: 'Portrait', slotId: CaptureShotId.front),
        cap(index: 1, label: 'Roof & eaves', slotId: CaptureShotId.roof),
      ];
      final report =
          ExteriorAnalysisService(forceLocalOnly: true).analyzeFeatureSnapshots(
            [
              ExteriorFeatureSnapshot.healthyElevation(seed: 2, label: 'Portrait'),
              ExteriorFeatureSnapshot.damagedRoof(seed: 21, label: 'Roof & eaves'),
            ],
            labels: const {
              'Person': 0.94,
              'Face': 0.88,
              'Portrait': 0.80,
              'Roof': 0.92,
              'Shingle': 0.86,
              'House': 0.70,
            },
            visionMode: true,
            source: 'mixed portrait + roof',
            capturePhotos: photos,
          );
      expect(report.issues, isNotEmpty);
      expect(
        report.conditionLabel.toLowerCase(),
        isNot(contains('insufficient exterior')),
      );
      for (final i in report.issues) {
        expect(i.sourcePhotoLabel.toLowerCase(), isNot(contains('portrait')));
        expect(i.photoIndex, isNot(0));
      }
      final roofIssue = report.issues.firstWhere(
        (i) {
          final t = i.title.toLowerCase();
          return t.contains('roof') ||
              t.contains('shingle') ||
              t.contains('granule');
        },
        orElse: () => report.issues.first,
      );
      final bound = FindingRetakeService.primaryEvidencePhoto(
        issue: roofIssue,
        photos: photos,
      );
      expect(bound, isNotNull);
      expect(bound!.slotId, CaptureShotId.roof);
    });

    test('person-labeled capture is never primary evidence', () {
      const roof = AnalysisIssue(
        title: 'Roof Surface Wear / Possible Impact',
        location: 'Roof field',
        severity: 'Medium',
        cost: 'TBD',
        confidence: 78,
        insight: 'Note',
        photoIndex: 0,
        sourcePhotoLabel: 'Portrait',
      );
      final bound = FindingRetakeService.primaryEvidencePhoto(
        issue: roof,
        photos: [
          cap(index: 0, label: 'Portrait', slotId: CaptureShotId.front),
          cap(index: 1, label: 'Roof & eaves', slotId: CaptureShotId.roof),
        ],
      );
      expect(bound, isNotNull);
      expect(bound!.slotId, CaptureShotId.roof);
    });
  });
}
