import 'package:pillar_ai/models/analysis_models.dart';
import 'package:pillar_ai/models/capture_models.dart';
import 'package:pillar_ai/models/property_memory_enums.dart';
import 'package:pillar_ai/models/property_memory_models.dart';
import 'package:pillar_ai/models/saved_report.dart';
import 'package:pillar_ai/models/twin_zone.dart';
import 'package:pillar_ai/services/finding_retake_service.dart';

/// Maps analysis outputs → Property Memory detections / coverage.
class PropertyMemoryMapper {
  PropertyMemoryMapper._();

  static List<PmDetection> mapSavedReportToDetections(SavedReport saved) {
    return mapAnalysisReport(
      saved.report,
      photos: saved.photos,
    );
  }

  static List<PmDetection> mapAnalysisReport(
    AnalysisReport report, {
    List<SavedPhoto> photos = const [],
  }) {
    final out = <PmDetection>[];
    for (final issue in report.issues) {
      if (FindingRetakeService.looksNonExteriorIssue(issue)) continue;
      out.add(_mapIssue(issue, photos: photos));
    }
    return out;
  }

  static PmDetection _mapIssue(
    AnalysisIssue issue, {
    required List<SavedPhoto> photos,
  }) {
    final surface = surfaceTypeFromTwinZone(issue.twinZone);
    final category = categoryFromIssue(issue);
    final severity = severityFromIssue(issue);
    final quality = imageQualityFromIssue(issue);
    final confidence = confidenceFromIssue(issue, quality);
    final loc = localizationFromIssue(issue);
    final region = regionFromIssue(issue);
    final photoIndex = issue.photoIndex;
    String? slot;
    if (photoIndex != null) {
      for (final p in photos) {
        if (p.index == photoIndex) {
          slot = p.slotId?.name;
          break;
        }
      }
    }
    final fingerprint =
        '${issue.title}|${issue.location}|${issue.twinZone.name}'.toLowerCase();

    return PmDetection(
      title: issue.homeownerTitle.trim().isEmpty
          ? issue.title
          : issue.homeownerTitle,
      description: issue.insight,
      surfaceType: surface,
      category: category,
      severityBand: severity,
      confidence: confidence,
      imageQuality: quality,
      localizationType: loc,
      regionNorm: region,
      twinAnchorId:
          issue.twinZone == TwinZone.none ? null : issue.twinZone.name,
      zoneHint: issue.sourcePhotoLabel.isEmpty ? issue.location : issue.sourcePhotoLabel,
      captureSlot: slot,
      photoIndex: photoIndex,
      sourceIssueFingerprint: fingerprint,
      modelExplanation: issue.insight,
    );
  }

  static SurfaceType surfaceTypeFromTwinZone(TwinZone zone) {
    switch (zone) {
      case TwinZone.roof:
        return SurfaceType.roof;
      case TwinZone.siding:
        return SurfaceType.siding;
      case TwinZone.windows:
        return SurfaceType.windowsFrames;
      case TwinZone.foundation:
        return SurfaceType.foundationVisible;
      case TwinZone.gutters:
        return SurfaceType.guttersDownspouts;
      case TwinZone.none:
        return SurfaceType.other;
    }
  }

  static ObservationCategory categoryFromIssue(AnalysisIssue issue) {
    final key = '${issue.title} ${issue.location} ${issue.insight}'.toLowerCase();
    if (key.contains('stain') ||
        key.contains('discolor') ||
        key.contains('mold') ||
        key.contains('algae') ||
        key.contains('rust')) {
      return ObservationCategory.staining;
    }
    if (key.contains('crack') || key.contains('split') || key.contains('fracture')) {
      return ObservationCategory.cracking;
    }
    if (key.contains('missing') ||
        key.contains('gap') ||
        key.contains('hole') ||
        key.contains('shingle loss') ||
        key.contains('loose shingle')) {
      return ObservationCategory.missingMaterial;
    }
    if (key.contains('vegetation') ||
        key.contains('vine') ||
        key.contains('tree contact') ||
        key.contains('bush')) {
      return ObservationCategory.vegetationContact;
    }
    if (key.contains('standing water') ||
        key.contains('pooling') ||
        key.contains('puddle') ||
        key.contains('drainage') ||
        key.contains('grade')) {
      return ObservationCategory.standingWaterIndication;
    }
    if (key.contains('peel') ||
        key.contains('wear') ||
        key.contains('weather') ||
        key.contains('granule') ||
        key.contains('fade') ||
        key.contains('aging')) {
      return ObservationCategory.wear;
    }
    if (key.contains('sag') ||
        key.contains('lean') ||
        key.contains('align') ||
        key.contains('uneven')) {
      return ObservationCategory.alignmentSagAppearance;
    }
    if (key.contains('caulk') ||
        key.contains('seal') ||
        key.contains('glazing') ||
        key.contains('weatherstrip')) {
      return ObservationCategory.sealantFailureAppearance;
    }
    if (key.contains('debris') ||
        key.contains('clog') ||
        key.contains('block') ||
        key.contains('overflow') ||
        key.contains('gutter')) {
      return ObservationCategory.debrisBlockageAppearance;
    }
    return ObservationCategory.other;
  }

  /// High→urgent, Medium→attention, Low→watch.
  static SeverityBand severityFromIssue(AnalysisIssue issue) {
    switch (issue.severity) {
      case 'High':
        return SeverityBand.urgent;
      case 'Medium':
        return SeverityBand.attention;
      case 'Low':
      default:
        return SeverityBand.watch;
    }
  }

  static ImageQualityBand imageQualityFromIssue(AnalysisIssue issue) {
    if (issue.needsCloserPhoto) return ImageQualityBand.poor;
    if (issue.confidence < 40) return ImageQualityBand.poor;
    if (issue.confidence >= 80) return ImageQualityBand.good;
    return ImageQualityBand.usable;
  }

