import 'package:flutter_test/flutter_test.dart';
import 'package:pillar_ai/models/property_memory_enums.dart';
import 'package:pillar_ai/models/property_memory_models.dart';
import 'package:pillar_ai/services/property_memory_reconciler.dart';

PmPropertyMemoryBundle _draftBundle() {
  final now = DateTime.utc(2026, 1, 1);
  return PmPropertyMemoryBundle(
    property: PmProperty(
      id: 'property_local_1',
      displayName: 'My home',
      lifecycleState: PropertyLifecycleState.draft,
      createdAt: now,
      updatedAt: now,
    ),
  );
}

PmCoverageReport _fullCoverage({bool meets = true, int photoCount = 4}) {
  return PmCoverageReport(
    meetsBaselineMinimum: meets,
    photoCount: photoCount,
    zones: [
      for (final z in ['front', 'left', 'right', 'rear'])
        PmCoverageZone(
          zoneId: z,
          surfaceType: SurfaceType.siding,
          status: meets ? CaptureZoneStatus.captured : CaptureZoneStatus.missing,
          quality: ImageQualityBand.usable,
        ),
      PmCoverageZone(
        zoneId: 'roof',
        surfaceType: SurfaceType.roof,
        status: meets ? CaptureZoneStatus.captured : CaptureZoneStatus.missing,
        quality: ImageQualityBand.usable,
      ),
      PmCoverageZone(
        zoneId: 'surface_gutters_downspouts',
        surfaceType: SurfaceType.guttersDownspouts,
        status: CaptureZoneStatus.captured,
        quality: ImageQualityBand.usable,
      ),
      PmCoverageZone(
        zoneId: 'surface_foundation_visible',
        surfaceType: SurfaceType.foundationVisible,
        status: CaptureZoneStatus.captured,
        quality: ImageQualityBand.usable,
      ),
    ],
  );
}

PmDetection _det({
  required String title,
  required SurfaceType surface,
  required ObservationCategory category,
  SeverityBand severity = SeverityBand.attention,
  ConfidenceBand confidence = ConfidenceBand.medium,
  ImageQualityBand quality = ImageQualityBand.usable,
  String? slot,
  RegionNorm? region,
}) {
  return PmDetection(
    title: title,
    surfaceType: surface,
    category: category,
    severityBand: severity,
    confidence: confidence,
    imageQuality: quality,
    localizationType:
        region != null ? LocalizationType.region : LocalizationType.surfaceOnly,
    regionNorm: region,
    captureSlot: slot,
    twinAnchorId: surface.toStorage(),
    photoIndex: 0,
  );
}

