import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pillar_ai/config/property_memory_flags.dart';
import 'package:pillar_ai/models/property_memory_enums.dart';
import 'package:pillar_ai/models/property_memory_models.dart';
import 'package:pillar_ai/models/saved_report.dart';
import 'package:pillar_ai/services/property_memory_mapper.dart';
import 'package:pillar_ai/services/property_memory_reconciler.dart';

/// Local Property Memory store (one property per install).
///
/// Persists a JSON bundle + evidence bytes in Hive box [boxName].
class PropertyMemoryStore extends ChangeNotifier {
  PropertyMemoryStore._();
  static final PropertyMemoryStore instance = PropertyMemoryStore._();

  static const boxName = 'pillar_pm_v1';
  static const bundleKey = 'bundle';

  Box<dynamic>? _box;
  bool _loaded = false;
  bool _loadFailed = false;
  Future<void>? _loadFuture;
  PmPropertyMemoryBundle? _bundle;

  bool get isLoaded => _loaded;
  bool get hasLoadFailed => _loadFailed;
  PmPropertyMemoryBundle? get bundle => _bundle;
  PmProperty? get property => _bundle?.property;

  List<PmObservation> get openObservations {
    final b = _bundle;
    if (b == null) return const [];
    return [
      for (final o in b.observations)
        if (!o.userDismissed && o.status != ObservationStatus.resolved) o,
    ];
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    // Concurrent callers await the same in-flight load (no early return while
    // _bundle is still null).
    final existing = _loadFuture;
    if (existing != null) {
      await existing;
      return;
    }
    final future = _loadBundle();
    _loadFuture = future;
    try {
      await future;
    } finally {
      if (identical(_loadFuture, future)) {
        _loadFuture = null;
      }
    }
  }

