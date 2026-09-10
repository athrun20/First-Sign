import 'package:pillar_ai/models/property_memory_enums.dart';
import 'package:pillar_ai/models/property_memory_models.dart';

/// Check-in / baseline reconciliation for Property Memory v1.
///
/// Invariants:
/// - NEVER auto-resolve (absence → unverified / unableToDetermine only)
/// - No automatic worsened / improved writes
/// - Matcher: same surface type + category; IoU≥0.3 → strong; same slot → medium; else weak
class PropertyMemoryReconciler {
  PropertyMemoryReconciler._();

  static const double regionIouStrong = 0.3;

  static PmReconcileResult reconcile({
    required PmPropertyMemoryBundle state,
    required ScanMode mode,
    required List<PmDetection> detections,
    required PmCoverageReport coverage,
    required String scanId,
    required DateTime capturedAt,
    String? sourceSavedReportId,
    SeasonalContext seasonalContext = SeasonalContext.unknown,
    ScanProcessingStatus processingStatus = ScanProcessingStatus.complete,
  }) {
    final property = state.property;
    final surfaces = [...state.surfaces];
    final observations = [...state.observations];
    final evidence = [...state.evidence];
    final events = [...state.events];
    final newEvents = <PmObservationEvent>[];
    final scans = [...state.scans];

    String eid() =>
        'evt_${capturedAt.microsecondsSinceEpoch}_${newEvents.length}';
    String oid() =>
        'obs_${capturedAt.microsecondsSinceEpoch}_${observations.length}';
    String evid() =>
        'ev_${capturedAt.microsecondsSinceEpoch}_${evidence.length}';
    String sid(SurfaceType t) => 'surface_${property.id}_${t.toStorage()}';

    PmSurface ensureSurface(SurfaceType type, {String? twin}) {
      final existing = surfaces.where((s) => s.type == type).toList();
      if (existing.isNotEmpty) {
        final i = surfaces.indexOf(existing.first);
        final updated = existing.first.copyWith(
          lastObservedAt: capturedAt,
          twinRegionId: twin ?? existing.first.twinRegionId,
          latestCoverageQuality: ImageQualityBand.usable,
        );
        surfaces[i] = updated;
        return updated;
      }
      final created = PmSurface(
        id: sid(type),
        propertyId: property.id,
        type: type,
        twinRegionId: twin,
        lastObservedAt: capturedAt,
        presence: SurfacePresence.present,
        latestCoverageQuality: ImageQualityBand.usable,
      );
      surfaces.add(created);
      return created;
    }

    void addEvent(PmObservationEvent e) {
      events.add(e);
      newEvents.add(e);
    }

    final scan = PmScan(
      id: scanId,
      propertyId: property.id,
      mode: mode,
      capturedAt: capturedAt,
      processingStatus: processingStatus,
      sourceSavedReportId: sourceSavedReportId,
      seasonalContext: seasonalContext,
      coverageReport: coverage,
      photoIds: [
        for (var i = 0; i < coverage.photoCount; i++) 'photo_$i',
      ],
    );
    scans.add(scan);

    if (mode == ScanMode.baseline) {
      // Incomplete baseline: record scan + lifecycle only — do NOT create
      // observations (prevents stacking provisionals on repeated Quick Scans).
      if (coverage.meetsBaselineMinimum) {
        for (final d in detections) {
          final surface = ensureSurface(d.surfaceType, twin: d.twinAnchorId);
          final obsId = oid();
          final obs = PmObservation(
            id: obsId,
            propertyId: property.id,
            surfaceId: surface.id,
            surfaceType: d.surfaceType,
            title: d.title,
            description: d.description,
            category: d.category,
            severityBand: d.severityBand,
            status: ObservationStatus.fresh,
            confidence: d.confidence,
            zoneHint: d.zoneHint,
            localizationType: d.localizationType,
            twinAnchorId: d.twinAnchorId,
            regionNorm: d.regionNorm,
            firstSeenScanId: scanId,
            firstSeenAt: capturedAt,
            lastSeenScanId: scanId,
            lastSeenAt: capturedAt,
            origin: ActorType.ai,
            sourceIssueFingerprint: d.sourceIssueFingerprint,
            captureSlot: d.captureSlot,
          );
          observations.add(obs);

          final evId = evid();
          evidence.add(
            PmEvidence(
              id: evId,
              observationId: obsId,
              scanId: scanId,
              photoKey: 'pm/ev/$evId',
              capturedAt: capturedAt,
              imageQuality: d.imageQuality,
              localizationType: d.localizationType,
              regionNorm: d.regionNorm,
              modelExplanation: d.modelExplanation,
              photoIndex: d.photoIndex,
            ),
          );

          addEvent(
            PmObservationEvent(
              id: eid(),
              propertyId: property.id,
              observationId: obsId,
              scanId: scanId,
              eventType: ObservationEventType.created,
              toStatus: ObservationStatus.fresh,
              actor: ActorType.ai,
              summary: 'Observation created from baseline scan',
              createdAt: capturedAt,
            ),
          );
          addEvent(
            PmObservationEvent(
              id: eid(),
              propertyId: property.id,
              observationId: obsId,
              scanId: scanId,
              eventType: ObservationEventType.evidenceAdded,
              actor: ActorType.ai,
              summary: 'Baseline evidence attached',
              createdAt: capturedAt,
            ),
          );
        }
      }
    } else {
      // Check-in reconciliation
      final matchedObsIds = <String>{};
      final usedDetectionIndexes = <int>{};

      // Pass 1: match detections to open observations (and reopen resolved).
      for (var di = 0; di < detections.length; di++) {
        final d = detections[di];
        ensureSurface(d.surfaceType, twin: d.twinAnchorId);

        final openMatches = <_ScoredMatch>[];
        final resolvedMatches = <_ScoredMatch>[];

        for (final obs in observations) {
          if (obs.surfaceType != d.surfaceType || obs.category != d.category) {
            continue;
          }
          final strength = matchStrength(obs, d);
          if (strength == MatchStrength.none) continue;
          final scored = _ScoredMatch(obs: obs, strength: strength);
          if (obs.status == ObservationStatus.resolved || obs.userDismissed) {
            // Dismissed: downweight — still reopen only if not dismissed.
            if (obs.userDismissed) continue;
            resolvedMatches.add(scored);
          } else if (obs.isOpenForMatch) {
            openMatches.add(scored);
          }
        }

        _ScoredMatch? best;
        var reopen = false;
        if (openMatches.isNotEmpty) {
          openMatches.sort(_compareMatches);
          best = openMatches.first;
        } else if (resolvedMatches.isNotEmpty) {
          resolvedMatches.sort(_compareMatches);
          best = resolvedMatches.first;
          reopen = true;
        }

        if (best == null) {
          // New observation (AT-8)
          final surface = ensureSurface(d.surfaceType, twin: d.twinAnchorId);
          final obsId = oid();
          final obs = PmObservation(
            id: obsId,
            propertyId: property.id,
            surfaceId: surface.id,
            surfaceType: d.surfaceType,
            title: d.title,
            description: d.description,
            category: d.category,
            severityBand: d.severityBand,
            status: ObservationStatus.fresh,
            confidence: d.confidence,
            zoneHint: d.zoneHint,
            localizationType: d.localizationType,
            twinAnchorId: d.twinAnchorId,
            regionNorm: d.regionNorm,
            firstSeenScanId: scanId,
            firstSeenAt: capturedAt,
            lastSeenScanId: scanId,
            lastSeenAt: capturedAt,
            origin: ActorType.ai,
            sourceIssueFingerprint: d.sourceIssueFingerprint,
            captureSlot: d.captureSlot,
          );
          observations.add(obs);
          matchedObsIds.add(obsId);
          usedDetectionIndexes.add(di);

          final evId = evid();
          evidence.add(
            PmEvidence(
              id: evId,
              observationId: obsId,
              scanId: scanId,
              photoKey: 'pm/ev/$evId',
              capturedAt: capturedAt,
              imageQuality: d.imageQuality,
              localizationType: d.localizationType,
              regionNorm: d.regionNorm,
              modelExplanation: d.modelExplanation,
              photoIndex: d.photoIndex,
            ),
          );
          addEvent(
            PmObservationEvent(
              id: eid(),
              propertyId: property.id,
              observationId: obsId,
              scanId: scanId,
              eventType: ObservationEventType.created,
              toStatus: ObservationStatus.fresh,
              actor: ActorType.ai,
              summary: 'New observation on check-in',
              createdAt: capturedAt,
            ),
          );
          continue;
        }

        final idx = observations.indexWhere((o) => o.id == best!.obs.id);
        var obs = observations[idx];
        final from = obs.status;
        usedDetectionIndexes.add(di);
        matchedObsIds.add(obs.id);

        // Poor new evidence: do not authoritative-verify (AT-11 style).
        final poorEvidence = !d.imageQuality.isAdequate;

        if (reopen) {
          obs = obs.copyWith(
            status: ObservationStatus.fresh,
            confidence: d.confidence,
            lastSeenScanId: scanId,
            lastSeenAt: capturedAt,
            regionNorm: d.regionNorm ?? obs.regionNorm,
            localizationType: d.localizationType,
            title: d.title.isNotEmpty ? d.title : obs.title,
          );
          observations[idx] = obs;
          addEvent(
            PmObservationEvent(
              id: eid(),
              propertyId: property.id,
              observationId: obs.id,
              scanId: scanId,
              eventType: ObservationEventType.reopened,
              fromStatus: from,
              toStatus: ObservationStatus.fresh,
              actor: ActorType.ai,
              summary: 'Previously resolved observation reopened',
              createdAt: capturedAt,
            ),
          );
        } else if (poorEvidence) {
          // Keep prior status; mark unable_to_determine for this pass if we
          // cannot trust the frame — prefer unableToDetermine over false verify.
          obs = obs.copyWith(
            status: ObservationStatus.unableToDetermine,
            lastSeenScanId: scanId,
            lastSeenAt: capturedAt,
          );
          observations[idx] = obs;
          addEvent(
            PmObservationEvent(
              id: eid(),
              propertyId: property.id,
              observationId: obs.id,
              scanId: scanId,
              eventType: ObservationEventType.unableToCompare,
              fromStatus: from,
              toStatus: ObservationStatus.unableToDetermine,
              actor: ActorType.ai,
              summary: 'Latest photos too weak to verify',
              payload: {'imageQuality': d.imageQuality.toStorage()},
              createdAt: capturedAt,
            ),
          );
        } else {
          // AT-4: monitoring + evidence
          // Severity updates only when confidence is at least medium
          // (adequate/comparable evidence already required on this branch).
          final canUpdateSeverity = d.confidence == ConfidenceBand.medium ||
              d.confidence == ConfidenceBand.high;
          obs = obs.copyWith(
            status: ObservationStatus.monitoring,
            confidence: d.confidence,
            severityBand:
                canUpdateSeverity ? d.severityBand : obs.severityBand,
            lastSeenScanId: scanId,
            lastSeenAt: capturedAt,
            lastVerifiedScanId: scanId,
            lastVerifiedAt: capturedAt,
            regionNorm: d.regionNorm ?? obs.regionNorm,
            localizationType: d.localizationType,
          );
          observations[idx] = obs;
          addEvent(
            PmObservationEvent(
              id: eid(),
              propertyId: property.id,
              observationId: obs.id,
              scanId: scanId,
              eventType: ObservationEventType.verifiedUnchanged,
              fromStatus: from,
              toStatus: ObservationStatus.monitoring,
              actor: ActorType.ai,
              summary: 'Still present; no directional change asserted',
              payload: {'matchStrength': best.strength.toStorage()},
              createdAt: capturedAt,
            ),
          );
        }

        // Always append evidence (history retained). Never delete prior.
        final evId = evid();
        evidence.add(
          PmEvidence(
            id: evId,
            observationId: obs.id,
            scanId: scanId,
            photoKey: 'pm/ev/$evId',
            capturedAt: capturedAt,
            imageQuality: d.imageQuality,
            localizationType: d.localizationType,
            regionNorm: d.regionNorm,
            modelExplanation: d.modelExplanation,
            photoIndex: d.photoIndex,
            isInvalidated: false,
          ),
        );
        addEvent(
          PmObservationEvent(
            id: eid(),
            propertyId: property.id,
            observationId: obs.id,
            scanId: scanId,
            eventType: ObservationEventType.evidenceAdded,
            actor: ActorType.ai,
            summary: 'Check-in evidence attached',
            createdAt: capturedAt,
          ),
        );
      }

      // Pass 2: unmatched open observations → unverified / unableToDetermine
      for (var i = 0; i < observations.length; i++) {
        final obs = observations[i];
        if (!obs.isOpenForMatch) continue;
        if (matchedObsIds.contains(obs.id)) continue;

        final from = obs.status;
        final adequately = _surfaceAdequatelyRecaptured(coverage, obs);
        final missing = _surfaceMissing(coverage, obs);
        final ObservationStatus to;
        final ObservationEventType evtType;

        if (missing) {
          // AT-7
          to = ObservationStatus.unableToDetermine;
          evtType = ObservationEventType.unableToCompare;
        } else if (adequately) {
          // AT-5
          to = ObservationStatus.unverified;
          evtType = ObservationEventType.statusChanged;
        } else {
          // AT-6 / AT-9 poor or incomparable
          to = ObservationStatus.unableToDetermine;
          evtType = ObservationEventType.unableToCompare;
        }

        // NEVER auto-resolve
        assert(to != ObservationStatus.resolved);

        observations[i] = obs.copyWith(status: to);
        addEvent(
          PmObservationEvent(
            id: eid(),
            propertyId: property.id,
            observationId: obs.id,
            scanId: scanId,
            eventType: evtType,
            fromStatus: from,
            toStatus: to,
            actor: ActorType.ai,
            summary: to == ObservationStatus.unverified
                ? 'Not visible in latest comparable photos; not marked fixed'
                : 'Could not re-verify; area missing or imagery inadequate',
            payload: {
              'adequatelyRecaptured': adequately,
              'surfaceMissing': missing,
            },
            createdAt: capturedAt,
          ),
        );
      }
    }

    final updatedProperty = _refreshPropertyAggregates(
      property: property,
      mode: mode,
      scanId: scanId,
      capturedAt: capturedAt,
      coverage: coverage,
      observations: observations,
    );

    // Refresh surface open counts
    for (var i = 0; i < surfaces.length; i++) {
      final s = surfaces[i];
      final count = observations
          .where(
            (o) =>
                o.surfaceId == s.id &&
                !o.userDismissed &&
                o.status != ObservationStatus.resolved,
          )
          .length;
      surfaces[i] = s.copyWith(openObservationCount: count);
    }

    final bundle = PmPropertyMemoryBundle(
      property: updatedProperty,
      surfaces: surfaces,
      scans: scans,
      observations: observations,
      evidence: evidence,
      events: events,
    );

    return PmReconcileResult(
      bundle: bundle,
      newEvents: newEvents,
      mode: mode,
    );
  }

