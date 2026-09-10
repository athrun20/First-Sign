import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:pillar_ai/config/property_memory_flags.dart';
import 'package:pillar_ai/models/analysis_models.dart';
import 'package:pillar_ai/models/capture_models.dart';
import 'package:pillar_ai/models/property_memory_enums.dart';
import 'package:pillar_ai/models/property_memory_models.dart';
import 'package:pillar_ai/models/saved_report.dart';
import 'package:pillar_ai/services/home_insight.dart';
import 'package:pillar_ai/services/home_read_adapter.dart';
import 'package:pillar_ai/services/property_memory_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';

AnalysisIssue _issue({
  required String title,
  String severity = 'Medium',
  String location = 'Front elevation siding',
}) {
  return AnalysisIssue(
    title: title,
    location: location,
    severity: severity,
    cost: r'$400',
    confidence: 80,
    insight: 'Visible cue from photos.',
    photoIndex: 0,
    sourcePhotoLabel: location,
  );
}

SavedPhoto _photo(int index, CaptureShotId slot) {
  return SavedPhoto(
    index: index,
    label: slot.name,
    slotId: slot,
    bytes: Uint8List.fromList(List.generate(16, (i) => index + i)),
  );
}

SavedReport _report({
  String id = 'report_1',
  int score = 72,
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
      overallScore: score,
      conditionLabel: 'Mixed',
      issues: issues ??
          [
            _issue(title: 'Peeling paint on siding', severity: 'Medium'),
          ],
      estimatedRepairRange: r'$500',
      analysisSource: 'test',
      photoCount: photos.length,
    ),
    photos: photos,
  );
}

PmObservation _obs({
  required String id,
  required String title,
  required SeverityBand severity,
  DateTime? lastSeenAt,
  bool dismissed = false,
  ObservationStatus status = ObservationStatus.fresh,
}) {
  final at = lastSeenAt ?? DateTime.utc(2026, 9, 1, 12);
  return PmObservation(
    id: id,
    propertyId: 'property_local_1',
    surfaceId: 'surface_siding',
    surfaceType: SurfaceType.siding,
    title: title,
    category: ObservationCategory.wear,
    severityBand: severity,
    status: status,
    confidence: ConfidenceBand.medium,
    firstSeenScanId: 'scan_1',
    firstSeenAt: at,
    lastSeenScanId: 'scan_1',
    lastSeenAt: at,
    userDismissed: dismissed,
  );
}

