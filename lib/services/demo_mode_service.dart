import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/analysis_models.dart';
import '../models/capture_models.dart';
import 'analysis_feature_snapshot.dart';
import 'exterior_analysis_service.dart';
import 'report_store.dart';

/// Result of a one-tap demo walkthrough (sample home → full report).
class DemoSession {
  final List<CapturePhoto> photos;
  final AnalysisReport report;
  final String savedReportId;

  const DemoSession({
    required this.photos,
    required this.report,
    required this.savedReportId,
  });
}

/// Builds a reliable demo assessment from painted sample elevations + the
/// golden-set calibrated analysis path (no camera required).
class DemoModeService {
  DemoModeService({ExteriorAnalysisService? analysis})
    : _analysis = analysis ?? ExteriorAnalysisService();

  final ExteriorAnalysisService _analysis;

  static const demoSource = 'Demo mode · sample home (AI exterior screening)';

  /// Run the full demo: sample photos → analysis → save to history.
  Future<DemoSession> run() async {
    final photos = await buildSamplePhotos();
    final report = buildDemoReport(photos);
    final saved = await ReportStore.instance.saveFromCapture(
      report: report,
      photos: photos,
      id: 'demo_${DateTime.now().millisecondsSinceEpoch}',
    );
    return DemoSession(photos: photos, report: report, savedReportId: saved.id);
  }

  /// Deterministic screening report tuned for a strong product walkthrough.
  AnalysisReport buildDemoReport(List<CapturePhoto> photos) {
    // Mixed sample home: clear roof issue + gutters — strong walkthrough story
    // without stacking so many Highs that the score looks catastrophic.
    final snapshots = <ExteriorFeatureSnapshot>[
      ExteriorFeatureSnapshot.healthyElevation(seed: 101, label: 'Front'),
      ExteriorFeatureSnapshot.healthyElevation(seed: 102, label: 'Left'),
      ExteriorFeatureSnapshot.gutterOverflow(seed: 103, label: 'Right / eave'),
      ExteriorFeatureSnapshot.healthyElevation(seed: 104, label: 'Rear'),
      ExteriorFeatureSnapshot.damagedRoof(seed: 105, label: 'Roof'),
      ExteriorFeatureSnapshot.agingRoof(seed: 106, label: 'Close-up'),
    ];

    // Use as many snapshots as photos (usually 6).
    final used = snapshots.take(photos.length).toList();
    while (used.length < photos.length) {
      used.add(
        ExteriorFeatureSnapshot.healthyElevation(seed: 200 + used.length),
      );
    }

    return _analysis.analyzeFeatureSnapshots(
      used,
      labels: const {
        'roof': 0.93,
        'shingle': 0.88,
        'damage': 0.80,
        'asphalt': 0.72,
        'gutter': 0.84,
        'downspout': 0.68,
        'leaf': 0.58,
        'debris': 0.52,
        'house': 0.90,
        'siding': 0.70,
        'window': 0.62,
      },
      visionMode: true,
      capturePhotos: photos,
      source: demoSource,
    );
  }

  /// Six guided-slot sample elevations painted on-device.
  Future<List<CapturePhoto>> buildSamplePhotos() async {
    final slots = <(CaptureShotId, String, _SampleScene)>[
      (CaptureShotId.front, 'Front of home', _SampleScene.front),
      (CaptureShotId.left, 'Left side', _SampleScene.left),
      (CaptureShotId.right, 'Right side', _SampleScene.right),
      (CaptureShotId.rear, 'Rear of home', _SampleScene.rear),
      (CaptureShotId.roof, 'Roof & eaves', _SampleScene.roof),
      (
        CaptureShotId.problemCloseup,
        'Problem close-up',
        _SampleScene.roofCloseup,
      ),
    ];

    final photos = <CapturePhoto>[];
    for (var i = 0; i < slots.length; i++) {
      final (id, label, scene) = slots[i];
      final bytes = await _paintSample(scene, seed: i + 1);
      photos.add(
        CapturePhoto(
          file: XFile.fromData(
            bytes,
            name: 'demo_${id.name}.png',
            mimeType: 'image/png',
          ),
          label: label,
          index: i,
          slotId: id,
        ),
      );
    }
    return photos;
  }

