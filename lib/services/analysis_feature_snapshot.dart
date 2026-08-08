/// Deterministic exterior photo feature profiles used for analysis calibration
/// and golden-set regression tests.
///
/// These are not neural embeddings — they mirror the multi-feature signals the
/// local analysis pipeline extracts from photos so we can tune detection /
/// scoring without shipping large binary fixtures.
class ExteriorFeatureSnapshot {
  final double brightness;
  final double contrast;
  final double edgeDensity;
  final double topEdgeDensity;
  final double midEdgeDensity;
  final double botEdgeDensity;
  final double horizontalBanding;
  final double verticalBanding;
  final double greenDominance;
  final double greyDominance;
  final double rustDominance;
  final double darkPatchRatio;
  final double darkTopBias;
  final double lowerThirdDark;
  final double midToneDominance;
  final double highLuminanceVariance;
  final double vegetationNear;
  final double roofSignal;
  final double wallSignal;
  final double foundationSignal;
  final double overallDistress;
  final double crackLineScore;
  final double peelingScore;
  final double moistureStainScore;
  final double gutterLineScore;
  final bool highTextureChaos;
  final int hashSeed;
  final String label;

  const ExteriorFeatureSnapshot({
    required this.brightness,
    required this.contrast,
    required this.edgeDensity,
    required this.topEdgeDensity,
    required this.midEdgeDensity,
    required this.botEdgeDensity,
    required this.horizontalBanding,
    required this.verticalBanding,
    required this.greenDominance,
    required this.greyDominance,
    required this.rustDominance,
    required this.darkPatchRatio,
    required this.darkTopBias,
    required this.lowerThirdDark,
    required this.midToneDominance,
    required this.highLuminanceVariance,
    required this.vegetationNear,
    required this.roofSignal,
    required this.wallSignal,
    required this.foundationSignal,
    required this.overallDistress,
    required this.crackLineScore,
    required this.peelingScore,
    required this.moistureStainScore,
    required this.gutterLineScore,
    required this.highTextureChaos,
    required this.hashSeed,
    this.label = '',
  });

  bool get roofLikely => roofSignal > 0.34;
  bool get wallLikely => wallSignal > 0.34;
  bool get foundationLikely => foundationSignal > 0.32;

  // ---------------------------------------------------------------------------
  // Golden profiles (calibrated against typical exterior photo patterns)
  // ---------------------------------------------------------------------------

  /// Clean multi-angle elevation: sound materials, low distress.
  factory ExteriorFeatureSnapshot.healthyElevation({
    int seed = 11,
    String label = 'healthy elevation',
  }) {
    return ExteriorFeatureSnapshot(
      brightness: 142,
      contrast: 28,
      edgeDensity: 0.11,
      topEdgeDensity: 0.10,
      midEdgeDensity: 0.12,
      botEdgeDensity: 0.10,
      horizontalBanding: 0.18,
      verticalBanding: 0.22,
      greenDominance: 0.06,
      greyDominance: 0.18,
      rustDominance: 0.02,
      darkPatchRatio: 0.06,
      darkTopBias: 0.14,
      lowerThirdDark: 0.12,
      midToneDominance: 0.55,
      highLuminanceVariance: 0.22,
      vegetationNear: 0.08,
      roofSignal: 0.36,
      wallSignal: 0.48,
      foundationSignal: 0.30,
      overallDistress: 0.16,
      crackLineScore: 0.10,
      peelingScore: 0.08,
      moistureStainScore: 0.07,
      gutterLineScore: 0.20,
      highTextureChaos: false,
      hashSeed: seed,
      label: label,
    );
  }

  /// Roof close-up / upper plane with missing tabs / impact chaos.
  factory ExteriorFeatureSnapshot.damagedRoof({
    int seed = 21,
    String label = 'damaged roof',
  }) {
    return ExteriorFeatureSnapshot(
      brightness: 98,
      contrast: 62,
      edgeDensity: 0.28,
      topEdgeDensity: 0.34,
      midEdgeDensity: 0.16,
      botEdgeDensity: 0.10,
      horizontalBanding: 0.32,
      verticalBanding: 0.14,
      greenDominance: 0.03,
      greyDominance: 0.42,
      rustDominance: 0.04,
      darkPatchRatio: 0.28,
      darkTopBias: 0.52,
      lowerThirdDark: 0.10,
      midToneDominance: 0.38,
      highLuminanceVariance: 0.78,
      vegetationNear: 0.04,
      roofSignal: 0.78,
      wallSignal: 0.18,
      foundationSignal: 0.12,
      overallDistress: 0.58,
      crackLineScore: 0.44,
      peelingScore: 0.12,
      moistureStainScore: 0.10,
      gutterLineScore: 0.22,
      highTextureChaos: true,
      hashSeed: seed,
      label: label,
    );
  }

