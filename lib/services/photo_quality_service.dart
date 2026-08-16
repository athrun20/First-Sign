import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:image_picker/image_picker.dart';

import '../models/capture_models.dart';

export '../models/capture_models.dart' show PhotoQualityResult;

/// Lightweight on-device quality gates for exterior photos.
///
/// Checks decodeability, resolution, and exposure — no ML required.
class PhotoQualityService {
  PhotoQualityService._();

  static const int minShortSide = 640;
  static const int softMinShortSide = 900;
  static const int minBytes = 12 * 1024; // ~12 KB
  static const double tooDark = 0.12;
  static const double tooBright = 0.92;
  static const double softDark = 0.18;
  static const double softBright = 0.88;

  /// Analyze [photo] bytes and return pass/warn/fail style feedback.
  static Future<PhotoQualityResult> check(XFile photo) async {
    try {
      final bytes = await photo.readAsBytes();
      if (bytes.isEmpty) {
        return const PhotoQualityResult(
          ok: false,
          warnings: ['Photo is empty — try again.'],
        );
      }
      if (bytes.length < minBytes) {
        return PhotoQualityResult(
          ok: false,
          warnings: [
            'Photo file is very small (${_kb(bytes.length)}). '
                'Retake at higher quality or from the camera.',
          ],
        );
      }

      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final width = image.width;
      final height = image.height;
      final shortSide = math.min(width, height);
      final longSide = math.max(width, height);

      if (shortSide < 32 || longSide < 32) {
        image.dispose();
        return const PhotoQualityResult(
          ok: false,
          warnings: ['Image could not be read clearly. Try another photo.'],
        );
      }

      final brightness = await _sampleBrightness(image);
      image.dispose();

      final warnings = <String>[];
      var hardFail = false;

      if (shortSide < minShortSide) {
        hardFail = true;
        warnings.add(
          'Resolution is low ($width×$height). '
          'Move closer or use a higher-quality photo.',
        );
      } else if (shortSide < softMinShortSide) {
        warnings.add(
          'A bit low-res ($width×$height). '
          'Closer or sharper photos improve AI results.',
        );
      }

      if (brightness != null) {
        if (brightness < tooDark) {
          hardFail = true;
          warnings.add(
            'Photo is very dark. Retake in daylight or turn on more light.',
          );
        } else if (brightness > tooBright) {
          hardFail = true;
          warnings.add(
            'Photo is overexposed (washed out). Avoid pointing into the sun.',
          );
        } else if (brightness < softDark) {
          warnings.add('A little dark — shade is fine, but more light helps.');
        } else if (brightness > softBright) {
          warnings.add('Quite bright — glare can hide surface detail.');
        }
      }

      // Extreme aspect ratio (panorama/crop) is usually not a full elevation.
      final aspect = longSide / shortSide;
      if (aspect > 3.2) {
        warnings.add(
          'Very wide crop — full elevations work better than extreme panoramas.',
        );
      }

      return PhotoQualityResult(
        ok: !hardFail,
        warnings: warnings,
        width: width,
        height: height,
        brightness: brightness,
      );
    } catch (_) {
      return const PhotoQualityResult(
        ok: false,
        warnings: [
          'Could not read this image. Use a JPG or PNG from your camera roll.',
        ],
      );
    }
  }

  static String _kb(int bytes) => '${(bytes / 1024).round()} KB';

  /// Average luminance on a downscaled sample grid (0–1).
  static Future<double?> _sampleBrightness(ui.Image image) async {
    try {
      final targetW = math.min(64, image.width);
      final targetH = math.max(
        1,
        (image.height * targetW / image.width).round(),
      );
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        ui.Rect.fromLTWH(0, 0, targetW.toDouble(), targetH.toDouble()),
        ui.Paint(),
      );
      final picture = recorder.endRecording();
      final small = await picture.toImage(targetW, targetH);
      picture.dispose();

      final bd = await small.toByteData();
      small.dispose();
      if (bd == null) return null;

      final data = bd.buffer.asUint8List();
      var sum = 0.0;
      var count = 0;
      // Sample every pixel of the tiny image.
      for (var i = 0; i + 3 < data.length; i += 4) {
        final r = data[i];
        final g = data[i + 1];
        final b = data[i + 2];
        // Perceived luminance.
        sum += (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
        count++;
      }
      if (count == 0) return null;
      return sum / count;
    } catch (_) {
      return null;
    }
  }
}