  Future<Uint8List> _paintSample(
    _SampleScene scene, {
    required int seed,
  }) async {
    const w = 720;
    const h = 540;
    final recorder = ui.PictureRecorder();
    final bounds = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    final canvas = Canvas(recorder, bounds);

    // Sky
    final sky = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        const Offset(0, h * 0.55),
        const [Color(0xFF7EC8E3), Color(0xFFB8D9F0), Color(0xFFE8F0F5)],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawRect(bounds, sky);

    // Ground
    final ground = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, h * 0.62),
        Offset(0, h.toDouble()),
        const [Color(0xFF5A8F4A), Color(0xFF3D6B35)],
      );
    canvas.drawRect(Rect.fromLTWH(0, h * 0.62, w.toDouble(), h * 0.38), ground);

    switch (scene) {
      case _SampleScene.front:
        _drawHouse(
          canvas,
          w: w,
          h: h,
          body: const Color(0xFFE8E0D4),
          roof: const Color(0xFF5C4A42),
          accent: const Color(0xFF2F5D50),
          damagedRoof: false,
          showGutters: true,
          seed: seed,
        );
      case _SampleScene.left:
        _drawHouse(
          canvas,
          w: w,
          h: h,
          body: const Color(0xFFD9CFC0),
          roof: const Color(0xFF6B5344),
          accent: const Color(0xFF4A6FA5),
          damagedRoof: false,
          showGutters: true,
          sideView: true,
          seed: seed,
        );
      case _SampleScene.right:
        _drawHouse(
          canvas,
          w: w,
          h: h,
          body: const Color(0xFFE2D6C6),
          roof: const Color(0xFF5C4A42),
          accent: const Color(0xFF8B5A2B),
          damagedRoof: false,
          showGutters: true,
          gutterDebris: true,
          sideView: true,
          seed: seed,
        );
      case _SampleScene.rear:
        _drawHouse(
          canvas,
          w: w,
          h: h,
          body: const Color(0xFFEDE4D8),
          roof: const Color(0xFF4E3F38),
          accent: const Color(0xFF6B7C85),
          damagedRoof: false,
          showGutters: true,
          rear: true,
          seed: seed,
        );
      case _SampleScene.roof:
        _drawRoofClose(canvas, w: w, h: h, damaged: true, seed: seed);
      case _SampleScene.roofCloseup:
        _drawRoofClose(
          canvas,
          w: w,
          h: h,
          damaged: true,
          extremeClose: true,
          seed: seed,
        );
    }

    // Demo watermark
    final watermark = TextPainter(
      text: TextSpan(
        text: 'SAMPLE · DEMO',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.72),
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final badge = RRect.fromRectAndRadius(
      Rect.fromLTWH(14, 14, watermark.width + 20, watermark.height + 12),
      const Radius.circular(8),
    );
    canvas.drawRRect(badge, Paint()..color = const Color(0xCC0B1220));
    watermark.paint(canvas, const Offset(24, 20));

    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    final bd = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bd?.buffer.asUint8List() ?? Uint8List(0);
  }

  void _drawHouse(
    Canvas canvas, {
    required int w,
    required int h,
    required Color body,
    required Color roof,
    required Color accent,
    required bool damagedRoof,
    required bool showGutters,
    required int seed,
    bool sideView = false,
    bool gutterDebris = false,
    bool rear = false,
  }) {
    final cx = w / 2;
    final baseY = h * 0.72;
    final houseW = sideView ? w * 0.52 : w * 0.58;
    final houseH = h * 0.38;
    final left = cx - houseW / 2;
    final top = baseY - houseH;

    // Shadow
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, baseY + 8),
        width: houseW * 1.05,
        height: 28,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.12),
    );

    // Walls
    final wallRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, houseW, houseH),
      const Radius.circular(4),
    );
    canvas.drawRRect(wallRect, Paint()..color = body);
    canvas.drawRRect(
      wallRect,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Siding lines
    final linePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (var y = top + 18; y < baseY - 8; y += 14) {
      canvas.drawLine(
        Offset(left + 6, y),
        Offset(left + houseW - 6, y),
        linePaint,
      );
    }

    // Roof triangle / plane
    final roofTop = top - houseH * 0.42;
    final roofPath = Path()
      ..moveTo(left - 18, top + 8)
      ..lineTo(cx, roofTop)
      ..lineTo(left + houseW + 18, top + 8)
      ..close();
    canvas.drawPath(roofPath, Paint()..color = roof);
    if (damagedRoof) {
      // Missing shingle patches
      final patch = Paint()..color = const Color(0xFF2A2220);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 30, roofTop + 36, 42, 22),
          const Radius.circular(3),
        ),
        patch,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx + 24, roofTop + 52, 28, 16),
          const Radius.circular(3),
        ),
        patch,
      );
    }

    // Ridge highlight
    canvas.drawLine(
      Offset(left + 20, top + 4),
      Offset(left + houseW - 20, top + 4),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..strokeWidth = 3,
    );

    if (showGutters) {
      final gutterY = top + 6;
      canvas.drawLine(
        Offset(left - 14, gutterY),
        Offset(left + houseW + 14, gutterY),
        Paint()
          ..color = const Color(0xFF8A9BA8)
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
      if (gutterDebris) {
        final leaf = Paint()..color = const Color(0xFF3D7A32);
        for (var i = 0; i < 7; i++) {
          canvas.drawCircle(
            Offset(left + 40 + i * 38.0 + (seed % 3), gutterY - 2),
            5 + (i % 3).toDouble(),
            leaf,
          );
        }
      }
      // Downspout
      canvas.drawLine(
        Offset(left + houseW + 10, gutterY),
        Offset(left + houseW + 10, baseY),
        Paint()
          ..color = const Color(0xFF8A9BA8)
          ..strokeWidth = 4,
      );
    }

    // Door / windows
    if (!sideView) {
      final doorW = houseW * 0.16;
      final doorH = houseH * 0.48;
      final doorLeft = cx - doorW / 2;
      final doorTop = baseY - doorH;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(doorLeft, doorTop, doorW, doorH),
          const Radius.circular(3),
        ),
        Paint()..color = accent,
      );
      // Windows
      void window(double x) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, top + houseH * 0.22, houseW * 0.14, houseH * 0.22),
            const Radius.circular(3),
          ),
          Paint()..color = const Color(0xFFA8C8DC),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, top + houseH * 0.22, houseW * 0.14, houseH * 0.22),
            const Radius.circular(3),
          ),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }

      window(left + houseW * 0.12);
      window(left + houseW * 0.74);
    } else {
      // Side windows
      for (var i = 0; i < 3; i++) {
        final x = left + houseW * (0.15 + i * 0.28);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, top + houseH * 0.28, houseW * 0.16, houseH * 0.2),
            const Radius.circular(3),
          ),
          Paint()..color = const Color(0xFFA8C8DC),
        );
      }
    }

    if (rear) {
      // Sliding door suggestion
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            cx - houseW * 0.18,
            baseY - houseH * 0.42,
            houseW * 0.36,
            houseH * 0.42,
          ),
          const Radius.circular(3),
        ),
        Paint()..color = const Color(0xFF9BB8C9),
      );
    }

    // Foundation strip
    canvas.drawRect(
      Rect.fromLTWH(left - 4, baseY - 10, houseW + 8, 14),
      Paint()..color = const Color(0xFF8A8680),
    );

    // Simple trees
    final treePaint = Paint()..color = const Color(0xFF2F6B3A);
    canvas.drawCircle(Offset(left - 48, baseY - 40), 28, treePaint);
    canvas.drawCircle(Offset(left + houseW + 52, baseY - 36), 24, treePaint);
    canvas.drawRect(
      Rect.fromLTWH(left - 54, baseY - 20, 12, 28),
      Paint()..color = const Color(0xFF5C4033),
    );
  }

  void _drawRoofClose(
    Canvas canvas, {
    required int w,
    required int h,
    required bool damaged,
    required int seed,
    bool extremeClose = false,
  }) {
    // Shingle field
    final base = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, h.toDouble()),
        const [Color(0xFF6B5A52), Color(0xFF4A3C36), Color(0xFF3A2E2A)],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), base);

    final tab = Paint()..color = const Color(0xFF5A4A44);
    final gap = Paint()..color = const Color(0xFF2A221F);
    final rowH = extremeClose ? 36.0 : 28.0;
    final tabW = extremeClose ? 52.0 : 40.0;

    for (var row = 0; row < (h / rowH).ceil() + 1; row++) {
      final y = row * rowH;
      final offset = (row.isEven ? 0.0 : tabW / 2) + (seed % 5);
      for (var col = -1; col < (w / tabW).ceil() + 2; col++) {
        final x = col * tabW + offset;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x + 1, y + 2, tabW - 3, rowH - 4),
            const Radius.circular(2),
          ),
          tab,
        );
      }
    }

    if (damaged) {
      // Missing / torn tabs
      final holes = [
        Offset(w * 0.35, h * 0.28),
        Offset(w * 0.52, h * 0.40),
        Offset(w * 0.44, h * 0.55),
        Offset(w * 0.62, h * 0.33),
      ];
      for (final o in holes) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: o,
              width: extremeClose ? 70 : 48,
              height: extremeClose ? 40 : 28,
            ),
            const Radius.circular(4),
          ),
          gap,
        );
        // Dark underlayment hint
        canvas.drawCircle(
          o.translate(6, 4),
          extremeClose ? 10 : 6,
          Paint()..color = const Color(0xFF1A1412),
        );
      }

      // Granule scatter
      final granule = Paint()..color = const Color(0xFF9A9590);
      for (var i = 0; i < 40; i++) {
        final x = ((i * 47 + seed * 13) % w).toDouble();
        final y = ((i * 31 + seed * 7) % (h ~/ 2)).toDouble() + h * 0.45;
        canvas.drawCircle(Offset(x, y), 1.5 + (i % 3) * 0.4, granule);
      }
    }

    // Eave / gutter strip at bottom third for context
    if (!extremeClose) {
      canvas.drawRect(
        Rect.fromLTWH(0, h * 0.82, w.toDouble(), h * 0.08),
        Paint()..color = const Color(0xFF8A9BA8),
      );
    }
  }
}

enum _SampleScene { front, left, right, rear, roof, roofCloseup }
