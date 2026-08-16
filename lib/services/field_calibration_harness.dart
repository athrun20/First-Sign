import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/analysis_models.dart';
import '../models/capture_models.dart';
import 'exterior_analysis_service.dart';

/// Field-fixture scenario loaded from `assets/calibration/<id>/manifest.json`.
///
/// Schema (A1):
/// ```json
/// {
///   "id": "healthy_multi",
///   "title": "…",
///   "photos": [{ "file": "00_front.jpg", "slot": "front", "label": "…" }],
///   "expected": {
///     "maxFindings": 8,
///     "allowedCategories": ["paint", "roof", …],
///     "forbiddenCategories": ["foundation"],
///     "scoreMin": 55,
///     "scoreMax": 98,
///     "maxSeverity": "Medium",
///     "needsCloserPhotoOk": true
///   },
///   "notes": "…"
/// }
/// ```
class FieldCalibrationScenario {
  final String id;
  final String title;
  final List<FieldCalibrationPhoto> photos;
  final FieldCalibrationExpected expected;
  final String notes;
  final String assetDir;

  const FieldCalibrationScenario({
    required this.id,
    required this.title,
    required this.photos,
    required this.expected,
    this.notes = '',
    required this.assetDir,
  });

  bool get hasPhotos => photos.isNotEmpty;

  factory FieldCalibrationScenario.fromJson(
    Map<String, dynamic> map, {
    required String assetDir,
  }) {
    final id = (map['id'] as String? ?? '').trim();
    final photoList = (map['photos'] as List<dynamic>? ?? const [])
        .map((e) => FieldCalibrationPhoto.fromJson(
              Map<String, dynamic>.from(e as Map),
            ))
        .where((p) => p.file.isNotEmpty)
        .toList();
    final expectedMap = map['expected'] is Map
        ? Map<String, dynamic>.from(map['expected'] as Map)
        : <String, dynamic>{};
    return FieldCalibrationScenario(
      id: id.isNotEmpty ? id : assetDir.split('/').last,
      title: (map['title'] as String? ?? map['description'] as String? ?? id)
          .trim(),
      photos: photoList,
      expected: FieldCalibrationExpected.fromJson(expectedMap),
      notes: (map['notes'] as String? ?? '').trim(),
      assetDir: assetDir,
    );
  }
}

class FieldCalibrationPhoto {
  final String file;
  final String? slot;
  final String label;

  const FieldCalibrationPhoto({
    required this.file,
    this.slot,
    this.label = '',
  });

  factory FieldCalibrationPhoto.fromJson(Map<String, dynamic> map) {
    return FieldCalibrationPhoto(
      file: (map['file'] as String? ?? '').trim(),
      slot: (map['slot'] as String?)?.trim(),
      label: (map['label'] as String? ?? '').trim(),
    );
  }
}

/// Band checks for a field fixture (does not change analysis thresholds).
class FieldCalibrationExpected {
  final int maxFindings;
  final int minFindings;
  final List<String> allowedCategories;
  final List<String> forbiddenCategories;
  /// When non-empty, at least one finding must map to each listed category.
  final List<String> requiredCategories;
  final int scoreMin;
  final int scoreMax;
  final String maxSeverity;
  final bool needsCloserPhotoOk;
  /// When true, at least one finding must have [AnalysisIssue.needsCloserPhoto].
  final bool requireNeedsCloserPhoto;

  const FieldCalibrationExpected({
    this.maxFindings = 20,
    this.minFindings = 0,
    this.allowedCategories = const [],
    this.forbiddenCategories = const [],
    this.requiredCategories = const [],
    this.scoreMin = 0,
    this.scoreMax = 100,
    this.maxSeverity = 'High',
    this.needsCloserPhotoOk = true,
    this.requireNeedsCloserPhoto = false,
  });

