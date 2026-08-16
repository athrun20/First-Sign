import 'package:flutter/material.dart';

import '../models/capture_models.dart';
import '../theme/app_lux.dart';

/// Tone for assistant messages (maps to color + icon).
enum AssistantTone { tip, success, warning, caution, progress }

/// One piece of guidance from the Smart Capture Assistant.
class AssistantAdvice {
  final AssistantTone tone;
  final String headline;
  final String body;
  final List<String> quickTips;
  final IconData icon;

  const AssistantAdvice({
    required this.tone,
    required this.headline,
    required this.body,
    this.quickTips = const [],
    this.icon = Icons.auto_awesome_rounded,
  });

  Color get accentColor {
    switch (tone) {
      case AssistantTone.success:
        return AppLux.teal;
      case AssistantTone.warning:
        return AppLux.warning;
      case AssistantTone.caution:
        return AppLux.danger;
      case AssistantTone.progress:
        return const Color(0xFF2563EB);
      case AssistantTone.tip:
        return AppLux.teal;
    }
  }
}

/// Lightweight, on-device capture coach — tips, quality feedback, suggestions.
///
/// No network / ML. Uses shot type + [PhotoQualityResult] + checklist progress.
class CaptureAssistantService {
  CaptureAssistantService._();

  /// Contextual coaching for the focused checklist shot.
  static AssistantAdvice adviceForShot(
    CaptureShotDef def, {
    required bool filled,
    PhotoQualityResult? quality,
    bool acceptedWithWarnings = false,
  }) {
    if (filled && quality != null) {
      return feedbackForQuality(
        quality,
        shotTitle: def.title,
        acceptedWithWarnings: acceptedWithWarnings,
      );
    }

    final tips = quickTipsFor(def.id);
    final pack = _shotPack(def.id);

    return AssistantAdvice(
      tone: AssistantTone.tip,
      headline: pack.headline,
      body: pack.body.isNotEmpty ? pack.body : def.tip,
      quickTips: tips,
      icon: pack.icon,
    );
  }

  /// Immediate feedback after a quality check (or when viewing a filled slot).
  static AssistantAdvice feedbackForQuality(
    PhotoQualityResult quality, {
    String shotTitle = 'Photo',
    bool acceptedWithWarnings = false,
  }) {
    if (quality.ok && !quality.hasWarnings) {
      return AssistantAdvice(
        tone: AssistantTone.success,
        headline: 'Looks good',
        body: _successBody(quality, shotTitle),
        quickTips: const [
          'Keep the same distance and light for the next angle.',
        ],
        icon: Icons.check_circle_rounded,
      );
    }

    if (!quality.ok) {
      return AssistantAdvice(
        tone: AssistantTone.caution,
        headline: 'Needs a better shot',
        body: quality.warnings.isNotEmpty
            ? quality.warnings.first
            : 'This photo may hurt analysis accuracy. Retake if you can.',
        quickTips: [
          ...quality.warnings.skip(1).take(2),
          ..._fixTipsForWarnings(quality).take(2),
        ].take(3).toList(),
        icon: Icons.error_outline_rounded,
      );
    }

    // Soft warnings only.
    return AssistantAdvice(
      tone: AssistantTone.warning,
      headline: acceptedWithWarnings
          ? 'Kept with a quality note'
          : 'Usable — small tip',
      body: quality.warnings.isNotEmpty
          ? quality.warnings.first
          : 'Photo is fine; a cleaner retake would help slightly.',
      quickTips: [
        ...quality.warnings.skip(1).take(2),
        ..._fixTipsForWarnings(quality).take(1),
      ].take(3).toList(),
      icon: Icons.info_outline_rounded,
    );
  }

  /// One progress-aware suggestion for the session strip.
  static String sessionSuggestion({
    required List<CaptureSlot> slots,
    required int filledRequired,
    required int requiredTotal,
    required int extraCount,
    CaptureShotId? focusId,
  }) {
    if (filledRequired == 0) {
      // Empty first shot: coach body covers framing — keep session quiet.
      return '';
    }

    if (filledRequired >= requiredTotal) {
      if (extraCount == 0) {
        return 'Checklist complete. Optional: add a close-up of any trouble spot.';
      }
      return 'You\'re set — review photos when ready, or add another close-up.';
    }

    final warnCount = slots
        .where(
          (s) =>
              s.isReady &&
              s.quality != null &&
              (!s.quality!.ok || s.quality!.hasWarnings),
        )
        .length;
    if (warnCount >= 2) {
      return 'A few shots have quality notes — retake the ones marked if lighting is better now.';
    }

    CaptureSlot? nextEmpty;
    for (final s in slots) {
      if (!s.isReady) {
        nextEmpty = s;
        break;
      }
    }
    final nextId = focusId ?? nextEmpty?.def.id;

    if (nextId == CaptureShotId.roof) {
      return 'Next up: roof & eaves from the ground — no ladder needed.';
    }
    if (nextId == CaptureShotId.problemCloseup) {
      return 'Almost done — capture one clear close-up of any issue you see.';
    }
    if (nextId == CaptureShotId.rear) {
      return 'Walk to the back when you can — rear elevation catches a lot of wear.';
    }

    final remaining = requiredTotal - filledRequired;
    if (filledRequired == 1) {
      return 'Nice start. Side shots help the AI compare elevations.';
    }
    if (remaining == 1) {
      return 'One shot left — you\'re almost ready for AI analysis.';
    }
    return '$filledRequired of $requiredTotal ready · $remaining left. Keep the camera level.';
  }