  /// Mild roof aging / granule loss without catastrophic failure.
  factory ExteriorFeatureSnapshot.agingRoof({
    int seed = 22,
    String label = 'aging roof',
  }) {
    return ExteriorFeatureSnapshot(
      brightness: 118,
      contrast: 38,
      edgeDensity: 0.16,
      topEdgeDensity: 0.18,
      midEdgeDensity: 0.12,
      botEdgeDensity: 0.09,
      horizontalBanding: 0.24,
      verticalBanding: 0.12,
      greenDominance: 0.04,
      greyDominance: 0.40,
      rustDominance: 0.03,
      darkPatchRatio: 0.12,
      darkTopBias: 0.30,
      lowerThirdDark: 0.10,
      midToneDominance: 0.42,
      highLuminanceVariance: 0.42,
      vegetationNear: 0.05,
      roofSignal: 0.62,
      wallSignal: 0.22,
      foundationSignal: 0.14,
      overallDistress: 0.30,
      crackLineScore: 0.18,
      peelingScore: 0.08,
      moistureStainScore: 0.08,
      gutterLineScore: 0.24,
      highTextureChaos: false,
      hashSeed: seed,
      label: label,
    );
  }

  /// Eave line with debris / vegetation overflow risk.
  factory ExteriorFeatureSnapshot.gutterOverflow({
    int seed = 31,
    String label = 'gutter overflow',
  }) {
    return ExteriorFeatureSnapshot(
      brightness: 124,
      contrast: 40,
      edgeDensity: 0.18,
      topEdgeDensity: 0.22,
      midEdgeDensity: 0.16,
      botEdgeDensity: 0.12,
      horizontalBanding: 0.48,
      verticalBanding: 0.14,
      greenDominance: 0.22,
      greyDominance: 0.20,
      rustDominance: 0.05,
      darkPatchRatio: 0.18,
      darkTopBias: 0.20,
      lowerThirdDark: 0.16,
      midToneDominance: 0.48,
      highLuminanceVariance: 0.40,
      vegetationNear: 0.40,
      roofSignal: 0.40,
      wallSignal: 0.38,
      foundationSignal: 0.28,
      overallDistress: 0.34,
      crackLineScore: 0.14,
      peelingScore: 0.10,
      moistureStainScore: 0.18,
      gutterLineScore: 0.62,
      highTextureChaos: false,
      hashSeed: seed,
      label: label,
    );
  }

  /// Ground-level downspout / discharge pipes with wet soil near foundation.
  ///
  /// Intentionally weak eave/gutter line so analysis must not invent
  /// "clogged gutter at the roof edge" copy for pipe-at-grade photos.
  factory ExteriorFeatureSnapshot.groundDischarge({
    int seed = 71,
    String label = 'downspout discharge at grade',
  }) {
    return ExteriorFeatureSnapshot(
      brightness: 118,
      contrast: 44,
      edgeDensity: 0.16,
      topEdgeDensity: 0.08,
      midEdgeDensity: 0.12,
      botEdgeDensity: 0.28,
      horizontalBanding: 0.12,
      verticalBanding: 0.30,
      greenDominance: 0.10,
      greyDominance: 0.28,
      rustDominance: 0.04,
      darkPatchRatio: 0.22,
      darkTopBias: 0.08,
      lowerThirdDark: 0.58,
      midToneDominance: 0.42,
      highLuminanceVariance: 0.46,
      vegetationNear: 0.14,
      roofSignal: 0.12,
      wallSignal: 0.36,
      foundationSignal: 0.62,
      overallDistress: 0.32,
      crackLineScore: 0.12,
      peelingScore: 0.08,
      moistureStainScore: 0.42,
      gutterLineScore: 0.10,
      highTextureChaos: false,
      hashSeed: seed,
      label: label,
    );
  }

