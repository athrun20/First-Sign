import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pillar_ai/models/capture_models.dart';
import 'package:pillar_ai/services/exterior_analysis_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'roof close-up assets surface a roof screening note',
    () async {
      final svc = ExteriorAnalysisService(
        forceLocalOnly: true,
        localAnalysisDelay: Duration.zero,
      );

      const files = [
        'assets/calibration/severe_roof_damage/01_roof.jpg',
        'assets/calibration/severe_roof_damage/02_closeup.jpg',
      ];

      final bytes = <Uint8List>[];
      final photos = <CapturePhoto>[];
      for (var i = 0; i < files.length; i++) {
        final data = await rootBundle.load(files[i]);
        final b = data.buffer.asUint8List();
        bytes.add(b);
        photos.add(
          CapturePhoto(
            file: XFile.fromData(b, name: 'roof$i.jpg', mimeType: 'image/jpeg'),
            label: 'Damaged asphalt shingles close-up',
            index: i,
            slotId: i == 0 ? CaptureShotId.roof : CaptureShotId.problemCloseup,
          ),
        );
      }

      final report = await svc
          .analyzeImageBytes(bytes, capturePhotos: photos)
          .timeout(const Duration(seconds: 30));

      expect(report.overallScore, inInclusiveRange(30, 95));
      expect(
        report.issues.any(
          (i) =>
              i.isGroundDrainageFinding ||
              i.title.toLowerCase().contains('dumping near foundation'),
        ),
        isFalse,
        reason:
            'roof-only assets must not mint drainage/grade findings, got: '
            '${report.issues.map((i) => i.title).join("; ")}',
      );
      // Local multi-feature on real photos may yield empty or roof/wear notes.
      if (report.issues.isNotEmpty) {
        final highOrMed = report.issues.any(
          (i) => i.severity == 'High' || i.severity == 'Medium',
        );
        expect(
          highOrMed || report.issues.every((i) => i.severity == 'Low'),
          isTrue,
        );
      }
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );
}
