import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:pillar_ai/config/property_memory_flags.dart';
import 'package:pillar_ai/models/analysis_models.dart';
import 'package:pillar_ai/models/capture_models.dart';
import 'package:pillar_ai/models/property_memory_enums.dart';
import 'package:pillar_ai/models/saved_report.dart';
import 'package:pillar_ai/services/property_memory_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

AnalysisIssue _issue({
  required String title,
  String location = 'Front elevation siding',
  String severity = 'Medium',
  int confidence = 80,
  int photoIndex = 0,
}) {
  return AnalysisIssue(
    title: title,
    location: location,
    severity: severity,
    cost: '\$400',
    confidence: confidence,
    insight: 'Visible cue from photos.',
    photoIndex: photoIndex,
    sourcePhotoLabel: location,
  );
}

SavedPhoto _photo(int index, CaptureShotId slot, {List<int>? bytes}) {
  return SavedPhoto(
    index: index,
    label: slot.name,
    slotId: slot,
    bytes: Uint8List.fromList(bytes ?? List.generate(16, (i) => index + i)),
  );
}

SavedReport _guidedReport({
  String id = 'report_guided',
  List<AnalysisIssue>? issues,
}) {
  final photos = [
    _photo(0, CaptureShotId.front),
    _photo(1, CaptureShotId.left),
    _photo(2, CaptureShotId.right),
    _photo(3, CaptureShotId.rear),
  ];
  return SavedReport(
    id: id,
    createdAt: DateTime.utc(2026, 9, 1, 12),
    report: AnalysisReport(
      overallScore: 70,
      conditionLabel: 'Mixed',
      issues: issues ??
          [
            _issue(title: 'Peeling paint on siding', location: 'Front siding'),
          ],
      estimatedRepairRange: '\$500',
      analysisSource: 'test',
      photoCount: photos.length,
    ),
    photos: photos,
  );
}