  static MatchStrength matchStrength(PmObservation obs, PmDetection d) {
    if (obs.surfaceType != d.surfaceType || obs.category != d.category) {
      return MatchStrength.none;
    }
    // Distinct regions: IoU below threshold → no match (AT-24)
    if (obs.regionNorm != null &&
        d.regionNorm != null &&
        obs.localizationType == LocalizationType.region &&
        d.localizationType == LocalizationType.region) {
      final iou = obs.regionNorm!.iou(d.regionNorm!);
      if (iou >= regionIouStrong) return MatchStrength.strong;
      // Low IoU with both localized → treat as separate (caller skips)
      if (iou < 0.05) return MatchStrength.none;
      // Ambiguous overlap: fall through to zone/weak
    } else if (obs.regionNorm != null && d.regionNorm != null) {
      final iou = obs.regionNorm!.iou(d.regionNorm!);
      if (iou >= regionIouStrong) return MatchStrength.strong;
    }

    final slotObs = obs.captureSlot;
    final slotDet = d.captureSlot;
    if (slotObs != null &&
        slotDet != null &&
        slotObs.isNotEmpty &&
        slotObs == slotDet) {
      return MatchStrength.medium;
    }
    if (obs.zoneHint != null &&
        d.zoneHint != null &&
        obs.zoneHint!.isNotEmpty &&
        obs.zoneHint!.toLowerCase() == d.zoneHint!.toLowerCase()) {
      return MatchStrength.medium;
    }
    return MatchStrength.weak;
  }

