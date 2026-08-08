import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pillar_ai/models/analysis_models.dart';
import 'package:pillar_ai/models/capture_models.dart';
import 'package:pillar_ai/services/demo_mode_service.dart';
import 'package:pillar_ai/services/report_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReportPdfService', () {
    final service = ReportPdfService();

    AnalysisReport sampleReport() {
      final photos = [
        for (var i = 0; i < 6; i++)
          CapturePhoto(
            file: XFile.fromData(
              Uint8List.fromList([1, 2, 3]),
              name: 'p$i.png',
              mimeType: 'image/png',
            ),
            label: 'Photo $i',
            index: i,
            slotId: CaptureShotId.values[i % CaptureShotId.values.length],
          ),
      ];
      return DemoModeService().buildDemoReport(photos);
    }

    test('defaultFileName includes score and date', () {
      const report = AnalysisReport(
        overallScore: 77,
        conditionLabel: 'Fair',
        issues: [],
        estimatedRepairRange: '\$0',
        analysisSource: 'Demo mode · sample home',
        photoCount: 6,
      );
      final name = service.defaultFileName(
        report: report,
        at: DateTime(2026, 7, 20),
      );
      expect(name, contains('FirstSign_Exterior_Screening'));
      expect(name, contains('Demo'));
      expect(name, contains('77'));
      expect(name, contains('2026-07-20'));
      expect(name.endsWith('.pdf'), isTrue);
    });

    test('buildPdfBytes produces non-empty PDF', () async {
      final report = sampleReport();
      final bytes = await service.buildPdfBytes(report);
      expect(bytes.length, greaterThan(500));
      // PDF magic header
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('success messages mention download on web path wording for share', () {
      expect(
        service.successMessage(PdfExportAction.print).toLowerCase(),
        contains('print'),
      );
      // share message is platform-dependent; both variants are non-empty.
      expect(service.successMessage(PdfExportAction.share), isNotEmpty);
    });

    test('pdfSafe normalizes Helvetica-unsafe punctuation', () {
      const raw =
          'Photo screening · not an inspection — plan within 1–2 weeks… '
          '“quotes” and ‘apostrophes’ • bullet → next';
      final safe = ReportPdfService.pdfSafe(raw);
      expect(safe, isNot(contains('·')));
      expect(safe, isNot(contains('—')));
      expect(safe, isNot(contains('–')));
      expect(safe, isNot(contains('…')));
      expect(safe, isNot(contains('“')));
      expect(safe, isNot(contains('”')));
      expect(safe, isNot(contains('•')));
      expect(safe, isNot(contains('→')));
      expect(safe, contains(' | '));
      expect(safe, contains('...'));
      expect(safe, contains('->'));
      expect(safe, contains('"quotes"'));
    });
  });
}