  /// Foundation / grade moisture or settlement cues.
  ///
  /// Includes clear lower-structure + linear crack support so golden tests
  /// still pass after the raised foundation false-positive bar.
  factory ExteriorFeatureSnapshot.foundationConcern({
    int seed = 41,
    String label = 'foundation concern',
  }) {
    return ExteriorFeatureSnapshot(
      brightness: 108,
      contrast: 50,
      edgeDensity: 0.22,
      topEdgeDensity: 0.10,
      midEdgeDensity: 0.16,
      botEdgeDensity: 0.32,
      horizontalBanding: 0.16,
      verticalBanding: 0.26,
      greenDominance: 0.08,
      greyDominance: 0.36,
      rustDominance: 0.03,
      darkPatchRatio: 0.26,
      darkTopBias: 0.10,
      lowerThirdDark: 0.60,
      midToneDominance: 0.40,
      highLuminanceVariance: 0.52,
      vegetationNear: 0.10,
      roofSignal: 0.16,
      wallSignal: 0.34,
      foundationSignal: 0.78,
      overallDistress: 0.46,
      crackLineScore: 0.56,
      peelingScore: 0.08,
      moistureStainScore: 0.38,
      gutterLineScore: 0.10,
      highTextureChaos: false,
      hashSeed: seed,
      label: label,
    );
  }

  /// Peeling paint / film failure on wall elevation.
  factory ExteriorFeatureSnapshot.peelingPaint({
    int seed = 51,
    String label = 'peeling paint',
  }) {
    return ExteriorFeatureSnapshot(
      brightness: 136,
      contrast: 56,
      edgeDensity: 0.22,
      topEdgeDensity: 0.12,
      midEdgeDensity: 0.24,
      botEdgeDensity: 0.14,
      horizontalBanding: 0.14,
      verticalBanding: 0.30,
      greenDominance: 0.05,
      greyDominance: 0.16,
      rustDominance: 0.02,
      darkPatchRatio: 0.10,
      darkTopBias: 0.12,
      lowerThirdDark: 0.14,
      midToneDominance: 0.52,
      highLuminanceVariance: 0.72,
      vegetationNear: 0.06,
      roofSignal: 0.22,
      wallSignal: 0.62,
      foundationSignal: 0.26,
      overallDistress: 0.38,
      crackLineScore: 0.16,
      peelingScore: 0.58,
      moistureStainScore: 0.12,
      gutterLineScore: 0.14,
      highTextureChaos: true,
      hashSeed: seed,
      label: label,
    );
  }

  /// Ambiguous / soft single-angle capture (should not over-claim).
  factory ExteriorFeatureSnapshot.weakAmbiguous({
    int seed = 61,
    String label = 'weak ambiguous',
  }) {
    return ExteriorFeatureSnapshot(
      brightness: 130,
      contrast: 22,
      edgeDensity: 0.08,
      topEdgeDensity: 0.07,
      midEdgeDensity: 0.08,
      botEdgeDensity: 0.07,
      horizontalBanding: 0.10,
      verticalBanding: 0.10,
      greenDominance: 0.10,
      greyDominance: 0.12,
      rustDominance: 0.02,
      darkPatchRatio: 0.08,
      darkTopBias: 0.12,
      lowerThirdDark: 0.12,
      midToneDominance: 0.45,
      highLuminanceVariance: 0.18,
      vegetationNear: 0.12,
      roofSignal: 0.24,
      wallSignal: 0.28,
      foundationSignal: 0.22,
      overallDistress: 0.18,
      crackLineScore: 0.08,
      peelingScore: 0.08,
      moistureStainScore: 0.08,
      gutterLineScore: 0.10,
      highTextureChaos: false,
      hashSeed: seed,
      label: label,
    );
  }

  /// Cracked siding / cladding damage.
  factory ExteriorFeatureSnapshot.crackedSiding({
    int seed = 71,
    String label = 'cracked siding',
  }) {
    return ExteriorFeatureSnapshot(
      brightness: 128,
      contrast: 54,
      edgeDensity: 0.26,
      topEdgeDensity: 0.14,
      midEdgeDensity: 0.30,
      botEdgeDensity: 0.16,
      horizontalBanding: 0.12,
      verticalBanding: 0.42,
      greenDominance: 0.04,
      greyDominance: 0.22,
      rustDominance: 0.02,
      darkPatchRatio: 0.14,
      darkTopBias: 0.12,
      lowerThirdDark: 0.18,
      midToneDominance: 0.50,
      highLuminanceVariance: 0.62,
      vegetationNear: 0.05,
      roofSignal: 0.20,
      wallSignal: 0.70,
      foundationSignal: 0.28,
      overallDistress: 0.46,
      crackLineScore: 0.56,
      peelingScore: 0.14,
      moistureStainScore: 0.16,
      gutterLineScore: 0.12,
      highTextureChaos: true,
      hashSeed: seed,
      label: label,
    );
  }

