import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/capture_models.dart';

/// Paints multi-photo exterior sets that stress the **pixel** analysis pipeline.
///
/// These are not real photographs — they are synthetic fixtures with engineered
/// color/edge structure so [ExteriorAnalysisService] local features fire
/// consistently. Drop real photos under `assets/calibration/<id>/` to override.
class CalibrationFixturePainter {
  CalibrationFixturePainter._();

  /// Build guided-slot photos for a named calibration scenario.
  static Future<List<CapturePhoto>> buildScenario(String scenarioId) async {
    switch (scenarioId) {
      case 'healthy_multi_angle':
        return _set([
          (CaptureShotId.front, 'Front of home', CalibrationScene.healthyFront),
          (CaptureShotId.left, 'Left side', CalibrationScene.healthySide),
          (CaptureShotId.right, 'Right side', CalibrationScene.healthySide),
          (CaptureShotId.rear, 'Rear of home', CalibrationScene.healthyRear),
        ]);
      case 'severe_roof_damage':
        return _set([
          (CaptureShotId.front, 'Front of home', CalibrationScene.healthyFront),
          (CaptureShotId.roof, 'Roof field', CalibrationScene.damagedRoof),
          (
            CaptureShotId.problemCloseup,
            'Roof close-up',
            CalibrationScene.damagedRoofClose,
          ),
          (CaptureShotId.rear, 'Rear of home', CalibrationScene.healthyRear),
        ]);
      case 'gutter_overflow':
        return _set([
          (CaptureShotId.front, 'Front of home', CalibrationScene.gutterDebris),
          (CaptureShotId.left, 'Left eave', CalibrationScene.gutterDebris),
          (CaptureShotId.roof, 'Eave line', CalibrationScene.gutterDebris),
        ]);
      case 'foundation_concern':
        return _set([
          (CaptureShotId.front, 'Front base', CalibrationScene.foundationCrack),
          (CaptureShotId.left, 'Left grade', CalibrationScene.foundationCrack),
          (
            CaptureShotId.right,
            'Right grade',
            CalibrationScene.foundationCrack,
          ),
        ]);
      case 'peeling_paint':
        return _set([
          (CaptureShotId.front, 'Front wall', CalibrationScene.peelingPaint),
          (CaptureShotId.left, 'Left wall', CalibrationScene.peelingPaint),
        ]);
      case 'cracked_siding':
        return _set([
          (CaptureShotId.front, 'Front wall', CalibrationScene.crackedSiding),
          (CaptureShotId.right, 'Right wall', CalibrationScene.crackedSiding),
          (
            CaptureShotId.problemCloseup,
            'Crack close-up',
            CalibrationScene.crackedSidingClose,
          ),
        ]);
      case 'weak_single_photo':
        return _set([
          (CaptureShotId.front, 'Ambiguous', CalibrationScene.weakBlurry),
        ]);
      case 'aging_roof_granules':
        return _set([
          (CaptureShotId.roof, 'Roof slope', CalibrationScene.agingRoof),
          (
            CaptureShotId.problemCloseup,
            'Granule field',
            CalibrationScene.agingRoof,
          ),
          (CaptureShotId.front, 'Front of home', CalibrationScene.healthyFront),
        ]);
      default:
        throw ArgumentError('Unknown calibration scenario: $scenarioId');
    }
  }

  static Future<List<CapturePhoto>> _set(
    List<(CaptureShotId, String, CalibrationScene)> slots,
  ) async {
    final out = <CapturePhoto>[];
    for (var i = 0; i < slots.length; i++) {
      final (id, label, scene) = slots[i];
      final bytes = await _paint(scene, seed: 100 + i * 17);
      out.add(
        CapturePhoto(
          file: XFile.fromData(
            bytes,
            name: '${id.name}_$i.png',
            mimeType: 'image/png',
          ),
          label: label,
          index: i,
          slotId: id,
        ),
      );
    }
    return out;
  }

