import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pillar_ai/models/capture_models.dart';
import 'package:pillar_ai/services/exterior_analysis_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'severe roof calibration assets produce screening findings',
    () async {
      final svc = ExteriorAnalysisService(
        forceLocalOnly: true,
        localAnalysisDelay: Duration.zero,
      );
      expect(svc.hasVisionKey, isFalse);

      const files = [
        'assets/calibration/severe_roof_damage/00_front.jpg',
        'assets/calibration/severe_roof_damage/01_roof.jpg',
        'assets/calibration/severe_roof_damage/02_closeup.jpg',
        'assets/calibration/severe_roof_damage/03_rear.jpg',
      ];

      final bytes = <Uint8List>[];
      final photos = <CapturePhoto>[];
      for (var i = 0; i < files.length; i++) {
        final data = await rootBundle.load(files[i]);
        final b = data.buffer.asUint8List();
        bytes.add(b);
        photos.add(
          CapturePhoto(
            file: XFile.fromData(b, name: 'p$i.jpg', mimeType: 'image/jpeg'),
            label: i == 1 ? 'Damaged asphalt shingles' : 'Front',
            index: i,
            slotId: i == 1 ? CaptureShotId.roof : CaptureShotId.front,
          ),
        );
      }

      final report = await svc
          .analyzeImageBytes(bytes, capturePhotos: photos)
          .timeout(const Duration(seconds: 30));

      expect(report.overallScore, inInclusiveRange(30, 90));
      expect(report.issues, isNotEmpty);
      final blob = report.issues.map((i) => i.title.toLowerCase()).join(' ');
      expect(
        blob.contains('roof') ||
            blob.contains('shingle') ||
            blob.contains('granule'),
        isTrue,
        reason: 'expected roof-related finding, got: $blob',
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