  static bool _surfaceAdequatelyRecaptured(
    PmCoverageReport coverage,
    PmObservation obs,
  ) {
    // Slot hint
    if (obs.captureSlot != null && obs.captureSlot!.isNotEmpty) {
      for (final z in coverage.zones) {
        if (z.zoneId == obs.captureSlot &&
            z.status == CaptureZoneStatus.captured &&
            (z.quality == null || z.quality!.isAdequate)) {
          return true;
        }
      }
    }
    for (final z in coverage.zones) {
      if (z.surfaceType == obs.surfaceType &&
          z.status == CaptureZoneStatus.captured &&
          (z.quality == null || z.quality!.isAdequate)) {
        return true;
      }
    }
    // Elevation slots imply siding coverage.
    if (obs.surfaceType == SurfaceType.siding ||
        obs.surfaceType == SurfaceType.windowsFrames ||
        obs.surfaceType == SurfaceType.doorsFrames ||
        obs.surfaceType == SurfaceType.trimFascia) {
      const elev = {'front', 'left', 'right', 'rear'};
      for (final z in coverage.zones) {
        if (elev.contains(z.zoneId) &&
            z.status == CaptureZoneStatus.captured &&
            (z.quality == null || z.quality!.isAdequate)) {
          return true;
        }
      }
    }
    if (obs.surfaceType == SurfaceType.roof) {
      for (final z in coverage.zones) {
        if (z.zoneId == 'roof' &&
            z.status == CaptureZoneStatus.captured &&
            (z.quality == null || z.quality!.isAdequate)) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _surfaceMissing(PmCoverageReport coverage, PmObservation obs) {
    if (obs.captureSlot != null && obs.captureSlot!.isNotEmpty) {
      for (final z in coverage.zones) {
        if (z.zoneId == obs.captureSlot) {
          return z.status == CaptureZoneStatus.missing;
        }
      }
      return true;
    }
    final related =
        coverage.zones.where((z) => z.surfaceType == obs.surfaceType).toList();
    if (related.isEmpty) {
      // No explicit zone — if elevations missing for siding-like, treat missing
      if (obs.surfaceType == SurfaceType.siding) {
        const elev = {'front', 'left', 'right', 'rear'};
        final elevZones =
            coverage.zones.where((z) => elev.contains(z.zoneId)).toList();
        if (elevZones.isEmpty) return true;
        return elevZones.every((z) => z.status == CaptureZoneStatus.missing);
      }
      return true;
    }
    return related.every((z) => z.status == CaptureZoneStatus.missing);
  }

  static PmProperty _refreshPropertyAggregates({
    required PmProperty property,
    required ScanMode mode,
    required String scanId,
    required DateTime capturedAt,
    required PmCoverageReport coverage,
    required List<PmObservation> observations,
  }) {
    final open = observations
        .where(
          (o) =>
              !o.userDismissed && o.status != ObservationStatus.resolved,
        )
        .toList();
    final priority = <String, int>{
      for (final b in SeverityBand.values) b.toStorage(): 0,
    };
    for (final o in open) {
      if (o.confidence == ConfidenceBand.insufficient) continue;
      priority[o.severityBand.toStorage()] =
          (priority[o.severityBand.toStorage()] ?? 0) + 1;
    }

    OverallConditionSignal signal;
    if (!coverage.meetsBaselineMinimum &&
        property.lifecycleState != PropertyLifecycleState.active &&
        mode == ScanMode.baseline) {
      signal = OverallConditionSignal.incompleteCoverage;
    } else if ((priority['urgent'] ?? 0) > 0) {
      signal = OverallConditionSignal.urgentAttention;
    } else if ((priority['attention'] ?? 0) > 0) {
      signal = OverallConditionSignal.needsAttention;
    } else {
      signal = OverallConditionSignal.stable;
    }

    var lifecycle = property.lifecycleState;
    String? baselineScanId = property.baselineScanId;
    DateTime? baselineAt = property.baselineEstablishedAt;
    String? lastCheckIn = property.lastCheckInScanId;
    DateTime? lastCheckInAt = property.lastCheckInAt;

    if (mode == ScanMode.baseline) {
      if (coverage.meetsBaselineMinimum) {
        lifecycle = PropertyLifecycleState.active;
        baselineScanId = scanId;
        baselineAt = capturedAt;
      } else {
        lifecycle = PropertyLifecycleState.baselineIncomplete;
        // Do not set baselineScanId
      }
    } else {
      lastCheckIn = scanId;
      lastCheckInAt = capturedAt;
    }

    return property.copyWith(
      lifecycleState: lifecycle,
      baselineScanId: baselineScanId,
      baselineEstablishedAt: baselineAt,
      lastCheckInScanId: lastCheckIn,
      lastCheckInAt: lastCheckInAt,
      openObservationCount: open.length,
      prioritySummary: priority,
      overallConditionSignal: signal,
      updatedAt: capturedAt,
      clearBaseline: mode == ScanMode.baseline && !coverage.meetsBaselineMinimum,
    );
  }

  static int _compareMatches(_ScoredMatch a, _ScoredMatch b) {
    int rank(MatchStrength s) => switch (s) {
          MatchStrength.strong => 3,
          MatchStrength.medium => 2,
          MatchStrength.weak => 1,
          MatchStrength.none => 0,
        };
    return rank(b.strength) - rank(a.strength);
  }
}

class _ScoredMatch {
  final PmObservation obs;
  final MatchStrength strength;
  _ScoredMatch({required this.obs, required this.strength});
}