  factory FieldCalibrationExpected.fromJson(Map<String, dynamic> map) {
    return FieldCalibrationExpected(
      maxFindings: (map['maxFindings'] as num?)?.toInt() ?? 20,
      minFindings: (map['minFindings'] as num?)?.toInt() ?? 0,
      allowedCategories: _stringList(map['allowedCategories']),
      forbiddenCategories: _stringList(map['forbiddenCategories']),
      requiredCategories: _stringList(map['requiredCategories']),
      scoreMin: (map['scoreMin'] as num?)?.toInt() ?? 0,
      scoreMax: (map['scoreMax'] as num?)?.toInt() ?? 100,
      maxSeverity: (map['maxSeverity'] as String? ?? 'High').trim(),
      needsCloserPhotoOk: map['needsCloserPhotoOk'] != false,
      requireNeedsCloserPhoto: map['requireNeedsCloserPhoto'] == true,
    );
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString().trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  int get maxSeverityRank => severityRank(maxSeverity);

  static int severityRank(String severity) {
    switch (severity.trim().toLowerCase()) {
      case 'high':
        return 3;
      case 'medium':
        return 2;
      case 'low':
        return 1;
      default:
        return 3;
    }
  }
}

/// Result of one field-fixture scenario run.
class FieldCalibrationResult {
  final String scenarioId;
  final String title;
  final AnalysisReport? report;
  final List<String> failures;
  final bool skipped;
  final String? skipReason;
  final int photoCount;

  const FieldCalibrationResult({
    required this.scenarioId,
    required this.title,
    this.report,
    this.failures = const [],
    this.skipped = false,
    this.skipReason,
    this.photoCount = 0,
  });

  bool get passed => !skipped && failures.isEmpty;

  String get summary {
    if (skipped) {
      return 'SKIP $scenarioId — ${skipReason ?? "no photos"}';
    }
    final r = report;
    if (r == null) {
      return 'FAIL $scenarioId — no report :: ${failures.join(" | ")}';
    }
    final cats = r.issues
        .map(FieldCalibrationHarness.inferCategory)
        .toSet()
        .join(',');
    final titles = r.issues
        .map((i) => '${i.severity}/${FieldCalibrationHarness.inferCategory(i)} ${i.title}')
        .join('; ');
    return '${passed ? "PASS" : "FAIL"} $scenarioId '
        'score=${r.overallScore} findings=${r.issues.length} '
        'photos=$photoCount cats=[$cats] issues=[$titles]'
        '${failures.isEmpty ? "" : " :: ${failures.join(" | ")}"}';
  }
}

/// Manifest-driven field fixture harness (local analysis only).
///
/// Discover scenarios by id under `assets/calibration/<id>/manifest.json`.
/// Missing manifests or empty photo sets are **skipped**, not failed.
class FieldCalibrationHarness {
  FieldCalibrationHarness({ExteriorAnalysisService? analysis})
      : _analysis = analysis ??
            ExteriorAnalysisService(
              forceLocalOnly: true,
              localAnalysisDelay: Duration.zero,
            );

  final ExteriorAnalysisService _analysis;

  /// Built-in field pack scenario folder names (A1).
  ///
  /// Add a new folder + manifest, then append the id here (and in pubspec).
  static const List<String> scenarioIds = [
    'healthy_multi',
    'paint_clear',
    'drainage_grade',
    'limited_dark',
    'mixed_ambiguous',
  ];

  /// Category keyword map (title/location/insight → category token).
  ///
  /// Findings do not store a structured category; this is harness-only labeling.
  static const Map<String, List<String>> categoryKeywords = {
    'roof': [
      'roof',
      'shingle',
      'granule',
      'asphalt',
      'tab',
      'ridge',
      'flashing',
    ],
    'paint': ['paint', 'peel', 'film', 'coating', 'flake', 'blister', 'chalk'],
    'siding': [
      'siding',
      'cladding',
      'clapboard',
      'vinyl',
      'masonry',
      'brick',
      'stucco',
    ],
    'gutter': [
      'gutter',
      'downspout',
      'eave',
      'fascia',
      'overflow',
      'clog',
      'debris',
    ],
    'drainage': [
      'drainage',
      'dumping',
      'pooling',
      'runoff',
      'splash',
      'outlet',
      'flood',
      'downspout',
      'at grade',
    ],
    'foundation': [
      'foundation',
      'settlement',
      'base',
      'concrete',
      'crawl',
      'footing',
      'spall',
    ],
    'window': ['window', 'glazing', 'sill', 'caulk', 'seal'],
    'vegetation': ['vegetation', 'vine', 'tree', 'plant', 'bush', 'moss'],
    'wiring': ['wiring', 'cable', 'electrical', 'conduit'],
    'chimney': ['chimney', 'flue', 'chase'],
    'rust': ['rust', 'corrosion', 'oxid'],
    'general': ['general', 'exterior', 'surface', 'weathering'],
  };