  static Future<Uint8List> _paint(
    CalibrationScene scene, {
    required int seed,
  }) async {
    const w = 640;
    const h = 480;
    final recorder = ui.PictureRecorder();
    final bounds = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    final canvas = Canvas(recorder, bounds);

    switch (scene) {
      case CalibrationScene.healthyFront:
      case CalibrationScene.healthySide:
      case CalibrationScene.healthyRear:
        _paintHouse(
          canvas,
          w: w,
          h: h,
          sideView: scene == CalibrationScene.healthySide,
          rear: scene == CalibrationScene.healthyRear,
          body: const Color(0xFFE8E0D4),
          roof: const Color(0xFF6B5A52),
          damagedRoof: false,
          gutterDebris: false,
          peeling: false,
          cracked: false,
          foundationIssue: false,
          seed: seed,
        );
      case CalibrationScene.damagedRoof:
        _paintRoofField(canvas, w: w, h: h, damaged: true, seed: seed);
      case CalibrationScene.damagedRoofClose:
        _paintRoofField(
          canvas,
          w: w,
          h: h,
          damaged: true,
          extreme: true,
          seed: seed,
        );
      case CalibrationScene.agingRoof:
        _paintRoofField(
          canvas,
          w: w,
          h: h,
          damaged: false,
          aging: true,
          seed: seed,
        );
      case CalibrationScene.gutterDebris:
        // Dedicated eave strip scene for reliable gutterLineScore / overflow cues.
        _paintGutterClose(canvas, w: w, h: h, seed: seed);
      case CalibrationScene.foundationCrack:
        _paintHouse(
          canvas,
          w: w,
          h: h,
          body: const Color(0xFFD9CFC0),
          roof: const Color(0xFF5C4A42),
          damagedRoof: false,
          gutterDebris: false,
          peeling: false,
          cracked: false,
          foundationIssue: true,
          seed: seed,
        );
      case CalibrationScene.peelingPaint:
        _paintHouse(
          canvas,
          w: w,
          h: h,
          body: const Color(0xFFEDE4D8),
          roof: const Color(0xFF4E3F38),
          damagedRoof: false,
          gutterDebris: false,
          peeling: true,
          cracked: false,
          foundationIssue: false,
          seed: seed,
        );
      case CalibrationScene.crackedSiding:
      case CalibrationScene.crackedSidingClose:
        _paintHouse(
          canvas,
          w: w,
          h: h,
          sideView: scene == CalibrationScene.crackedSiding,
          body: const Color(0xFFE0D5C8),
          roof: const Color(0xFF5C4A42),
          damagedRoof: false,
          gutterDebris: false,
          peeling: false,
          cracked: true,
          foundationIssue: false,
          seed: seed,
          extremeWall: scene == CalibrationScene.crackedSidingClose,
        );
      case CalibrationScene.weakBlurry:
        _paintWeak(canvas, w, h, seed: seed);
    }

    // Calibration watermark (not "DEMO" so real-photo drops stay distinct).
    final tp = TextPainter(
      text: TextSpan(
        text: 'CAL FIXTURE',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.65),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(10, 10, tp.width + 16, tp.height + 10),
        const Radius.circular(6),
      ),
      Paint()..color = const Color(0x990B1220),
    );
    tp.paint(canvas, const Offset(18, 15));

    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    final bd = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bd?.buffer.asUint8List() ?? Uint8List(0);
  }

  static void _paintSkyGround(
    Canvas canvas,
    int w,
    int h, {
    bool lushLawn = false,
  }) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, h * 0.55),
          const [Color(0xFF8EC8E0), Color(0xFFC5DCEA), Color(0xFFEAF1F5)],
          const [0.0, 0.55, 1.0],
        ),
    );
    // Healthy scenes use light driveway/soil — dark green lawn inflates
    // vegetation + foundation false positives in the pixel pipeline.
    final groundTop = lushLawn
        ? const Color(0xFF4F8A45)
        : const Color(0xFFC8C2B4);
    final groundBot = lushLawn
        ? const Color(0xFF3A6B34)
        : const Color(0xFFB5AFA0);
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.68, w.toDouble(), h * 0.32),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, h * 0.68),
          Offset(0, h.toDouble()),
          [groundTop, groundBot],
        ),
    );
  }

  static void _paintHouse(
    Canvas canvas, {
    required int w,
    required int h,
    required Color body,
    required Color roof,
    required bool damagedRoof,
    required bool gutterDebris,
    required bool peeling,
    required bool cracked,
    required bool foundationIssue,
    required int seed,
    bool sideView = false,
    bool rear = false,
    bool extremeWall = false,
  }) {
    final problemScene =
        damagedRoof || gutterDebris || peeling || cracked || foundationIssue;
    // Only foundation scenarios use dark vegetation ground.
    _paintSkyGround(canvas, w, h, lushLawn: foundationIssue);
    final cx = w / 2.0;
    final baseY = h * 0.70;
    final houseW = sideView ? w * 0.55 : w * 0.60;
    final houseH = extremeWall ? h * 0.50 : h * 0.36;
    final left = cx - houseW / 2;
    final top = baseY - houseH;

    // Walls — flat mid-tone body
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, houseW, houseH),
        const Radius.circular(3),
      ),
      Paint()..color = body,
    );

    // Healthy: soft horizontal clapboard only (no vertical edges → fewer cracks)
    if (!cracked && !peeling) {
      final clap = Paint()
        ..color = Colors.black.withValues(alpha: 0.04)
        ..strokeWidth = 1;
      for (var y = top + 16; y < baseY - 12; y += 16) {
        canvas.drawLine(
          Offset(left + 8, y),
          Offset(left + houseW - 8, y),
          clap,
        );
      }
    }

    if (cracked) {
      // Vertical board seams + fracture paths
      final seam = Paint()
        ..color = Colors.black.withValues(alpha: 0.20)
        ..strokeWidth = 2.4;
      for (var x = left + 14; x < left + houseW - 8; x += 16.0) {
        canvas.drawLine(Offset(x, top + 6), Offset(x, baseY - 6), seam);
      }
      final crack = Paint()
        ..color = const Color(0xFF1A1412)
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(
        Path()
          ..moveTo(left + houseW * 0.34, top + houseH * 0.12)
          ..lineTo(left + houseW * 0.38, top + houseH * 0.42)
          ..lineTo(left + houseW * 0.32, top + houseH * 0.70)
          ..lineTo(left + houseW * 0.40, baseY - 10),
        crack,
      );
      canvas.drawPath(
        Path()
          ..moveTo(left + houseW * 0.64, top + houseH * 0.18)
          ..lineTo(left + houseW * 0.58, top + houseH * 0.52)
          ..lineTo(left + houseW * 0.66, top + houseH * 0.88),
        crack,
      );
    }

    if (peeling) {
      // High local luminance variance patches (peelingScore signal).
      for (var i = 0; i < 48; i++) {
        final px = left + 16 + ((i * 43 + seed) % (houseW - 55));
        final py = top + 16 + ((i * 61 + seed * 3) % (houseH - 60));
        final bright = i % 3 == 0;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(px, py, 22 + (i % 7) * 3.0, 16 + (i % 6) * 2.5),
            const Radius.circular(2),
          ),
          Paint()
            ..color = bright
                ? const Color(0xFFFFFBF5)
                : (i.isEven
                      ? const Color(0xFF8A7A68)
                      : const Color(0xFFD8C8B0)),
        );
      }
    }

    // Roof plane
    final roofTop = top - houseH * 0.38;
    final roofPath = Path()
      ..moveTo(left - 14, top + 5)
      ..lineTo(cx, roofTop)
      ..lineTo(left + houseW + 14, top + 5)
      ..close();
    canvas.drawPath(
      roofPath,
      Paint()..color = problemScene ? roof : const Color(0xFF7A6A62),
    );
    if (damagedRoof) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 36, roofTop + 28, 48, 24),
          const Radius.circular(2),
        ),
        Paint()..color = const Color(0xFF1A1412),
      );
    }

    // Gutter — thick continuous eave line when debris scenario
    final gutterY = top + houseH * 0.08;
    canvas.drawLine(
      Offset(left - 14, gutterY),
      Offset(left + houseW + 14, gutterY),
      Paint()
        ..color = const Color(0xFF8A9BA8)
        ..strokeWidth = gutterDebris ? 11 : 4
        ..strokeCap = StrokeCap.round,
    );
    if (gutterDebris) {
      // Multiple parallel eave bands (horizontal banding / gutterLineScore)
      for (var k = 0; k < 3; k++) {
        canvas.drawLine(
          Offset(left - 12, gutterY + 8.0 + k * 7),
          Offset(left + houseW + 12, gutterY + 8.0 + k * 7),
          Paint()
            ..color = Color.fromARGB(220, 100 + k * 12, 110, 120)
            ..strokeWidth = 4,
        );
      }
      for (var i = 0; i < 14; i++) {
        canvas.drawCircle(
          Offset(left + 18 + i * 26.0, gutterY - 2),
          8 + (i % 3).toDouble(),
          Paint()..color = const Color(0xFF1E4A22),
        );
      }
      canvas.drawRect(
        Rect.fromLTWH(left + 10, gutterY + 2, houseW - 20, 28),
        Paint()..color = const Color(0x772A2220),
      );
      // Downspout vertical
      canvas.drawLine(
        Offset(left + houseW + 8, gutterY),
        Offset(left + houseW + 8, baseY),
        Paint()
          ..color = const Color(0xFF8A9BA8)
          ..strokeWidth = 5,
      );
    }

    // Windows only on non-extreme problem walls
    if (!extremeWall && !cracked) {
      void window(double x) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, top + houseH * 0.28, houseW * 0.13, houseH * 0.18),
            const Radius.circular(2),
          ),
          Paint()..color = const Color(0xFFB0C8D8),
        );
      }

      window(left + houseW * 0.14);
      window(left + houseW * 0.72);
    }

    // Foundation — light on healthy; dark + cracks only when intended
    if (foundationIssue) {
      canvas.drawRect(
        Rect.fromLTWH(left - 6, baseY - 18, houseW + 12, 36),
        Paint()..color = const Color(0xFF2E2A26),
      );
      final c = Paint()
        ..color = const Color(0xFF0E0C0A)
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(left + houseW * 0.22, baseY - 14),
        Offset(left + houseW * 0.28, baseY + 14),
        c,
      );
      canvas.drawLine(
        Offset(left + houseW * 0.52, baseY - 12),
        Offset(left + houseW * 0.62, baseY + 16),
        c,
      );
      canvas.drawCircle(
        Offset(left + houseW * 0.4, baseY + 4),
        16,
        Paint()..color = const Color(0x883D5A3A),
      );
    } else if (!problemScene) {
      // Thin light foundation — avoids lowerThirdDark false High
      canvas.drawRect(
        Rect.fromLTWH(left, baseY - 6, houseW, 8),
        Paint()..color = const Color(0xFFC4BFB6),
      );
    } else {
      canvas.drawRect(
        Rect.fromLTWH(left - 2, baseY - 10, houseW + 4, 12),
        Paint()..color = const Color(0xFF9A958C),
      );
    }

    if (rear && !extremeWall) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            cx - houseW * 0.15,
            baseY - houseH * 0.38,
            houseW * 0.30,
            houseH * 0.38,
          ),
          const Radius.circular(2),
        ),
        Paint()..color = const Color(0xFFA8C0CE),
      );
    }
  }

  static void _paintRoofField(
    Canvas canvas, {
    required int w,
    required int h,
    required bool damaged,
    required int seed,
    bool aging = false,
    bool extreme = false,
  }) {
    // Full-frame roof: darker upper band → darkTopBias / roofSignal.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, h.toDouble()),
          aging
              ? const [Color(0xFF6A6560), Color(0xFF8A8680), Color(0xFF9A9590)]
              : const [Color(0xFF2A221F), Color(0xFF3A2E2A), Color(0xFF5A4A44)],
          const [0.0, 0.45, 1.0],
        ),
    );

    // Horizontal shingle courses only (no vertical board look → siding false +).
    final rowH = extreme ? 30.0 : 22.0;
    final tab = Paint()
      ..color = aging ? const Color(0xFF7A7570) : const Color(0xFF4A3C36)
      ..strokeWidth = 1.2;
    for (var row = 0; row < (h / rowH).ceil() + 1; row++) {
      final y = row * rowH + 2;
      canvas.drawLine(Offset(0, y), Offset(w.toDouble(), y), tab);
      // Soft tab breaks along the course (horizontal only)
      for (var col = 0; col < 14; col++) {
        final x = col * (w / 12.0) + (row.isEven ? 8 : 0);
        canvas.drawLine(
          Offset(x, y),
          Offset(x, y + rowH * 0.55),
          Paint()
            ..color = Colors.black.withValues(alpha: aging ? 0.08 : 0.12)
            ..strokeWidth = 1,
        );
      }
    }

    if (damaged) {
      final holes = [
        Offset(w * 0.32, h * 0.28),
        Offset(w * 0.50, h * 0.42),
        Offset(w * 0.44, h * 0.58),
        Offset(w * 0.62, h * 0.35),
        Offset(w * 0.55, h * 0.22),
      ];
      for (final o in holes) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: o,
              width: extreme ? 72 : 50,
              height: extreme ? 42 : 28,
            ),
            const Radius.circular(3),
          ),
          Paint()..color = const Color(0xFF120E0C),
        );
      }
      // Chaos texture patches
      for (var i = 0; i < 40; i++) {
        final x = ((i * 51 + seed) % w).toDouble();
        final y = ((i * 37 + seed * 5) % h).toDouble();
        canvas.drawCircle(
          Offset(x, y),
          2 + (i % 4).toDouble(),
          Paint()..color = Color.fromARGB(180, 30 + (i % 20), 25, 22),
        );
      }
    }

    if (aging) {
      // High grey dominance + variance for granule-loss path (Medium wear).
      for (var i = 0; i < 220; i++) {
        final x = ((i * 47 + seed * 3) % w).toDouble();
        final y = ((i * 31 + seed) % h).toDouble();
        canvas.drawCircle(
          Offset(x, y),
          1.6 + (i % 3) * 0.4,
          Paint()
            ..color = i.isEven
                ? const Color(0xFFC4BEB6)
                : const Color(0xFF6A6560),
        );
      }
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w.toDouble(), h * 0.28),
        Paint()..color = const Color(0x6622201C),
      );
      // Extra edge energy on upper plane
      for (var y = 0.0; y < h * 0.35; y += 10) {
        canvas.drawLine(
          Offset(0, y),
          Offset(w.toDouble(), y),
          Paint()
            ..color = Colors.black.withValues(alpha: 0.14)
            ..strokeWidth = 1.5,
        );
      }
    }

    // Eave strip (not wall structure)
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.88, w.toDouble(), h * 0.06),
      Paint()..color = const Color(0xFF8A9BA8),
    );
  }

  static void _paintGutterClose(
    Canvas canvas, {
    required int w,
    required int h,
    required int seed,
  }) {
    // Mid-frame eave trough: avoid dark roof chaos (false shingle damage).
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = const Color(0xFFE4DCD0),
    );
    // Soft sky
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h * 0.22),
      Paint()..color = const Color(0xFFC5D8E6),
    );
    // Light roof lip (not damaged asphalt field)
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.20, w.toDouble(), h * 0.08),
      Paint()..color = const Color(0xFF8A7A70),
    );
    // Dominant horizontal gutter troughs (mid band) — heavy edge energy
    for (var k = 0; k < 8; k++) {
      final y = h * 0.34 + k * 7.0;
      canvas.drawLine(
        Offset(0, y),
        Offset(w.toDouble(), y),
        Paint()
          ..color = Color.fromARGB(255, 125 + k * 5, 135, 145)
          ..strokeWidth = 8,
      );
    }
    // Dense green debris band (raises greenDominance / vegetationNear)
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.36, w.toDouble(), h * 0.10),
      Paint()..color = const Color(0xFF1A5020),
    );
    for (var i = 0; i < 40; i++) {
      final x = (i * 17.0 + (seed % 5)) % w;
      final y = h * 0.38 + (i % 5) * 6.0;
      canvas.drawCircle(
        Offset(x, y),
        8 + (i % 4).toDouble(),
        Paint()..color = const Color(0xFF0F3A14),
      );
    }
    // Overflow staining under trough
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.48, w.toDouble(), h * 0.12),
      Paint()..color = const Color(0x55302820),
    );
    // Calm lower wall
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.62, w.toDouble(), h * 0.38),
      Paint()..color = const Color(0xFFEAE3D8),
    );
    // Soft clapboard only
    for (var y = h * 0.66; y < h * 0.95; y += 14) {
      canvas.drawLine(
        Offset(0, y),
        Offset(w.toDouble(), y),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.04)
          ..strokeWidth = 1,
      );
    }
  }

  static void _paintWeak(Canvas canvas, int w, int h, {required int seed}) {
    // Low-contrast mush — should not over-claim High findings.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = const Color(0xFFB8C0C8),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w / 2, h / 2),
        width: w * 0.5,
        height: h * 0.4,
      ),
      Paint()..color = const Color(0xFFA8B0B8),
    );
    canvas.drawRect(
      Rect.fromLTWH(w * 0.2, h * 0.55, w * 0.6, h * 0.2),
      Paint()..color = const Color(0xFF9AA2AA),
    );
  }
}

/// Synthetic exterior scene kinds used by painted calibration fixtures.
enum CalibrationScene {
  healthyFront,
  healthySide,
  healthyRear,
  damagedRoof,
  damagedRoofClose,
  agingRoof,
  gutterDebris,
  foundationCrack,
  peelingPaint,
  crackedSiding,
  crackedSidingClose,
  weakBlurry,
}
