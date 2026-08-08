import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'storage_exception.dart';

/// Compress / downscale images for local persistence (reports, drafts, leads).
class ImageCodecUtil {
  ImageCodecUtil._();

  /// Scale + re-encode so the long side ≤ [maxSide] and size ≤ [maxBytes].
  ///
  /// Falls back to a trimmed original slice only if decode fails entirely.
  static Future<Uint8List> compressForStorage(
    Uint8List input, {
    int? maxSide,
    int? maxBytes,
  }) async {
    if (input.isEmpty) return input;

    final side = maxSide ?? StorageLimits.maxPhotoSide(isWeb: kIsWeb);
    final budget = maxBytes ?? StorageLimits.maxPhotoBytes(isWeb: kIsWeb);

    // Already small enough raw JPEG/WebP — keep if under budget.
    if (input.lengthInBytes <= budget) {
      // Still cap dimensions when we can decode.
      try {
        final scaled = await _scaleToSide(input, side);
        if (scaled.lengthInBytes <= budget) {
          return scaled.lengthInBytes < input.lengthInBytes ? scaled : input;
        }
        return _shrinkToBudget(scaled, budget, side);
      } catch (_) {
        return input;
      }
    }

    try {
      final current = await _scaleToSide(input, side);
      if (current.lengthInBytes <= budget) return current;
      return _shrinkToBudget(current, budget, side);
    } catch (_) {
      // Last resort: hard truncate is invalid for images — return empty so
      // callers skip the photo rather than store multi-MB garbage.
      if (input.lengthInBytes > budget * 4) return Uint8List(0);
      return input;
    }
  }

  static Future<Uint8List> _scaleToSide(Uint8List input, int maxSide) async {
    final codec = await ui.instantiateImageCodec(input);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final w = image.width;
    final h = image.height;
    final longSide = math.max(w, h);

    if (longSide <= maxSide) {
      final bd = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bd == null) return input;
      final out = bd.buffer.asUint8List();
      return out.lengthInBytes < input.lengthInBytes * 1.15 ? out : input;
    }

    final scale = maxSide / longSide;
    final tw = math.max(1, (w * scale).round());
    final th = math.max(1, (h * scale).round());

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Rect.fromLTWH(0, 0, tw.toDouble(), th.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    image.dispose();
    final picture = recorder.endRecording();
    final scaled = await picture.toImage(tw, th);
    picture.dispose();
    final bd = await scaled.toByteData(format: ui.ImageByteFormat.png);
    scaled.dispose();
    if (bd == null) return input;
    return bd.buffer.asUint8List();
  }

  /// Progressively reduce long-edge until under [budget] or min side reached.
  static Future<Uint8List> _shrinkToBudget(
    Uint8List input,
    int budget,
    int startSide,
  ) async {
    var side = startSide;
    var current = input;
    while (current.lengthInBytes > budget && side > 320) {
      side = (side * 0.72).round().clamp(320, startSide);
      current = await _scaleToSide(current, side);
    }
    return current;
  }
}
