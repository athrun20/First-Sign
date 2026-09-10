/// Property Memory v1 enums.
///
/// Dart identifiers use camelCase. Persist with [toStorage] / [fromStorage]
/// helpers so JSON matches the approved schema strings (e.g. `fresh` → `"new"`,
/// `checkIn` → `"check_in"`).
library;

// ---------------------------------------------------------------------------
// Storage helpers (shared pattern)
// ---------------------------------------------------------------------------

String _snake(String camel) {
  final buf = StringBuffer();
  for (var i = 0; i < camel.length; i++) {
    final c = camel[i];
    if (c.toUpperCase() == c && c.toLowerCase() != c && i > 0) {
      buf.write('_');
      buf.write(c.toLowerCase());
    } else {
      buf.write(c.toLowerCase());
    }
  }
  return buf.toString();
}

T? _byStorage<T extends Enum>(List<T> values, String? raw, String Function(T) to) {
  if (raw == null || raw.isEmpty) return null;
  for (final v in values) {
    if (to(v) == raw || v.name == raw) return v;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum ScanMode {
  baseline,
  checkIn;

  String toStorage() => this == ScanMode.checkIn ? 'check_in' : name;

  static ScanMode fromStorage(String? raw, {ScanMode fallback = ScanMode.baseline}) =>
      _byStorage(ScanMode.values, raw, (e) => e.toStorage()) ?? fallback;
}

enum ScanProcessingStatus {
  pending,
  complete,
  failed,
  partial;

  String toStorage() => name;

  static ScanProcessingStatus fromStorage(
    String? raw, {
    ScanProcessingStatus fallback = ScanProcessingStatus.pending,
  }) =>
      _byStorage(ScanProcessingStatus.values, raw, (e) => e.toStorage()) ??
      fallback;
}

enum PropertyLifecycleState {
  draft,
  baselineIncomplete,
  active,
  archived;

  String toStorage() => switch (this) {
        PropertyLifecycleState.baselineIncomplete => 'baseline_incomplete',
        _ => name,
      };

  static PropertyLifecycleState fromStorage(
    String? raw, {
    PropertyLifecycleState fallback = PropertyLifecycleState.draft,
  }) =>
      _byStorage(PropertyLifecycleState.values, raw, (e) => e.toStorage()) ??
      fallback;
}

enum OverallConditionSignal {
  incompleteCoverage,
  stable,
  needsAttention,
  urgentAttention;

  String toStorage() => _snake(name);

  static OverallConditionSignal fromStorage(
    String? raw, {
    OverallConditionSignal fallback = OverallConditionSignal.incompleteCoverage,
  }) =>
      _byStorage(OverallConditionSignal.values, raw, (e) => e.toStorage()) ??
      fallback;
}

enum SurfaceType {
  roof,
  siding,
  trimFascia,
  guttersDownspouts,
  windowsFrames,
  doorsFrames,
  foundationVisible,
  chimneyVents,
  decksPorchesRailings,
  other;

  String toStorage() => _snake(name);

  static SurfaceType fromStorage(
    String? raw, {
    SurfaceType fallback = SurfaceType.other,
  }) =>
      _byStorage(SurfaceType.values, raw, (e) => e.toStorage()) ?? fallback;
}

enum SurfacePresence {
  present,
  notApplicable,
  notVisible,
  inaccessible;

  String toStorage() => switch (this) {
        SurfacePresence.notApplicable => 'not_applicable',
        SurfacePresence.notVisible => 'not_visible',
        _ => name,
      };

  static SurfacePresence fromStorage(
    String? raw, {
    SurfacePresence fallback = SurfacePresence.present,
  }) =>
      _byStorage(SurfacePresence.values, raw, (e) => e.toStorage()) ?? fallback;
}

enum ObservationCategory {
  staining,
  cracking,
  missingMaterial,
  vegetationContact,
  standingWaterIndication,
  wear,
  alignmentSagAppearance,
  sealantFailureAppearance,
  debrisBlockageAppearance,
  other;

  String toStorage() => _snake(name);

  static ObservationCategory fromStorage(
    String? raw, {
    ObservationCategory fallback = ObservationCategory.other,
  }) =>
      _byStorage(ObservationCategory.values, raw, (e) => e.toStorage()) ??
      fallback;
}

enum SeverityBand {
  info,
  watch,
  attention,
  urgent;

  String toStorage() => name;

  static SeverityBand fromStorage(
    String? raw, {
    SeverityBand fallback = SeverityBand.watch,
  }) =>
      _byStorage(SeverityBand.values, raw, (e) => e.toStorage()) ?? fallback;
}

/// Schema stores `"new"`; Dart uses [fresh] because `new` is reserved.
enum ObservationStatus {
  fresh,
  monitoring,
  unverified,
  unableToDetermine,
  resolved,
  changed,
  worsened,
  improved;

  String toStorage() => switch (this) {
        ObservationStatus.fresh => 'new',
        ObservationStatus.unableToDetermine => 'unable_to_determine',
        _ => name,
      };

  static ObservationStatus fromStorage(
    String? raw, {
    ObservationStatus fallback = ObservationStatus.fresh,
  }) {
    if (raw == 'new' || raw == 'fresh') return ObservationStatus.fresh;
    return _byStorage(ObservationStatus.values, raw, (e) => e.toStorage()) ??
        fallback;
  }

  bool get isOpen =>
      this != ObservationStatus.resolved &&
      this != ObservationStatus.improved; // improved kept for forward-compat
}

enum ConfidenceBand {
  high,
  medium,
  low,
  insufficient;

  String toStorage() => name;

  static ConfidenceBand fromStorage(
    String? raw, {
    ConfidenceBand fallback = ConfidenceBand.low,
  }) =>
      _byStorage(ConfidenceBand.values, raw, (e) => e.toStorage()) ?? fallback;
}

enum ImageQualityBand {
  good,
  usable,
  poor,
  unusable;

  String toStorage() => name;

  static ImageQualityBand fromStorage(
    String? raw, {
    ImageQualityBand fallback = ImageQualityBand.usable,
  }) =>
      _byStorage(ImageQualityBand.values, raw, (e) => e.toStorage()) ??
      fallback;

  bool get isAdequate =>
      this == ImageQualityBand.good || this == ImageQualityBand.usable;
}

enum LocalizationType {
  fullImage,
  region,
  surfaceOnly,
  unlocalized;

  String toStorage() => _snake(name);

  static LocalizationType fromStorage(
    String? raw, {
    LocalizationType fallback = LocalizationType.unlocalized,
  }) =>
      _byStorage(LocalizationType.values, raw, (e) => e.toStorage()) ??
      fallback;
}

enum MatchStrength {
  strong,
  medium,
  weak,
  none;

  String toStorage() => name;

  static MatchStrength fromStorage(
    String? raw, {
    MatchStrength fallback = MatchStrength.none,
  }) =>
      _byStorage(MatchStrength.values, raw, (e) => e.toStorage()) ?? fallback;
}

enum ObservationEventType {
  created,
  verifiedUnchanged,
  statusChanged,
  severityChanged,
  evidenceAdded,
  userCorrected,
  userDismissed,
  userConfirmedPresent,
  userMarkedRepaired,
  reopened,
  unableToCompare;

  String toStorage() => _snake(name);

  static ObservationEventType fromStorage(
    String? raw, {
    ObservationEventType fallback = ObservationEventType.created,
  }) =>
      _byStorage(ObservationEventType.values, raw, (e) => e.toStorage()) ??
      fallback;
}

enum ActorType {
  ai,
  user,
  system;

  String toStorage() => name;

  static ActorType fromStorage(
    String? raw, {
    ActorType fallback = ActorType.ai,
  }) =>
      _byStorage(ActorType.values, raw, (e) => e.toStorage()) ?? fallback;
}

enum SeasonalContext {
  none,
  wet,
  snowIce,
  leafCover,
  vegetationHeavy,
  unknown;

  String toStorage() => switch (this) {
        SeasonalContext.snowIce => 'snow_ice',
        SeasonalContext.leafCover => 'leaf_cover',
        SeasonalContext.vegetationHeavy => 'vegetation_heavy',
        _ => name,
      };

  static SeasonalContext fromStorage(
    String? raw, {
    SeasonalContext fallback = SeasonalContext.unknown,
  }) =>
      _byStorage(SeasonalContext.values, raw, (e) => e.toStorage()) ?? fallback;
}

/// Coverage capture-zone status (used inside [PmCoverageReport]).
enum CaptureZoneStatus {
  captured,
  missing,
  lowQuality,
  skippedNa;

  String toStorage() => switch (this) {
        CaptureZoneStatus.lowQuality => 'low_quality',
        CaptureZoneStatus.skippedNa => 'skipped_na',
        _ => name,
      };

  static CaptureZoneStatus fromStorage(
    String? raw, {
    CaptureZoneStatus fallback = CaptureZoneStatus.missing,
  }) =>
      _byStorage(CaptureZoneStatus.values, raw, (e) => e.toStorage()) ??
      fallback;
}
