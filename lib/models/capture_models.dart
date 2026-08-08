import 'package:image_picker/image_picker.dart';

/// Required exterior shot types for a guided homeowner capture.
enum CaptureShotId { front, left, right, rear, roof, problemCloseup }

/// A photo tagged with its checklist slot for analysis + report binding.
class CapturePhoto {
  final XFile file;

  /// Checklist slot when known (null for legacy/unguided picks).
  final CaptureShotId? slotId;

  /// Human label, e.g. "Front of home".
  final String label;

  /// Index in the ordered capture list (0-based).
  final int index;

  const CapturePhoto({
    required this.file,
    required this.label,
    required this.index,
    this.slotId,
  });

  String get shortLabel {
    switch (slotId) {
      case CaptureShotId.front:
        return 'Front';
      case CaptureShotId.left:
        return 'Left';
      case CaptureShotId.right:
        return 'Right';
      case CaptureShotId.rear:
        return 'Rear';
      case CaptureShotId.roof:
        return 'Roof';
      case CaptureShotId.problemCloseup:
        // Quick Scan / custom labels beat the generic "Close-up" chip.
        final t = label.trim();
        if (t.isNotEmpty &&
            t != 'Problem close-up' &&
            t != 'Quick Scan photo' &&
            !t.toLowerCase().startsWith('extra close-up')) {
          return t.length > 18 ? '${t.substring(0, 16)}…' : t;
        }
        return 'Close-up';
      case null:
        return label.length > 14 ? 'Photo ${index + 1}' : label;
    }
  }

  /// Build tagged photos from plain files (no guided slots).
  static List<CapturePhoto> fromXFiles(List<XFile> files) {
    return [
      for (var i = 0; i < files.length; i++)
        CapturePhoto(file: files[i], label: 'Photo ${i + 1}', index: i),
    ];
  }
}

/// Static definition for a guided shot slot.
class CaptureShotDef {
  final CaptureShotId id;
  final String title;
  final String shortLabel;
  final String tip;
  final String howTo;
  final bool required;

  const CaptureShotDef({
    required this.id,
    required this.title,
    required this.shortLabel,
    required this.tip,
    required this.howTo,
    this.required = true,
  });
}

/// Built-in checklist used by [GuidedCaptureScreen] (full multi-shot flow).
const List<CaptureShotDef> kGuidedShotChecklist = [
  CaptureShotDef(
    id: CaptureShotId.front,
    title: 'Front of home',
    shortLabel: 'Front',
    tip: 'Stand back so the full front fits — roof edge to foundation.',
    howTo: 'Face the front door. Include roof, siding, windows, and grade.',
  ),
  CaptureShotDef(
    id: CaptureShotId.left,
    title: 'Left side',
    shortLabel: 'Left',
    tip:
        'Walk to the left elevation. Capture the full wall from ground to eaves.',
    howTo: 'Keep the camera level. Avoid extreme zoom.',
  ),
  CaptureShotDef(
    id: CaptureShotId.right,
    title: 'Right side',
    shortLabel: 'Right',
    tip: 'Same idea on the right side — full height if you can.',
    howTo: 'Include corners where walls meet the roof.',
  ),
  CaptureShotDef(
    id: CaptureShotId.rear,
    title: 'Rear of home',
    shortLabel: 'Rear',
    tip: 'Back elevation, full width when possible.',
    howTo: 'Patio doors, decks, and roof lines are all useful.',
  ),
  CaptureShotDef(
    id: CaptureShotId.roof,
    title: 'Roof & eaves',
    shortLabel: 'Roof',
    tip: 'Aim up at the roof field, ridge, or eave line (gutters help).',
    howTo: 'Safe ground-level shot is fine — no ladders needed.',
  ),
  CaptureShotDef(
    id: CaptureShotId.problemCloseup,
    title: 'Problem close-up',
    shortLabel: 'Close-up',
    tip: 'Any crack, stain, missing shingle, or soft wood you already notice.',
    howTo: 'Fill the frame with the issue, in good light if possible.',
  ),
];