  /// Infer a single primary category for a finding (harness only).
  ///
  /// Title is checked first so a clear "Peeling paint" label is not stolen by
  /// incidental words like "grade" in a long insight string.
  static String inferCategory(AnalysisIssue issue) {
    const order = [
      'roof',
      'paint',
      'siding',
      'gutter',
      'foundation',
      'drainage',
      'window',
      'chimney',
      'wiring',
      'vegetation',
      'rust',
      'general',
    ];
    final title = issue.title.toLowerCase();
    // Explicit ground-outlet title wins over the word "foundation" alone.
    if (title.contains('dumping near foundation') ||
        title.contains('ground outlets') ||
        (title.contains('drainage') && title.contains('check'))) {
      return 'drainage';
    }
    for (final cat in order) {
      final keys = categoryKeywords[cat] ?? const [];
      for (final k in keys) {
        if (title.contains(k)) return cat;
      }
    }
    final blob =
        '${issue.location} ${issue.insight}'.toLowerCase();
    for (final cat in order) {
      final keys = categoryKeywords[cat] ?? const [];
      for (final k in keys) {
        if (blob.contains(k)) return cat;
      }
    }
    return 'general';
  }

  /// Load one scenario manifest (null if missing/invalid).
  Future<FieldCalibrationScenario?> loadScenario(String scenarioId) async {
    final assetDir = 'assets/calibration/$scenarioId';
    try {
      final raw = await rootBundle.loadString('$assetDir/manifest.json');
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return FieldCalibrationScenario.fromJson(map, assetDir: assetDir);
    } catch (e) {
      debugPrint('FieldCalibration: no manifest for $scenarioId ($e)');
      return null;
    }
  }

  /// Load photo bytes listed in the scenario. Returns empty if none load.
  Future<({List<CapturePhoto> photos, List<Uint8List> bytes})> loadPhotos(
    FieldCalibrationScenario scenario,
  ) async {
    final photos = <CapturePhoto>[];
    final bytes = <Uint8List>[];
    for (var i = 0; i < scenario.photos.length; i++) {
      final item = scenario.photos[i];
      final assetPath = '${scenario.assetDir}/${item.file}';
      try {
        final data = await rootBundle.load(assetPath);
        final b = data.buffer.asUint8List();
        if (b.isEmpty) continue;
        bytes.add(b);
        final label = item.label.isNotEmpty ? item.label : 'Photo ${i + 1}';
        photos.add(
          CapturePhoto(
            file: XFile.fromData(
              b,
              name: item.file,
              mimeType: item.file.toLowerCase().endsWith('.png')
                  ? 'image/png'
                  : 'image/jpeg',
            ),
            label: label,
            index: i,
            slotId: _slotFromName(item.slot),
          ),
        );
      } catch (e) {
        debugPrint('FieldCalibration: missing photo $assetPath ($e)');
      }
    }
    return (photos: photos, bytes: bytes);
  }