  Future<void> _loadBundle() async {
    try {
      await _openBox();
      final raw = _box!.get(bundleKey);
      if (raw == null || (raw is String && raw.isEmpty)) {
        // Missing/empty bundle key → empty OK (not a load failure).
        _bundle = null;
        _loadFailed = false;
        _loaded = true;
      } else if (raw is String) {
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          _bundle = PmPropertyMemoryBundle.fromJson(map);
          _loadFailed = false;
          _loaded = true;
        } catch (e, st) {
          debugPrint('PropertyMemoryStore decode/parse failed: $e\n$st');
          _bundle = null;
          _loadFailed = true;
          _loaded = true;
        }
      } else {
        debugPrint(
          'PropertyMemoryStore unexpected bundle type: ${raw.runtimeType}',
        );
        _bundle = null;
        _loadFailed = true;
        _loaded = true;
      }
    } catch (e, st) {
      debugPrint('PropertyMemoryStore load failed: $e\n$st');
      _bundle = null;
      _loadFailed = true;
      _loaded = true;
    } finally {
      notifyListeners();
    }
  }

  Future<void> _openBox() async {
    if (_box != null && _box!.isOpen) return;
    try {
      await Hive.initFlutter();
    } catch (_) {
      try {
        // Share the same on-disk root LocalBlobStore uses in unit tests.
        Hive.init('.dart_tool/pillar_hive');
      } catch (_) {
        // Hive already initialized by another store in this process.
      }
    }
    if (Hive.isBoxOpen(boxName)) {
      _box = Hive.box<dynamic>(boxName);
    } else {
      _box = await Hive.openBox<dynamic>(boxName);
    }
  }

  /// Dual-write entry from [ReportStore.saveFromCapture].
  ///
  /// Never rethrows — report save must not fail if memory fails.
  Future<void> applyFromSavedReport(SavedReport saved) async {
    try {
      if (!await PropertyMemoryFlags.isEnabled) return;
      await ensureLoaded();
      // Never mint fresh property over corrupt data.
      if (_loadFailed) return;
      await _applyFromSavedReportInner(saved);
    } catch (e, st) {
      debugPrint('PropertyMemory applyFromSavedReport failed (ignored): $e\n$st');
    }
  }

  Future<void> _applyFromSavedReportInner(SavedReport saved) async {
    final now = saved.createdAt;
    final detections = PropertyMemoryMapper.mapSavedReportToDetections(saved);
    final coverage = PropertyMemoryMapper.buildCoverage(saved);

    var bundle = _bundle;
    if (bundle == null) {
      bundle = PmPropertyMemoryBundle(
        property: PmProperty(
          id: 'property_local_1',
          displayName: 'My home',
          lifecycleState: PropertyLifecycleState.draft,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    // Retake: same SavedReport id → replace that scan/timepoint only.
    String? reuseScanId;
    final priorForReport = [
      for (final s in bundle.scans)
        if (s.sourceSavedReportId == saved.id) s,
    ];
    if (priorForReport.isNotEmpty) {
      reuseScanId = priorForReport.first.id;
      bundle = await _stripScanContribution(bundle, reuseScanId);
    }

    final active = bundle.property.lifecycleState ==
            PropertyLifecycleState.active &&
        bundle.property.baselineScanId != null;

    // Quick Scan / single photo / single slot cannot complete baseline.
    final quickOrSingle = PropertyMemoryMapper.looksLikeQuickOrSingleShot(saved);
    final meets = coverage.meetsBaselineMinimum && !quickOrSingle;

    final ScanMode mode;
    final PmCoverageReport effectiveCoverage;
    if (active) {
      mode = ScanMode.checkIn;
      effectiveCoverage = coverage;
    } else {
      mode = ScanMode.baseline;
      effectiveCoverage = PmCoverageReport(
        meetsBaselineMinimum: meets,
        photoCount: coverage.photoCount,
        zones: coverage.zones,
        notes: [
          ...coverage.notes,
          if (quickOrSingle)
            'Quick Scan / single-slot capture cannot complete baseline',
        ],
      );
      // Completing baseline after incomplete: discard any leftover provisional
      // rows (defensive — incomplete scans no longer create observations) and
      // clean orphaned pm/ev bytes.
      if (meets &&
          bundle.property.lifecycleState ==
              PropertyLifecycleState.baselineIncomplete) {
        final orphanIds = [for (final e in bundle.evidence) e.id];
        await _deleteEvidenceBytes(orphanIds);
        bundle = bundle.copyWith(
          observations: const [],
          evidence: const [],
          // Keep prior incomplete scan rows + surfaces for history.
        );
      }
    }

    final scanId =
        reuseScanId ?? 'scan_${now.millisecondsSinceEpoch}_${saved.id}';
    final processing = meets || active
        ? ScanProcessingStatus.complete
        : ScanProcessingStatus.partial;

    final result = PropertyMemoryReconciler.reconcile(
      state: bundle,
      mode: mode,
      detections: detections,
      coverage: effectiveCoverage,
      scanId: scanId,
      capturedAt: now,
      sourceSavedReportId: saved.id,
      processingStatus: processing,
    );

    // Copy photo bytes into pm/ev/{evidenceId} for new evidence on this scan.
    await _copyEvidenceBytes(
      saved: saved,
      evidence: [
        for (final e in result.bundle.evidence)
          if (e.scanId == scanId) e,
      ],
    );

    _bundle = result.bundle;
    await _persistBundle();
    notifyListeners();
  }

  /// Remove one scan's contribution (row, evidence bytes, events) and revert
  /// observations that only referenced that scan as last-seen.
  ///
  /// When an observation originated on [scanId] (`firstSeenScanId`), it is
  /// removed along with **all** remaining evidence/events for that observation
  /// id (including rows from later scans) so nothing orphans.
  Future<PmPropertyMemoryBundle> _stripScanContribution(
    PmPropertyMemoryBundle bundle,
    String scanId,
  ) async {
    final removedObsIds = {
      for (final obs in bundle.observations)
        if (obs.firstSeenScanId == scanId) obs.id,
    };

    // Bytes to delete: evidence on this scan, plus any leftover evidence for
    // observations that originated on this scan (may live on later scans).
    final doomedEvidenceIds = {
      for (final e in bundle.evidence)
        if (e.scanId == scanId || removedObsIds.contains(e.observationId)) e.id,
    };
    await _deleteEvidenceBytes(doomedEvidenceIds);

    final evidence = [
      for (final e in bundle.evidence)
        if (e.scanId != scanId && !removedObsIds.contains(e.observationId)) e,
    ];
    final events = [
      for (final e in bundle.events)
        if (e.scanId != scanId && !removedObsIds.contains(e.observationId)) e,
    ];
    final scans = [
      for (final s in bundle.scans)
        if (s.id != scanId) s,
    ];

    final observations = <PmObservation>[];
    for (final obs in bundle.observations) {
      if (removedObsIds.contains(obs.id)) {
        continue;
      }
      if (obs.lastSeenScanId != scanId) {
        observations.add(obs);
        continue;
      }

      // Revert lastSeen to latest remaining evidence (or firstSeen).
      final remEv = [
        for (final e in evidence)
          if (e.observationId == obs.id) e,
      ]..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
      final lastSeenScanId =
          remEv.isNotEmpty ? remEv.last.scanId : obs.firstSeenScanId;
      final lastSeenAt =
          remEv.isNotEmpty ? remEv.last.capturedAt : obs.firstSeenAt;

      // Revert status from latest remaining event with toStatus (else keep).
      final remStatusEv = [
        for (final e in events)
          if (e.observationId == obs.id && e.toStatus != null) e,
      ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final status =
          remStatusEv.isNotEmpty ? remStatusEv.last.toStatus! : obs.status;

      if (obs.lastVerifiedScanId == scanId) {
        observations.add(
          PmObservation(
            id: obs.id,
            propertyId: obs.propertyId,
            surfaceId: obs.surfaceId,
            surfaceType: obs.surfaceType,
            title: obs.title,
            description: obs.description,
            category: obs.category,
            severityBand: obs.severityBand,
            status: status,
            confidence: obs.confidence,
            zoneHint: obs.zoneHint,
            localizationType: obs.localizationType,
            twinAnchorId: obs.twinAnchorId,
            regionNorm: obs.regionNorm,
            firstSeenScanId: obs.firstSeenScanId,
            firstSeenAt: obs.firstSeenAt,
            lastSeenScanId: lastSeenScanId,
            lastSeenAt: lastSeenAt,
            lastVerifiedScanId: null,
            lastVerifiedAt: null,
            userDismissed: obs.userDismissed,
            userCorrected: obs.userCorrected,
            origin: obs.origin,
            sourceIssueFingerprint: obs.sourceIssueFingerprint,
            captureSlot: obs.captureSlot,
          ),
        );
      } else {
        observations.add(
          obs.copyWith(
            lastSeenScanId: lastSeenScanId,
            lastSeenAt: lastSeenAt,
            status: status,
          ),
        );
      }
    }

    final property = _propertyAfterRemovingScan(
      previous: bundle.property,
      remainingScans: scans,
      remainingObservations: observations,
    );

    final surfaces = [
      for (final s in bundle.surfaces)
        s.copyWith(
          openObservationCount: observations
              .where(
                (o) =>
                    o.surfaceId == s.id &&
                    !o.userDismissed &&
                    o.status != ObservationStatus.resolved,
              )
              .length,
        ),
    ];

    return bundle.copyWith(
      property: property,
      scans: scans,
      observations: observations,
      evidence: evidence,
      events: events,
      surfaces: surfaces,
    );
  }

  PmProperty _propertyAfterRemovingScan({
    required PmProperty previous,
    required List<PmScan> remainingScans,
    required List<PmObservation> remainingObservations,
  }) {
    final scanIds = {for (final s in remainingScans) s.id};

    var baselineScanId = previous.baselineScanId;
    var baselineEstablishedAt = previous.baselineEstablishedAt;
    var lifecycle = previous.lifecycleState;
    var lastCheckInScanId = previous.lastCheckInScanId;
    var lastCheckInAt = previous.lastCheckInAt;

    final baselineRemoved =
        baselineScanId != null && !scanIds.contains(baselineScanId);
    if (baselineRemoved) {
      final completedBaselines = [
        for (final s in remainingScans)
          if (s.mode == ScanMode.baseline &&
              s.processingStatus == ScanProcessingStatus.complete)
            s,
      ]..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
      if (completedBaselines.isNotEmpty) {
        final b = completedBaselines.last;
        baselineScanId = b.id;
        baselineEstablishedAt = b.capturedAt;
        lifecycle = PropertyLifecycleState.active;
      } else {
        baselineScanId = null;
        baselineEstablishedAt = null;
        lifecycle = remainingScans.isEmpty
            ? PropertyLifecycleState.draft
            : PropertyLifecycleState.baselineIncomplete;
      }
    }

    final checkInRemoved =
        lastCheckInScanId != null && !scanIds.contains(lastCheckInScanId);
    if (checkInRemoved) {
      final checkIns = [
        for (final s in remainingScans)
          if (s.mode == ScanMode.checkIn) s,
      ]..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
      if (checkIns.isNotEmpty) {
        lastCheckInScanId = checkIns.last.id;
        lastCheckInAt = checkIns.last.capturedAt;
      } else {
        lastCheckInScanId = null;
        lastCheckInAt = null;
      }
    }

    final openCount = remainingObservations
        .where(
          (o) =>
              !o.userDismissed && o.status != ObservationStatus.resolved,
        )
        .length;

    // Reconstruct so lastCheckIn* can be cleared to null (copyWith cannot).
    return PmProperty(
      id: previous.id,
      displayName: previous.displayName,
      addressLine: previous.addressLine,
      lifecycleState: lifecycle,
      baselineScanId: baselineScanId,
      baselineEstablishedAt: baselineEstablishedAt,
      lastCheckInScanId: lastCheckInScanId,
      lastCheckInAt: lastCheckInAt,
      openObservationCount: openCount,
      prioritySummary: previous.prioritySummary,
      overallConditionSignal: previous.overallConditionSignal,
      createdAt: previous.createdAt,
      updatedAt: DateTime.now(),
      featureGeneration: previous.featureGeneration,
    );
  }

  /// Remove PM scans tied to [reportId] (and their evidence/events/obs contrib).
  ///
  /// Runs when the feature flag is on **or** a residual bundle is already
  /// loaded/present (so delete can clear privacy data with the flag off).
  Future<void> forgetReport(String reportId) async {
    try {
      final enabled = await PropertyMemoryFlags.isEnabled;
      await ensureLoaded();
      if (_loadFailed) return;
      if (!enabled && _bundle == null) return;

      var bundle = _bundle;
      if (bundle == null) return;

      final doomed = [
        for (final s in bundle.scans)
          if (s.sourceSavedReportId == reportId) s.id,
      ];
      if (doomed.isEmpty) return;

      for (final scanId in doomed) {
        bundle = await _stripScanContribution(bundle!, scanId);
      }

      _bundle = bundle;
      await _persistBundle();
      notifyListeners();
    } catch (e, st) {
      debugPrint('PropertyMemory forgetReport failed (ignored): $e\n$st');
    }
  }

  /// Wipe entire PM bundle + all `pm/ev/*` evidence bytes (privacy reset).
  ///
  /// Runs even when the feature flag is off so residual box data is cleared.
  Future<void> wipeAll() async {
    try {
      await _openBox();
      final keys = _box!.keys
          .whereType<String>()
          .where((k) => k == bundleKey || k.startsWith('pm/ev/'))
          .toList();
      if (keys.isNotEmpty) await _box!.deleteAll(keys);
      _bundle = null;
      _loadFailed = false;
      _loaded = true;
      notifyListeners();
    } catch (e, st) {
      debugPrint('PropertyMemory wipeAll failed (ignored): $e\n$st');
      _bundle = null;
      _loadFailed = false;
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> _copyEvidenceBytes({
    required SavedReport saved,
    required List<PmEvidence> evidence,
  }) async {
    await _openBox();
    for (final e in evidence) {
      final idx = e.photoIndex;
      if (idx == null) continue;
      Uint8List? bytes;
      for (final p in saved.photos) {
        if (p.index == idx) {
          bytes = p.bytes;
          break;
        }
      }
      // Fallback: first photo if index missing from list.
      if ((bytes == null || bytes.isEmpty) && saved.photos.isNotEmpty) {
        bytes = saved.photos.first.bytes;
      }
      if (bytes == null || bytes.isEmpty) continue;
      final key = 'pm/ev/${e.id}';
      await _box!.put(key, bytes);
    }
  }

  Future<void> _deleteEvidenceBytes(Iterable<String> evidenceIds) async {
    await _openBox();
    final keys = [
      for (final id in evidenceIds) 'pm/ev/$id',
    ];
    if (keys.isNotEmpty) {
      await _box!.deleteAll(keys);
    }
  }

  Future<void> _persistBundle() async {
    await _openBox();
    final b = _bundle;
    if (b == null) {
      await _box!.delete(bundleKey);
      return;
    }
    await _box!.put(bundleKey, jsonEncode(b.toJson()));
  }

  Future<Uint8List?> evidenceBytes(String evidenceId) async {
    await ensureLoaded();
    await _openBox();
    final v = _box!.get('pm/ev/$evidenceId');
    if (v is Uint8List) return v;
    if (v is List<int>) return Uint8List.fromList(v);
    return null;
  }

  // ---------------------------------------------------------------------------
  // Public user-feedback APIs (UI not wired in PR1; used by tests)
  // ---------------------------------------------------------------------------

  Future<void> dismissObservation(String observationId) async {
    await ensureLoaded();
    final b = _bundle;
    if (b == null) return;
    final idx = b.observations.indexWhere((o) => o.id == observationId);
    if (idx < 0) return;
    final obs = b.observations[idx];
    final updated = [...b.observations];
    updated[idx] = obs.copyWith(userDismissed: true);
    final evt = PmObservationEvent(
      id: 'evt_dismiss_${DateTime.now().microsecondsSinceEpoch}',
      propertyId: b.property.id,
      observationId: observationId,
      eventType: ObservationEventType.userDismissed,
      actor: ActorType.user,
      summary: 'User dismissed observation',
      createdAt: DateTime.now(),
    );
    _bundle = b.copyWith(
      observations: updated,
      events: [...b.events, evt],
      property: b.property.copyWith(
        openObservationCount: updated
            .where(
              (o) =>
                  !o.userDismissed && o.status != ObservationStatus.resolved,
            )
            .length,
        updatedAt: DateTime.now(),
      ),
    );
    await _persistBundle();
    notifyListeners();
  }

  Future<void> markRepaired(String observationId) async {
    await ensureLoaded();
    final b = _bundle;
    if (b == null) return;
    final idx = b.observations.indexWhere((o) => o.id == observationId);
    if (idx < 0) return;
    final obs = b.observations[idx];
    final from = obs.status;
    final updated = [...b.observations];
    updated[idx] = obs.copyWith(status: ObservationStatus.resolved);
    final evt = PmObservationEvent(
      id: 'evt_repaired_${DateTime.now().microsecondsSinceEpoch}',
      propertyId: b.property.id,
      observationId: observationId,
      eventType: ObservationEventType.userMarkedRepaired,
      fromStatus: from,
      toStatus: ObservationStatus.resolved,
      actor: ActorType.user,
      summary: 'User marked repaired',
      createdAt: DateTime.now(),
    );
    _bundle = b.copyWith(
      observations: updated,
      events: [...b.events, evt],
      property: b.property.copyWith(
        openObservationCount: updated
            .where(
              (o) =>
                  !o.userDismissed && o.status != ObservationStatus.resolved,
            )
            .length,
        updatedAt: DateTime.now(),
      ),
    );
    await _persistBundle();
    notifyListeners();
  }

  Future<void> confirmPresent(String observationId) async {
    await ensureLoaded();
    final b = _bundle;
    if (b == null) return;
    final idx = b.observations.indexWhere((o) => o.id == observationId);
    if (idx < 0) return;
    final obs = b.observations[idx];
    final from = obs.status;
    final updated = [...b.observations];
    updated[idx] = obs.copyWith(status: ObservationStatus.monitoring);
    final evt = PmObservationEvent(
      id: 'evt_confirm_${DateTime.now().microsecondsSinceEpoch}',
      propertyId: b.property.id,
      observationId: observationId,
      eventType: ObservationEventType.userConfirmedPresent,
      fromStatus: from,
      toStatus: ObservationStatus.monitoring,
      actor: ActorType.user,
      summary: 'User confirmed still present',
      createdAt: DateTime.now(),
    );
    _bundle = b.copyWith(
      observations: updated,
      events: [...b.events, evt],
    );
    await _persistBundle();
    notifyListeners();
  }

  Future<void> correctObservation(
    String observationId, {
    ObservationCategory? category,
    SurfaceType? surfaceType,
  }) async {
    await ensureLoaded();
    final b = _bundle;
    if (b == null) return;
    final idx = b.observations.indexWhere((o) => o.id == observationId);
    if (idx < 0) return;
    final obs = b.observations[idx];
    var surfaceId = obs.surfaceId;
    if (surfaceType != null && surfaceType != obs.surfaceType) {
      final existing =
          b.surfaces.where((s) => s.type == surfaceType).toList();
      if (existing.isNotEmpty) {
        surfaceId = existing.first.id;
      } else {
        surfaceId = 'surface_${b.property.id}_${surfaceType.toStorage()}';
      }
    }
    final updated = [...b.observations];
    updated[idx] = obs.copyWith(
      category: category ?? obs.category,
      surfaceType: surfaceType ?? obs.surfaceType,
      surfaceId: surfaceId,
      userCorrected: true,
    );
    final surfaces = [...b.surfaces];
    if (surfaceType != null &&
        surfaces.every((s) => s.type != surfaceType)) {
      surfaces.add(
        PmSurface(
          id: surfaceId,
          propertyId: b.property.id,
          type: surfaceType,
        ),
      );
    }
    final evt = PmObservationEvent(
      id: 'evt_correct_${DateTime.now().microsecondsSinceEpoch}',
      propertyId: b.property.id,
      observationId: observationId,
      eventType: ObservationEventType.userCorrected,
      actor: ActorType.user,
      summary: 'User corrected observation',
      payload: {
        'before': {
          'category': obs.category.toStorage(),
          'surfaceType': obs.surfaceType.toStorage(),
        },
        'after': {
          'category': (category ?? obs.category).toStorage(),
          'surfaceType': (surfaceType ?? obs.surfaceType).toStorage(),
        },
      },
      createdAt: DateTime.now(),
    );
    _bundle = b.copyWith(
      observations: updated,
      surfaces: surfaces,
      events: [...b.events, evt],
    );
    await _persistBundle();
    notifyListeners();
  }

  /// Test helper: wipe in-memory + box bundle (keeps box open).
  Future<void> debugReset() async {
    await _openBox();
    final keys = _box!.keys
        .whereType<String>()
        .where((k) => k == bundleKey || k.startsWith('pm/ev/'))
        .toList();
    if (keys.isNotEmpty) await _box!.deleteAll(keys);
    _bundle = null;
    _loadFailed = false;
    _loaded = true;
    notifyListeners();
  }

  /// Test helper: replace singleton state after Hive re-init.
  @visibleForTesting
  void debugDetachBox() {
    _box = null;
    _loaded = false;
    _loadFailed = false;
    _loadFuture = null;
    _bundle = null;
  }
}