  /// Mismatched / patched siding (color-block replacement boards).
  ///
  /// High mid-wall luminance variance without crack-line geometry — e.g. white
  /// boards against weathered beige cladding.
  factory ExteriorFeatureSnapshot.mismatchedSiding({
    int seed = 91,
    String label = 'mismatched siding patch',
  }) {
    return ExteriorFeatureSnapshot(
      brightness: 136,
      contrast: 58,
      edgeDensity: 0.22,
      topEdgeDensity: 0.12,
      midEdgeDensity: 0.28,
      botEdgeDensity: 0.14,
      horizontalBanding: 0.16,
      verticalBanding: 0.30,
      greenDominance: 0.05,
      greyDominance: 0.18,
      rustDominance: 0.02,
      darkPatchRatio: 0.16,
      darkTopBias: 0.14,
      lowerThirdDark: 0.16,
      midToneDominance: 0.46,
      highLuminanceVariance: 0.72,
      vegetationNear: 0.06,
      roofSignal: 0.22,
      wallSignal: 0.74,
      foundationSignal: 0.24,
      overallDistress: 0.42,
      crackLineScore: 0.22,
      peelingScore: 0.18,
      moistureStainScore: 0.12,
      gutterLineScore: 0.12,
      highTextureChaos: false,
      hashSeed: seed,
      label: label,
    );
  }

  /// Exterior wall with heavy surface cable / wiring clutter.
  factory ExteriorFeatureSnapshot.exteriorWiringClutter({
    int seed = 101,
    String label = 'exterior cable clutter',
  }) {
    return ExteriorFeatureSnapshot(
      brightness: 130,
      contrast: 48,
      edgeDensity: 0.24,
      topEdgeDensity: 0.14,
      midEdgeDensity: 0.30,
      botEdgeDensity: 0.16,
      horizontalBanding: 0.14,
      verticalBanding: 0.46,
      greenDominance: 0.04,
      greyDominance: 0.20,
      rustDominance: 0.03,
      darkPatchRatio: 0.14,
      darkTopBias: 0.16,
      lowerThirdDark: 0.18,
      midToneDominance: 0.50,
      highLuminanceVariance: 0.48,
      vegetationNear: 0.05,
      roofSignal: 0.24,
      wallSignal: 0.68,
      foundationSignal: 0.26,
      overallDistress: 0.36,
      crackLineScore: 0.18,
      peelingScore: 0.12,
      moistureStainScore: 0.10,
      gutterLineScore: 0.12,
      highTextureChaos: false,
      hashSeed: seed,
      label: label,
    );
  }
}

/// Expected outcome band for a golden scenario (regression harness).
class GoldenScenarioExpectation {
  final String id;
  final String description;
  final int minScore;
  final String? primaryDefect;
  final List<String> primaryDefectHints;
  final int maxScore;
  final int maxHighCount;
  final int minHighCount;
  final List<String> mustIncludeCategoryHints;
  final List<String> mustNotIncludeCategoryHints;
  final bool allowOnlyLowOrEmpty;
  final int maxConfidence;
  final bool requireNeedsCloserWhenWeak;

  const GoldenScenarioExpectation({
    required this.id,
    required this.description,
    required this.minScore,
    required this.maxScore,
    this.maxHighCount = 3,
    this.minHighCount = 0,
    this.mustIncludeCategoryHints = const [],
    this.mustNotIncludeCategoryHints = const [],
    this.allowOnlyLowOrEmpty = false,
    this.maxConfidence = 97,
    this.requireNeedsCloserWhenWeak = false,
    this.primaryDefect,
    this.primaryDefectHints = const [],
  });
}

/// Named golden scenarios used to keep detection + scoring consistent.
class AnalysisGoldenSet {
  AnalysisGoldenSet._();