SavedReport _quickScanReport({String id = 'report_qs'}) {
  final photos = [_photo(0, CaptureShotId.problemCloseup)];
  return SavedReport(
    id: id,
    createdAt: DateTime.utc(2026, 9, 1, 10),
    report: AnalysisReport(
      overallScore: 65,
      conditionLabel: 'Limited',
      issues: [
        _issue(title: 'Stain on wall', location: 'Unknown elevation'),
      ],
      estimatedRepairRange: 'TBD',
      analysisSource: 'test',
      photoCount: 1,
    ),
    photos: photos,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PropertyMemoryFlags.setEnabled(true);
    tempDir = await Directory.systemTemp.createTemp('pm_hive_');
    Hive.init(tempDir.path);
    PropertyMemoryStore.instance.debugDetachBox();
    await PropertyMemoryStore.instance.ensureLoaded();
    await PropertyMemoryStore.instance.debugReset();
  });

  tearDown(() async {
    try {
      if (Hive.isBoxOpen(PropertyMemoryStore.boxName)) {
        await Hive.box<dynamic>(PropertyMemoryStore.boxName).clear();
        await Hive.box<dynamic>(PropertyMemoryStore.boxName).close();
      }
    } catch (_) {}
    PropertyMemoryStore.instance.debugDetachBox();
    try {
      await Hive.close();
    } catch (_) {}
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('flag off → applyFromSavedReport is a no-op', () async {
    await PropertyMemoryFlags.setEnabled(false);
    final store = PropertyMemoryStore.instance;
    await store.applyFromSavedReport(_guidedReport());
    expect(store.bundle, isNull);
  });

  test('AT-1 store baseline success via applyFromSavedReport', () async {
    final store = PropertyMemoryStore.instance;
    await store.applyFromSavedReport(_guidedReport());
    expect(store.property?.lifecycleState, PropertyLifecycleState.active);
    expect(store.property?.baselineScanId, isNotNull);
    expect(store.openObservations, isNotEmpty);
    expect(store.bundle!.scans.single.mode, ScanMode.baseline);
    expect(store.bundle!.scans.single.sourceSavedReportId, 'report_guided');
    // Evidence bytes copied
    final ev = store.bundle!.evidence.single;
    final bytes = await store.evidenceBytes(ev.id);
    expect(bytes, isNotNull);
    expect(bytes!.isNotEmpty, isTrue);
  });

  test('AT-2 Quick Scan → baselineIncomplete, no baselineScanId', () async {
    final store = PropertyMemoryStore.instance;
    await store.applyFromSavedReport(_quickScanReport());
    expect(
      store.property?.lifecycleState,
      PropertyLifecycleState.baselineIncomplete,
    );
    expect(store.property?.baselineScanId, isNull);
    // Incomplete baseline creates no observations.
    expect(store.bundle!.observations, isEmpty);
  });

  test('AT-3 second guided scan is check-in', () async {
    final store = PropertyMemoryStore.instance;
    await store.applyFromSavedReport(_guidedReport(id: 'r1'));
    await store.applyFromSavedReport(
      _guidedReport(
        id: 'r2',
        issues: [
          _issue(title: 'Peeling paint on siding', location: 'Front siding'),
        ],
      ).copyWithCreatedAt(DateTime.utc(2026, 9, 15)),
    );
    expect(store.bundle!.scans.length, 2);
    expect(store.bundle!.scans.last.mode, ScanMode.checkIn);
    expect(store.property?.lastCheckInScanId, isNotNull);
  });

  test('AT-17 markRepaired → resolved; AT-18 reopen on recurrence', () async {
    final store = PropertyMemoryStore.instance;
    await store.applyFromSavedReport(_guidedReport(id: 'r1'));
    final obsId = store.openObservations.single.id;
    await store.markRepaired(obsId);
    expect(
      store.bundle!.observations.single.status,
      ObservationStatus.resolved,
    );
    expect(store.openObservations, isEmpty);

    await store.applyFromSavedReport(
      _guidedReport(
        id: 'r2',
        issues: [
          _issue(title: 'Peeling paint on siding', location: 'Front siding'),
        ],
      ).copyWithCreatedAt(DateTime.utc(2026, 10, 1)),
    );
    expect(store.bundle!.observations.single.id, obsId);
    expect(
      store.bundle!.observations.single.status,
      ObservationStatus.fresh,
    );
  });

  test('dismissObservation hides from openObservations', () async {
    final store = PropertyMemoryStore.instance;
    await store.applyFromSavedReport(_guidedReport());
    final obsId = store.openObservations.single.id;
    await store.dismissObservation(obsId);
    expect(store.openObservations, isEmpty);
    expect(store.bundle!.observations.single.userDismissed, isTrue);
  });

  test('confirmPresent / correctObservation APIs', () async {
    final store = PropertyMemoryStore.instance;
    await store.applyFromSavedReport(_guidedReport());
    final obsId = store.openObservations.single.id;
    // Force unverified then confirm
    await store.markRepaired(obsId); // resolve then we'll reopen path separately
    // Use a fresh baseline-like state: reset and apply again
    await store.debugReset();
    await store.applyFromSavedReport(_guidedReport(id: 'r_new'));
    final id2 = store.openObservations.single.id;
    await store.confirmPresent(id2);
    expect(
      store.bundle!.observations.single.status,
      ObservationStatus.monitoring,
    );
    await store.correctObservation(
      id2,
      category: ObservationCategory.wear,
    );
    expect(store.bundle!.observations.single.userCorrected, isTrue);
    expect(
      store.bundle!.observations.single.category,
      ObservationCategory.wear,
    );
  });


  test('concurrent ensureLoaded shares one load future', () async {
    PropertyMemoryStore.instance.debugDetachBox();
    final a = PropertyMemoryStore.instance.ensureLoaded();
    final b = PropertyMemoryStore.instance.ensureLoaded();
    await Future.wait([a, b]);
    expect(PropertyMemoryStore.instance.bundle, isNull);
    // Second load after detach+reset still works.
    await PropertyMemoryStore.instance.debugReset();
    await PropertyMemoryStore.instance.applyFromSavedReport(_guidedReport());
    expect(PropertyMemoryStore.instance.property, isNotNull);
  });

  test('errors are swallowed (never rethrow)', () async {
    final store = PropertyMemoryStore.instance;
    // Even with odd input, should not throw out of applyFromSavedReport.
    await store.applyFromSavedReport(
      SavedReport(
        id: 'empty',
        createdAt: DateTime.utc(2026, 1, 1),
        report: const AnalysisReport(
          overallScore: 100,
          conditionLabel: 'Good',
          issues: [],
          estimatedRepairRange: '',
          analysisSource: 'test',
          photoCount: 0,
        ),
        photos: const [],
      ),
    );
  });

  test('PR1.5 retake same report id does not create second scan', () async {
    final store = PropertyMemoryStore.instance;
    await store.applyFromSavedReport(_guidedReport(id: 'r_retake'));
    expect(store.bundle!.scans.length, 1);
    final scanId = store.bundle!.scans.single.id;
    final obsCount = store.bundle!.observations.length;

    await store.applyFromSavedReport(
      _guidedReport(
        id: 'r_retake',
        issues: [
          _issue(title: 'Peeling paint on siding', location: 'Front siding'),
        ],
      ).copyWithCreatedAt(DateTime.utc(2026, 9, 2, 12)),
    );

    expect(store.bundle!.scans.length, 1);
    expect(store.bundle!.scans.single.id, scanId);
    expect(store.bundle!.scans.single.sourceSavedReportId, 'r_retake');
    expect(store.bundle!.observations.length, obsCount);
    expect(store.property?.lifecycleState, PropertyLifecycleState.active);
  });

  test('PR1.5 baseline → check-in → retake check-in preserves history',
      () async {
    final store = PropertyMemoryStore.instance;
    await store.applyFromSavedReport(_guidedReport(id: 'r_base'));
    final baselineScanId = store.bundle!.scans.single.id;
    final baselineObsIds = [for (final o in store.bundle!.observations) o.id];
    expect(baselineObsIds, isNotEmpty);
    final baselineEvIds = [
      for (final e in store.bundle!.evidence)
        if (e.scanId == baselineScanId) e.id,
    ];

    await store.applyFromSavedReport(
      _guidedReport(
        id: 'r_checkin',
        issues: [
          _issue(title: 'Peeling paint on siding', location: 'Front siding'),
        ],
      ).copyWithCreatedAt(DateTime.utc(2026, 9, 20)),
    );
    expect(store.bundle!.scans.length, 2);
    final checkInScanId = store.bundle!.scans.last.id;
    expect(store.bundle!.scans.last.mode, ScanMode.checkIn);
    // Baseline observations survive check-in rematch (same ids).
    expect(
      [for (final o in store.bundle!.observations) o.id],
      containsAll(baselineObsIds),
    );

    await store.applyFromSavedReport(
      _guidedReport(
        id: 'r_checkin',
        issues: [
          _issue(title: 'Peeling paint on siding', location: 'Front siding'),
        ],
      ).copyWithCreatedAt(DateTime.utc(2026, 9, 21)),
    );

    // Still exactly two scans; check-in reuses same scan id/timepoint.
    expect(store.bundle!.scans.length, 2);
    expect(store.bundle!.scans.first.id, baselineScanId);
    expect(store.bundle!.scans.first.sourceSavedReportId, 'r_base');
    expect(store.bundle!.scans.last.id, checkInScanId);
    expect(store.bundle!.scans.last.sourceSavedReportId, 'r_checkin');
    expect(store.bundle!.scans.last.mode, ScanMode.checkIn);

    // Baseline observations preserved.
    final afterObsIds = [for (final o in store.bundle!.observations) o.id];
    expect(afterObsIds, containsAll(baselineObsIds));

    // No orphan evidence/events: every row references a live observation
    // (or, for events, an observation that still exists).
    final liveObs = afterObsIds.toSet();
    for (final e in store.bundle!.evidence) {
      expect(liveObs.contains(e.observationId), isTrue,
          reason: 'orphan evidence ${e.id}');
      expect(
        store.bundle!.scans.any((s) => s.id == e.scanId),
        isTrue,
        reason: 'evidence ${e.id} points at missing scan',
      );
    }
    for (final ev in store.bundle!.events) {
      expect(liveObs.contains(ev.observationId), isTrue,
          reason: 'orphan event ${ev.id}');
    }
    // Baseline evidence bytes still present.
    for (final id in baselineEvIds) {
      expect(await store.evidenceBytes(id), isNotNull);
    }
  });

  test('PR1.5 new report id after baseline creates second scan', () async {
    final store = PropertyMemoryStore.instance;
    await store.applyFromSavedReport(_guidedReport(id: 'r_base'));
    expect(store.bundle!.scans.length, 1);

    await store.applyFromSavedReport(
      _guidedReport(
        id: 'r_checkin',
        issues: [
          _issue(title: 'Peeling paint on siding', location: 'Front siding'),
        ],
      ).copyWithCreatedAt(DateTime.utc(2026, 9, 20)),
    );

    expect(store.bundle!.scans.length, 2);
    expect(store.bundle!.scans.first.sourceSavedReportId, 'r_base');
    expect(store.bundle!.scans.last.sourceSavedReportId, 'r_checkin');
    expect(store.bundle!.scans.last.mode, ScanMode.checkIn);
    expect(store.property?.lastCheckInScanId, store.bundle!.scans.last.id);
  });

  test('PR1.5 forgetReport removes only that report scan; baseline remains',
      () async {
    final store = PropertyMemoryStore.instance;
    await store.applyFromSavedReport(_guidedReport(id: 'r_base'));
    final baselineScanId = store.property!.baselineScanId;
    final baseEvIds = [for (final e in store.bundle!.evidence) e.id];

    await store.applyFromSavedReport(
      _guidedReport(
        id: 'r_later',
        issues: [
          _issue(title: 'Peeling paint on siding', location: 'Front siding'),
        ],
      ).copyWithCreatedAt(DateTime.utc(2026, 9, 20)),
    );
    expect(store.bundle!.scans.length, 2);
    final laterEvIds = [
      for (final e in store.bundle!.evidence)
        if (e.scanId == store.bundle!.scans.last.id) e.id,
    ];

    await store.forgetReport('r_later');

    expect(store.bundle!.scans.length, 1);
    expect(store.bundle!.scans.single.sourceSavedReportId, 'r_base');
    expect(store.property!.baselineScanId, baselineScanId);
    expect(store.property!.lastCheckInScanId, isNull);
    for (final id in laterEvIds) {
      expect(await store.evidenceBytes(id), isNull);
    }
    // Baseline evidence bytes still present.
    for (final id in baseEvIds) {
      expect(await store.evidenceBytes(id), isNotNull);
    }
  });

  test('PR1.5 wipeAll clears PM bundle and evidence', () async {
    final store = PropertyMemoryStore.instance;
    await store.applyFromSavedReport(_guidedReport(id: 'r_wipe'));
    final evId = store.bundle!.evidence.single.id;
    expect(await store.evidenceBytes(evId), isNotNull);

    await store.wipeAll();

    expect(store.bundle, isNull);
    expect(store.property, isNull);
    expect(store.hasLoadFailed, isFalse);
    expect(await store.evidenceBytes(evId), isNull);
  });

  test('PR1.5 corrupt bundle → hasLoadFailed; apply does not overwrite',
      () async {
    final store = PropertyMemoryStore.instance;
    await store.ensureLoaded();
    final box = Hive.box<dynamic>(PropertyMemoryStore.boxName);
    await box.put(PropertyMemoryStore.bundleKey, '{not-valid-json');

    store.debugDetachBox();
    await store.ensureLoaded();

    expect(store.hasLoadFailed, isTrue);
    expect(store.bundle, isNull);

    await store.applyFromSavedReport(_guidedReport(id: 'r_corrupt'));

    expect(store.hasLoadFailed, isTrue);
    expect(store.bundle, isNull);
  });
}

extension on SavedReport {
  SavedReport copyWithCreatedAt(DateTime at) => SavedReport(
        id: id,
        createdAt: at,
        report: report,
        photos: photos,
      );
}