/// Single-photo Quick Scan slot (any exterior area of concern).
const CaptureShotDef kQuickScanShotDef = CaptureShotDef(
  id: CaptureShotId.problemCloseup,
  title: 'Your exterior photo',
  shortLabel: 'Scan',
  tip:
      'One clear photo of the area that concerns you — a full wall, roof plane, '
      'or a focused close-up of damage.',
  howTo:
      'Step back in good light, keep the camera level, and fill the frame with '
      'the subject. Optional: tag the area below so screening prioritizes the '
      'right systems.',
  required: true,
);

/// Optional area tags for Quick Scan (improves analysis slot binding).
class QuickScanAreaOption {
  final String label;
  final String hint;
  final CaptureShotId slotId;

  const QuickScanAreaOption({
    required this.label,
    required this.slotId,
    this.hint = '',
  });
}

/// Area chips for Quick Scan. First option is a general / untagged scan.
const List<QuickScanAreaOption> kQuickScanAreaOptions = [
  QuickScanAreaOption(
    label: 'General area',
    hint: 'Any exterior concern',
    slotId: CaptureShotId.problemCloseup,
  ),
  QuickScanAreaOption(
    label: 'Roof & eaves',
    hint: 'Shingles, ridge, gutters',
    slotId: CaptureShotId.roof,
  ),
  QuickScanAreaOption(
    label: 'Front of home',
    hint: 'Entry elevation',
    slotId: CaptureShotId.front,
  ),
  QuickScanAreaOption(
    label: 'Left side',
    hint: 'Left elevation',
    slotId: CaptureShotId.left,
  ),
  QuickScanAreaOption(
    label: 'Right side',
    hint: 'Right elevation',
    slotId: CaptureShotId.right,
  ),
  QuickScanAreaOption(
    label: 'Rear of home',
    hint: 'Back elevation',
    slotId: CaptureShotId.rear,
  ),
];

/// Result of a simple on-device quality check.
class PhotoQualityResult {
  final bool ok;
  final List<String> warnings;
  final int? width;
  final int? height;
  final double? brightness; // 0–1 average luminance

  const PhotoQualityResult({
    required this.ok,
    this.warnings = const [],
    this.width,
    this.height,
    this.brightness,
  });

  bool get hasWarnings => warnings.isNotEmpty;

  String get summary {
    if (ok && !hasWarnings) return 'Looks good';
    if (ok) return warnings.first;
    return warnings.isEmpty ? 'Could not check photo' : warnings.first;
  }
}

/// One slot on the guided checklist (may or may not have a photo yet).
class CaptureSlot {
  final CaptureShotDef def;
  XFile? photo;
  PhotoQualityResult? quality;

  /// User accepted a photo despite quality warnings.
  bool acceptedWithWarnings;

  CaptureSlot({
    required this.def,
    this.photo,
    this.quality,
    this.acceptedWithWarnings = false,
  });

  bool get isFilled => photo != null;

  bool get isReady {
    if (photo == null) return false;
    final q = quality;
    if (q == null) return true;
    if (q.ok) return true;
    return acceptedWithWarnings;
  }

  CaptureSlot copyWith({
    XFile? photo,
    PhotoQualityResult? quality,
    bool? acceptedWithWarnings,
    bool clearPhoto = false,
  }) {
    return CaptureSlot(
      def: def,
      photo: clearPhoto ? null : (photo ?? this.photo),
      quality: clearPhoto ? null : (quality ?? this.quality),
      acceptedWithWarnings: clearPhoto
          ? false
          : (acceptedWithWarnings ?? this.acceptedWithWarnings),
    );
  }
}

/// Optional extra close-ups beyond the required problem shot.
class ExtraCloseup {
  final XFile photo;
  final PhotoQualityResult? quality;
  final bool acceptedWithWarnings;

  const ExtraCloseup({
    required this.photo,
    this.quality,
    this.acceptedWithWarnings = false,
  });

  bool get isReady {
    final q = quality;
    if (q == null) return true;
    if (q.ok) return true;
    return acceptedWithWarnings;
  }
}