  static ConfidenceBand confidenceFromIssue(
    AnalysisIssue issue,
    ImageQualityBand quality,
  ) {
    ConfidenceBand band;
    if (issue.needsCloserPhoto) {
      band = ConfidenceBand.insufficient;
    } else if (issue.confidence >= 85) {
      band = ConfidenceBand.high;
    } else if (issue.confidence >= 65) {
      band = ConfidenceBand.medium;
    } else if (issue.confidence >= 40) {
      band = ConfidenceBand.low;
    } else {
      band = ConfidenceBand.insufficient;
    }
    return capConfidenceByQuality(band, quality);
  }

  static ConfidenceBand capConfidenceByQuality(
    ConfidenceBand band,
    ImageQualityBand quality,
  ) {
    if (quality == ImageQualityBand.unusable) {
      return ConfidenceBand.insufficient;
    }
    if (quality == ImageQualityBand.poor) {
      // Poor imagery cannot stay high/medium — cap to low (or keep insufficient).
      if (band == ConfidenceBand.insufficient) {
        return ConfidenceBand.insufficient;
      }
      return ConfidenceBand.low;
    }
    return band;
  }

  static LocalizationType localizationFromIssue(AnalysisIssue issue) {
    if (issue.hasLocalizedHighlight) return LocalizationType.region;
    if (issue.twinZone != TwinZone.none) return LocalizationType.surfaceOnly;
    return LocalizationType.unlocalized;
  }

  static RegionNorm? regionFromIssue(AnalysisIssue issue) {
    if (!issue.hasLocalizedHighlight) return null;
    return RegionNorm(
      left: issue.highlightLeft!,
      top: issue.highlightTop!,
      width: issue.highlightWidth!,
      height: issue.highlightHeight!,
    );
  }

  /// Build coverage from saved photos (slots + count).
  static PmCoverageReport buildCoverage(SavedReport saved) {
    final photos = saved.photos;
    final photoCount = saved.photoCount;
    final slots = <CaptureShotId>{
      for (final p in photos)
        if (p.slotId != null) p.slotId!,
    };

    final zones = <PmCoverageZone>[];
    void addSlot(CaptureShotId id, SurfaceType? surface) {
      final present = slots.contains(id);
      zones.add(
        PmCoverageZone(
          zoneId: id.name,
          surfaceType: surface,
          status: present
              ? CaptureZoneStatus.captured
              : CaptureZoneStatus.missing,
          quality: present ? ImageQualityBand.usable : null,
        ),
      );
    }

    addSlot(CaptureShotId.front, SurfaceType.siding);
    addSlot(CaptureShotId.left, SurfaceType.siding);
    addSlot(CaptureShotId.right, SurfaceType.siding);
    addSlot(CaptureShotId.rear, SurfaceType.siding);
    addSlot(CaptureShotId.roof, SurfaceType.roof);
    addSlot(CaptureShotId.problemCloseup, null);

    // Soft surface coverage from twin zones in findings.
    final seenSurfaces = <SurfaceType>{};
    for (final issue in saved.report.issues) {
      seenSurfaces.add(surfaceTypeFromTwinZone(issue.twinZone));
    }
    for (final s in SurfaceType.values) {
      if (s == SurfaceType.other) continue;
      if (zones.any((z) => z.surfaceType == s)) continue;
      zones.add(
        PmCoverageZone(
          zoneId: 'surface_${s.toStorage()}',
          surfaceType: s,
          status: seenSurfaces.contains(s)
              ? CaptureZoneStatus.captured
              : CaptureZoneStatus.missing,
          quality: seenSurfaces.contains(s) ? ImageQualityBand.usable : null,
        ),
      );
    }

    final meets = meetsBaselineMinimum(photoCount: photoCount, slots: slots);
    final notes = <String>[];
    if (photoCount <= 1) {
      notes.add('Quick Scan / single photo — baseline incomplete');
    } else if (!meets) {
      notes.add('Insufficient elevations for completed baseline');
    }

    return PmCoverageReport(
      meetsBaselineMinimum: meets,
      photoCount: photoCount,
      zones: zones,
      notes: notes,
    );
  }

  /// Completed baseline requires Guided Capture elevation coverage (slots),
  /// never bare photo count.
  ///
  /// Qualifies when:
  /// - front+left+right+rear are all present, OR
  /// - at least 3 distinct elevations plus roof.
  static bool meetsBaselineMinimum({
    required int photoCount,
    required Set<CaptureShotId> slots,
  }) {
    const elevations = {
      CaptureShotId.front,
      CaptureShotId.left,
      CaptureShotId.right,
      CaptureShotId.rear,
    };
    if (elevations.every(slots.contains)) return true;
    final elevPresent = elevations.intersection(slots).length;
    if (elevPresent >= 3 && slots.contains(CaptureShotId.roof)) return true;
    return false;
  }

  /// True when capture is Quick Scan / single-slot / close-up-only / untagged.
  static bool looksLikeQuickOrSingleShot(SavedReport saved) {
    if (saved.photoCount <= 1) return true;
    final slots = <CaptureShotId>{
      for (final p in saved.photos)
        if (p.slotId != null) p.slotId!,
    };
    if (slots.isEmpty) return true; // untagged set
    if (slots.length == 1) return true;
    // Only problemCloseup / no elevation or roof slots.
    final guided = slots.intersection({
      CaptureShotId.front,
      CaptureShotId.left,
      CaptureShotId.right,
      CaptureShotId.rear,
      CaptureShotId.roof,
    });
    return guided.isEmpty;
  }
}