void main() {
  group('PropertyMemoryReconciler', () {
    test('AT-1 baseline success creates fresh observations + active lifecycle',
        () {
      final t0 = DateTime.utc(2026, 2, 1);
      final result = PropertyMemoryReconciler.reconcile(
        state: _draftBundle(),
        mode: ScanMode.baseline,
        detections: [
          _det(
            title: 'Siding stain',
            surface: SurfaceType.siding,
            category: ObservationCategory.staining,
            slot: 'front',
          ),
          _det(
            title: 'Gutter debris',
            surface: SurfaceType.guttersDownspouts,
            category: ObservationCategory.debrisBlockageAppearance,
            slot: 'front',
          ),
        ],
        coverage: _fullCoverage(),
        scanId: 'scan_baseline',
        capturedAt: t0,
        sourceSavedReportId: 'report_b',
      );

      expect(result.mode, ScanMode.baseline);
      expect(result.bundle.property.lifecycleState,
          PropertyLifecycleState.active);
      expect(result.bundle.property.baselineScanId, 'scan_baseline');
      expect(result.bundle.scans.single.mode, ScanMode.baseline);
      expect(result.bundle.scans.single.coverageReport.meetsBaselineMinimum, isTrue);
      expect(result.bundle.observations.length, 2);
      expect(
        result.bundle.observations.every(
          (o) => o.status == ObservationStatus.fresh,
        ),
        isTrue,
      );
      expect(result.bundle.evidence.length, 2);
      expect(
        result.newEvents
            .where((e) => e.eventType == ObservationEventType.created)
            .length,
        2,
      );
    });

    test('AT-2 incomplete baseline → baselineIncomplete, no baselineScanId',
        () {
      final result = PropertyMemoryReconciler.reconcile(
        state: _draftBundle(),
        mode: ScanMode.baseline,
        detections: [
          _det(
            title: 'Quick stain',
            surface: SurfaceType.siding,
            category: ObservationCategory.staining,
          ),
        ],
        coverage: _fullCoverage(meets: false, photoCount: 1),
        scanId: 'scan_qs',
        capturedAt: DateTime.utc(2026, 2, 2),
      );
      expect(result.bundle.property.lifecycleState,
          PropertyLifecycleState.baselineIncomplete);
      expect(result.bundle.property.baselineScanId, isNull);
      // Incomplete baseline must not create observations (no provisional stack).
      expect(result.bundle.observations, isEmpty);
    });

    test('AT-3/AT-4 check-in rematch → monitoring + evidence retained', () {
      final t0 = DateTime.utc(2026, 3, 1);
      final baseline = PropertyMemoryReconciler.reconcile(
        state: _draftBundle(),
        mode: ScanMode.baseline,
        detections: [
          _det(
            title: 'Siding stain',
            surface: SurfaceType.siding,
            category: ObservationCategory.staining,
            slot: 'front',
          ),
        ],
        coverage: _fullCoverage(),
        scanId: 'scan_b',
        capturedAt: t0,
      );
      final obsId = baseline.bundle.observations.single.id;

      final checkIn = PropertyMemoryReconciler.reconcile(
        state: baseline.bundle,
        mode: ScanMode.checkIn,
        detections: [
          _det(
            title: 'Siding stain',
            surface: SurfaceType.siding,
            category: ObservationCategory.staining,
            slot: 'front',
          ),
        ],
        coverage: _fullCoverage(),
        scanId: 'scan_c1',
        capturedAt: t0.add(const Duration(days: 30)),
      );

      expect(checkIn.bundle.scans.last.mode, ScanMode.checkIn);
      expect(checkIn.bundle.observations.length, 1);
      expect(checkIn.bundle.observations.single.id, obsId);
      expect(checkIn.bundle.observations.single.status,
          ObservationStatus.monitoring);
      expect(checkIn.bundle.evidence.length, 2);
      expect(
        checkIn.newEvents.any(
          (e) => e.eventType == ObservationEventType.verifiedUnchanged,
        ),
        isTrue,
      );
    });

    test('AT-5 absent on good recapture → unverified (never resolved)', () {
      final t0 = DateTime.utc(2026, 4, 1);
      final baseline = PropertyMemoryReconciler.reconcile(
        state: _draftBundle(),
        mode: ScanMode.baseline,
        detections: [
          _det(
            title: 'Siding stain',
            surface: SurfaceType.siding,
            category: ObservationCategory.staining,
            slot: 'front',
          ),
        ],
        coverage: _fullCoverage(),
        scanId: 'scan_b',
        capturedAt: t0,
      );

      final checkIn = PropertyMemoryReconciler.reconcile(
        state: baseline.bundle,
        mode: ScanMode.checkIn,
        detections: const [], // absent
        coverage: _fullCoverage(),
        scanId: 'scan_c',
        capturedAt: t0.add(const Duration(days: 10)),
      );

      expect(checkIn.bundle.observations.single.status,
          ObservationStatus.unverified);
      expect(checkIn.bundle.observations.single.status,
          isNot(ObservationStatus.resolved));
      expect(checkIn.bundle.evidence, isNotEmpty); // history retained
    });

    test('AT-7 zone missing → unableToDetermine', () {
      final t0 = DateTime.utc(2026, 5, 1);
      final baseline = PropertyMemoryReconciler.reconcile(
        state: _draftBundle(),
        mode: ScanMode.baseline,
        detections: [
          _det(
            title: 'Roof wear',
            surface: SurfaceType.roof,
            category: ObservationCategory.wear,
            slot: 'roof',
          ),
        ],
        coverage: _fullCoverage(),
        scanId: 'scan_b',
        capturedAt: t0,
      );

      final missingRoof = PmCoverageReport(
        meetsBaselineMinimum: true,
        photoCount: 4,
        zones: [
          for (final z in ['front', 'left', 'right', 'rear'])
            PmCoverageZone(
              zoneId: z,
              surfaceType: SurfaceType.siding,
              status: CaptureZoneStatus.captured,
              quality: ImageQualityBand.usable,
            ),
          const PmCoverageZone(
            zoneId: 'roof',
            surfaceType: SurfaceType.roof,
            status: CaptureZoneStatus.missing,
          ),
        ],
      );

      final checkIn = PropertyMemoryReconciler.reconcile(
        state: baseline.bundle,
        mode: ScanMode.checkIn,
        detections: const [],
        coverage: missingRoof,
        scanId: 'scan_c',
        capturedAt: t0.add(const Duration(days: 5)),
      );

      expect(checkIn.bundle.observations.single.status,
          ObservationStatus.unableToDetermine);
      expect(
        checkIn.newEvents.any(
          (e) => e.eventType == ObservationEventType.unableToCompare,
        ),
        isTrue,
      );
    });

    test('AT-8 new detection creates fresh observation', () {
      final t0 = DateTime.utc(2026, 6, 1);
      final baseline = PropertyMemoryReconciler.reconcile(
        state: _draftBundle(),
        mode: ScanMode.baseline,
        detections: [
          _det(
            title: 'Siding stain',
            surface: SurfaceType.siding,
            category: ObservationCategory.staining,
            slot: 'front',
          ),
        ],
        coverage: _fullCoverage(),
        scanId: 'scan_b',
        capturedAt: t0,
      );

      final checkIn = PropertyMemoryReconciler.reconcile(
        state: baseline.bundle,
        mode: ScanMode.checkIn,
        detections: [
          _det(
            title: 'Siding stain',
            surface: SurfaceType.siding,
            category: ObservationCategory.staining,
            slot: 'front',
          ),
          _det(
            title: 'Foundation crack',
            surface: SurfaceType.foundationVisible,
            category: ObservationCategory.cracking,
            slot: 'front',
          ),
        ],
        coverage: _fullCoverage(),
        scanId: 'scan_c',
        capturedAt: t0.add(const Duration(days: 7)),
      );

      expect(checkIn.bundle.observations.length, 2);
      final neu = checkIn.bundle.observations
          .where((o) => o.category == ObservationCategory.cracking)
          .single;
      expect(neu.status, ObservationStatus.fresh);
    });

    test('AT-18 resolved reopen same observation id → fresh', () {
      final t0 = DateTime.utc(2026, 7, 1);
      final baseline = PropertyMemoryReconciler.reconcile(
        state: _draftBundle(),
        mode: ScanMode.baseline,
        detections: [
          _det(
            title: 'Siding stain',
            surface: SurfaceType.siding,
            category: ObservationCategory.staining,
            slot: 'front',
          ),
        ],
        coverage: _fullCoverage(),
        scanId: 'scan_b',
        capturedAt: t0,
      );
      final obsId = baseline.bundle.observations.single.id;
      final resolved = baseline.bundle.copyWith(
        observations: [
          baseline.bundle.observations.single
              .copyWith(status: ObservationStatus.resolved),
        ],
      );

      final checkIn = PropertyMemoryReconciler.reconcile(
        state: resolved,
        mode: ScanMode.checkIn,
        detections: [
          _det(
            title: 'Siding stain again',
            surface: SurfaceType.siding,
            category: ObservationCategory.staining,
            slot: 'front',
          ),
        ],
        coverage: _fullCoverage(),
        scanId: 'scan_c',
        capturedAt: t0.add(const Duration(days: 60)),
      );

      expect(checkIn.bundle.observations.length, 1);
      expect(checkIn.bundle.observations.single.id, obsId);
      expect(checkIn.bundle.observations.single.status,
          ObservationStatus.fresh);
      expect(
        checkIn.newEvents.any(
          (e) => e.eventType == ObservationEventType.reopened,
        ),
        isTrue,
      );
    });

    test('severity rematch only when confidence ≥ medium', () {
      final t0 = DateTime.utc(2026, 8, 1);
      final baseline = PropertyMemoryReconciler.reconcile(
        state: _draftBundle(),
        mode: ScanMode.baseline,
        detections: [
          _det(
            title: 'Siding stain',
            surface: SurfaceType.siding,
            category: ObservationCategory.staining,
            slot: 'front',
            severity: SeverityBand.watch,
            confidence: ConfidenceBand.medium,
          ),
        ],
        coverage: _fullCoverage(),
        scanId: 'scan_b',
        capturedAt: t0,
      );

      final lowConf = PropertyMemoryReconciler.reconcile(
        state: baseline.bundle,
        mode: ScanMode.checkIn,
        detections: [
          _det(
            title: 'Siding stain',
            surface: SurfaceType.siding,
            category: ObservationCategory.staining,
            slot: 'front',
            severity: SeverityBand.urgent,
            confidence: ConfidenceBand.low,
          ),
        ],
        coverage: _fullCoverage(),
        scanId: 'scan_c_low',
        capturedAt: t0.add(const Duration(days: 7)),
      );
      expect(
        lowConf.bundle.observations.single.severityBand,
        SeverityBand.watch,
      );

      final hiConf = PropertyMemoryReconciler.reconcile(
        state: baseline.bundle,
        mode: ScanMode.checkIn,
        detections: [
          _det(
            title: 'Siding stain',
            surface: SurfaceType.siding,
            category: ObservationCategory.staining,
            slot: 'front',
            severity: SeverityBand.urgent,
            confidence: ConfidenceBand.high,
          ),
        ],
        coverage: _fullCoverage(),
        scanId: 'scan_c_hi',
        capturedAt: t0.add(const Duration(days: 8)),
      );
      expect(
        hiConf.bundle.observations.single.severityBand,
        SeverityBand.urgent,
      );
    });

    test('AT-22 mixed check-in outcomes in one batch', () {
      final t0 = DateTime.utc(2026, 8, 1);
      final baseline = PropertyMemoryReconciler.reconcile(
        state: _draftBundle(),
        mode: ScanMode.baseline,
        detections: [
          _det(
            title: 'A stain',
            surface: SurfaceType.siding,
            category: ObservationCategory.staining,
            slot: 'front',
          ),
          _det(
            title: 'B crack',
            surface: SurfaceType.siding,
            category: ObservationCategory.cracking,
            slot: 'left',
          ),
          _det(
            title: 'C roof wear',
            surface: SurfaceType.roof,
            category: ObservationCategory.wear,
            slot: 'roof',
          ),
          _det(
            title: 'D gutter',
            surface: SurfaceType.guttersDownspouts,
            category: ObservationCategory.debrisBlockageAppearance,
            slot: 'front',
          ),
        ],
        coverage: _fullCoverage(),
        scanId: 'scan_b',
        capturedAt: t0,
      );

      // Resolve D
      final withResolved = baseline.bundle.copyWith(
        observations: [
          for (final o in baseline.bundle.observations)
            if (o.category == ObservationCategory.debrisBlockageAppearance)
              o.copyWith(status: ObservationStatus.resolved)
            else
              o,
        ],
      );

      // Coverage: elevations ok, roof missing
      final cov = PmCoverageReport(
        meetsBaselineMinimum: true,
        photoCount: 4,
        zones: [
          for (final z in ['front', 'left', 'right', 'rear'])
            PmCoverageZone(
              zoneId: z,
              surfaceType: SurfaceType.siding,
              status: CaptureZoneStatus.captured,
              quality: ImageQualityBand.usable,
            ),
          const PmCoverageZone(
            zoneId: 'roof',
            surfaceType: SurfaceType.roof,
            status: CaptureZoneStatus.missing,
          ),
          const PmCoverageZone(
            zoneId: 'surface_gutters_downspouts',
            surfaceType: SurfaceType.guttersDownspouts,
            status: CaptureZoneStatus.captured,
            quality: ImageQualityBand.usable,
          ),
        ],
      );

      final checkIn = PropertyMemoryReconciler.reconcile(
        state: withResolved,
        mode: ScanMode.checkIn,
        detections: [
          // A unchanged
          _det(
            title: 'A stain',
            surface: SurfaceType.siding,
            category: ObservationCategory.staining,
            slot: 'front',
          ),
          // B absent (good recapture) — no detection
          // C zone missing — no detection
          // E new
          _det(
            title: 'E window seal',
            surface: SurfaceType.windowsFrames,
            category: ObservationCategory.sealantFailureAppearance,
            slot: 'front',
          ),
          // D recurrence
          _det(
            title: 'D gutter',
            surface: SurfaceType.guttersDownspouts,
            category: ObservationCategory.debrisBlockageAppearance,
            slot: 'front',
          ),
        ],
        coverage: cov,
        scanId: 'scan_mixed',
        capturedAt: t0.add(const Duration(days: 14)),
      );

      ObservationStatus statusOf(ObservationCategory c) => checkIn
          .bundle.observations
          .where((o) => o.category == c)
          .single
          .status;

      expect(statusOf(ObservationCategory.staining),
          ObservationStatus.monitoring);
      expect(statusOf(ObservationCategory.cracking),
          ObservationStatus.unverified);
      expect(statusOf(ObservationCategory.wear),
          ObservationStatus.unableToDetermine);
      expect(statusOf(ObservationCategory.sealantFailureAppearance),
          ObservationStatus.fresh);
      expect(statusOf(ObservationCategory.debrisBlockageAppearance),
          ObservationStatus.fresh); // reopened
      expect(
        checkIn.newEvents.any(
          (e) => e.eventType == ObservationEventType.reopened,
        ),
        isTrue,
      );
    });

    test('AT-30 no auto-resolve paths for absence variants', () {
      final t0 = DateTime.utc(2026, 9, 1);
      final baseline = PropertyMemoryReconciler.reconcile(
        state: _draftBundle(),
        mode: ScanMode.baseline,
        detections: [
          _det(
            title: 'Siding stain',
            surface: SurfaceType.siding,
            category: ObservationCategory.staining,
            slot: 'front',
          ),
        ],
        coverage: _fullCoverage(),
        scanId: 'scan_b',
        capturedAt: t0,
      );

      for (final cov in [
        _fullCoverage(), // good absence → unverified
        PmCoverageReport(
          meetsBaselineMinimum: true,
          photoCount: 4,
          zones: [
            for (final z in ['front', 'left', 'right', 'rear'])
              PmCoverageZone(
                zoneId: z,
                surfaceType: SurfaceType.siding,
                status: CaptureZoneStatus.captured,
                quality: ImageQualityBand.poor,
              ),
          ],
        ),
        PmCoverageReport(
          meetsBaselineMinimum: false,
          photoCount: 0,
          zones: [
            for (final z in ['front', 'left', 'right', 'rear'])
              PmCoverageZone(
                zoneId: z,
                surfaceType: SurfaceType.siding,
                status: CaptureZoneStatus.missing,
              ),
          ],
        ),
      ]) {
        final checkIn = PropertyMemoryReconciler.reconcile(
          state: baseline.bundle,
          mode: ScanMode.checkIn,
          detections: const [],
          coverage: cov,
          scanId: 'scan_${cov.hashCode}',
          capturedAt: t0.add(Duration(days: cov.photoCount + 1)),
        );
        expect(
          checkIn.bundle.observations.single.status,
          isNot(ObservationStatus.resolved),
        );
        expect(
          checkIn.bundle.observations.single.status,
          anyOf(
            ObservationStatus.unverified,
            ObservationStatus.unableToDetermine,
          ),
        );
      }
    });

    test('matcher: IoU >= 0.3 → strong; same slot → medium', () {
      final obs = PmObservation(
        id: 'o1',
        propertyId: 'p',
        surfaceId: 's',
        surfaceType: SurfaceType.siding,
        title: 'Stain',
        category: ObservationCategory.staining,
        severityBand: SeverityBand.watch,
        status: ObservationStatus.fresh,
        confidence: ConfidenceBand.medium,
        localizationType: LocalizationType.region,
        regionNorm: const RegionNorm(left: 0.1, top: 0.1, width: 0.4, height: 0.4),
        firstSeenScanId: 's0',
        firstSeenAt: DateTime.utc(2026, 1, 1),
        captureSlot: 'front',
      );
      final strong = _det(
        title: 'Stain',
        surface: SurfaceType.siding,
        category: ObservationCategory.staining,
        region: const RegionNorm(left: 0.15, top: 0.15, width: 0.4, height: 0.4),
      );
      expect(
        PropertyMemoryReconciler.matchStrength(obs, strong),
        MatchStrength.strong,
      );

      final medium = _det(
        title: 'Stain',
        surface: SurfaceType.siding,
        category: ObservationCategory.staining,
        slot: 'front',
      );
      final obsNoRegion = PmObservation(
        id: 'o1',
        propertyId: 'p',
        surfaceId: 's',
        surfaceType: SurfaceType.siding,
        title: 'Stain',
        category: ObservationCategory.staining,
        severityBand: SeverityBand.watch,
        status: ObservationStatus.fresh,
        confidence: ConfidenceBand.medium,
        localizationType: LocalizationType.surfaceOnly,
        firstSeenScanId: 's0',
        firstSeenAt: DateTime.utc(2026, 1, 1),
        captureSlot: 'front',
      );
      expect(
        PropertyMemoryReconciler.matchStrength(obsNoRegion, medium),
        MatchStrength.medium,
      );
    });
  });
}