  /// Run one scenario: skip if no photos; else analyze + assert expected bands.
  Future<FieldCalibrationResult> runScenario(String scenarioId) async {
    final scenario = await loadScenario(scenarioId);
    if (scenario == null) {
      return FieldCalibrationResult(
        scenarioId: scenarioId,
        title: scenarioId,
        skipped: true,
        skipReason: 'manifest missing or unreadable',
      );
    }
    if (!scenario.hasPhotos) {
      return FieldCalibrationResult(
        scenarioId: scenario.id,
        title: scenario.title,
        skipped: true,
        skipReason: 'photos[] empty — drop real images and update manifest',
      );
    }

    final loaded = await loadPhotos(scenario);
    if (loaded.photos.isEmpty || loaded.bytes.isEmpty) {
      return FieldCalibrationResult(
        scenarioId: scenario.id,
        title: scenario.title,
        skipped: true,
        skipReason: 'no photo files loaded (placeholder folder)',
        photoCount: 0,
      );
    }

    final report = await _analysis.analyzeImageBytes(
      loaded.bytes,
      capturePhotos: loaded.photos,
    );
    final failures = evaluate(report, scenario.expected);
    return FieldCalibrationResult(
      scenarioId: scenario.id,
      title: scenario.title,
      report: report,
      failures: failures,
      photoCount: loaded.photos.length,
    );
  }

  Future<List<FieldCalibrationResult>> runAll({
    List<String>? ids,
  }) async {
    final list = ids ?? scenarioIds;
    final out = <FieldCalibrationResult>[];
    for (final id in list) {
      out.add(await runScenario(id));
    }
    return out;
  }

  /// Pure evaluation against [FieldCalibrationExpected].
  static List<String> evaluate(
    AnalysisReport report,
    FieldCalibrationExpected exp,
  ) {
    final failures = <String>[];

    if (report.issues.length > exp.maxFindings) {
      failures.add(
        'finding count ${report.issues.length} > maxFindings ${exp.maxFindings}',
      );
    }
    if (report.issues.length < exp.minFindings) {
      failures.add(
        'finding count ${report.issues.length} < minFindings ${exp.minFindings}',
      );
    }

    if (report.overallScore < exp.scoreMin ||
        report.overallScore > exp.scoreMax) {
      failures.add(
        'score ${report.overallScore} outside ${exp.scoreMin}-${exp.scoreMax}',
      );
    }

    final maxRank = exp.maxSeverityRank;
    for (final issue in report.issues) {
      final rank = FieldCalibrationExpected.severityRank(issue.severity);
      if (rank > maxRank) {
        failures.add(
          'severity ${issue.severity} exceeds maxSeverity ${exp.maxSeverity} '
          '(${issue.title})',
        );
      }
      if (!exp.needsCloserPhotoOk && issue.needsCloserPhoto) {
        failures.add(
          'needsCloserPhoto not allowed (${issue.title})',
        );
      }
    }

    if (exp.requireNeedsCloserPhoto &&
        !report.issues.any((i) => i.needsCloserPhoto)) {
      failures.add('requireNeedsCloserPhoto but no finding has needsCloserPhoto');
    }

    final categories = report.issues.map(inferCategory).toList();
    final forbidden = exp.forbiddenCategories.map((c) => c.toLowerCase()).toSet();
    for (final cat in categories) {
      if (forbidden.contains(cat)) {
        failures.add('forbidden category "$cat" present');
      }
    }

    // allowedCategories: when non-empty, every inferred category must be listed
    // (or "general" which is always permitted as residual).
    final allowed = exp.allowedCategories.map((c) => c.toLowerCase()).toSet();
    if (allowed.isNotEmpty) {
      for (final cat in categories) {
        if (cat == 'general') continue;
        if (!allowed.contains(cat)) {
          failures.add(
            'category "$cat" not in allowedCategories ${exp.allowedCategories}',
          );
        }
      }
    }

    // requiredCategories: each listed category must appear at least once.
    final required =
        exp.requiredCategories.map((c) => c.toLowerCase()).toSet();
    if (required.isNotEmpty) {
      final present = categories.map((c) => c.toLowerCase()).toSet();
      for (final cat in required) {
        if (!present.contains(cat)) {
          failures.add(
            'required category "$cat" missing (have: ${categories.join(", ")})',
          );
        }
      }
    }

    return failures;
  }

  static CaptureShotId? _slotFromName(String? name) {
    if (name == null || name.isEmpty) return null;
    for (final v in CaptureShotId.values) {
      if (v.name == name) return v;
    }
    return null;
  }
}
