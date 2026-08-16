import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pillar_ai/models/analysis_models.dart';
import 'package:pillar_ai/models/capture_models.dart';
import 'package:pillar_ai/services/analysis_feature_snapshot.dart';
import 'package:pillar_ai/services/exterior_analysis_service.dart';
import 'package:pillar_ai/services/finding_retake_service.dart';

void main() {
  final service = ExteriorAnalysisService(forceLocalOnly: true);

  CapturePhoto photo({
    required int index,
    required String label,
    CaptureShotId? slotId,
  }) {
    return CapturePhoto(
      file: XFile.fromData(
        Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xD9]),
        name: 'photo_$index.jpg',
        mimeType: 'image/jpeg',
      ),
      label: label,
      index: index,
      slotId: slotId,
    );
  }

  group('evidence photo binding', () {
    test('roof finding primary is roof slot, not soil close-up', () {
      final photos = [
        photo(
          index: 0,
          label: 'Wet soil near downspout outlet',
          slotId: CaptureShotId.problemCloseup,
        ),
        photo(
          index: 1,
          label: 'Roof field',
          slotId: CaptureShotId.roof,
        ),
      ];
      final report = service.analyzeFeatureSnapshots(
        [
          ExteriorFeatureSnapshot.groundDischarge(
            seed: 71,
            label: 'Wet soil near downspout outlet',
          ),
          ExteriorFeatureSnapshot.damagedRoof(
            seed: 21,
            label: 'Roof field',
          ),
        ],
        labels: const {
          'roof': 0.84,
          'shingle': 0.78,
          'pipe': 0.80,
          'downspout': 0.72,
          'soil': 0.60,
          'house': 0.55,
        },
        visionMode: true,
        source: 'roof vs soil evidence binding',
        capturePhotos: photos,
      );

      final roofIssues = report.issues.where((i) {
        final t = i.title.toLowerCase();
        return t.contains('roof') ||
            t.contains('shingle') ||
            t.contains('granule');
      }).toList();
      expect(
        roofIssues,
        isNotEmpty,
        reason:
            'expected a roof finding, got: '
            '${report.issues.map((i) => i.title).join("; ")}',
      );
      for (final roof in roofIssues) {
        expect(
          roof.photoIndex,
          1,
          reason:
              'roof primary must be Roof field, got index=${roof.photoIndex} '
              'label=${roof.sourcePhotoLabel}',
        );
        expect(
          roof.sourcePhotoLabel.toLowerCase(),
          contains('roof'),
        );
      }

      final drainage = report.issues.where((i) => i.isGroundDrainageFinding);
      for (final d in drainage) {
        expect(
          d.photoIndex,
          isNot(1),
          reason:
              'drainage must not use the roof field as primary '
              '(index=${d.photoIndex} label=${d.sourcePhotoLabel})',
        );
        expect(
          d.photoIndex,
          0,
          reason:
              'drainage primary should be the soil close-up, got '
              'index=${d.photoIndex} label=${d.sourcePhotoLabel}',
        );
      }
    });

    test('UI rematch: roof finding does not open soil when index is wrong', () {
      const roofIssue = AnalysisIssue(
        title: 'Roof Surface Wear / Possible Impact',
        location: 'Roof field',
        severity: 'Medium',
        cost: 'TBD',
        confidence: 78,
        insight: 'Screening note.',
        photoIndex: 0,
        sourcePhotoLabel: 'Wet soil near downspout outlet',
      );
      final photos = [
        photo(
          index: 0,
          label: 'Wet soil near downspout outlet',
          slotId: CaptureShotId.problemCloseup,
        ),
        photo(
          index: 1,
          label: 'Roof field',
          slotId: CaptureShotId.roof,
        ),
      ];
      final bound = FindingRetakeService.primaryEvidencePhoto(
        issue: roofIssue,
        photos: photos,
      );
      expect(bound, isNotNull);
      expect(bound!.slotId, CaptureShotId.roof);
      expect(bound.label.toLowerCase(), contains('roof'));
    });

    test('UI rematch: drainage finding prefers grade close-up', () {
      const drainIssue = AnalysisIssue(
        title: 'Water May Be Dumping Near Foundation',
        location: 'Downspout outlets & soil at grade',
        severity: 'Medium',
        cost: 'TBD',
        confidence: 76,
        insight: 'Screening note.',
        photoIndex: 1,
        sourcePhotoLabel: 'Roof field',
      );
      final photos = [
        photo(
          index: 0,
          label: 'Wet soil near downspout outlet',
          slotId: CaptureShotId.problemCloseup,
        ),
        photo(
          index: 1,
          label: 'Roof field',
          slotId: CaptureShotId.roof,
        ),
      ];
      final bound = FindingRetakeService.primaryEvidencePhoto(
        issue: drainIssue,
        photos: photos,
      );
      expect(bound, isNotNull);
      expect(bound!.slotId, CaptureShotId.problemCloseup);
      expect(bound.label.toLowerCase(), contains('soil'));
    });

    test('never defaults to front/photo0 when a category match exists', () {
      final photos = [
        photo(index: 0, label: 'Front of home', slotId: CaptureShotId.front),
        photo(index: 1, label: 'Roof ridge', slotId: CaptureShotId.roof),
        photo(
          index: 2,
          label: 'Wet soil near downspout outlet',
          slotId: CaptureShotId.problemCloseup,
        ),
      ];

      const drain = AnalysisIssue(
        title: 'Water May Be Dumping Near Foundation',
        location: 'Downspout outlets & soil at grade',
        severity: 'Medium',
        cost: 'TBD',
        confidence: 76,
        insight: 'Screening note.',
        photoIndex: 0,
        sourcePhotoLabel: 'Front of home',
      );
      final drainBound = FindingRetakeService.primaryEvidencePhoto(
        issue: drain,
        photos: photos,
        fallbackIndex: 0,
      );
      expect(drainBound, isNotNull);
      expect(drainBound!.index, 2);
      expect(drainBound.label.toLowerCase(), contains('soil'));
      expect(drainBound.slotId, isNot(CaptureShotId.roof));

      const roof = AnalysisIssue(
        title: 'Roof Surface Wear / Possible Impact',
        location: 'Roof field',
        severity: 'Medium',
        cost: 'TBD',
        confidence: 78,
        insight: 'Screening note.',
        photoIndex: 0,
        sourcePhotoLabel: 'Front of home',
      );
      final roofBound = FindingRetakeService.primaryEvidencePhoto(
        issue: roof,
        photos: photos,
        fallbackIndex: 0,
      );
      expect(roofBound, isNotNull);
      expect(roofBound!.index, 1);
      expect(roofBound.slotId, CaptureShotId.roof);
      expect(roofBound.label.toLowerCase(), isNot(contains('soil')));
    });

    test('drainage primary is never the Roof & eaves slot', () {
      const drain = AnalysisIssue(
        title: 'Water May Be Dumping Near Foundation',
        location: 'Downspout outlets & soil at grade',
        severity: 'Medium',
        cost: 'TBD',
        confidence: 76,
        insight: 'Screening note.',
        photoIndex: 1,
        sourcePhotoLabel: 'Roof & eaves',
      );
      final photos = [
        photo(
          index: 0,
          label: 'Wet soil near downspout outlet',
          slotId: CaptureShotId.problemCloseup,
        ),
        photo(
          index: 1,
          label: 'Roof & eaves',
          slotId: CaptureShotId.roof,
        ),
      ];
      final bound = FindingRetakeService.primaryEvidencePhoto(
        issue: drain,
        photos: photos,
        fallbackIndex: 1,
      );
      expect(bound, isNotNull);
      expect(bound!.slotId, isNot(CaptureShotId.roof));
      expect(bound.label.toLowerCase(), isNot(contains('roof')));
      expect(bound.label.toLowerCase(), contains('soil'));

      final rebound = FindingRetakeService.rebindIssue(
        issue: drain,
        photos: photos,
      );
      expect(rebound.photoIndex, 0);
      expect(rebound.sourcePhotoLabel.toLowerCase(), contains('soil'));
    });

    test('roof finding does not use a generic soil problem close-up', () {
      const roof = AnalysisIssue(
        title: 'Roof Surface Wear / Possible Impact',
        location: 'Roof field',
        severity: 'Medium',
        cost: 'TBD',
        confidence: 64,
        insight: 'Screening note.',
        needsCloserPhoto: true,
        photoIndex: 0,
        sourcePhotoLabel: 'Problem close-up',
      );
      final photos = [
        photo(
          index: 0,
          label: 'Problem close-up',
          slotId: CaptureShotId.problemCloseup,
        ),
        photo(index: 1, label: 'Roof field', slotId: CaptureShotId.roof),
      ];
      // Caption "Problem close-up" is not grade-like; slot is still soil-like
      // only if we refuse to prefer it over the roof slot.
      final bound = FindingRetakeService.primaryEvidencePhoto(
        issue: roof,
        photos: photos,
        fallbackIndex: 0,
      );
      expect(bound, isNotNull);
      expect(bound!.slotId, CaptureShotId.roof);
    });

    test('roof-only photo does not support a drainage finding', () {
      const drain = AnalysisIssue(
        title: 'Water May Be Dumping Near Foundation',
        location: 'Downspout outlets & soil at grade',
        severity: 'Medium',
        cost: 'TBD',
        confidence: 76,
        insight: 'Screening note.',
        photoIndex: 0,
        sourcePhotoLabel: 'Roof & eaves',
      );
      final roof = photo(
        index: 0,
        label: 'Roof & eaves',
        slotId: CaptureShotId.roof,
      );
      expect(FindingRetakeService.photoSupportsIssue(drain, roof), isFalse);
      expect(
        FindingRetakeService.bestIssueForPhoto(photo: roof, issues: [drain]),
        isNull,
      );
    });

    test('gallery pick prefers roof finding over drainage on a roof frame', () {
      const drain = AnalysisIssue(
        title: 'Water May Be Dumping Near Foundation',
        location: 'Downspout outlets & soil at grade',
        severity: 'Medium',
        cost: 'TBD',
        confidence: 76,
        insight: 'Screening note.',
        photoIndex: 0,
        sourcePhotoLabel: 'Wet soil near downspout outlet',
      );
      const roofIssue = AnalysisIssue(
        title: 'Roof Surface Wear / Possible Impact',
        location: 'Roof field',
        severity: 'Medium',
        cost: 'TBD',
        confidence: 78,
        insight: 'Screening note.',
        photoIndex: 1,
        sourcePhotoLabel: 'Roof & eaves',
      );
      final roof = photo(
        index: 1,
        label: 'Roof & eaves',
        slotId: CaptureShotId.roof,
      );
      final picked = FindingRetakeService.bestIssueForPhoto(
        photo: roof,
        issues: [drain, roofIssue],
      );
      expect(picked, isNotNull);
      expect(picked!.title.toLowerCase(), contains('roof'));
      expect(picked.isGroundDrainageFinding, isFalse);
    });

    test('rebind drops drainage when every photo is roof-domain', () {
      const drain = AnalysisIssue(
        title: 'Water May Be Dumping Near Foundation',
        location: 'Downspout outlets & soil at grade',
        severity: 'Medium',
        cost: 'TBD',
        confidence: 76,
        insight: 'Screening note.',
        photoIndex: 0,
        sourcePhotoLabel: 'Roof & eaves',
      );
      const roofIssue = AnalysisIssue(
        title: 'Roof Surface Wear / Possible Impact',
        location: 'Roof field',
        severity: 'Medium',
        cost: 'TBD',
        confidence: 78,
        insight: 'Screening note.',
        photoIndex: 0,
        sourcePhotoLabel: 'Roof & eaves',
      );
      final photos = [
        photo(index: 0, label: 'Roof & eaves', slotId: CaptureShotId.roof),
      ];
      final rebound = FindingRetakeService.rebindIssues(
        issues: [drain, roofIssue],
        photos: photos,
      );
      expect(rebound.any((i) => i.isGroundDrainageFinding), isFalse);
      expect(rebound, isNotEmpty);
      expect(rebound.first.title.toLowerCase(), contains('roof'));
    });

    test('evidence caption never mixes grade location with Roof & eaves', () {
      const drain = AnalysisIssue(
        title: 'Water May Be Dumping Near Foundation',
        location: 'Downspout outlets & soil at grade',
        severity: 'Medium',
        cost: 'TBD',
        confidence: 76,
        insight: 'Screening note.',
      );
      final mixed = FindingRetakeService.evidenceCaption(
        issue: drain,
        photoLabel: 'Roof & eaves',
        photoSupportsFinding: true,
      );
      expect(mixed.toLowerCase(), isNot(contains('roof & eaves')));
      expect(mixed.toLowerCase(), contains('grade'));

      final related = FindingRetakeService.evidenceCaption(
        issue: drain,
        photoLabel: 'Roof & eaves',
        photoSupportsFinding: false,
      );
      expect(related.toLowerCase(), contains('related context'));
      expect(related.toLowerCase(), contains('roof & eaves'));
      expect(related.toLowerCase(), isNot(contains('soil at grade')));

      final note = FindingRetakeService.relatedContextNote(drain);
      expect(note.toLowerCase(), contains('related context'));
      expect(note.toLowerCase(), contains('not proof'));
    });
  });
}
