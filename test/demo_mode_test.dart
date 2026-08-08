import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pillar_ai/models/capture_models.dart';
import 'package:pillar_ai/services/demo_mode_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DemoModeService', () {
    test('buildDemoReport produces screening findings and demo source', () {
      final photos = [
        for (var i = 0; i < 6; i++)
          CapturePhoto(
            file: XFile.fromData(
              Uint8List.fromList([0, 1, 2, 3]),
              name: 'p$i.png',
              mimeType: 'image/png',
            ),
            label: 'Photo $i',
            index: i,
            slotId: CaptureShotId.values[i % CaptureShotId.values.length],
          ),
      ];

      final report = DemoModeService().buildDemoReport(photos);

      expect(report.photoCount, 6);
      expect(report.analysisSource.toLowerCase(), contains('demo'));
      expect(report.analysisSource.toLowerCase(), contains('screening'));
      expect(report.overallScore, inInclusiveRange(34, 92));
      expect(report.issues, isNotEmpty);
      // Sample home should surface a roof-related story beat.
      final blob = report.issues.map((i) => i.title.toLowerCase()).join(' ');
      expect(
        blob.contains('roof') ||
            blob.contains('shingle') ||
            blob.contains('gutter'),
        isTrue,
        reason:
            'Demo should flag roof/gutter findings for walkthrough value: $blob',
      );
      for (final issue in report.issues) {
        expect(issue.confidence, lessThanOrEqualTo(94));
      }
    });

    test(
      'buildSamplePhotos returns 6 guided slots with SAMPLE bytes',
      () async {
        final photos = await DemoModeService().buildSamplePhotos();
        expect(photos, hasLength(6));
        expect(
          photos.map((p) => p.slotId).toSet(),
          containsAll([
            CaptureShotId.front,
            CaptureShotId.roof,
            CaptureShotId.problemCloseup,
          ]),
        );
        for (final p in photos) {
          final bytes = await p.file.readAsBytes();
          expect(
            bytes.length,
            greaterThan(500),
            reason: '${p.label} should be a real painted PNG',
          );
          // PNG magic
          expect(bytes[0], 0x89);
          expect(bytes[1], 0x50);
        }
      },
    );
  });
}
