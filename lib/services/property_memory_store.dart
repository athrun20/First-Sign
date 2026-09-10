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
  Future<void>? _loadFuture;
  PmPropertyMemoryBundle? _bundle;

  bool get isLoaded => _loaded;
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
      if (raw is String && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _bundle = PmPropertyMemoryBundle.fromJson(map);
      }
      _loaded = true;
    } catch (e, st) {
      debugPrint('PropertyMemoryStore load failed: $e\n$st');
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

    final scanId = 'scan_${now.millisecondsSinceEpoch}_${saved.id}';
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
    _loaded = true;
    notifyListeners();
  }

  /// Test helper: replace singleton state after Hive re-init.
  @visibleForTesting
  void debugDetachBox() {
    _box = null;
    _loaded = false;
    _loadFuture = null;
    _bundle = null;
  }
}
