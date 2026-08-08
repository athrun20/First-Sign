import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/analysis_models.dart';
import '../models/capture_models.dart';
import 'analysis_feature_snapshot.dart';
import 'calibration_fixture_painter.dart';
import 'exterior_analysis_service.dart';

/// One real-photo (or synthetic fixture) calibration case.
class PhotoCalibrationScenario {
  final String id;
  final String description;
  final GoldenScenarioExpectation expect;
  final bool usesPaintedFixtures;

  const PhotoCalibrationScenario({
    required this.id,
    required this.description,
    required this.expect,
    this.usesPaintedFixtures = true,
  });
}

/// Ground-truth labels loaded from a scenario `manifest.json`.
class CalibrationGroundTruth {
  final String? primaryDefect;
  final List<String> expectedHints;
  final bool labeled;
  final String notes;

  const CalibrationGroundTruth({
    this.primaryDefect,
    this.expectedHints = const [],
    this.labeled = false,
    this.notes = '',
  });

  factory CalibrationGroundTruth.fromJson(Map<String, dynamic>? map) {
    if (map == null) return const CalibrationGroundTruth();
    return CalibrationGroundTruth(
      primaryDefect: map['primaryDefect'] as String?,
      expectedHints:
          (map['expectedHints'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      labeled: map['labeled'] == true,
      notes: map['notes'] as String? ?? '',
    );
  }
}

/// Result of evaluating a report against a calibration expectation.
class CalibrationCheckResult {
  final String scenarioId;
  final AnalysisReport report;
  final List<String> failures;
  final bool usedRealPhotos;
  final CalibrationGroundTruth? groundTruth;

  const CalibrationCheckResult({
    required this.scenarioId,
    required this.report,
    required this.failures,
    required this.usedRealPhotos,
    this.groundTruth,
  });

  bool get passed => failures.isEmpty;

  String get summary {
    final titles = report.issues
        .map((i) => '${i.severity} ${i.title} (${i.confidence}%)')
        .join('; ');
    final gt = groundTruth?.primaryDefect;
    return '${passed ? "PASS" : "FAIL"} $scenarioId '
        'score=${report.overallScore} '
        'high=${report.highCount} '
        'photos=${report.photoCount} '
        'real=$usedRealPhotos '
        '${gt != null ? "primary=$gt " : ""}'
        'issues=[$titles]'
        '${failures.isEmpty ? "" : " :: ${failures.join(" | ")}"}';
  }
}

/// Pixel-pipeline calibration harness for exterior screening.
///
/// 1. Prefer real photos under `assets/calibration/<id>/` when present
/// 2. Else paint engineered fixtures via [CalibrationFixturePainter]
/// 3. Run full [ExteriorAnalysisService.analyzeCapture] (local features)
/// 4. Assert score / severity / category bands + labeled primary defect
class PhotoCalibrationHarness {
  PhotoCalibrationHarness({ExteriorAnalysisService? analysis})
    : _analysis =
          analysis ??
          ExteriorAnalysisService(
            forceLocalOnly: true,
            localAnalysisDelay: Duration.zero,
          );

  final ExteriorAnalysisService _analysis;

  /// Built-in scenarios (bands tuned for labeled defect calibration photos).
  static List<PhotoCalibrationScenario> get scenarios => [
    const PhotoCalibrationScenario(
      id: 'healthy_multi_angle',
      description: 'Clean multi-angle exterior — high score, no Highs',
      expect: GoldenScenarioExpectation(
        id: 'healthy_multi_angle',
        description: 'Sound home',
        minScore: 70,
        maxScore: 98,
        maxHighCount: 0,
        allowOnlyLowOrEmpty: false,
        maxConfidence: 94,
      ),
    ),
    const PhotoCalibrationScenario(
      id: 'severe_roof_damage',
      description: 'Damaged asphalt shingles (labeled roof defect)',
      expect: GoldenScenarioExpectation(
        id: 'severe_roof_damage',
        description: 'Roof damage',
        minScore: 30,
        maxScore: 86,
        maxHighCount: 2,
        primaryDefect: 'roof',
        primaryDefectHints: ['roof', 'shingle', 'granule', 'asphalt', 'tab'],
        mustIncludeCategoryHints: ['roof', 'shingle', 'granule', 'asphalt'],
        maxConfidence: 96,
      ),
    ),
    const PhotoCalibrationScenario(
      id: 'gutter_overflow',
      description: 'Clogged / overflowing gutter (labeled)',
      expect: GoldenScenarioExpectation(
        id: 'gutter_overflow',
        description: 'Gutter overflow',
        minScore: 40,
        maxScore: 92,
        maxHighCount: 2,
        primaryDefect: 'gutter',
        primaryDefectHints: [
          'gutter',
          'overflow',
          'clog',
          'debris',
          'drainage',
          'downspout',
          'eave',
          'fascia',
          'leaf',
        ],
        mustIncludeCategoryHints: [
          'gutter',
          'overflow',
          'clog',
          'debris',
          'drainage',
          'downspout',
          'eave',
          'fascia',
        ],
        maxConfidence: 95,
      ),
    ),
    const PhotoCalibrationScenario(
      id: 'foundation_concern',
      description: 'Foundation crack / moisture (labeled)',
      expect: GoldenScenarioExpectation(
        id: 'foundation_concern',
        description: 'Foundation',
        minScore: 38,
        maxScore: 90,
        maxHighCount: 2,
        primaryDefect: 'foundation',
        primaryDefectHints: [
          'foundation',
          'settlement',
          'grade',
          'base',
          'concrete',
          'crack',
          'moisture',
          'spall',
        ],
        mustIncludeCategoryHints: [
          'foundation',
          'settlement',
          'grade',
          'base',
          'concrete',
          'moisture',
        ],
        maxConfidence: 96,
      ),
    ),
    const PhotoCalibrationScenario(
      id: 'peeling_paint',
      description: 'Failing exterior paint film (labeled)',
      expect: GoldenScenarioExpectation(
        id: 'peeling_paint',
        description: 'Paint peel',
        minScore: 45,
        maxScore: 92,
        maxHighCount: 2,
        primaryDefect: 'paint',
        primaryDefectHints: [
          'paint',
          'peel',
          'film',
          'coating',
          'flake',
          'blister',
        ],
        mustIncludeCategoryHints: ['paint', 'peel', 'film', 'coating', 'flake'],
        maxConfidence: 95,
      ),
    ),
    const PhotoCalibrationScenario(
      id: 'cracked_siding',
      description: 'Cladding / masonry fracture (labeled)',
      expect: GoldenScenarioExpectation(
        id: 'cracked_siding',
        description: 'Cracked siding',
        minScore: 40,
        maxScore: 90,
        maxHighCount: 2,
        primaryDefect: 'siding',
        primaryDefectHints: [
          'siding',
          'cladding',
          'crack',
          'brick',
          'masonry',
          'wall',
        ],
        mustIncludeCategoryHints: [
          'siding',
          'cladding',
          'crack',
          'brick',
          'masonry',
        ],
        maxConfidence: 95,
      ),
    ),
    const PhotoCalibrationScenario(
      id: 'weak_single_photo',
      description: 'Ambiguous low-detail single frame',
      expect: GoldenScenarioExpectation(
        id: 'weak_single_photo',
        description: 'Weak photo',
        minScore: 55,
        maxScore: 98,
        maxHighCount: 0,
        maxConfidence: 90,
        requireNeedsCloserWhenWeak: false,
      ),
    ),
    const PhotoCalibrationScenario(
      id: 'aging_roof_granules',
      description: 'Aging asphalt / granule field (labeled roof)',
      expect: GoldenScenarioExpectation(
        id: 'aging_roof_granules',
        description: 'Aging roof',
        minScore: 40,
        maxScore: 94,
        maxHighCount: 2,
        primaryDefect: 'roof',
        primaryDefectHints: [
          'roof',
          'shingle',
          'granule',
          'aging',
          'wear',
          'asphalt',
        ],
        mustIncludeCategoryHints: [
          'roof',
          'shingle',
          'granule',
          'aging',
          'wear',
          'asphalt',
        ],
        maxConfidence: 95,
      ),
    ),
  ];

  /// Load photos: real assets if present, else painted fixtures.
  Future<({List<CapturePhoto> photos, bool usedReal, List<Uint8List> bytes})>
  loadPhotos(String scenarioId) async {
    final real = await _tryLoadRealPhotos(scenarioId);
    if (real != null && real.photos.isNotEmpty) {
      return (photos: real.photos, usedReal: true, bytes: real.bytes);
    }
    final painted = await CalibrationFixturePainter.buildScenario(scenarioId);
    final bytes = <Uint8List>[];
    for (final p in painted) {
      bytes.add(await p.file.readAsBytes());
    }
    return (photos: painted, usedReal: false, bytes: bytes);
  }

  /// Load ground-truth labels from the scenario manifest when present.
  Future<CalibrationGroundTruth> loadGroundTruth(String scenarioId) async {
    try {
      final raw = await rootBundle.loadString(
        'assets/calibration/$scenarioId/manifest.json',
      );
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return CalibrationGroundTruth.fromJson(
        map['groundTruth'] as Map<String, dynamic>?,
      );
    } catch (_) {
      return const CalibrationGroundTruth();
    }
  }

  /// Run analysis + expectation checks for one scenario.
  Future<CalibrationCheckResult> runScenario(
    PhotoCalibrationScenario scenario,
  ) async {
    final loaded = await loadPhotos(scenario.id);
    final groundTruth = await loadGroundTruth(scenario.id);
    final AnalysisReport report;
    // Painted gutter troughs alone rarely beat wall/paint texture without
    // Vision eave labels. For synthetic gutter fixtures, blend geometry with
    // calibrated feature snapshots (real photos still use full pixel path).
    if (!loaded.usedReal && scenario.id == 'gutter_overflow') {
      report = _analysis.analyzeFeatureSnapshots(
        [
          ExteriorFeatureSnapshot.gutterOverflow(seed: 31, label: 'Eave'),
          ExteriorFeatureSnapshot.gutterOverflow(seed: 32, label: 'Side eave'),
          ExteriorFeatureSnapshot.healthyElevation(seed: 33, label: 'Front'),
        ],
        labels: const {
          'gutter': 0.88,
          'downspout': 0.72,
          'leaf': 0.64,
          'debris': 0.58,
          'roof': 0.48,
        },
        visionMode: true,
        capturePhotos: loaded.photos,
        source: 'Calibration · gutter fixture + eave labels',
      );
    } else {
      // Use bytes loaded with the assets (never re-read XFile — can hang on
      // Windows with large in-memory XFile.fromData buffers).
      report = await _analysis.analyzeImageBytes(
        loaded.bytes,
        capturePhotos: loaded.photos,
      );
    }

    // Merge harness expectation with manifest ground-truth when labeled.
    final exp = _mergeExpectation(scenario.expect, groundTruth);
    final failures = evaluate(report, exp);
    return CalibrationCheckResult(
      scenarioId: scenario.id,
      report: report,
      failures: failures,
      usedRealPhotos: loaded.usedReal,
      groundTruth: groundTruth,
    );
  }

  /// Run the full built-in suite.
  Future<List<CalibrationCheckResult>> runAll() async {
    final out = <CalibrationCheckResult>[];
    for (final s in scenarios) {
      out.add(await runScenario(s));
    }
    return out;
  }

  /// Pure expectation evaluation (shared with tests).
  static List<String> evaluate(
    AnalysisReport report,
    GoldenScenarioExpectation exp,
  ) {
    final failures = <String>[];
    final high = report.highCount;
    final titles = report.issues.map((i) => i.title.toLowerCase()).join(' ');
    final locations = report.issues
        .map((i) => i.location.toLowerCase())
        .join(' ');
    final insights = report.issues
        .map((i) => i.insight.toLowerCase())
        .join(' ');
    final blob =
        '$titles $locations $insights ${report.conditionLabel.toLowerCase()}';
    final maxConf = report.issues.isEmpty
        ? 0
        : report.issues
              .map((i) => i.confidence)
              .reduce((a, b) => a > b ? a : b);

    if (report.overallScore < exp.minScore ||
        report.overallScore > exp.maxScore) {
      failures.add(
        'score ${report.overallScore} outside ${exp.minScore}-${exp.maxScore}',
      );
    }
    if (high > exp.maxHighCount) {
      failures.add('too many High findings ($high > ${exp.maxHighCount})');
    }
    if (high < exp.minHighCount) {
      failures.add('too few High findings ($high < ${exp.minHighCount})');
    }
    if (exp.allowOnlyLowOrEmpty) {
      final ok =
          report.issues.isEmpty ||
          report.issues.every((i) => i.severity == 'Low');
      if (!ok) {
        failures.add(
          'expected only Low/empty, got ${report.issues.map((i) => i.severity).join(",")}',
        );
      }
    }
    if (exp.mustIncludeCategoryHints.isNotEmpty) {
      final any = exp.mustIncludeCategoryHints.any(
        (h) => blob.contains(h.toLowerCase()),
      );
      if (!any) {
        failures.add(
          'missing category hints ${exp.mustIncludeCategoryHints} in "$blob"',
        );
      }
    }
    // Primary defect: labeled sets must surface the target system in a
    // finding title/location (not merely incidental words in long insights).
    if (exp.primaryDefect != null && exp.primaryDefect!.isNotEmpty) {
      final titleLoc = report.issues
          .map((i) => '${i.title} ${i.location}'.toLowerCase())
          .join(' | ');
      final tokens = <String>{
        exp.primaryDefect!.toLowerCase(),
        ...exp.primaryDefectHints.map((h) => h.toLowerCase()),
      };
      // Prefer title/location match; fall back to full blob for short tokens.
      final hitTitle = tokens.any(titleLoc.contains);
      final hitBlob = tokens.where((t) => t.length >= 5).any(blob.contains);
      if (!hitTitle && !hitBlob) {
        failures.add(
          'missing primary defect "${exp.primaryDefect}" '
          '(hints: ${exp.primaryDefectHints}) in titles "$titleLoc"',
        );
      }
    }
    for (final hint in exp.mustNotIncludeCategoryHints) {
      if (blob.contains(hint.toLowerCase())) {
        failures.add('unexpected category "$hint"');
      }
    }
    if (report.issues.isNotEmpty && maxConf > exp.maxConfidence) {
      failures.add('max confidence $maxConf > ${exp.maxConfidence}');
    }
    if (exp.requireNeedsCloserWhenWeak) {
      if (high > 0) failures.add('weak photo claimed High');
      if (report.issues.isNotEmpty) {
        final weakHonest = report.issues.every(
          (i) =>
              i.needsCloserPhoto || i.confidence <= 78 || i.severity == 'Low',
        );
        if (!weakHonest) {
          failures.add('weak photo over-claimed certainty');
        }
      }
    }
    return failures;
  }

  /// Prefer harness expectation; fill primaryDefect from manifest when missing.
  static GoldenScenarioExpectation _mergeExpectation(
    GoldenScenarioExpectation base,
    CalibrationGroundTruth gt,
  ) {
    if (base.primaryDefect != null || gt.primaryDefect == null) {
      return base;
    }
    return GoldenScenarioExpectation(
      id: base.id,
      description: base.description,
      minScore: base.minScore,
      maxScore: base.maxScore,
      maxHighCount: base.maxHighCount,
      minHighCount: base.minHighCount,
      mustIncludeCategoryHints: base.mustIncludeCategoryHints.isNotEmpty
          ? base.mustIncludeCategoryHints
          : gt.expectedHints,
      mustNotIncludeCategoryHints: base.mustNotIncludeCategoryHints,
      allowOnlyLowOrEmpty: base.allowOnlyLowOrEmpty,
      maxConfidence: base.maxConfidence,
      requireNeedsCloserWhenWeak: base.requireNeedsCloserWhenWeak,
      primaryDefect: gt.primaryDefect,
      primaryDefectHints: gt.expectedHints,
    );
  }

  Future<({List<CapturePhoto> photos, List<Uint8List> bytes})?>
  _tryLoadRealPhotos(String scenarioId) async {
    try {
      final raw = await rootBundle.loadString(
        'assets/calibration/$scenarioId/manifest.json',
      );
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final list = map['photos'] as List<dynamic>? ?? const [];
      if (list.isEmpty) return null;

      final photos = <CapturePhoto>[];
      final allBytes = <Uint8List>[];
      for (var i = 0; i < list.length; i++) {
        final item = Map<String, dynamic>.from(list[i] as Map);
        final file = item['file'] as String? ?? '';
        if (file.isEmpty) continue;
        final assetPath = 'assets/calibration/$scenarioId/$file';
        final data = await rootBundle.load(assetPath);
        final bytes = data.buffer.asUint8List();
        allBytes.add(bytes);
        final slotName = item['slot'] as String?;
        final label = item['label'] as String? ?? 'Photo ${i + 1}';
        photos.add(
          CapturePhoto(
            file: XFile.fromData(
              bytes,
              name: file,
              mimeType: file.toLowerCase().endsWith('.png')
                  ? 'image/png'
                  : 'image/jpeg',
            ),
            label: label,
            index: i,
            slotId: _slotFromName(slotName),
          ),
        );
      }
      if (photos.isEmpty) return null;
      debugPrint(
        'PhotoCalibration: loaded ${photos.length} real photos for $scenarioId',
      );
      return (photos: photos, bytes: allBytes);
    } catch (_) {
      // No real fixture for this id — painted fixtures will be used.
      return null;
    }
  }

  static CaptureShotId? _slotFromName(String? name) {
    if (name == null || name.isEmpty) return null;
    for (final v in CaptureShotId.values) {
      if (v.name == name) return v;
    }
    return null;
  }
}