PmPropertyMemoryBundle _bundle({
  PropertyLifecycleState lifecycle = PropertyLifecycleState.active,
  String? baselineScanId = 'scan_1',
  OverallConditionSignal signal = OverallConditionSignal.stable,
  bool meetsCoverage = true,
  List<PmObservation> observations = const [],
}) {
  final now = DateTime.utc(2026, 9, 1, 12);
  return PmPropertyMemoryBundle(
    property: PmProperty(
      id: 'property_local_1',
      displayName: 'My home',
      lifecycleState: lifecycle,
      baselineScanId: baselineScanId,
      baselineEstablishedAt: baselineScanId == null ? null : now,
      overallConditionSignal: signal,
      openObservationCount: observations
          .where(
            (o) => !o.userDismissed && o.status != ObservationStatus.resolved,
          )
          .length,
      createdAt: now,
      updatedAt: now,
    ),
    scans: [
      PmScan(
        id: 'scan_1',
        propertyId: 'property_local_1',
        mode: ScanMode.baseline,
        capturedAt: now,
        processingStatus: ScanProcessingStatus.complete,
        coverageReport: PmCoverageReport(
          meetsBaselineMinimum: meetsCoverage,
          photoCount: 4,
        ),
      ),
    ],
    observations: observations,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PropertyMemoryFlags.setEnabled(false);
    HomeReadAdapter.debugSetFlagCache(false);
    tempDir = await Directory.systemTemp.createTemp('pm_home_hive_');
    Hive.init(tempDir.path);
    PropertyMemoryStore.instance.debugDetachBox();
    await PropertyMemoryStore.instance.ensureLoaded();
    await PropertyMemoryStore.instance.debugReset();
  });

  tearDown(() async {
    HomeReadAdapter.debugSetFlagCache(null);
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

  test('1. Flag off + SavedReport → fromPropertyMemory false; whatMatters == latestInsightLine',
      () {
    final report = _report();
    final summary = HomeReadAdapter.compose(
      flagEnabled: false,
      latestReport: report,
      pmLoaded: true,
      pmLoadFailed: false,
      bundle: null,
    );
    expect(summary.fromPropertyMemory, isFalse);
    expect(summary.whatMattersLine, latestInsightLine(report.report));
    expect(summary.reassuranceLine, homeReassuranceLine(report.report));
    expect(summary.companionNote, firstSignAiCompanionNote(report.report));
    expect(summary.score, report.score);
    expect(summary.latestReport, same(report));
  });

  test('2. Flag on + empty PM + report → fallback', () {
    final report = _report();
    final summary = HomeReadAdapter.compose(
      flagEnabled: true,
      latestReport: report,
      pmLoaded: true,
      pmLoadFailed: false,
      bundle: null,
    );
    expect(summary.fromPropertyMemory, isFalse);
    expect(summary.whatMattersLine, latestInsightLine(report.report));
  });

  test('3. Flag on + hasLoadFailed → fallback', () async {
    await PropertyMemoryFlags.setEnabled(true);
    final store = PropertyMemoryStore.instance;
    await store.ensureLoaded();
    final box = Hive.box<dynamic>(PropertyMemoryStore.boxName);
    await box.put(PropertyMemoryStore.bundleKey, '{not-valid-json');
    store.debugDetachBox();
    await store.ensureLoaded();
    expect(store.hasLoadFailed, isTrue);

    final report = _report();
    final summary = HomeReadAdapter.compose(
      flagEnabled: true,
      latestReport: report,
      pmLoaded: store.isLoaded,
      pmLoadFailed: store.hasLoadFailed,
      bundle: store.bundle,
    );
    expect(summary.fromPropertyMemory, isFalse);
    expect(summary.whatMattersLine, latestInsightLine(report.report));
  });

  test('4. Flag on + active PM + urgent open obs → PM owns whatMatters; score from report',
      () {
    // Report finding differs from PM top observation so ownership is obvious.
    final report = _report(
      score: 61,
      issues: [_issue(title: 'Peeling paint on siding', severity: 'Medium')],
    );
    final bundle = _bundle(
      signal: OverallConditionSignal.urgentAttention,
      observations: [
        _obs(
          id: 'obs_urgent',
          title: 'Possible roof edge damage',
          severity: SeverityBand.urgent,
          lastSeenAt: DateTime.utc(2026, 9, 2),
        ),
        _obs(
          id: 'obs_watch',
          title: 'Minor siding stain',
          severity: SeverityBand.watch,
          lastSeenAt: DateTime.utc(2026, 9, 3),
        ),
      ],
    );

    final summary = HomeReadAdapter.compose(
      flagEnabled: true,
      latestReport: report,
      pmLoaded: true,
      pmLoadFailed: false,
      bundle: bundle,
    );

    expect(summary.fromPropertyMemory, isTrue);
    expect(summary.whatMattersLine, isNot(latestInsightLine(report.report)));
    expect(summary.whatMattersLine.toLowerCase(), contains('roof edge damage'));
    expect(summary.whatMattersLine, contains('closer look soon'));
    expect(summary.score, 61);
    expect(summary.latestReport, same(report));
    expect(summary.openObservationCount, 2);
    expect(summary.reassuranceLine, 'Worth a closer look soon');
  });

  test('5. Flag on + active PM + zero open obs + stable → calm whatMatters; not incompleteCoverage healthy',
      () {
    final report = _report(score: 90, issues: const []);
    final bundle = _bundle(
      signal: OverallConditionSignal.stable,
      observations: const [],
    );
    final summary = HomeReadAdapter.compose(
      flagEnabled: true,
      latestReport: report,
      pmLoaded: true,
      pmLoadFailed: false,
      bundle: bundle,
    );
    expect(summary.fromPropertyMemory, isTrue);
    expect(
      summary.whatMattersLine,
      'No open exterior items to track right now.',
    );
    expect(summary.reassuranceLine, 'Your home looks healthy');
    // incompleteCoverage must never yield healthy via authoritative path
    final incomplete = HomeReadAdapter.compose(
      flagEnabled: true,
      latestReport: report,
      pmLoaded: true,
      pmLoadFailed: false,
      bundle: _bundle(
        signal: OverallConditionSignal.incompleteCoverage,
        // Force non-authoritative via coverage gate:
        meetsCoverage: false,
      ),
    );
    expect(incomplete.fromPropertyMemory, isFalse);
    // Non-authoritative → SavedReport path (may still say healthy from score);
    // PM must not own the summary when coverage is inadequate.
  });

  test('6. Flag on + baselineIncomplete (or draft) → fromPropertyMemory false',
      () {
    final report = _report();
    for (final life in [
      PropertyLifecycleState.baselineIncomplete,
      PropertyLifecycleState.draft,
    ]) {
      final summary = HomeReadAdapter.compose(
        flagEnabled: true,
        latestReport: report,
        pmLoaded: true,
        pmLoadFailed: false,
        bundle: _bundle(
          lifecycle: life,
          baselineScanId: null,
          signal: OverallConditionSignal.incompleteCoverage,
          meetsCoverage: false,
          observations: [
            _obs(
              id: 'obs_x',
              title: 'Stain on wall',
              severity: SeverityBand.attention,
            ),
          ],
        ),
      );
      expect(summary.fromPropertyMemory, isFalse, reason: '$life');
      expect(summary.whatMattersLine, latestInsightLine(report.report));
    }
  });

  test('7. Never healthy-only-from-zero-obs without active baseline', () {
    final report = _report(score: 95, issues: const []);
    final incompleteEmpty = HomeReadAdapter.compose(
      flagEnabled: true,
      latestReport: report,
      pmLoaded: true,
      pmLoadFailed: false,
      bundle: _bundle(
        lifecycle: PropertyLifecycleState.baselineIncomplete,
        baselineScanId: null,
        signal: OverallConditionSignal.incompleteCoverage,
        meetsCoverage: false,
        observations: const [],
      ),
    );
    expect(incompleteEmpty.fromPropertyMemory, isFalse);
    // Fallback uses SavedReport path — empty issues + high score may say healthy,
    // but must NOT be PM-owned healthy-from-zero-obs.
    expect(incompleteEmpty.fromPropertyMemory, isFalse);

    // Active without baselineScanId is also non-authoritative.
    final activeNoBaseline = HomeReadAdapter.compose(
      flagEnabled: true,
      latestReport: report,
      pmLoaded: true,
      pmLoadFailed: false,
      bundle: _bundle(
        lifecycle: PropertyLifecycleState.active,
        baselineScanId: null,
        signal: OverallConditionSignal.stable,
        observations: const [],
      ),
    );
    expect(activeNoBaseline.fromPropertyMemory, isFalse);

    // Zero open + incompleteCoverage signal even if somehow active: coverage false
    // keeps non-authoritative; if we ignore coverage by empty scans... we always
    // have a scan in helper. Explicit: authoritative empty + incompleteCoverage
    // should not say healthy.
    final forced = HomeReadAdapter.compose(
      flagEnabled: true,
      latestReport: report,
      pmLoaded: true,
      pmLoadFailed: false,
      bundle: _bundle(
        signal: OverallConditionSignal.incompleteCoverage,
        meetsCoverage: true,
        observations: const [],
      ),
    );
    // Authoritative by gate (active+baseline+coverage) but incompleteCoverage
    // reassurance must not claim healthy.
    expect(forced.fromPropertyMemory, isTrue);
    expect(forced.reassuranceLine.toLowerCase(), isNot(contains('healthy')));
    expect(
      forced.whatMattersLine.toLowerCase(),
      isNot(contains('healthy')),
    );
  });
}