  /// Short do-this tips for a shot type.
  static List<String> quickTipsFor(CaptureShotId id) {
    switch (id) {
      case CaptureShotId.front:
        return const [
          'Step back until roof edge and foundation both fit.',
          'Shoot in daylight; avoid harsh midday glare if you can.',
          'Hold the phone level — no extreme tilt.',
        ];
      case CaptureShotId.left:
      case CaptureShotId.right:
        return const [
          'Capture the full wall height: grade to eaves.',
          'Include the corner where wall meets roof.',
          'Stay far enough that the whole elevation is visible.',
        ];
      case CaptureShotId.rear:
        return const [
          'Include decks, patio doors, and roof lines.',
          'Full width when possible — step back, don\'t zoom hard.',
          'Watch for shadows; shade is fine if detail stays clear.',
        ];
      case CaptureShotId.roof:
        return const [
          'From the ground, aim at ridge, field, or gutter line.',
          'Safety first — never climb for this app.',
          'Overcast light often shows shingle texture better.',
        ];
      case CaptureShotId.problemCloseup:
        return const [
          'Fill the frame with the crack, stain, or soft wood.',
          'Get close enough to see texture, stay sharp.',
          'Good light on the defect beats a distant wide shot.',
        ];
    }
  }

  /// Compact quality badge text for tiles / chips.
  static String qualityBadge(
    PhotoQualityResult? quality, {
    bool accepted = false,
  }) {
    if (quality == null) return 'Not checked';
    if (quality.ok && !quality.hasWarnings) return 'Good quality';
    if (!quality.ok) return accepted ? 'Weak · kept' : 'Needs retake';
    return accepted ? 'OK · tip' : 'Usable · tip';
  }

  /// 0–100 simple score for UI meters (heuristic, not ML).
  static int qualityScore(PhotoQualityResult quality) {
    if (!quality.ok && quality.warnings.isEmpty) return 25;
    var score = quality.ok ? 88 : 48;

    final b = quality.brightness;
    if (b != null) {
      if (b >= 0.28 && b <= 0.78) {
        score += 8;
      } else if (b < 0.18 || b > 0.88) {
        score -= 18;
      } else {
        score -= 8;
      }
    }

    final w = quality.width;
    final h = quality.height;
    if (w != null && h != null) {
      final short = w < h ? w : h;
      if (short >= 1200) {
        score += 6;
      } else if (short >= 900) {
        score += 3;
      } else if (short < 640) {
        score -= 20;
      } else {
        score -= 6;
      }
    }

    score -= quality.warnings.length * 6;
    return score.clamp(12, 98);
  }

  static String _successBody(PhotoQualityResult q, String shotTitle) {
    final parts = <String>['$shotTitle looks clear enough for analysis.'];
    final b = q.brightness;
    if (b != null && b >= 0.30 && b <= 0.75) {
      parts.add('Lighting looks balanced.');
    }
    if (q.width != null && q.height != null) {
      final short = q.width! < q.height! ? q.width! : q.height!;
      if (short >= 900) parts.add('Resolution is solid.');
    }
    return parts.join(' ');
  }

  static List<String> _fixTipsForWarnings(PhotoQualityResult quality) {
    final tips = <String>[];
    final text = quality.warnings.join(' ').toLowerCase();
    if (text.contains('dark')) {
      tips.add(
        'Face the house with the sun behind you, or wait for brighter light.',
      );
    }
    if (text.contains('bright') ||
        text.contains('glare') ||
        text.contains('overexpose')) {
      tips.add('Step to the side so the sun isn\'t blasting the lens.');
    }
    if (text.contains('low-res') ||
        text.contains('resolution') ||
        text.contains('small')) {
      tips.add('Use the camera (not a tiny screenshot) and avoid heavy zoom.');
    }
    if (text.contains('wide') || text.contains('panorama')) {
      tips.add('Take a normal photo of one elevation at a time.');
    }
    if (tips.isEmpty) {
      tips.add('Retake in daylight, full elevation, phone held steady.');
    }
    return tips;
  }

  static _ShotPack _shotPack(CaptureShotId id) {
    switch (id) {
      case CaptureShotId.front:
        return const _ShotPack(
          headline: 'Frame the whole front',
          body: 'Roof edge to foundation in one calm, level shot.',
          icon: Icons.home_outlined,
        );
      case CaptureShotId.left:
        return const _ShotPack(
          headline: 'Left elevation, full height',
          body:
              'Walk to the left side. Corners and eaves matter as much as the wall face.',
          icon: Icons.border_left_rounded,
        );
      case CaptureShotId.right:
        return const _ShotPack(
          headline: 'Right elevation, full height',
          body:
              'Mirror the left: full wall, roof line, and foundation if you can.',
          icon: Icons.border_right_rounded,
        );
      case CaptureShotId.rear:
        return const _ShotPack(
          headline: 'Capture the back of the home',
          body:
              'Rear walls and roof lines often hide wear. Include decks and patio doors.',
          icon: Icons.other_houses_outlined,
        );
      case CaptureShotId.roof:
        return const _ShotPack(
          headline: 'Roof & eaves from the ground',
          body:
              'Aim up at the field, ridge, or gutter line. Stay safe — ground level only.',
          icon: Icons.roofing_rounded,
        );
      case CaptureShotId.problemCloseup:
        return const _ShotPack(
          headline: 'Zoom in on a problem',
          body:
              'Fill the frame with the issue. Texture and color detail help confidence scores.',
          icon: Icons.zoom_in_rounded,
        );
    }
  }
}

class _ShotPack {
  final String headline;
  final String body;
  final IconData icon;

  const _ShotPack({
    required this.headline,
    required this.body,
    required this.icon,
  });
}