  static List<
    ({
      String id,
      List<ExteriorFeatureSnapshot> photos,
      Map<String, double> labels,
      GoldenScenarioExpectation expect,
    })
  >
  get scenarios => [
    (
      id: 'healthy_multi_angle',
      photos: [
        ExteriorFeatureSnapshot.healthyElevation(seed: 11, label: 'Front'),
        ExteriorFeatureSnapshot.healthyElevation(seed: 12, label: 'Left'),
        ExteriorFeatureSnapshot.healthyElevation(seed: 13, label: 'Right'),
        ExteriorFeatureSnapshot.healthyElevation(seed: 14, label: 'Rear'),
      ],
      labels: const {
        'house': 0.92,
        'building': 0.88,
        'siding': 0.70,
        'roof': 0.55,
        'window': 0.60,
      },
      expect: const GoldenScenarioExpectation(
        id: 'healthy_multi_angle',
        description: 'Sound home: high score, no High severity alarms',
        minScore: 88,
        maxScore: 98,
        maxHighCount: 0,
        allowOnlyLowOrEmpty: true,
        maxConfidence: 90,
      ),
    ),
    (
      id: 'severe_roof_damage',
      photos: [
        ExteriorFeatureSnapshot.damagedRoof(seed: 21, label: 'Roof'),
        ExteriorFeatureSnapshot.damagedRoof(seed: 22, label: 'Roof close-up'),
        ExteriorFeatureSnapshot.healthyElevation(seed: 23, label: 'Front'),
      ],
      labels: const {
        'roof': 0.94,
        'shingle': 0.88,
        'damage': 0.82,
        'asphalt': 0.70,
        'crack': 0.55,
      },
      expect: const GoldenScenarioExpectation(
        id: 'severe_roof_damage',
        description: 'Damaged roof corroborated across photos',
        minScore: 40,
        maxScore: 78,
        minHighCount: 0, // High preferred but strong Medium accepted
        maxHighCount: 2,
        mustIncludeCategoryHints: ['roof', 'shingle'],
        maxConfidence: 96,
      ),
    ),
    (
      id: 'gutter_overflow',
      photos: [
        ExteriorFeatureSnapshot.gutterOverflow(seed: 31, label: 'Eave'),
        ExteriorFeatureSnapshot.gutterOverflow(seed: 32, label: 'Side eave'),
        ExteriorFeatureSnapshot.healthyElevation(seed: 33, label: 'Front'),
      ],
      labels: const {
        'gutter': 0.86,
        'downspout': 0.70,
        'leaf': 0.62,
        'debris': 0.58,
        'roof': 0.50,
      },
      expect: const GoldenScenarioExpectation(
        id: 'gutter_overflow',
        description: 'Overflow risk without inventing foundation failure',
        minScore: 70,
        maxScore: 92,
        maxHighCount: 0,
        mustIncludeCategoryHints: ['gutter'],
        mustNotIncludeCategoryHints: [],
        maxConfidence: 94,
      ),
    ),
    (
      id: 'foundation_concern',
      photos: [
        ExteriorFeatureSnapshot.foundationConcern(seed: 41, label: 'Base'),
        ExteriorFeatureSnapshot.foundationConcern(seed: 42, label: 'Grade'),
        ExteriorFeatureSnapshot.healthyElevation(seed: 43, label: 'Front'),
      ],
      labels: const {
        'foundation': 0.80,
        'concrete': 0.72,
        'crack': 0.68,
        'wall': 0.55,
      },
      expect: const GoldenScenarioExpectation(
        id: 'foundation_concern',
        description: 'Foundation moisture / settlement screening note',
        minScore: 55,
        maxScore: 88,
        maxHighCount: 1,
        mustIncludeCategoryHints: ['foundation', 'settlement', 'grade', 'base'],
        maxConfidence: 94,
      ),
    ),
    (
      id: 'peeling_paint',
      photos: [
        ExteriorFeatureSnapshot.peelingPaint(seed: 51, label: 'Wall'),
        ExteriorFeatureSnapshot.peelingPaint(seed: 52, label: 'Elevation'),
      ],
      labels: const {'paint': 0.84, 'peel': 0.76, 'wall': 0.70, 'house': 0.80},
      expect: const GoldenScenarioExpectation(
        id: 'peeling_paint',
        description: 'Paint peel as Medium/Low, not false High roof',
        minScore: 72,
        maxScore: 94,
        maxHighCount: 0,
        mustIncludeCategoryHints: ['paint', 'peel', 'film', 'coating'],
        maxConfidence: 93,
      ),
    ),
    (
      id: 'cracked_siding',
      photos: [
        ExteriorFeatureSnapshot.crackedSiding(seed: 71, label: 'Wall'),
        ExteriorFeatureSnapshot.crackedSiding(seed: 72, label: 'Corner'),
        ExteriorFeatureSnapshot.healthyElevation(seed: 73, label: 'Front'),
      ],
      labels: const {
        'siding': 0.88,
        'crack': 0.80,
        'damage': 0.72,
        'wall': 0.78,
        'vinyl': 0.60,
      },
      expect: const GoldenScenarioExpectation(
        id: 'cracked_siding',
        description: 'Damaged cladding flagged consistently',
        minScore: 50,
        // Fewer false co-findings can raise overall score slightly.
        maxScore: 92,
        maxHighCount: 2,
        mustIncludeCategoryHints: ['siding', 'cladding', 'crack'],
        maxConfidence: 95,
      ),
    ),
    (
      id: 'weak_single_photo',
      photos: [
        ExteriorFeatureSnapshot.weakAmbiguous(seed: 61, label: 'Ambiguous'),
      ],
      labels: const {'house': 0.55, 'building': 0.48},
      expect: const GoldenScenarioExpectation(
        id: 'weak_single_photo',
        description: 'Weak evidence must not over-claim High certainty',
        minScore: 78,
        maxScore: 98,
        maxHighCount: 0,
        maxConfidence: 86,
        requireNeedsCloserWhenWeak: true,
      ),
    ),
    (
      id: 'aging_roof_granules',
      photos: [
        ExteriorFeatureSnapshot.agingRoof(seed: 81, label: 'Roof field'),
        ExteriorFeatureSnapshot.agingRoof(seed: 82, label: 'Slope'),
        ExteriorFeatureSnapshot.healthyElevation(seed: 83, label: 'Front'),
      ],
      labels: const {
        'roof': 0.88,
        'shingle': 0.80,
        'asphalt': 0.70,
        'worn': 0.45,
      },
      expect: const GoldenScenarioExpectation(
        id: 'aging_roof_granules',
        description: 'Aging roof is Medium planning item, not false Excellent',
        minScore: 72,
        maxScore: 92,
        maxHighCount: 0,
        mustIncludeCategoryHints: ['roof', 'shingle', 'granule'],
        maxConfidence: 93,
      ),
    ),
    (
      id: 'mismatched_siding',
      photos: [
        ExteriorFeatureSnapshot.mismatchedSiding(
          seed: 91,
          label: 'Front wall patch',
        ),
        ExteriorFeatureSnapshot.mismatchedSiding(
          seed: 92,
          label: 'Side elevation',
        ),
        ExteriorFeatureSnapshot.healthyElevation(seed: 93, label: 'Rear'),
      ],
      labels: const {
        'siding': 0.86,
        'house': 0.90,
        'wall': 0.78,
        'discoloration': 0.72,
        'patch': 0.68,
        'window': 0.55,
      },
      expect: const GoldenScenarioExpectation(
        id: 'mismatched_siding',
        description:
            'Obvious patched / mismatched cladding flagged as Medium, not missed',
        minScore: 62,
        maxScore: 92,
        maxHighCount: 1,
        mustIncludeCategoryHints: [
          'siding',
          'patch',
          'mismatched',
          'cladding',
        ],
        // Prefer not inventing roof/foundation from wall color blocks.
        mustNotIncludeCategoryHints: ['foundation crack', 'missing shingle'],
        maxConfidence: 95,
      ),
    ),
    (
      id: 'exterior_wiring_clutter',
      photos: [
        ExteriorFeatureSnapshot.exteriorWiringClutter(
          seed: 101,
          label: 'Wall cables',
        ),
        ExteriorFeatureSnapshot.exteriorWiringClutter(
          seed: 102,
          label: 'Side cables',
        ),
        ExteriorFeatureSnapshot.healthyElevation(seed: 103, label: 'Front'),
      ],
      labels: const {
        'house': 0.88,
        'siding': 0.74,
        'wall': 0.70,
        'cable': 0.82,
        'wiring': 0.78,
        'electrical': 0.60,
      },
      expect: const GoldenScenarioExpectation(
        id: 'exterior_wiring_clutter',
        description: 'Heavy exterior surface cable clutter is reported',
        minScore: 68,
        maxScore: 94,
        maxHighCount: 0,
        mustIncludeCategoryHints: ['wiring', 'cable'],
        maxConfidence: 95,
      ),
    ),
  ];
}
