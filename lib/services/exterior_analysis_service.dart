import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../models/analysis_models.dart';
import '../models/capture_models.dart';
import 'analysis_feature_snapshot.dart';
import 'finding_retake_service.dart';

/// Analyzes homeowner exterior photos via Google Cloud Vision when a key is
/// provided, otherwise uses an on-device multi-feature pipeline.
///
/// Pass the key at build/run time (any of these defines work):
/// ```bash
/// # Preferred: formspree.env.json (gitignored) — see docs/VISION_API_SETUP.md
/// flutter run -d windows --dart-define-from-file=formspree.env.json
/// flutter run --dart-define=GOOGLE_VISION_API_KEY=your_key
/// flutter run --dart-define=GCV_API_KEY=your_key
/// flutter run --dart-define=VISION_API_KEY=your_key
/// ```
///
/// Or inject at construction: `ExteriorAnalysisService(visionApiKey: key)`.
///
/// Credibility notes:
/// - Findings are an **AI-assisted exterior screening**, not a licensed inspection.
/// - Confidence is capped and demoted when evidence is thin or single-angle.
/// - Golden-set scenarios in [AnalysisGoldenSet] keep score/severity bands stable.
/// - When Vision is available it is the **primary** path; local multi-feature is
///   the graceful fallback (no key, forced local, or Vision request failure).
class ExteriorAnalysisService {
  ExteriorAnalysisService({
    String? visionApiKey,
    http.Client? client,
    this.localAnalysisDelay = const Duration(milliseconds: 650),
    this.forceLocalOnly = false,
  }) : visionApiKey = resolveVisionApiKey(visionApiKey) {
    // Lazy HTTP client: avoid constructing Client outside a test binding zone.
    _httpClient = client;
  }

  final String visionApiKey;
  http.Client? _httpClient;

  /// Lazily create HTTP client so constructing the service in tests does not
  /// require a binding-zone HttpClient.
  http.Client get _http => _httpClient ??= http.Client();

  /// Artificial pause for the local pipeline (UI feedback). Tests should use
  /// [Duration.zero].
  final Duration localAnalysisDelay;

  /// When true, never call Google Vision (calibration / offline).
  final bool forceLocalOnly;

  bool get hasVisionKey => !forceLocalOnly && visionApiKey.isNotEmpty;

  /// Resolve a usable API key from an override or compile-time dart-defines.
  ///
  /// Strips surrounding quotes/whitespace so pasted keys still work.
  static String resolveVisionApiKey([String? override]) {
    if (override != null) {
      final s = _sanitizeApiKey(override);
      if (s.isNotEmpty) return s;
    }
    // Compile-time defines (preferred for Flutter mobile/web/desktop).
    const candidates = <String>[
      String.fromEnvironment('GOOGLE_VISION_API_KEY'),
      String.fromEnvironment('GCV_API_KEY'),
      String.fromEnvironment('VISION_API_KEY'),
    ];
    for (final raw in candidates) {
      final s = _sanitizeApiKey(raw);
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static String _sanitizeApiKey(String raw) {
    var k = raw.trim();
    if (k.isEmpty) return '';
    if ((k.startsWith('"') && k.endsWith('"')) ||
        (k.startsWith("'") && k.endsWith("'"))) {
      k = k.substring(1, k.length - 1).trim();
    }
    // Reject obvious placeholders so we fall back to local cleanly.
    final lower = k.toLowerCase();
    if (lower == 'your_key' ||
        lower == 'your_key_here' ||
        lower == 'null' ||
        lower == 'undefined' ||
        lower == 'none' ||
        lower == 'todo' ||
        lower.contains('replace_me') ||
        lower.contains('paste_') ||
        lower.startsWith('your_')) {
      return '';
    }
    return k;
  }

  // ── Vision label trust filters ───────────────────────────────────────────

  /// Person / portrait labels — a face photo is never exterior evidence.
  static const List<String> _personNeedles = [
    'person',
    'people',
    'human',
    'face',
    'selfie',
    'portrait',
    'headshot',
    'mugshot',
    'man',
    'woman',
    'child',
    'crowd',
  ];

  /// Labels that strongly indicate the photo is *not* a home exterior.
  /// Kitchen / indoor appliance scenes must never mint roof/siding findings.
  static const List<String> _nonExteriorNeedles = [
    'person',
    'people',
    'human',
    'face',
    'selfie',
    'portrait',
    'headshot',
    'man',
    'woman',
    'child',
    'crowd',
    'indoor',
    'interior',
    'inside',
    'room',
    'kitchen',
    'bedroom',
    'bathroom',
    'living room',
    'livingroom',
    'dining room',
    'diningroom',
    'family room',
    'office',
    'hallway',
    'corridor',
    'closet',
    'pantry',
    'laundry',
    'basement rec',
    'furniture',
    'sofa',
    'couch',
    'chair',
    'table',
    'desk',
    'bed',
    'cabinet',
    'cupboard',
    'drawer',
    'countertop',
    'counter top',
    'counter',
    'backsplash',
    'stove',
    'oven',
    'range hood',
    'cooktop',
    'range',
    'microwave',
    'dishwasher',
    'appliance',
    'faucet',
    'sink',
    'kitchen island',
    'refrigerator',
    'fridge',
    'freezer',
    'toaster',
    'blender',
    'coffee maker',
    'coffee machine',
    'washer',
    'dryer',
    'toilet',
    'shower',
    'bathtub',
    'bath tub',
    'mirror',
    'curtain',
    'blinds',
    'carpet',
    'rug',
    'flooring',
    'hardwood floor',
    'tile floor',
    'ceiling fan',
    'chandelier',
    'light fixture',
    'television',
    'tv screen',
    'laptop',
    'computer',
    'monitor',
    'keyboard',
    'phone',
    'mobile phone',
    'smartphone',
    'tablet',
    'food',
    'meal',
    'plate',
    'utensil',
    'restaurant',
    'grocery',
    'supermarket',
    'dog',
    'cat',
    'pet',
    'animal',
    'clothing',
    'fashion',
    'screenshot',
    'document',
    'text',
    'book',
    'cartoon',
    'artwork',
    'painting',
    'poster',
    'product',
    'packaging',
    'car interior',
    'dashboard',
    'steering wheel',
    'shelf',
    'bookshelf',
    'wardrobe',
    'dresser',
    'nightstand',
  ];

  /// Hard indoor-room / appliance needles — any moderate hit is enough to
  /// reject when true exterior envelope structure is absent.
  static const List<String> _hardIndoorRoomNeedles = [
    'kitchen',
    'bedroom',
    'bathroom',
    'living room',
    'livingroom',
    'dining room',
    'diningroom',
    'laundry',
    'pantry',
    'closet',
    'hallway',
    'stove',
    'oven',
    'cooktop',
    'microwave',
    'dishwasher',
    'refrigerator',
    'fridge',
    'cabinet',
    'countertop',
    'counter top',
    'backsplash',
    'toilet',
    'shower',
    'bathtub',
    'appliance',
  ];

  /// Roof / siding / gutter / foundation — not a generic house behind a person.
  static const List<String> _exteriorSystemNeedles = [
    'roof',
    'rooftop',
    'shingle',
    'tile roof',
    'ridge',
    'eave',
    'eaves',
    'chimney',
    'flashing',
    'skylight',
    'gutter',
    'downspout',
    'soffit',
    'fascia',
    'siding',
    'cladding',
    'brick',
    'brickwork',
    'masonry',
    'stucco',
    'vinyl siding',
    'facade',
    'façade',
    'foundation',
    'crawlspace',
  ];

  /// True exterior envelope structure (not indoor walls/paint/tile/windows).
  static const List<String> _exteriorStructureNeedles = [
    'roof',
    'rooftop',
    'shingle',
    'tile roof',
    'ridge',
    'eave',
    'eaves',
    'chimney',
    'flashing',
    'skylight',
    'gutter',
    'downspout',
    'soffit',
    'fascia',
    'siding',
    'cladding',
    'brick',
    'brickwork',
    'masonry',
    'stucco',
    'vinyl siding',
    'facade',
    'façade',
    'foundation',
    'crawlspace',
    'house',
    'home',
    'building',
    'property',
    'residential',
    'exterior',
  ];

  /// Exterior systems / distress cues we keep from Vision.
  /// Avoid bare "tile", "board", "drain", "wall" — they mint indoor FPs.
  static const List<String> _exteriorRelevantNeedles = [
    'roof',
    'rooftop',
    'shingle',
    'asphalt shingle',
    'asphalt roof',
    'tile roof',
    'ridge',
    'eave',
    'eaves',
    'chimney',
    'flashing',
    'skylight',
    'gutter',
    'downspout',
    'rain gutter',
    'soffit',
    'fascia',
    'siding',
    'cladding',
    'brick',
    'brickwork',
    'masonry',
    'stucco',
    'vinyl siding',
    'facade',
    'façade',
    'exterior',
    'house',
    'home',
    'building',
    'property',
    'residential',
    'peeling paint',
    'peeling',
    'flaking',
    'weathered',
    'foundation',
    'crawlspace',
    'settlement',
    'sidewalk',
    'driveway',
    'grade',
    'window',
    'door',
    'caulk',
    'vegetation',
    'vine',
    'ivy',
    'shrub',
    'moss',
    'algae',
    'leaf',
    'leaves',
    'tree against',
    'damage',
    'broken',
    'crack',
    'decay',
    'rot',
    'rust',
    'corrosion',
    'discoloration',
    'leak',
    'debris',
    'worn',
    'hail',
    'storm damage',
    'missing shingle',
    'rust stain',
    'clapboard',
    'plywood',
    'cable',
    'wire',
    'wiring',
    'electrical',
    'conduit',
    'power line',
    'utility line',
  ];

  /// Match label [key] to [needle] without reverse-containment traps
  /// (e.g. bare "tile" must NOT match "tile roof").
  static bool _needleHit(String key, String needle) {
    if (key.isEmpty || needle.isEmpty) return false;
    if (key == needle) return true;
    // Key mentions the needle (Vision often returns longer phrases).
    if (key.contains(needle)) return true;
    // Multi-word needle: allow key to be a substantial token of the phrase
    // only when the key is long enough to avoid short false stems.
    if (needle.contains(' ') &&
        key.length >= 5 &&
        needle.split(RegExp(r'\s+')).contains(key)) {
      return true;
    }
    return false;
  }

  static bool _anyNeedle(String key, List<String> needles) =>
      needles.any((n) => _needleHit(key, n));

  /// Person/face tokens as whole words — do not match "surface" via "face".
  static bool _personLabelHit(String key) {
    for (final n in _personNeedles) {
      if (key == n) return true;
      if (key.startsWith('$n ') ||
          key.endsWith(' $n') ||
          key.contains(' $n ')) {
        return true;
      }
    }
    return false;
  }

  static bool _portraitTypeLabelHit(String key) {
    const types = ['selfie', 'portrait', 'headshot', 'mugshot'];
    for (final n in types) {
      if (key == n) return true;
      if (key.startsWith('$n ') ||
          key.endsWith(' $n') ||
          key.contains(' $n ')) {
        return true;
      }
    }
    return false;
  }

  static bool _faceLabelHit(String key) {
    return key == 'face' ||
        key.startsWith('face ') ||
        key.endsWith(' face') ||
        key.contains(' face ');
  }

  /// Roof / siding / gutter / foundation — a house in the background is not enough.
  static bool isExteriorSystemLabel(String raw) {
    final key = raw.toLowerCase().trim();
    if (key.isEmpty) return false;
    return _anyNeedle(key, _exteriorSystemNeedles);
  }

  /// True exterior envelope structure label (gates indoor wall/paint/tile).
  static bool isExteriorStructureLabel(String raw) {
    final key = raw.toLowerCase().trim();
    if (key.isEmpty) return false;
    // Bare vinyl / concrete / paint are not enough structure on their own.
    if (key == 'vinyl' ||
        key == 'concrete' ||
        key == 'cement' ||
        key == 'paint' ||
        key == 'wall' ||
        key == 'window' ||
        key == 'door' ||
        key == 'tile' ||
        key == 'board' ||
        key == 'asphalt') {
      return false;
    }
    return _anyNeedle(key, _exteriorStructureNeedles);
  }

  /// True when a Vision label is clearly exterior-relevant (system or distress).
  static bool isExteriorRelevantLabel(String raw) {
    final key = raw.toLowerCase().trim();
    if (key.isEmpty) return false;
    // Bare ambiguous tokens — indoor kitchens/rooms share these constantly.
    if (key == 'wall' ||
        key == 'glass' ||
        key == 'plant' ||
        key == 'tree' ||
        key == 'tile' ||
        key == 'board' ||
        key == 'drain' ||
        key == 'paint' ||
        key == 'coating' ||
        key == 'concrete' ||
        key == 'cement' ||
        key == 'floor' ||
        key == 'flooring' ||
        key == 'asphalt' ||
        key == 'patch' ||
        key == 'repair' ||
        key == 'replacement' ||
        key == 'stain' ||
        key == 'seal' ||
        key == 'hole' ||
        key == 'mold' ||
        key == 'fungus') {
      return false;
    }
    if (key == 'basement') return true; // foundation-adjacent
    // Asphalt only as roof material language.
    if (key.contains('asphalt') &&
        (key.contains('shingle') ||
            key.contains('roof') ||
            key.contains('tile'))) {
      return true;
    }
    return _anyNeedle(key, _exteriorRelevantNeedles);
  }

  /// True when a Vision label points to people, indoor scenes, or random objects.
  static bool isNonExteriorLabel(String raw) {
    final key = raw.toLowerCase().trim();
    if (key.isEmpty) return false;
    // Bare "range" alone is ambiguous (mountain range vs appliance); require
    // kitchen/appliance context for short tokens handled elsewhere.
    if (key == 'range' || key == 'island' || key == 'counter') {
      // Still non-exterior when clearly appliance/kitchen compounds handled
      // by needles; bare forms are treated as non-exterior to prefer recall
      // of indoor rejection over inventing exterior damage.
      return true;
    }
    return _anyNeedle(key, _nonExteriorNeedles);
  }

  /// Keep only exterior-relevant scores (drops people / indoor / product noise).
  static Map<String, double> filterExteriorVisionLabels(
    Map<String, double> raw, {
    bool dropSceneIfNonExterior = true,
  }) {
    // When the scene is clearly indoor / people / product, drop everything —
    // do not keep a stray "building" or "window" that invents exterior work.
    // Mixed scans (portrait + roof) pass [dropSceneIfNonExterior] = false so
    // roof cues survive after per-frame / per-photo exclusion.
    if (dropSceneIfNonExterior && isClearlyNonExteriorScene(raw)) {
      return const {};
    }

    final out = <String, double>{};
    for (final e in raw.entries) {
      final key = e.key.toLowerCase().trim();
      final s = e.value.clamp(0.0, 1.0);
      if (key.isEmpty || s < 0.12) continue;
      if (isNonExteriorLabel(key)) continue;
      if (!isExteriorRelevantLabel(key) && !isExteriorStructureLabel(key)) {
        continue;
      }
      final prev = out[key] ?? 0;
      if (s > prev) out[key] = s;
    }
    return out;
  }

  /// Strong non-exterior signal without enough exterior structure evidence.
  ///
  /// Kitchen / indoor appliance / furniture / person-dominant photos must
  /// return true so callers emit the insufficient-exterior report path.
  static bool isClearlyNonExteriorScene(Map<String, double> rawLabels) {
    if (rawLabels.isEmpty) return false;

    var nonExt = 0.0;
    var exterior = 0.0;
    var nonExtMass = 0.0;
    var exteriorMass = 0.0;
    var nonExtCount = 0;
    var hardIndoor = 0.0;

    for (final e in rawLabels.entries) {
      final key = e.key.toLowerCase().trim();
      final s = e.value.clamp(0.0, 1.0);
      if (key.isEmpty || s < 0.12) continue;

      if (isNonExteriorLabel(key)) {
        nonExt = max(nonExt, s);
        nonExtMass += s;
        if (s >= 0.30) nonExtCount++;
      }
      if (_anyNeedle(key, _hardIndoorRoomNeedles)) {
        hardIndoor = max(hardIndoor, s);
      }
      // Only true exterior envelope structure counts against indoor rejection.
      if (isExteriorStructureLabel(key)) {
        exterior = max(exterior, s);
        exteriorMass += s;
      }
    }

    var person = 0.0;
    var personMass = 0.0;
    var face = 0.0;
    var portraitType = 0.0;
    var system = 0.0;
    for (final e in rawLabels.entries) {
      final key = e.key.toLowerCase().trim();
      final s = e.value.clamp(0.0, 1.0);
      if (key.isEmpty || s < 0.12) continue;
      if (_personLabelHit(key)) {
        person = max(person, s);
        personMass += s;
      }
      if (_faceLabelHit(key)) face = max(face, s);
      if (_portraitTypeLabelHit(key)) portraitType = max(portraitType, s);
      if (isExteriorSystemLabel(key)) system = max(system, s);
    }

    // Portrait / selfie / face — never treat as an exterior screening photo,
    // even if a house sits in the background. Generic house/building does
    // not defeat this gate; only a real roof/siding/gutter/foundation system.
    if (portraitType >= 0.40) return true;
    if (face >= 0.58 && person >= 0.42) return true;
    if (person >= 0.70 && system < 0.50) return true;
    if (person >= 0.78 && (face >= 0.40 || system < 0.55)) return true;
    if (person >= 0.55 && person + 0.08 >= system && system < 0.70) {
      return true;
    }
    if (person >= 0.42 && system < 0.52) return true;
    if (personMass >= 0.90 && system < 0.60) return true;

    // Hard indoor room / appliance with no real exterior envelope.
    if (hardIndoor >= 0.35 && exterior < 0.50) return true;
    if (hardIndoor >= 0.50 && exterior < 0.58) return true;

    // People / indoor rooms / products dominate and structure is weak.
    if (nonExt >= 0.40 && exterior < 0.42) return true;
    if (nonExt >= 0.52 && exterior < 0.50) return true;
    if (nonExt >= 0.68 && exterior < 0.58) return true;

    // Multiple indoor cues outweigh thin structure tags.
    if (nonExtCount >= 2 && nonExt >= 0.32 && exterior < 0.48) return true;
    if (nonExtMass >= 1.15 && exteriorMass < 0.55) return true;
    if (nonExtMass >= 0.90 && exterior < 0.36) return true;

    return false;
  }

  /// After expansion/filter: enough exterior structure to run detection.
  ///
  /// Indoor walls, paint, windows, concrete floors, and bare "tile" do **not**
  /// count — those were minting kitchen → roof false positives.
  static bool hasExteriorEvidence(Map<String, double> labels) {
    var structure = 0.0;
    for (final e in labels.entries) {
      final key = e.key.toLowerCase().trim();
      final s = e.value;
      if (isExteriorStructureLabel(key)) {
        structure = max(structure, s);
      }
    }
    // Higher bar so weak ambient tags don't invent a full exterior report.
    return structure >= 0.38;
  }

  /// Map finding category → Vision object names that can supply a box.
  /// Specific objects are listed first; large structure names last (fallback only).
  static List<String> visionObjectNeedlesForCategory(
    String category, {
    bool groundDrainage = false,
  }) {
    switch (category) {
      case 'roof':
        return const ['roof', 'chimney', 'building', 'house', 'home'];
      case 'chimney':
        return const ['chimney', 'roof', 'building', 'house', 'home'];
      case 'gutter':
      case 'fascia':
        // Ground outlets: prefer base/grade objects over roof-edge boxes.
        if (groundDrainage) {
          return const [
            'downspout',
            'pipe',
            'drain',
            'foundation',
            'concrete',
            'sidewalk',
            'wall',
            'house',
            'building',
            'home',
          ];
        }
        return const [
          'gutter',
          'downspout',
          'roof',
          'house',
          'building',
          'home',
        ];
      case 'siding':
      case 'paint':
        return const ['wall', 'brick', 'house', 'building', 'home'];
      case 'wiring':
        return const [
          'cable',
          'wire',
          'electrical',
          'wall',
          'house',
          'building',
          'home',
        ];
      case 'foundation':
        // Prefer grade-level objects before full house/building structure.
        return const [
          'foundation',
          'concrete',
          'sidewalk',
          'wall',
          'brick',
          'house',
          'building',
          'home',
        ];
      case 'window':
        return const ['window', 'door', 'house', 'building'];
      case 'vegetation':
        return const ['plant', 'tree', 'house', 'building'];
      case 'rust':
        return const ['vehicle', 'metal', 'house', 'building'];
      default:
        return const ['roof', 'window', 'house', 'building', 'home'];
    }
  }

  /// Large structure localizations — usable only when no specific object exists.
  static bool isLargeStructureObject(String name) {
    final n = name.toLowerCase().trim();
    return n == 'house' ||
        n == 'building' ||
        n == 'home' ||
        n == 'property' ||
        n == 'residential';
  }

  /// True when the object name is a specific match for the finding category.
  static bool isSpecificObjectForCategory(String name, String category) {
    final n = name.toLowerCase().trim();
    switch (category) {
      case 'window':
        return n.contains('window') || n == 'door';
      case 'roof':
        return n.contains('roof') || n.contains('shingle');
      case 'chimney':
        return n.contains('chimney');
      case 'gutter':
      case 'fascia':
        return n.contains('gutter') ||
            n.contains('downspout') ||
            n.contains('drain') ||
            n.contains('pipe') ||
            n.contains('eave') ||
            n.contains('fascia') ||
            n.contains('soffit');
      case 'foundation':
        return n.contains('foundation') ||
            n.contains('concrete') ||
            n.contains('sidewalk') ||
            n.contains('retaining') ||
            n.contains('wall') ||
            n.contains('brick');
      case 'vegetation':
        return n.contains('plant') || n.contains('tree') || n.contains('bush');
      case 'siding':
      case 'paint':
        return n.contains('wall') ||
            n.contains('brick') ||
            n.contains('siding');
      case 'wiring':
        return n.contains('cable') ||
            n.contains('wire') ||
            n.contains('electrical') ||
            n.contains('conduit');
      case 'rust':
        return n.contains('vehicle') ||
            n.contains('metal') ||
            n.contains('car');
      default:
        return !isLargeStructureObject(n);
    }
  }

  /// Parse Vision normalizedVertices into a clamped LTRB box (0–1).
  /// Public for unit tests.
  static ({double l, double t, double w, double h})? parseVisionBoundingBox(
    Map<String, dynamic> objectAnnotation,
  ) {
    final poly = objectAnnotation['boundingPoly'] as Map<String, dynamic>?;
    final verts =
        poly?['normalizedVertices'] as List<dynamic>? ??
        poly?['vertices'] as List<dynamic>?;
    if (verts == null || verts.isEmpty) return null;

    var minX = 1.0;
    var minY = 1.0;
    var maxX = 0.0;
    var maxY = 0.0;
    var any = false;
    for (final raw in verts) {
      final v = raw as Map<String, dynamic>;
      final x = (v['x'] as num?)?.toDouble();
      final y = (v['y'] as num?)?.toDouble();
      if (x == null || y == null) continue;
      // Non-normalized vertices (pixel) are rare with OBJECT_LOCALIZATION;
      // skip if clearly not 0–1 (caller should prefer normalizedVertices).
      if (x > 1.5 || y > 1.5) continue;
      any = true;
      minX = min(minX, x);
      minY = min(minY, y);
      maxX = max(maxX, x);
      maxY = max(maxY, y);
    }
    if (!any) return null;
    minX = minX.clamp(0.0, 1.0);
    minY = minY.clamp(0.0, 1.0);
    maxX = maxX.clamp(0.0, 1.0);
    maxY = maxY.clamp(0.0, 1.0);
    final w = (maxX - minX).clamp(0.0, 1.0);
    final h = (maxY - minY).clamp(0.0, 1.0);
    if (w < 0.04 || h < 0.04) return null;
    return (l: minX, t: minY, w: w, h: h);
  }

  /// Refine a structure box into a tighter band for the finding category.
  ///
  /// [objectIsExactMatch] true → keep the Vision poly, inset slightly (no grow).
  /// Structure boxes (house/building) are cropped to a precise system band.
  static ({double l, double t, double w, double h}) refineBoxForCategory(
    String category,
    double l,
    double t,
    double w,
    double h, {
    required bool objectIsExactMatch,
    bool groundDrainage = false,
  }) {
    // Real Vision object poly — inset only (never expand with padding).
    // Larger polys get a deeper inset so the surface highlight hugs the cue.
    if (objectIsExactMatch) {
      final area = w * h;
      final adaptiveInset = area > 0.35
          ? 0.065
          : area > 0.18
          ? 0.048
          : area > 0.08
          ? 0.032
          : 0.022;
      return _insetNormBox(l, t, w, h, inset: adaptiveInset, minSide: 0.032);
    }
    switch (category) {
      case 'roof':
        // Upper roof field — tight top band on structure (real phone elevations).
        return _padNormBox(
          l + w * 0.14,
          t + h * 0.02,
          w * 0.72,
          h * 0.15,
          pad: 0.0,
          minSide: 0.045,
          maxW: 0.62,
          maxH: 0.22,
        );
      case 'chimney':
        return _padNormBox(
          l + w * 0.62,
          t + h * 0.01,
          w * 0.24,
          h * 0.20,
          pad: 0.0,
          minSide: 0.04,
          maxW: 0.34,
          maxH: 0.26,
        );
      case 'gutter':
      case 'fascia':
        // Ground discharge: base strip (pipes / wet soil), not thin eave band.
        if (groundDrainage) {
          return _padNormBox(
            l + w * 0.12,
            t + h * 0.82,
            w * 0.76,
            h * 0.14,
            pad: 0.0,
            minSide: 0.035,
            maxW: 0.82,
            maxH: 0.18,
          );
        }
        // Thin eave strip at roof/wall junction.
        return _padNormBox(
          l + w * 0.06,
          t + h * 0.17,
          w * 0.88,
          h * 0.06,
          pad: 0.0,
          minSide: 0.03,
          maxW: 0.88,
          maxH: 0.09,
        );
      case 'foundation':
        // Grade / base strip only — bottom of structure.
        return _padNormBox(
          l + w * 0.12,
          t + h * 0.88,
          w * 0.76,
          h * 0.09,
          pad: 0.0,
          minSide: 0.035,
          maxW: 0.80,
          maxH: 0.13,
        );
      case 'siding':
      case 'paint':
        // Mid-wall face — compact vertical strip near the cue.
        return _padNormBox(
          l + w * 0.16,
          t + h * 0.36,
          w * 0.26,
          h * 0.30,
          pad: 0.0,
          minSide: 0.045,
          maxW: 0.38,
          maxH: 0.40,
        );
      case 'window':
        return _padNormBox(
          l + w * 0.34,
          t + h * 0.38,
          w * 0.26,
          h * 0.22,
          pad: 0.0,
          minSide: 0.045,
          maxW: 0.36,
          maxH: 0.30,
        );
      case 'vegetation':
        return _padNormBox(
          l + w * 0.02,
          t + h * 0.44,
          w * 0.20,
          h * 0.34,
          pad: 0.0,
          minSide: 0.04,
          maxW: 0.30,
          maxH: 0.44,
        );
      case 'rust':
        return _padNormBox(
          l + w * 0.22,
          t + h * 0.32,
          w * 0.24,
          h * 0.22,
          pad: 0.0,
          minSide: 0.04,
          maxW: 0.34,
          maxH: 0.30,
        );
      default:
        return _padNormBox(
          l + w * 0.16,
          t + h * 0.16,
          w * 0.44,
          h * 0.38,
          pad: 0.0,
          minSide: 0.045,
          maxW: 0.54,
          maxH: 0.44,
        );
    }
  }

  /// Shrink a Vision object box inward (prefer real localization, no bloating).
  static ({double l, double t, double w, double h}) _insetNormBox(
    double l,
    double t,
    double w,
    double h, {
    double inset = 0.015,
    double minSide = 0.035,
  }) {
    final ix = (w * inset).clamp(0.0, w * 0.24);
    final iy = (h * inset).clamp(0.0, h * 0.24);
    var left = (l + ix).clamp(0.0, 0.95);
    var top = (t + iy).clamp(0.0, 0.95);
    var width = (w - 2 * ix).clamp(minSide, 1.0 - left);
    var height = (h - 2 * iy).clamp(minSide, 1.0 - top);
    // Cap oversized "Roof"/object spans so surface highlight stays on the cue.
    if (width > 0.58) {
      final excess = width - 0.58;
      left = (left + excess / 2).clamp(0.0, 0.42);
      width = 0.58;
    }
    if (height > 0.44) {
      final excess = height - 0.44;
      top = (top + excess / 2).clamp(0.0, 0.56);
      height = min(0.44, 1.0 - top);
    }
    return (l: left, t: top, w: width, h: height);
  }

  static ({double l, double t, double w, double h}) _padNormBox(
    double l,
    double t,
    double w,
    double h, {
    double pad = 0.0,
    double minSide = 0.05,
    double maxW = 0.72,
    double maxH = 0.55,
  }) {
    var left = (l - pad).clamp(0.0, 0.95);
    var top = (t - pad).clamp(0.0, 0.95);
    var width = (w + pad * 2).clamp(minSide, 1.0 - left);
    var height = (h + pad * 2).clamp(minSide, 1.0 - top);
    if (width > maxW) {
      final excess = width - maxW;
      left = (left + excess / 2).clamp(0.0, 1.0 - maxW);
      width = maxW;
    }
    if (height > maxH) {
      final excess = height - maxH;
      top = (top + excess / 2).clamp(0.0, 1.0 - maxH);
      height = min(maxH, 1.0 - top);
    }
    return (l: left, t: top, w: width, h: height);
  }

  /// Expand raw Google Vision label/object names into exterior-domain synonyms
  /// so the detection engine can bind them to roof/siding/gutter/etc. findings.
  ///
  /// Aggressively drops non-exterior labels (people, indoor rooms, products).
  /// Public for unit tests; used on the Vision path before [_detectIssues].
  static Map<String, double> expandVisionLabels(Map<String, double> raw) {
    final out = <String, double>{};
    void bump(String key, double score) {
      final k = key.toLowerCase().trim();
      if (k.isEmpty || score <= 0) return;
      final prev = out[k] ?? 0;
      if (score > prev) out[k] = score.clamp(0.0, 1.0);
    }

    // Scene-level indoor rejection before any synonym expansion.
    if (isClearlyNonExteriorScene(raw)) {
      return out;
    }

    // First pass: true exterior envelope structure (gates ambiguous mappings).
    var hasStructure = false;
    for (final e in raw.entries) {
      final key = e.key.toLowerCase().trim();
      final s = e.value.clamp(0.0, 1.0);
      if (s < 0.12 || isNonExteriorLabel(key)) continue;
      if (isExteriorStructureLabel(key) && s >= 0.28) {
        hasStructure = true;
      }
    }

    for (final e in raw.entries) {
      final key = e.key.toLowerCase().trim();
      final s = e.value.clamp(0.0, 1.0);
      if (key.isEmpty || s < 0.12) continue;
      // Drop people / indoor / product noise entirely — never invent findings.
      if (isNonExteriorLabel(key)) continue;
      if (!isExteriorRelevantLabel(key) && !isExteriorStructureLabel(key)) {
        continue;
      }

      bool has(List<String> needles) => _anyNeedle(key, needles);

      // Roof system — bare "asphalt" / "tile" alone are not roof (roads / floors).
      final roofMaterial =
          has([
            'roof',
            'rooftop',
            'shingle',
            'tile roof',
            'ridge',
            'eave',
            'chimney',
            'flashing',
            'skylight',
          ]) ||
          (hasStructure &&
              (key.contains('asphalt shingle') ||
                  key.contains('asphalt roof') ||
                  (key.contains('asphalt') && key.contains('shingle'))));
      if (roofMaterial) {
        bump('roof', s * 0.98);
        bump('shingle', s * 0.72);
        if (has(['damage', 'broken', 'missing', 'torn', 'hole', 'debris'])) {
          bump('damage', s * 0.9);
          bump('broken', s * 0.75);
        }
      }

      // Gutters / drainage
      if (has([
        'gutter',
        'downspout',
        'drain',
        'eaves',
        'soffit',
        'fascia',
        'rain gutter',
      ])) {
        bump('gutter', s * 0.95);
        bump('downspout', s * 0.7);
        bump('eaves', s * 0.65);
      }

      // Siding / cladding — do not map bare "wall" (indoor false positive).
      if (has([
        'siding',
        'cladding',
        'brick',
        'brickwork',
        'masonry',
        'stucco',
        'vinyl',
        'facade',
        'façade',
        'exterior wall',
        'exterior',
        'clapboard',
      ])) {
        bump('siding', s * 0.88);
        bump('wall', s * 0.7);
        if (has(['brick', 'brickwork', 'masonry'])) bump('concrete', s * 0.55);
      }
      // Patched / mismatched cladding language (replacement boards, color blocks).
      if (hasStructure &&
          has([
            'patch',
            'repair',
            'replacement',
            'mismatched',
            'discoloration',
            'plywood',
          ])) {
        bump('siding', max(out['siding'] ?? 0, s * 0.82));
        bump('wall', max(out['wall'] ?? 0, s * 0.62));
        bump('patch', s * 0.90);
        bump('discoloration', s * 0.78);
        if (has(['repair', 'replacement', 'mismatched'])) {
          bump('repair', s * 0.85);
        }
      }
      // Exterior surface wiring / cable runs — only with structure context.
      if (hasStructure &&
          has([
            'cable',
            'wire',
            'wiring',
            'electrical',
            'conduit',
            'power line',
            'utility line',
            'extension cord',
          ])) {
        bump('wiring', s * 0.92);
        bump('cable', s * 0.88);
        if (has(['electrical', 'conduit', 'power line'])) {
          bump('electrical', s * 0.80);
        }
      }

      // Paint / coating (exterior-only when structure is present)
      if (has(['paint', 'peeling', 'flaking', 'coating', 'weathered']) &&
          (hasStructure || has(['peeling', 'flaking', 'exterior']))) {
        bump('paint', s * 0.9);
        bump('peeling', s * 0.75);
      }

      // Foundation / grade — bare indoor "concrete" floors must not mint grade
      // findings without exterior envelope or explicit foundation language.
      if (has([
            'foundation',
            'basement',
            'crawlspace',
            'settlement',
            'sidewalk',
            'driveway',
          ]) ||
          (hasStructure && has(['concrete', 'cement']))) {
        bump('foundation', s * 0.82);
        bump('concrete', s * 0.7);
      }
      // Cracks only when structure/foundation context exists.
      // Window/glass shatter lines must not mint cladding crack labels.
      final glassContext = has([
        'window',
        'glass',
        'pane',
        'glazing',
        'sill',
      ]);
      if (has(['crack', 'settlement', 'fracture']) &&
          (hasStructure ||
              has(['foundation', 'concrete', 'siding', 'brick', 'stucco']))) {
        if (glassContext &&
            !has(['siding', 'cladding', 'clapboard', 'vinyl siding'])) {
          // Prefer window domain for glass + crack language.
          bump('window', max(out['window'] ?? 0, s * 0.88));
          bump('glass', max(out['glass'] ?? 0, s * 0.82));
        } else {
          bump('crack', s * 0.88);
          if (has(['foundation', 'concrete', 'settlement', 'basement'])) {
            bump('foundation', max(out['foundation'] ?? 0, s * 0.75));
          }
        }
      }

      // Windows / openings on exterior elevations
      if (hasStructure &&
          has([
            'window',
            'door',
            'caulk',
            'seal',
            'window frame',
            'glass',
            'pane',
            'glazing',
          ])) {
        bump('window', s * 0.9);
        bump('seal', s * 0.55);
        if (has(['glass', 'pane', 'glazing'])) {
          bump('glass', max(out['glass'] ?? 0, s * 0.85));
        }
      }
      // Broken glass language (with or without generic structure tags).
      if (has(['broken glass', 'shattered', 'shatter', 'cracked glass']) ||
          (has(['glass', 'window', 'pane']) &&
              has(['broken', 'shatter', 'damage']))) {
        bump('window', max(out['window'] ?? 0, s * 0.92));
        bump('glass', max(out['glass'] ?? 0, s * 0.9));
        bump('broken', max(out['broken'] ?? 0, s * 0.75));
      }

      // Vegetation against structure only — not generic indoor plants
      if (hasStructure &&
          has([
            'vegetation',
            'vine',
            'ivy',
            'shrub',
            'moss',
            'algae',
            'leaf',
            'leaves',
            'tree',
            'plant',
          ])) {
        bump('vegetation', s * 0.85);
        bump('leaf', s * 0.55);
        if (has(['moss', 'algae', 'mold', 'fungus'])) {
          bump('moisture', s * 0.7);
          bump('stain', s * 0.55);
        }
      }

      // Damage / distress — only bind when exterior structure is visible
      if (hasStructure &&
          has([
            'damage',
            'broken',
            'decay',
            'rot',
            'rust',
            'corrosion',
            'stain',
            'discoloration',
            'leak',
            'hole',
            'debris',
            'worn',
            'hail',
          ])) {
        bump('damage', s * 0.85);
        if (has(['rust', 'corrosion'])) bump('rust stain', s * 0.9);
        if (has(['stain', 'discoloration', 'moisture'])) {
          bump('stain', s * 0.8);
          bump('moisture', s * 0.65);
        }
      }

      // House / structure presence (weak prior for exterior context)
      if (has(['house', 'home', 'building', 'property', 'residential'])) {
        bump('exterior', s * 0.55);
        if (s >= 0.4) bump('wall', s * 0.32);
      }
    }

    return out;
  }

  /// Deterministic calibration entry used by golden-set tests and demos.
  ///
  /// Bypasses image decode and Vision — injects feature snapshots that mirror
  /// real exterior photo patterns so detection + scoring stay consistent.
  AnalysisReport analyzeFeatureSnapshots(
    List<ExteriorFeatureSnapshot> snapshots, {
    Map<String, double> labels = const {},
    Map<String, int> photoHits = const {},
    bool visionMode = false,
    List<CapturePhoto>? capturePhotos,
    String source = 'Golden-set calibrated local screening',
  }) {
    if (snapshots.isEmpty) {
      return const AnalysisReport(
        overallScore: 100,
        conditionLabel: 'Excellent — no photos to assess (screening)',
        issues: [],
        estimatedRepairRange: '\$0',
        analysisSource: 'No photos',
        photoCount: 0,
      );
    }

    final features = snapshots.map(_ImageFeatures.fromSnapshot).toList();
    final agg = _ImageFeatures.aggregate(features);
    final photos = capturePhotos ?? const [];
    final hasExteriorCapture = photos.any(_isExteriorCapturePhoto);

    // Indoor / people / product scenes never mint exterior findings — same
    // path as live Vision analysis (Quick Scan and Full Assessment).
    // Mixed sets (portrait + roof) keep going when a real exterior photo exists.
    if (labels.isNotEmpty &&
        isClearlyNonExteriorScene(labels) &&
        !hasExteriorCapture) {
      return _insufficientExteriorReport(
        photoCount: snapshots.length,
        source: source,
        features: agg,
      );
    }

    // Drop people / indoor keys only — keep paint/peel/roof cues that the
    // strict exterior-relevant filter would discard as too generic.
    final detectLabels = {
      for (final e in labels.entries)
        if (!isNonExteriorLabel(e.key)) e.key: e.value,
    };

    // Filtered labels with no exterior envelope → honest empty report.
    if (labels.isNotEmpty &&
        visionMode &&
        !hasExteriorEvidence(detectLabels) &&
        !hasExteriorEvidence(filterExteriorVisionLabels(labels)) &&
        !hasExteriorCapture) {
      return _insufficientExteriorReport(
        photoCount: snapshots.length,
        source: source,
        features: agg,
      );
    }
    final hits = photoHits.isNotEmpty
        ? photoHits
        : {
            for (final e in detectLabels.entries)
              e.key: e.value >= 0.55 ? snapshots.length : 1,
          };

    final issues = _detectIssues(
      features: features,
      labels: detectLabels,
      photoHits: hits,
      photoCount: snapshots.length,
      visionMode: visionMode,
      capturePhotos: photos,
    );

    return _buildReport(
      issues: issues,
      photoCount: snapshots.length,
      features: agg,
      source: source,
    );
  }

  /// Preferred entry: guided capture photos with slot labels.
  Future<AnalysisReport> analyzeCapture(List<CapturePhoto> photos) async {
    if (photos.isEmpty) {
      return const AnalysisReport(
        overallScore: 100,
        conditionLabel: 'Excellent — no photos to assess',
        issues: [],
        estimatedRepairRange: '\$0',
        analysisSource: 'No photos',
        photoCount: 0,
      );
    }

    final imageBytes = <Uint8List>[];
    for (final photo in photos) {
      imageBytes.add(await photo.file.readAsBytes());
    }

    return analyzeImageBytes(imageBytes, capturePhotos: photos);
  }

  /// Pixel-pipeline analysis from raw image bytes (calibration + tests).
  ///
  /// Goes through full decode → feature extraction → detection → scoring,
  /// not the feature-snapshot shortcut used by the synthetic golden set.
  Future<AnalysisReport> analyzeImageBytes(
    List<Uint8List> imageBytes, {
    List<CapturePhoto> capturePhotos = const [],
  }) async {
    if (imageBytes.isEmpty) {
      return const AnalysisReport(
        overallScore: 100,
        conditionLabel: 'Excellent — no photos to assess',
        issues: [],
        estimatedRepairRange: '\$0',
        analysisSource: 'No photos',
        photoCount: 0,
      );
    }

    final photos = capturePhotos.isNotEmpty
        ? capturePhotos
        : [
            for (var i = 0; i < imageBytes.length; i++)
              CapturePhoto(
                file: XFile.fromData(
                  imageBytes[i],
                  name: 'photo_$i.png',
                  mimeType: 'image/png',
                ),
                label: 'Photo ${i + 1}',
                index: i,
              ),
          ];

    // Primary path: real Google Cloud Vision when a key is configured.
    if (hasVisionKey) {
      try {
        return await _analyzeWithGoogleVision(imageBytes, photos);
      } catch (_) {
        // Graceful fallback — keep offline/demo experience unbroken.
        final fallback = await _analyzeWithLocalFeatures(imageBytes, photos);
        return AnalysisReport(
          overallScore: fallback.overallScore,
          conditionLabel: fallback.conditionLabel,
          issues: fallback.issues,
          estimatedRepairRange: fallback.estimatedRepairRange,
          analysisSource:
              'Local multi-feature · Vision unavailable (offline fallback)',
          photoCount: imageBytes.length,
        );
      }
    }

    return _analyzeWithLocalFeatures(imageBytes, photos);
  }

  /// Backward-compatible: untagged files become "Photo N".
  Future<AnalysisReport> analyzePhotos(List<XFile> photos) {
    return analyzeCapture(CapturePhoto.fromXFiles(photos));
  }

  // ---------------------------------------------------------------------------
  // Google Cloud Vision (primary when key present)
  // ---------------------------------------------------------------------------

  static const int _maxVisionPhotos = 8;
  static const int _visionMaxBytes = 3 * 1024 * 1024; // ~3MB payload target
  static const int _visionMaxSide = 1600;

  Future<AnalysisReport> _analyzeWithGoogleVision(
    List<Uint8List> images,
    List<CapturePhoto> capturePhotos,
  ) async {
    final batch = images.take(_maxVisionPhotos).toList();
    final prepared = <Uint8List>[];
    for (final bytes in batch) {
      prepared.add(await _prepareBytesForVision(bytes));
    }

    // Single HTTP round-trip for multi-photo (and single-photo) efficiency.
    final frames = await _annotateImagesBatch(prepared);

    // Merge only exterior frames — a selfie in the set must not wipe a roof
    // photo, and must never contribute labels or boxes to findings.
    final rawMerged = <String, double>{};
    final visionBoxes = <_VisionObjectBox>[];
    var exteriorFrameCount = 0;
    for (var i = 0; i < frames.length; i++) {
      final frame = frames[i];
      final captionNonExt = i < capturePhotos.length &&
          !_isExteriorCapturePhoto(capturePhotos[i]) &&
          _isNonExteriorCapturePhoto(capturePhotos[i]);
      if (isClearlyNonExteriorScene(frame.labels) || captionNonExt) {
        continue;
      }
      exteriorFrameCount++;
      for (final e in frame.labels.entries) {
        final prev = rawMerged[e.key] ?? 0;
        if (e.value > prev) rawMerged[e.key] = e.value;
      }
      for (final box in frame.objects) {
        visionBoxes.add(box.withImageIndex(i));
      }
    }

    final n = images.length;
    final source = n == 1
        ? 'AI exterior screening · Google Cloud Vision (single photo) + local features'
        : 'AI exterior screening · Google Cloud Vision + local features · $n photos';

    final stats = <_ImageFeatures>[];
    for (final bytes in images.take(_maxVisionPhotos)) {
      stats.add(await _ImageFeatures.fromBytes(bytes));
    }
    final agg = _ImageFeatures.aggregate(stats);

    // People / indoor / product-dominant photos: do not invent exterior issues.
    // All frames excluded (portraits / indoor) → honest empty report.
    if ((frames.isNotEmpty && exteriorFrameCount == 0) ||
        isClearlyNonExteriorScene(rawMerged)) {
      return _insufficientExteriorReport(
        photoCount: images.length,
        source: source,
        features: agg,
      );
    }

    final merged = <String, double>{};
    final photoHits = <String, int>{};
    for (final frame in frames) {
      // Expand only exterior-relevant labels; drops indoor/person noise.
      final expanded = expandVisionLabels(
        filterExteriorVisionLabels(frame.labels),
      );
      for (final entry in expanded.entries) {
        final prev = merged[entry.key] ?? 0;
        if (entry.value > prev) merged[entry.key] = entry.value;
        // Higher bar: only count confident exterior-relevant hits.
        if (entry.value >= 0.42) {
          photoHits[entry.key] = (photoHits[entry.key] ?? 0) + 1;
        }
      }
    }

    // No exterior structure from Vision → honest empty report (no invented findings).
    if (!hasExteriorEvidence(merged) && !hasExteriorEvidence(rawMerged)) {
      return _insufficientExteriorReport(
        photoCount: images.length,
        source: source,
        features: agg,
      );
    }

    // Soft capture priors help slot binding only when Vision already saw exterior.
    // Never apply soft damage invent on indoor / non-exterior scenes (already
    // returned above) or when filtered labels lack exterior envelope.
    final soft = _softLabelsFromCapture(
      capturePhotos.take(_maxVisionPhotos).toList(),
      stats,
      allowDamageInvent: hasExteriorEvidence(merged),
    );
    if (hasExteriorEvidence(merged)) {
      for (final e in soft.labels.entries) {
        final prev = merged[e.key] ?? 0;
        final softScore = e.value * 0.38;
        if (softScore > prev) merged[e.key] = softScore;
      }
      for (final e in soft.photoHits.entries) {
        photoHits[e.key] = max(photoHits[e.key] ?? 0, e.value);
      }
    }

    final issues = _detectIssues(
      features: stats,
      labels: merged,
      photoHits: photoHits,
      photoCount: images.length,
      visionMode: true,
      capturePhotos: capturePhotos,
      visionBoxes: visionBoxes,
    );

    final refined = issues
        .map(
          (i) =>
              _polishVisionIssue(i, labels: merged, photoCount: images.length),
        )
        .toList();

    return _buildReport(
      issues: refined,
      photoCount: images.length,
      features: agg,
      source: source,
    );
  }

  /// Honest empty report when Vision sees no clear home exterior.
  AnalysisReport _insufficientExteriorReport({
    required int photoCount,
    required String source,
    required _ImageFeatures features,
  }) {
    return AnalysisReport(
      // Neutral score — not "excellent home"; UI story keys off the label.
      overallScore: 88,
      conditionLabel:
          'Insufficient exterior evidence — photos may not show a home exterior (screening)',
      issues: const [],
      estimatedRepairRange: 'TBD — no exterior findings',
      analysisSource: source,
      photoCount: photoCount,
    );
  }

  /// Downscale very large captures so Vision requests stay reliable.
  Future<Uint8List> _prepareBytesForVision(Uint8List input) async {
    if (input.isEmpty) return input;
    if (input.lengthInBytes <= _visionMaxBytes) {
      // Still cap extreme megapixel stills for latency.
      try {
        return await _scaleImageBytes(input, _visionMaxSide);
      } catch (_) {
        return input;
      }
    }
    try {
      var scaled = await _scaleImageBytes(input, _visionMaxSide);
      if (scaled.lengthInBytes <= _visionMaxBytes) return scaled;
      // Second pass smaller if still huge (e.g. uncompressed PNG).
      scaled = await _scaleImageBytes(scaled, 1200);
      return scaled;
    } catch (_) {
      // Last resort: trim is invalid for images — send original and let API reject.
      return input;
    }
  }

  Future<Uint8List> _scaleImageBytes(Uint8List input, int maxSide) async {
    final codec = await ui.instantiateImageCodec(
      input,
      targetWidth: null,
      targetHeight: null,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final w = image.width;
    final h = image.height;
    final longSide = max(w, h);
    if (longSide <= maxSide) {
      final bd = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bd == null) return input;
      final out = bd.buffer.asUint8List();
      // Prefer original if already compact JPEG and re-encode ballooned size.
      return out.lengthInBytes < input.lengthInBytes * 1.2 ? out : input;
    }
    final scale = maxSide / longSide;
    final tw = max(1, (w * scale).round());
    final th = max(1, (h * scale).round());
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Rect.fromLTWH(0, 0, tw.toDouble(), th.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    image.dispose();
    final picture = recorder.endRecording();
    final outImage = await picture.toImage(tw, th);
    picture.dispose();
    final bd = await outImage.toByteData(format: ui.ImageByteFormat.png);
    outImage.dispose();
    if (bd == null) return input;
    return bd.buffer.asUint8List();
  }

  /// Annotate up to [_maxVisionPhotos] images in one Vision API call.
  Future<List<_VisionFrameResult>> _annotateImagesBatch(
    List<Uint8List> images,
  ) async {
    if (images.isEmpty) return const [];

    final uri = Uri.parse(
      'https://vision.googleapis.com/v1/images:annotate?key=$visionApiKey',
    );

    final features = [
      {'type': 'LABEL_DETECTION', 'maxResults': 40},
      {'type': 'OBJECT_LOCALIZATION', 'maxResults': 20},
      {'type': 'IMAGE_PROPERTIES', 'maxResults': 8},
    ];

    final requests = <Map<String, dynamic>>[
      for (final bytes in images)
        {
          'image': {'content': base64Encode(bytes)},
          'features': features,
        },
    ];

    final response = await _http
        .post(
          uri,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode({'requests': requests}),
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode == 400 || response.statusCode == 403) {
      throw Exception(
        'Vision API auth/config error ${response.statusCode}: check GOOGLE_VISION_API_KEY and API enablement',
      );
    }
    if (response.statusCode != 200) {
      throw Exception(
        'Vision API error ${response.statusCode}: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final responses = data['responses'] as List<dynamic>? ?? [];
    final out = <_VisionFrameResult>[];

    for (var i = 0; i < images.length; i++) {
      if (i >= responses.length) {
        out.add(const _VisionFrameResult.empty());
        continue;
      }
      final first = responses[i] as Map<String, dynamic>;
      if (first['error'] != null) {
        // Per-image error: keep empty labels for that frame, continue others.
        out.add(const _VisionFrameResult.empty());
        continue;
      }
      out.add(_parseVisionFrame(first, imageIndex: i));
    }

    // If every frame failed empty while API returned 200, treat as hard failure
    // only when zero labels overall (caller will fall back to local).
    final anyLabel = out.any((f) => f.labels.isNotEmpty);
    if (!anyLabel && responses.isNotEmpty) {
      final firstErr = responses.first as Map<String, dynamic>;
      if (firstErr['error'] != null) {
        throw Exception('Vision API response error: ${firstErr['error']}');
      }
    }

    return out;
  }

  /// Labels + object localization boxes for one Vision response frame.
  _VisionFrameResult _parseVisionFrame(
    Map<String, dynamic> first, {
    required int imageIndex,
  }) {
    final labels = <_VisionLabel>[];
    final objects = <_VisionObjectBox>[];

    final labelAnnotations = first['labelAnnotations'] as List<dynamic>? ?? [];
    for (final raw in labelAnnotations) {
      final map = raw as Map<String, dynamic>;
      labels.add(
        _VisionLabel(
          description: map['description'] as String? ?? '',
          score: (map['score'] as num?)?.toDouble() ?? 0,
        ),
      );
    }

    final objectAnnotations =
        first['localizedObjectAnnotations'] as List<dynamic>? ?? [];
    for (final raw in objectAnnotations) {
      final map = raw as Map<String, dynamic>;
      final name = map['name'] as String? ?? '';
      final score = ((map['score'] as num?)?.toDouble() ?? 0) * 1.05;
      final clamped = score.clamp(0.0, 1.0);
      if (name.isEmpty || isNonExteriorLabel(name)) continue;

      // Object names are strong spatial cues for labels + boxes.
      labels.add(_VisionLabel(description: name, score: clamped));

      final box = parseVisionBoundingBox(map);
      if (box != null && clamped >= 0.28) {
        objects.add(
          _VisionObjectBox(
            name: name.toLowerCase().trim(),
            score: clamped,
            left: box.l,
            top: box.t,
            width: box.w,
            height: box.h,
            imageIndex: imageIndex,
          ),
        );
      }
    }

    // Color-only cues are weak and invent rust/vegetation on non-exteriors.
    // Apply only when label/object annotations already show exterior structure.
    final hasExteriorObject = labels.any(
      (l) => isExteriorRelevantLabel(l.description) && l.score >= 0.40,
    );
    final props = first['imagePropertiesAnnotation'] as Map<String, dynamic>?;
    final colors =
        (props?['dominantColors'] as Map<String, dynamic>?)?['colors']
            as List<dynamic>?;
    if (hasExteriorObject && colors != null) {
      for (final raw in colors.take(6)) {
        final map = raw as Map<String, dynamic>;
        final color = map['color'] as Map<String, dynamic>? ?? {};
        final r = (color['red'] as num?)?.toDouble() ?? 0;
        final g = (color['green'] as num?)?.toDouble() ?? 0;
        final b = (color['blue'] as num?)?.toDouble() ?? 0;
        final score = ((map['score'] as num?)?.toDouble() ?? 0.2) * 0.50;
        if (score < 0.20) continue;
        if (r > g + 28 && r > b + 30 && r > 95) {
          labels.add(_VisionLabel(description: 'rust stain', score: score));
        }
        if (g > r + 20 && g > b + 12 && g > 70) {
          labels.add(
            _VisionLabel(description: 'vegetation algae', score: score * 0.65),
          );
        }
      }
    }

    final local = <String, double>{};
    for (final label in labels) {
      final key = label.description.toLowerCase().trim();
      if (key.isEmpty) continue;
      if (isNonExteriorLabel(key)) continue;
      final prev = local[key] ?? 0;
      if (label.score > prev) local[key] = label.score.clamp(0.0, 1.0);
    }
    return _VisionFrameResult(labels: local, objects: objects);
  }

  /// Homeowner-facing polish when Vision labels support a finding.
  AnalysisIssue _polishVisionIssue(
    AnalysisIssue issue, {
    required Map<String, double> labels,
    required int photoCount,
  }) {
    final top = labels.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final relevant = top
        .where((e) => e.value >= 0.45)
        .take(4)
        .map((e) => e.key)
        .toList();

    var insight = issue.insight.trim();
    var conf = issue.confidence;
    final severity = issue.severity;

    // Nudge confidence slightly when Vision provided rich labels (capped).
    // Keep ground-discharge estimates more conservative (zone-level honesty).
    if (relevant.length >= 2 && conf < 90) {
      conf = min(94, conf + 2);
    }
    if (_isGroundDrainageIssue(issue)) {
      conf = min(conf, 84);
    }

    // Single-photo + Vision: keep honesty but avoid over-softening strong AI hits.
    if (photoCount == 1 && conf >= 82 && severity == 'High') {
      // leave High when Vision-backed and confident
    }

    if (relevant.isNotEmpty) {
      final labelBit = relevant.take(3).join(', ');
      if (!insight.toLowerCase().contains('vision') &&
          !insight.toLowerCase().contains('cloud ai')) {
        if (!insight.endsWith('.')) insight = '$insight.';
        insight =
            '$insight Cloud Vision scene cues included: $labelBit. '
            'Still a photo screening — confirm on-site before major work.';
      }
    }

    if (photoCount == 1) {
      if (!insight.toLowerCase().contains('single') &&
          !insight.toLowerCase().contains('one angle') &&
          !insight.toLowerCase().contains('one photo')) {
        if (!insight.endsWith('.')) insight = '$insight.';
        insight =
            '$insight Single-photo Quick Scan: AI helps this angle, but other elevations are not covered.';
      }
    }

    return issue.copyWith(
      confidence: conf.clamp(48, 94),
      severity: severity,
      insight: insight,
    );
  }

  // ---------------------------------------------------------------------------
  // Local pipeline
  // ---------------------------------------------------------------------------

  Future<AnalysisReport> _analyzeWithLocalFeatures(
    List<Uint8List> images,
    List<CapturePhoto> capturePhotos,
  ) async {
    if (localAnalysisDelay > Duration.zero) {
      await Future<void>.delayed(localAnalysisDelay);
    }

    final features = <_ImageFeatures>[];
    for (var i = 0; i < images.length; i++) {
      features.add(await _ImageFeatures.fromBytes(images[i]));
    }

    final agg = _ImageFeatures.aggregate(features);
    const source =
        'AI exterior screening · local multi-feature (add GOOGLE_VISION_API_KEY for Cloud Vision)';

    // Per-photo indoor / person captions — a selfie in the set must not
    // reject a roof photo, and an all-portrait set must not invent findings.
    final outdoorPhotos = [
      for (final p in capturePhotos)
        if (_isExteriorCapturePhoto(p)) p,
    ];
    if (capturePhotos.isNotEmpty && outdoorPhotos.isEmpty) {
      return _insufficientExteriorReport(
        photoCount: images.length,
        source: source,
        features: agg,
      );
    }

    // Guided capture slots + photo captions are weak but useful prior cues
    // when Vision is off (calibration harness + offline screening).
    // Damage invent requires exterior feature support and/or exterior caption
    // language so mis-tagged indoor photos cannot mint shingle Highs — while
    // real roof calibration shots labeled "Roof slope" still work.
    final captionBlob = outdoorPhotos
        .map((p) => '${p.label} ${p.file.name}')
        .join(' ')
        .toLowerCase();
    final captionExteriorSupport = _captionClearlyExterior(captionBlob);
    final localExteriorSupport =
        captionExteriorSupport ||
        features.any(
          (f) =>
              f.roofSignal > 0.34 ||
              f.wallSignal > 0.38 ||
              f.foundationSignal > 0.40 ||
              f.gutterLineScore > 0.32 ||
              f.darkTopBias > 0.30,
        );
    final soft = _softLabelsFromCapture(
      capturePhotos,
      features,
      allowDamageInvent: localExteriorSupport,
    );

    // Soft labels alone with no exterior envelope → insufficient (no invent).
    if (!hasExteriorEvidence(soft.labels) && !localExteriorSupport) {
      return _insufficientExteriorReport(
        photoCount: images.length,
        source: source,
        features: agg,
      );
    }

    final issues = _detectIssues(
      features: features,
      labels: soft.labels,
      photoHits: soft.photoHits,
      photoCount: images.length,
      visionMode: false,
      capturePhotos: capturePhotos,
    );

    return _buildReport(
      issues: issues,
      photoCount: images.length,
      features: agg,
      source: source,
    );
  }

  static bool _isNonExteriorCapturePhoto(CapturePhoto photo) {
    return FindingRetakeService.looksNonExteriorPhoto(photo) ||
        _captionClearlyIndoor('${photo.label} ${photo.file.name}');
  }

  /// Usable exterior frame — not a person / indoor / product caption.
  static bool _isExteriorCapturePhoto(CapturePhoto photo) =>
      !_isNonExteriorCapturePhoto(photo);

  /// Caption/filename language that clearly describes an indoor scene.
  static bool _captionClearlyIndoor(String caption) {
    final c = caption.toLowerCase();
    if (c.trim().isEmpty) return false;
    const needles = [
      'kitchen',
      'bedroom',
      'bathroom',
      'living room',
      'dining room',
      'indoor',
      'interior',
      'cabinet',
      'countertop',
      'stove',
      'oven',
      'appliance',
      'refrigerator',
      'fridge',
      'dishwasher',
      'microwave',
      'toilet',
      'shower',
      'bathtub',
      'sofa',
      'couch',
      'furniture',
    ];
    if (needles.any(c.contains)) return true;
    final tokens = c.split(RegExp('[^a-z0-9]+')).where((t) => t.isNotEmpty);
    const people = {
      'person',
      'people',
      'selfie',
      'portrait',
      'headshot',
      'face',
    };
    return tokens.any(people.contains);
  }

  /// Caption/filename language that clearly describes exterior systems.
  static bool _captionClearlyExterior(String caption) {
    final c = caption.toLowerCase();
    if (c.trim().isEmpty) return false;
    // Prefer exterior terms; do not treat bare "home" alone as enough.
    const needles = [
      'roof',
      'shingle',
      'gutter',
      'eave',
      'fascia',
      'soffit',
      'siding',
      'cladding',
      'foundation',
      'chimney',
      'downspout',
      'asphalt',
      'granule',
      'exterior',
      'elevation',
      'facade',
      'façade',
      'brick',
      'stucco',
    ];
    return needles.any(c.contains);
  }

  /// Build soft label priors from guided slots, captions, and per-photo features.
  /// Helps full-frame defect close-ups (shingle fields, foundation cracks) that
  /// lack classic elevation geometry.
  ///
  /// When [allowDamageInvent] is false (indoor Vision context or no exterior
  /// feature support), slot tags may only add weak system presence — never
  /// damage/broken/torn labels that mint "Missing / Damaged Shingles".
  ({Map<String, double> labels, Map<String, int> photoHits})
  _softLabelsFromCapture(
    List<CapturePhoto> photos,
    List<_ImageFeatures> features, {
    bool allowDamageInvent = true,
  }) {
    final labels = <String, double>{};
    final hits = <String, int>{};

    void bump(String key, double score, {int photoHit = 1}) {
      final prev = labels[key] ?? 0;
      if (score > prev) labels[key] = score.clamp(0.0, 0.92);
      hits[key] = (hits[key] ?? 0) + photoHit;
    }

    for (var i = 0; i < photos.length; i++) {
      final photo = photos[i];
      final f = i < features.length ? features[i] : null;
      final slot = photo.slotId;
      final caption = '${photo.label} ${photo.file.name}'.toLowerCase();
      if (_isNonExteriorCapturePhoto(photo)) continue;

      // Slot priors
      if (slot == CaptureShotId.roof) {
        // Default checklist title is "Roof & eaves" — that must stay roof-first.
        // Do not invent gutter/overflow from the stock slot name alone.
        final defaultRoofSlotName =
            caption.contains('roof & eave') ||
            caption.contains('roof and eave');
        final eaveFocused =
            caption.contains('gutter') ||
            caption.contains('fascia') ||
            caption.contains('soffit') ||
            caption.contains('overflow') ||
            (caption.contains('eave') && !defaultRoofSlotName);
        // Require roof-like image support OR explicit roof caption language.
        // Slot tag alone must not invent a roof on indoor mis-tags.
        final roofFeatureOk =
            f == null ||
            f.roofSignal > 0.32 ||
            f.darkTopBias > 0.28 ||
            (f.horizontalBanding > 0.30 && f.greyDominance > 0.20) ||
            caption.contains('roof') ||
            caption.contains('shingle') ||
            caption.contains('asphalt');
        if (!roofFeatureOk && !eaveFocused) {
          // Skip roof invent for this frame.
        } else if (eaveFocused) {
          // Eave-line shots are drainage-first; don't invent roof impact damage.
          bump('gutter', 0.78);
          bump('eaves', 0.70);
          bump('fascia', 0.52);
          bump('roof', 0.48);
          // Debris/overflow priors on true eave close-ups with veg or trough cues.
          if (f != null &&
              (f.vegetationNear > 0.16 ||
                  f.gutterLineScore > 0.28 ||
                  (f.horizontalBanding > 0.32 && f.darkPatchRatio > 0.12))) {
            bump('debris', 0.58);
            bump('leaf', 0.50);
            bump('overflow', 0.50);
          }
        } else {
          bump('roof', allowDamageInvent ? 0.84 : 0.50);
          bump('shingle', allowDamageInvent ? 0.72 : 0.42);
          if (allowDamageInvent) {
            bump('asphalt', 0.58);
            // Roof-slot guided shots map to the roof system when features support.
            bump('worn', 0.52);
            // Never invent damage from a bare roof *slot tag* alone (indoor
            // mis-tags). Require guided roof language and/or roof-like texture.
            // allowDamageInvent is false when Vision/local is indoor-only.
            final captionRoofLang =
                caption.contains('roof') ||
                caption.contains('shingle') ||
                caption.contains('asphalt') ||
                caption.contains('granule');
            final textureOk =
                f != null &&
                (f.highTextureChaos ||
                    f.peelingScore > 0.28 ||
                    f.crackLineScore > 0.24 ||
                    f.darkTopBias > 0.26 ||
                    f.darkPatchRatio > 0.12 ||
                    f.highLuminanceVariance > 0.38 ||
                    f.topEdgeDensity > 0.12);
            final roofGeomOk =
                f != null &&
                (f.roofSignal > 0.36 ||
                    f.darkTopBias > 0.30 ||
                    (f.horizontalBanding > 0.32 && f.greyDominance > 0.22));
            if (textureOk && roofGeomOk) {
              bump('damage', 0.72);
              bump('broken', 0.56);
            } else if (captionRoofLang) {
              // Guided roof captions (calibration + full assessment roof slot):
              // keep historical soft damage strength so real roof photos still
              // surface Medium findings under local multi-feature mode.
              bump('damage', 0.72);
              bump('worn', 0.58);
            } else if (roofGeomOk && f.roofSignal > 0.48) {
              // Geometry-only presence — mild wear prior, not hard damage invent.
              // (f is non-null when roofGeomOk is true.)
              bump('worn', 0.48);
            }
          }
        }
      }
      if (slot == CaptureShotId.problemCloseup) {
        // Close-ups inherit category from texture + caption.
        // Prefer explicit caption category over ambiguous texture bleed.
        final captionFoundation =
            caption.contains('foundation') ||
            caption.contains('concrete') ||
            caption.contains('settlement') ||
            caption.contains('spall') ||
            caption.contains('grade') ||
            caption.contains('honeycomb');
        // Pipe / soil / mulch close-ups are grade drainage, not wall cladding.
        final captionGradeOutlet =
            caption.contains('pipe') ||
            caption.contains('outlet') ||
            caption.contains('discharge') ||
            caption.contains('soil') ||
            caption.contains('mulch') ||
            caption.contains('gravel') ||
            (caption.contains('downspout') &&
                (caption.contains('ground') ||
                    caption.contains('base') ||
                    caption.contains('end') ||
                    caption.contains('foundation')));
        final captionPaint =
            caption.contains('paint') ||
            caption.contains('peel') ||
            caption.contains('film') ||
            caption.contains('flake');
        final captionRoof =
            caption.contains('shingle') ||
            caption.contains('roof') ||
            caption.contains('asphalt') ||
            caption.contains('granule');
        final captionGutter =
            caption.contains('gutter') ||
            caption.contains('eave') ||
            caption.contains('debris') ||
            caption.contains('overflow');
        final captionWall =
            caption.contains('siding') ||
            caption.contains('brick') ||
            caption.contains('cladding') ||
            (caption.contains('wall') &&
                !captionFoundation &&
                !captionGradeOutlet);

        if (f != null && allowDamageInvent) {
          // Only invent roof damage priors when caption is roof-focused or
          // shingle-field geometry is unmistakable (not wall/foundation CUs).
          // Gated by allowDamageInvent so indoor Vision/local context cannot
          // mint shingle findings from a mis-tagged close-up.
          if (captionRoof ||
              (!captionFoundation &&
                  !captionPaint &&
                  !captionWall &&
                  f.roofSignal > 0.48 &&
                  f.greyDominance > 0.28 &&
                  f.horizontalBanding > 0.28)) {
            bump('roof', 0.74);
            bump('shingle', 0.60);
            if (f.highTextureChaos ||
                f.peelingScore > 0.34 ||
                f.darkPatchRatio > 0.16 ||
                f.highLuminanceVariance > 0.45) {
              bump('damage', 0.64);
              bump('torn', 0.48);
            } else if (captionRoof) {
              // Explicit roof close-up labels (calibration / guided retake).
              bump('worn', 0.58);
              bump('damage', 0.66);
            }
          }
          // Foundation priors only with clear base context — not from soil-line
          // darkness alone (elevations often darken at grade without a crack).
          if (captionFoundation ||
              (!captionRoof &&
                  !captionGutter &&
                  (f.foundationSignal > 0.48 ||
                      (f.lowerThirdDark > 0.54 &&
                          f.botEdgeDensity > 0.20 &&
                          f.crackLineScore > 0.44 &&
                          f.foundationSignal > 0.38)))) {
            bump('foundation', 0.66);
            bump('concrete', 0.52);
            // Crack/settlement labels need visible linear structure or caption.
            if (f.crackLineScore > 0.44 ||
                caption.contains('crack') ||
                caption.contains('settlement')) {
              bump('crack', 0.55);
              bump('settling', 0.44);
            }
            if (caption.contains('moisture') || f.moistureStainScore > 0.30) {
              bump('moisture', 0.44);
            }
          }
          // Do not invent gutters from horizontal shingle lines on roof CUs.
          if (captionGutter ||
              (!captionRoof &&
                  !captionFoundation &&
                  f.gutterLineScore > 0.34)) {
            bump('gutter', 0.66);
            bump('debris', 0.48);
            if (f.darkPatchRatio > 0.14 || f.vegetationNear > 0.12) {
              bump('leaf', 0.42);
            }
          }
          // Foundation / grade / outlet close-ups share edges with walls — do not
          // invent cladding damage when the frame is soil, pipe, or base.
          // Device "Problem close-up" captions are often generic; rely on geometry.
          final frameLooksGrade =
              captionGradeOutlet ||
              captionFoundation ||
              (f.foundationSignal > 0.42 &&
                  f.wallSignal < 0.50 &&
                  f.lowerThirdDark > 0.38) ||
              (f.foundationSignal >= f.wallSignal - 0.02 &&
                  f.lowerThirdDark > 0.42 &&
                  f.botEdgeDensity > 0.16) ||
              (f.vegetationNear > 0.20 &&
                  f.lowerThirdDark > 0.40 &&
                  f.wallSignal < 0.50 &&
                  f.midEdgeDensity < 0.22);
          // Paint only when caption is peel-focused or peel texture is extreme —
          // never invent paint/peel from grade soil/mulch/pipe texture variance.
          if (!frameLooksGrade &&
              !captionGradeOutlet &&
              ((captionPaint && !captionFoundation) ||
                  (f.peelingScore > 0.58 &&
                      f.highLuminanceVariance > 0.55 &&
                      f.wallSignal > 0.44 &&
                      f.foundationSignal < f.wallSignal - 0.06 &&
                      !captionWall &&
                      !captionFoundation &&
                      !captionRoof))) {
            bump('paint', 0.68);
            bump('peel', 0.62);
            if (f.peelingScore > 0.55 || caption.contains('flake')) {
              bump('flake', 0.50);
            }
          }
          if (!frameLooksGrade &&
              (captionWall ||
                  (f.crackLineScore > 0.40 &&
                      f.wallSignal > 0.42 &&
                      !captionRoof))) {
            bump('siding', 0.72);
            bump('wall', 0.60);
            if (caption.contains('crack') ||
                caption.contains('fracture') ||
                f.crackLineScore > 0.48) {
              bump('crack', 0.60);
            }
            // High wall luminance variance often marks patched / replacement boards.
            if (f.highLuminanceVariance > 0.54 &&
                f.peelingScore < 0.48 &&
                f.crackLineScore < 0.52) {
              bump('discoloration', 0.58);
              bump('patch', 0.52);
            }
          }
          // Grade/outlet CUs: prefer drainage labels, never siding invent.
          // Real phone outlet shots often lack "pipe" in the caption — invent
          // soft downspout priors from wet soil / base geometry at grade.
          if (frameLooksGrade || captionGradeOutlet) {
            final outletGeometry =
                f.lowerThirdDark > 0.34 &&
                f.gutterLineScore < 0.42 &&
                f.darkTopBias < 0.42 &&
                (f.moistureStainScore > 0.20 ||
                    f.vegetationNear > 0.10 ||
                    f.darkPatchRatio > 0.08 ||
                    f.botEdgeDensity > 0.14) &&
                (f.foundationSignal > 0.28 ||
                    f.wallSignal > 0.28 ||
                    f.botEdgeDensity > 0.16);
            final moistureAtGrade =
                (caption.contains('moisture') ||
                    caption.contains('wet') ||
                    caption.contains('soil') ||
                    caption.contains('grade') ||
                    caption.contains('foundation')) &&
                f.lowerThirdDark > 0.34 &&
                f.gutterLineScore < 0.45;
            if (caption.contains('pipe') ||
                caption.contains('downspout') ||
                caption.contains('outlet') ||
                caption.contains('drain') ||
                caption.contains('discharge') ||
                captionGradeOutlet ||
                outletGeometry ||
                moistureAtGrade ||
                f.foundationSignal > 0.46) {
              bump('downspout', max(labels['downspout'] ?? 0, 0.64));
              bump('pipe', max(labels['pipe'] ?? 0, 0.60));
              bump('drain', max(labels['drain'] ?? 0, 0.54));
              if (f.moistureStainScore > 0.22 || f.lowerThirdDark > 0.40) {
                bump('moisture', max(labels['moisture'] ?? 0, 0.48));
              }
            }
          }
        }
      }

      // Caption keywords (manifest labels like "Damaged asphalt shingles").
      // Explicit roof language is trusted; damage invent still needs allow flag.
      if (caption.contains('shingle') ||
          (caption.contains('asphalt') &&
              (caption.contains('roof') || caption.contains('shingle')))) {
        bump('roof', 0.78);
        bump('shingle', 0.74);
        bump('asphalt', 0.62);
      }
      if (caption.contains('roof') &&
          !caption.contains('proof') &&
          !caption.contains('waterproof')) {
        bump('roof', max(labels['roof'] ?? 0, 0.70));
      }
      // Only treat "damage/damaged" as roof damage when roof language is present.
      if (allowDamageInvent &&
          (caption.contains('damage') ||
              caption.contains('damaged') ||
              caption.contains('failure') ||
              caption.contains('torn')) &&
          (caption.contains('roof') ||
              caption.contains('shingle') ||
              caption.contains('asphalt'))) {
        bump('damage', 0.58);
      }
      if (caption.contains('gutter') ||
          caption.contains('clog') ||
          caption.contains('overflow') ||
          caption.contains('leaf') ||
          caption.contains('eave') ||
          caption.contains('fascia') ||
          caption.contains('downspout')) {
        bump('gutter', 0.74);
        bump('debris', 0.50);
        bump('eaves', 0.55);
      }
      if (caption.contains('foundation') ||
          caption.contains('settlement') ||
          caption.contains('honeycomb') ||
          caption.contains('grade') ||
          caption.contains('spall') ||
          caption.contains('concrete')) {
        // Outlet / wet-soil captions often say "foundation" but are drainage
        // first — keep foundation presence softer so drainage is not demoted.
        final outletCaption =
            caption.contains('pipe') ||
            caption.contains('outlet') ||
            caption.contains('discharge') ||
            caption.contains('downspout') ||
            caption.contains('soil') ||
            caption.contains('wet');
        bump('foundation', outletCaption ? 0.58 : 0.82);
        bump('concrete', outletCaption ? 0.48 : 0.70);
        if (caption.contains('crack') || caption.contains('settlement')) {
          bump('crack', 0.70);
          bump('settling', 0.58);
        }
        if (caption.contains('moisture')) bump('moisture', 0.55);
      }
      // Do not promote paint from foundation captions that mention surface peel.
      final captionIsFoundation =
          caption.contains('foundation') ||
          caption.contains('settlement') ||
          caption.contains('honeycomb') ||
          caption.contains('spall') ||
          caption.contains('concrete');
      if (!captionIsFoundation &&
          (caption.contains('paint') ||
              caption.contains('peel') ||
              caption.contains('flake') ||
              caption.contains('blister') ||
              (caption.contains('film') && caption.contains('fail')))) {
        bump('paint', 0.80);
        bump('peel', 0.76);
        bump('flake', 0.60);
      }
      final captionIsGradeOutlet =
          caption.contains('pipe') ||
          caption.contains('outlet') ||
          caption.contains('discharge') ||
          caption.contains('soil') ||
          caption.contains('mulch') ||
          caption.contains('gravel') ||
          (caption.contains('downspout') &&
              (caption.contains('ground') ||
                  caption.contains('base') ||
                  caption.contains('end') ||
                  caption.contains('foundation') ||
                  caption.contains('grade')));
      // Explicit grade / outlet captions (manifest + retake labels).
      if (captionIsGradeOutlet ||
          (caption.contains('moisture') &&
              (caption.contains('foundation') ||
                  caption.contains('grade') ||
                  caption.contains('base') ||
                  caption.contains('close-up') ||
                  caption.contains('closeup')))) {
        bump('downspout', max(labels['downspout'] ?? 0, 0.58));
        bump('pipe', max(labels['pipe'] ?? 0, 0.54));
        bump('drain', max(labels['drain'] ?? 0, 0.48));
        if (caption.contains('moisture') || caption.contains('wet')) {
          bump('moisture', max(labels['moisture'] ?? 0, 0.50));
        }
      }
      if (!captionIsFoundation &&
          !captionIsGradeOutlet &&
          (caption.contains('siding') ||
              caption.contains('brick') ||
              caption.contains('cladding') ||
              caption.contains('masonry') ||
              (caption.contains('wall') &&
                  !caption.contains('foundation') &&
                  !caption.contains('roof')))) {
        bump('siding', 0.78);
        bump('wall', 0.70);
        bump('brick', 0.52);
        // Wall elevations and wall close-ups support cladding defect priors.
        // Prefer crack priors only when crack language is explicit — not every
        // wall caption (avoids inventing cracks over obvious patch work).
        if (caption.contains('crack') ||
            caption.contains('fracture') ||
            caption.contains('split')) {
          bump('crack', 0.68);
        } else if (caption.contains('close-up') ||
            caption.contains('closeup')) {
          bump('crack', 0.52);
        }
        if (caption.contains('patch') ||
            caption.contains('mismatched') ||
            caption.contains('repair') ||
            caption.contains('replacement') ||
            caption.contains('discolor')) {
          bump('patch', 0.72);
          bump('discoloration', 0.64);
          bump('repair', 0.58);
        }
      }
      // Exterior wiring / cable clutter captions.
      if (!captionIsFoundation &&
          (caption.contains('wiring') ||
              caption.contains('cable') ||
              caption.contains('electrical') ||
              caption.contains('conduit') ||
              (caption.contains('wire') && !caption.contains('wireless')))) {
        bump('wiring', 0.74);
        bump('cable', 0.70);
        bump('electrical', 0.55);
      }

      // Obvious wall color-block / patch geometry on elevations (white boards
      // against weathered cladding, etc.) — soft prior, not a hard claim.
      if (f != null &&
          !captionIsFoundation &&
          f.wallSignal > 0.48 &&
          f.highLuminanceVariance > 0.56 &&
          f.roofSignal < 0.48 &&
          f.peelingScore < 0.50 &&
          f.crackLineScore < 0.50) {
        bump('siding', max(labels['siding'] ?? 0, 0.70));
        bump('wall', max(labels['wall'] ?? 0, 0.58));
        bump('discoloration', max(labels['discoloration'] ?? 0, 0.56));
        bump('patch', max(labels['patch'] ?? 0, 0.50));
      }

      // Full-frame shingle field (close-up dominated by courses) — not a
      // distant elevation with landscaping texture.
      if (f != null &&
          f.horizontalBanding > 0.34 &&
          f.greyDominance > 0.24 &&
          f.highTextureChaos &&
          f.wallSignal < 0.48 &&
          f.vegetationNear < 0.22 &&
          (slot == CaptureShotId.roof ||
              slot == CaptureShotId.problemCloseup ||
              caption.contains('shingle') ||
              caption.contains('roof'))) {
        bump('roof', max(labels['roof'] ?? 0, 0.64));
        bump('shingle', max(labels['shingle'] ?? 0, 0.52));
        if (f.peelingScore > 0.40 || f.crackLineScore > 0.34) {
          bump('damage', max(labels['damage'] ?? 0, 0.58));
        }
      }

      // Full-frame foundation crack — caption/slot + strong linear crack only.
      // Healthy elevations with soil bands must not invent settlement labels.
      if (f != null &&
          f.greyDominance > 0.38 &&
          f.crackLineScore > 0.56 &&
          f.vegetationNear < 0.14 &&
          f.lowerThirdDark > 0.48 &&
          f.foundationSignal > 0.46 &&
          f.botEdgeDensity > 0.14 &&
          (slot == CaptureShotId.problemCloseup ||
              caption.contains('foundation') ||
              caption.contains('concrete') ||
              caption.contains('settlement') ||
              caption.contains('honeycomb') ||
              caption.contains('grade crack'))) {
        bump('foundation', max(labels['foundation'] ?? 0, 0.62));
        bump('crack', max(labels['crack'] ?? 0, 0.50));
        bump('concrete', max(labels['concrete'] ?? 0, 0.44));
      }
    }

    return (labels: labels, photoHits: hits);
  }

  // ---------------------------------------------------------------------------
  // Detection engine — per-photo votes + dual-gate (presence × defect)
  // ---------------------------------------------------------------------------

  List<AnalysisIssue> _detectIssues({
    required List<_ImageFeatures> features,
    required Map<String, double> labels,
    required Map<String, int> photoHits,
    required int photoCount,
    required bool visionMode,
    required List<CapturePhoto> capturePhotos,
    List<_VisionObjectBox> visionBoxes = const [],
  }) {
    final agg = _ImageFeatures.aggregate(features);
    final perPhoto = features.map(_CategorySignals.fromFeatures).toList();
    final fused = _CategorySignals.fuse(perPhoto, agg);

    bool hasAny(List<String> needles) =>
        labels.keys.any((k) => needles.any((n) => k.contains(n)));

    /// Best Vision/label score for any synonym; partial matches are discounted
    /// so short tokens like "wall" do not dominate over real defect labels.
    double maxLabel(List<String> needles, {double partialScale = 0.72}) {
      var best = 0.0;
      for (final e in labels.entries) {
        final key = e.key;
        for (final n in needles) {
          if (key == n) {
            best = max(best, e.value);
          } else if (key.contains(n) || n.contains(key)) {
            best = max(best, e.value * partialScale);
          }
        }
      }
      return best;
    }

    int labelHits(List<String> needles) {
      var hits = 0;
      for (final e in photoHits.entries) {
        if (needles.any((n) => e.key.contains(n) || n.contains(e.key))) {
          hits = max(hits, e.value);
        }
      }
      return hits;
    }

    /// How many photos independently support a defect category.
    int photoVotes(bool Function(_CategorySignals s) pred) {
      var n = 0;
      for (final s in perPhoto) {
        if (pred(s)) n++;
      }
      return n;
    }

    /// Photo-coverage factor: more independent views → higher trust.
    final coverageFactor = (0.72 + 0.07 * min(4, photoCount)).clamp(0.72, 1.0);

    final groundSceneOk = _sceneSupportsGroundDrainage(
      features: features,
      photos: capturePhotos,
      labels: labels,
    );
    final roofSceneOk = _sceneSupportsRoofField(
      features: features,
      photos: capturePhotos,
      labels: labels,
    );
    final roofDominantScene = _sceneIsRoofDominant(
      features: features,
      photos: capturePhotos,
    );
    final soilOnlyScene = _sceneIsSoilOnly(
      features: features,
      photos: capturePhotos,
    );

    final candidates = <_ScoredIssue>[];

    // ── Roof ──────────────────────────────────────────────────────────────
    final roofLabel = maxLabel([
      'roof',
      'shingle',
      'tile roof',
      'asphalt',
      'ridge',
      'rooftop',
      'eave',
    ]);
    // Note: do not include bare "crack" here — foundation crack labels would
    // falsely inflate roof damage on grade photos.
    final roofDamageLabel = maxLabel([
      'damage',
      'broken',
      'debris',
      'storm',
      'hole',
      'missing',
      'worn',
      'leak',
      'hail',
      'torn',
      'curling',
      'cupped',
      'bald',
      'shingle damage',
    ]);
    final roofPresence = max(fused.roofPresence, roofLabel);
    // Caption/slot priors: true damage words only — "worn" alone is aging,
    // not impact failure (golden aging set must stay Medium, not High).
    final hardDamageLabel = maxLabel([
      'damage',
      'broken',
      'missing',
      'torn',
      'hail',
      'storm',
      'hole',
      'debris',
      'curling',
      'cupped',
      'bald',
    ]);
    // Hard damage labels must be strong — weak "debris" alone shouldn't force High.
    // Soft capture priors peak near 0.62; allow that band for Medium titles only.
    // Medium roofs stay reachable from texture; High still needs multi-signal proof.
    final labeledRoofDamage = roofLabel > 0.62 && hardDamageLabel >= 0.64;
    final roofDefect = _maxN([
      fused.roofDefect,
      roofDamageLabel * (roofLabel > 0.42 ? 1.0 : 0.36),
      if (labeledRoofDamage) 0.55 else 0.0,
      // Upper-plane texture cues (real phone elevations + close-ups).
      // Enough for Medium findings; High gates ignore texture-alone.
      if (agg.highTextureChaos && fused.roofPresence > 0.38) 0.43 else 0.0,
      if (agg.darkTopBias > 0.34 && agg.darkPatchRatio > 0.18) 0.41 else 0.0,
      if (agg.crackLineScore > 0.38 && fused.roofPresence > 0.38) 0.39 else 0.0,
      if (agg.topEdgeDensity > 0.18 &&
          agg.darkTopBias > 0.32 &&
          agg.highLuminanceVariance > 0.40)
        0.37
      else
        0.0,
    ]);
    final roofVotes = photoVotes(
      (s) =>
          s.roofDefect > 0.38 || (s.roofPresence > 0.45 && s.roofDefect > 0.32),
    );
    final granuleLoss =
        !(roofDefect > 0.56) &&
        fused.roofPresence > 0.34 &&
        agg.greyDominance > 0.34 &&
        agg.topEdgeDensity > 0.10 &&
        agg.highLuminanceVariance > 0.32 &&
        agg.darkTopBias > 0.20;
    // Real roof elevations: upper-plane chaos/patches without hard labels still
    // warrant a Medium wear note so grade-line noise does not own the report.
    final upperPlaneWear =
        !labeledRoofDamage &&
        fused.roofPresence > 0.32 &&
        agg.darkTopBias > 0.34 &&
        (agg.highTextureChaos ||
            agg.darkPatchRatio > 0.16 ||
            (agg.topEdgeDensity > 0.12 && agg.highLuminanceVariance > 0.30));

    // Dual-gate: require clearer presence/defect so healthy roofs don't invent
    // medium alarms. High severity needs strong multi-signal corroboration.
    // Real phone roof close-ups often need upper-plane texture alone to enter.
    if (roofPresence > 0.38 ||
        roofDefect > 0.42 ||
        roofLabel > 0.48 ||
        labeledRoofDamage ||
        upperPlaneWear ||
        (agg.darkTopBias > 0.38 &&
            agg.darkPatchRatio > 0.16 &&
            agg.topEdgeDensity > 0.12)) {
      final damaged =
          roofDefect > 0.56 ||
          labeledRoofDamage ||
          (roofLabel > 0.58 && roofDamageLabel > 0.64) ||
          (agg.highTextureChaos &&
              fused.roofPresence > 0.50 &&
              roofDefect > 0.52 &&
              agg.darkTopBias > 0.36 &&
              hardDamageLabel > 0.44);
      // High "Missing Shingles" requires multi-signal proof — texture alone
      // on real phone elevations over-calls Highs. Prefer fewer false Highs.
      // Ambiguous single-elevation noise stays Medium even with damage labels.
      final severity = damaged
          ? ((labeledRoofDamage &&
                        roofDefect > 0.80 &&
                        hardDamageLabel > 0.80 &&
                        roofVotes >= 2 &&
                        photoCount >= 3 &&
                        agg.darkTopBias > 0.40 &&
                        agg.highTextureChaos &&
                        (agg.darkPatchRatio > 0.20 ||
                            agg.crackLineScore > 0.40)) ||
                    (roofVotes >= 2 &&
                        roofDefect > 0.84 &&
                        fused.roofPresence > 0.60 &&
                        hardDamageLabel > 0.72 &&
                        photoCount >= 3 &&
                        agg.darkTopBias > 0.44 &&
                        agg.highTextureChaos &&
                        agg.darkPatchRatio > 0.18) ||
                    (hardDamageLabel > 0.88 &&
                        roofLabel > 0.80 &&
                        roofVotes >= 2 &&
                        roofDefect > 0.78 &&
                        photoCount >= 3 &&
                        agg.darkTopBias > 0.38 &&
                        agg.highTextureChaos)
                ? 'High'
                : 'Medium')
          : (granuleLoss || upperPlaneWear)
          ? 'Medium'
          : 'Low';
      // Skip weak "surface wear" on multi-angle healthy sets (low distress).
      if (!damaged &&
          !granuleLoss &&
          !upperPlaneWear &&
          agg.overallDistress < 0.26 &&
          roofDefect < 0.38 &&
          photoCount >= 3) {
        // no-op: leave roof out of candidates for clean homes
      } else {
        // Reserve the strong "Missing / Damaged Shingles" title for real damage
        // evidence — multi-photo aging alone must not promote to High via title.
        final hardDamageTitle =
            (labeledRoofDamage &&
                hardDamageLabel > 0.70 &&
                roofDefect > 0.58) ||
            (roofVotes >= 2 && hardDamageLabel > 0.66 && roofDefect > 0.64) ||
            (roofDefect > 0.80 && hardDamageLabel > 0.58) ||
            (hardDamageLabel > 0.76 && roofLabel > 0.68 && roofDefect > 0.62);
        // Prefer honest aging title when this is granule/UV wear, not impact.
        final preferAgingTitle =
            (granuleLoss || upperPlaneWear) &&
            !labeledRoofDamage &&
            hardDamageLabel < 0.48 &&
            !damaged;
        final title = preferAgingTitle
            ? 'Shingle Granule Loss & Aging'
            : damaged
            ? (hardDamageTitle
                  ? 'Missing / Damaged Shingles'
                  : 'Roof Surface Wear / Possible Impact')
            : granuleLoss
            ? 'Shingle Granule Loss & Aging'
            : upperPlaneWear
            ? 'Roof Surface Wear / Possible Impact'
            : 'Roof Surface Wear';

        final evidence = <_Evidence>[
          if (fused.roofPresence > 0.38)
            _Evidence(
              'roof plane signature in upper frame',
              fused.roofPresence,
            ),
          if (agg.highTextureChaos)
            const _Evidence('irregular roof texture / tab chaos', 0.84),
          if (agg.darkPatchRatio > 0.16 && agg.darkTopBias > 0.20)
            const _Evidence('dark patches on upper surfaces', 0.74),
          if (agg.crackLineScore > 0.34 && fused.roofPresence > 0.3)
            _Evidence('linear disruption on roof field', agg.crackLineScore),
          if (granuleLoss || upperPlaneWear)
            const _Evidence('grey granule-like aging field', 0.70),
          if (roofLabel > 0.38) _Evidence('roof materials labeled', roofLabel),
          if (roofDamageLabel > 0.4)
            _Evidence('damage-related labels near roof', roofDamageLabel),
          if (roofVotes >= 2)
            _Evidence(
              'corroborated in $roofVotes of $photoCount photos',
              0.88 * coverageFactor,
            ),
        ];

        final conf = _confidence(
          presence: roofPresence,
          defect: damaged || granuleLoss || upperPlaneWear
              ? max(roofDefect, (granuleLoss || upperPlaneWear) ? 0.55 : 0)
              : roofPresence * 0.48,
          evidence: evidence,
          labelHits: labelHits([
            'roof',
            'shingle',
            'asphalt shingle',
            'asphalt roof',
            'tile roof',
          ]),
          photoVotes: roofVotes,
          photoCount: photoCount,
          visionMode: visionMode,
          categoryWeight: 1.0,
        );

        // Caption-labeled roof damage must survive secondary demotion filters.
        // Boost when upper-plane cues dominate so roof ranks over wall bleed.
        final upperPlaneDominant =
            fused.roofPresence > 0.42 &&
            agg.darkTopBias > 0.34 &&
            fused.wallPresence < 0.55;
        final roofScore =
            (roofPresence * 0.28 +
                    roofDefect * 0.54 +
                    (damaged ? 0.22 : 0) +
                    (granuleLoss || upperPlaneWear ? 0.16 : 0) +
                    (labeledRoofDamage ? 0.14 : 0) +
                    (hardDamageTitle ? 0.08 : 0) +
                    (upperPlaneDominant || upperPlaneWear ? 0.16 : 0) +
                    (agg.highTextureChaos && fused.roofPresence > 0.42
                        ? 0.10
                        : 0))
                .clamp(0.0, 1.0);
        // Dual-gate severity is authoritative — labels raise Medium, not free High.
        final roofSeverity = severity;

        // Pure soil/grade frames must not invent roof-field damage.
        if (soilOnlyScene && !roofSceneOk) {
          // skip
        } else {
        candidates.add(
          _ScoredIssue(
            category: 'roof',
            criticality: 1.0,
            score: roofScore,
            issue: AnalysisIssue(
              title: title,
              location: damaged
                  ? (agg.darkTopBias > 0.42
                        ? 'Primary upper roof plane'
                        : 'Roof field, ridges & valleys')
                  : granuleLoss
                  ? 'Sun-exposed roof slopes'
                  : 'Roof field & transitions',
              severity: roofSeverity,
              cost: damaged
                  ? (roofSeverity == 'High'
                        ? '\$2,200 – \$5,400'
                        : '\$1,600 – \$3,800')
                  : granuleLoss || upperPlaneWear
                  ? '\$1,200 – \$2,800'
                  : '\$750 – \$1,900',
              // Do not inflate confidence enough to unlock High on weak frames.
              confidence: labeledRoofDamage && hardDamageLabel > 0.70
                  ? max(conf, 80)
                  : conf,
              insight: _reasonedInsight(
                finding: damaged
                    ? 'Roof damage is supported by disrupted upper-plane texture and dark patching consistent with missing tabs, impact scars, or uplift.'
                    : granuleLoss || upperPlaneWear
                    ? 'Asphalt aging shows a grey, finely textured field typical of granule loss (UV shield thinning).'
                    : 'Roof surfaces are readable with only mild wear; no strong failure cluster.',
                evidence: evidence,
                confidence: conf,
                whyItMatters: damaged
                    ? 'Openings in the roof system let water reach underlayment and decking, driving interior leaks and mold risk.'
                    : granuleLoss
                    ? 'Lost granules shorten remaining shingle life and leave slopes more vulnerable in the next storms.'
                    : 'Early monitoring catches problems before a full slope replacement is needed.',
                action: damaged
                    ? 'Prioritize ridges, valleys, and windward slopes; soft decking needs a roofer, not a patch kit.'
                    : granuleLoss
                    ? 'Check gutters for granule piles and plan overlay/replacement on the worst slopes within a few seasons.'
                    : 'Add a closer ridge/valley photo if you have leaks after rain.',
              ),
            ),
          ),
        );
        } // soil-only scene gate
      } // end skip-weak-healthy-roof
    }

    // ── Drainage (eave gutters vs ground discharge) ───────────────────────
    // Split honestly: roof-edge clogging/overflow ≠ water dumping at grade.
    // Do not reuse eave/gutter-line wording when evidence is pipes/soil at grade.
    final eaveStructureLabel = maxLabel([
      'gutter',
      'eaves',
      'eave',
      'soffit',
      'fascia',
      'rain gutter',
    ]);
    // Roof vents labeled "pipe" are not grade outlets. Keep pipe only when
    // a real drainage-domain photo exists in the set.
    final downspoutLabel = maxLabel(
      groundSceneOk
          ? const ['downspout', 'drain', 'pipe', 'outlet', 'discharge']
          : const ['downspout', 'drain', 'outlet', 'discharge'],
    );
    final gutterStructureLabel = max(eaveStructureLabel, downspoutLabel);
    final debrisLabel = maxLabel(['debris', 'leaf', 'clog', 'overflow']);
    final gutterLabel = max(gutterStructureLabel, debrisLabel);
    final eaveLinePresence = _maxN([
      fused.gutterPresence,
      eaveStructureLabel,
      if (agg.gutterLineScore > 0.36) agg.gutterLineScore * 0.88 else 0.0,
      if (agg.horizontalBanding > 0.40 && agg.darkTopBias > 0.26)
        agg.horizontalBanding * 0.72
      else
        0.0,
    ]);
    // Per-photo grade vs eave strength — real house sets often mix eave + pipe photos.
    // Computed before defect fusion so geometry-only outlet frames can fire
    // without Vision labels (field fixture under-call fix).
    var bestGroundFrame = 0.0;
    var bestEaveFrame = 0.0;
    var gradeCloseupFrames = 0;
    for (var i = 0; i < features.length; i++) {
      final f = features[i];
      final photo = i < capturePhotos.length ? capturePhotos[i] : null;
      final roofFieldOnly = photo != null &&
          (_isRoofFieldOnlyPhoto(photo, f) ||
              (_isRoofHostPhoto(photo, f) &&
                  !_isGradeOutletSoilPhoto(photo, f)));
      final groundFrame =
          (f.lowerThirdDark * 0.38 +
                  f.foundationSignal * 0.28 +
                  f.moistureStainScore * 0.24 +
                  f.botEdgeDensity * 0.18 +
                  f.vegetationNear * 0.12 -
                  f.gutterLineScore * 0.45 -
                  f.darkTopBias * 0.12 -
                  f.roofSignal * 0.10)
              .clamp(0.0, 1.0);
      final eaveFrame =
          (f.gutterLineScore * 0.55 +
                  f.horizontalBanding * 0.28 +
                  f.darkTopBias * 0.12 +
                  f.vegetationNear * 0.10 -
                  f.lowerThirdDark * 0.20)
              .clamp(0.0, 1.0);
      if (eaveFrame > bestEaveFrame) bestEaveFrame = eaveFrame;
      // Roof / ridge / vent frames must not contribute grade strength.
      if (roofFieldOnly) continue;
      if (groundFrame > bestGroundFrame) bestGroundFrame = groundFrame;
      // Close-up grade/outlet: dark lower soil, weak roof/eave, wall or base present.
      // Thresholds are intentionally softer than synthetic groundDischarge
      // snapshots so real phone outlet + wet soil CUs still qualify.
      final gradeCloseup =
          f.lowerThirdDark > 0.30 &&
          f.gutterLineScore < 0.46 &&
          f.darkTopBias < 0.46 &&
          f.roofSignal < 0.52 &&
          (f.moistureStainScore > 0.16 ||
              f.vegetationNear > 0.08 ||
              f.darkPatchRatio > 0.06 ||
              f.botEdgeDensity > 0.14) &&
          (f.foundationSignal > 0.24 ||
              f.wallSignal > 0.26 ||
              f.botEdgeDensity > 0.12 ||
              f.lowerThirdDark > 0.38);
      if (gradeCloseup) gradeCloseupFrames++;
    }

    final groundDischargePresence = _maxN([
      downspoutLabel,
      if (agg.lowerThirdDark > 0.42) agg.lowerThirdDark * 0.72 else 0.0,
      if (agg.moistureStainScore > 0.28 && agg.lowerThirdDark > 0.34)
        agg.moistureStainScore * 0.80
      else
        0.0,
      if (fused.foundationPresence > 0.40 && downspoutLabel > 0.34)
        fused.foundationPresence * 0.55
      else
        0.0,
      if (agg.botEdgeDensity > 0.16 && agg.lowerThirdDark > 0.38)
        agg.botEdgeDensity * 0.55
      else
        0.0,
      // Geometry-only grade/outlet presence (local multi-feature, no Vision).
      if (gradeCloseupFrames >= 1 && bestGroundFrame > 0.36)
        max(0.42, bestGroundFrame * 0.88)
      else
        0.0,
    ]);
    // Combined drainage presence (eave line or ground outlet).
    final gutterPresence = _maxN([eaveLinePresence, groundDischargePresence]);
    final labeledOverflow =
        (eaveStructureLabel > 0.52 && debrisLabel > 0.45) ||
        (debrisLabel > 0.52 &&
            hasAny(['clog', 'overflow', 'debris', 'leaf', 'gutter'])) ||
        (gutterLabel > 0.58 &&
            hasAny(['clog', 'overflow', 'debris', 'leaf']) &&
            eaveStructureLabel > 0.40);
    final overflowDefect = _maxN([
      fused.gutterDefect,
      // Vegetation + eave structure (real overflow calibration cases).
      if (eaveLinePresence > 0.34 && agg.vegetationNear > 0.24) 0.50 else 0.0,
      if (agg.gutterLineScore > 0.38 && agg.vegetationNear > 0.22)
        0.52
      else
        0.0,
      if (agg.horizontalBanding > 0.40 && agg.vegetationNear > 0.24)
        0.52
      else
        0.0,
      // Eave structure + debris labels without needing high veg.
      if (eaveStructureLabel > 0.55 && debrisLabel > 0.45) 0.54 else 0.0,
      // Dark trough staining only with vegetation or debris labels + eave line.
      if (eaveLinePresence > 0.38 &&
          agg.darkPatchRatio > 0.18 &&
          (agg.vegetationNear > 0.20 || debrisLabel > 0.42))
        0.44
      else
        0.0,
      if (eaveLinePresence > 0.30) debrisLabel * 0.92 else debrisLabel * 0.35,
      if (labeledOverflow) 0.60 else 0.0,
    ]);
    // Ground: water may dump near foundation (short outlets, wet soil, pipes).
    final groundDischargeDefect = _maxN([
      if (downspoutLabel > 0.42 &&
          (agg.lowerThirdDark > 0.40 ||
              agg.moistureStainScore > 0.28 ||
              fused.foundationPresence > 0.38))
        0.52
      else
        0.0,
      if (downspoutLabel > 0.50) downspoutLabel * 0.70 else 0.0,
      if (agg.moistureStainScore > 0.32 &&
          agg.lowerThirdDark > 0.42 &&
          (downspoutLabel > 0.34 || fused.foundationPresence > 0.40))
        0.48
      else
        0.0,
      if (agg.lowerThirdDark > 0.50 &&
          fused.foundationPresence > 0.42 &&
          downspoutLabel > 0.38)
        0.50
      else
        0.0,
      if (hasAny(['discharge', 'outlet', 'pipe']) &&
          (agg.lowerThirdDark > 0.36 || agg.moistureStainScore > 0.26))
        0.46
      else
        0.0,
      // Geometry-only: wet/eroded soil + base/outlet close-up without labels.
      // Gated so multi-angle healthy elevations with landscaping do not invent
      // drainage findings (require grade close-up frame + weak eave plane).
      if (gradeCloseupFrames >= 1 &&
          bestGroundFrame > 0.34 &&
          agg.gutterLineScore < 0.48 &&
          bestGroundFrame >= bestEaveFrame - 0.08 &&
          (agg.moistureStainScore > 0.16 ||
              agg.vegetationNear > 0.08 ||
              downspoutLabel > 0.30 ||
              hasAny(['pipe', 'outlet', 'discharge', 'soil'])) &&
          (agg.lowerThirdDark > 0.30 || fused.foundationPresence > 0.30))
        0.50
      else
        0.0,
      if (gradeCloseupFrames >= 2 &&
          bestGroundFrame > 0.40 &&
          agg.gutterLineScore < 0.42)
        0.50
      else
        0.0,
    ]);
    final gutterVotes = photoVotes(
      (s) =>
          s.gutterPresence > 0.34 ||
          (s.gutterDefect > 0.34 && s.gutterPresence > 0.28),
    );
    final groundVotes = photoVotes(
      (s) =>
          s.foundationPresence > 0.40 ||
          (s.vegetationNear < 0.50 && s.foundationPresence > 0.32),
    );

    // Ground-dominant when grade/outlet cues beat eave-line structure.
    // Do not require aggregate gutterLineScore to be low — another photo may
    // carry eave geometry while the primary evidence is pipes at grade.
    final pipeOutletLabels =
        downspoutLabel > 0.48 ||
        hasAny(['pipe', 'outlet', 'discharge', 'drain']);
    final groundDominant =
        groundDischargeDefect > 0.38 &&
        (groundDischargePresence > 0.34 || bestGroundFrame > 0.40) &&
        (
        // Aggregate ground strength beats eave overflow path
        (groundDischargePresence + groundDischargeDefect + bestGroundFrame) >
                (eaveLinePresence +
                    overflowDefect * 0.75 +
                    bestEaveFrame +
                    0.04) ||
            // Strong pipe/outlet labels without real eave structure labels
            (pipeOutletLabels &&
                eaveStructureLabel < 0.50 &&
                eaveLinePresence < 0.52) ||
            // Best frame is clearly grade-level
            (bestGroundFrame > bestEaveFrame + 0.10 &&
                bestGroundFrame > 0.42 &&
                agg.gutterLineScore < 0.48) ||
            // Geometry-only grade/outlet close-up (field fixtures, local mode)
            (gradeCloseupFrames >= 1 &&
                bestGroundFrame > 0.40 &&
                eaveLinePresence < 0.48 &&
                agg.gutterLineScore < 0.44));

    // Emit only with real drainage presence — not soft landscaping alone.
    final gutterEligible =
        gutterPresence > 0.34 ||
        eaveStructureLabel > 0.42 ||
        labeledOverflow ||
        (overflowDefect > 0.46 && eaveLinePresence > 0.30) ||
        (groundDominant && groundDischargeDefect > 0.38) ||
        (downspoutLabel > 0.48 && groundDischargePresence > 0.34) ||
        (pipeOutletLabels && bestGroundFrame > 0.44) ||
        (gradeCloseupFrames >= 1 &&
            groundDischargeDefect > 0.42 &&
            bestGroundFrame > 0.40);

    if (gutterEligible) {
      final geometryOverflow =
          overflowDefect > 0.48 &&
          eaveLinePresence > 0.36 &&
          (agg.vegetationNear > 0.22 || debrisLabel > 0.42) &&
          (agg.gutterLineScore > 0.32 ||
              gutterVotes >= 2 ||
              eaveStructureLabel > 0.50) &&
          !groundDominant;
      final overflow = (labeledOverflow || geometryOverflow) && !groundDominant;

      // Modes: ground discharge | clear eave overflow | soft drainage check.
      final isGroundMode = groundDominant;
      final isEaveOverflowMode = !isGroundMode && overflow;

      final evidence = <_Evidence>[
        if (isGroundMode) ...[
          if (downspoutLabel > 0.34)
            _Evidence('downspout / outlet labels', downspoutLabel),
          if (agg.lowerThirdDark > 0.36)
            _Evidence('darker wet-looking soil near grade', agg.lowerThirdDark),
          if (agg.moistureStainScore > 0.26)
            _Evidence('moisture stains near base', agg.moistureStainScore),
          if (fused.foundationPresence > 0.36)
            _Evidence(
              'foundation / grade area in the photo',
              fused.foundationPresence,
            ),
          if (groundVotes >= 2)
            _Evidence('ground-level cues in $groundVotes photos', 0.72),
        ] else ...[
          if (fused.gutterPresence > 0.32)
            _Evidence('gutter line along the roof edge', fused.gutterPresence),
          if (agg.gutterLineScore > 0.34)
            _Evidence('continuous eave / gutter shape', agg.gutterLineScore),
          if (agg.vegetationNear > 0.24)
            _Evidence(
              'plants or debris near the roof edge',
              agg.vegetationNear,
            ),
          if (eaveStructureLabel > 0.35)
            _Evidence('gutter / eave labels', eaveStructureLabel),
          if (debrisLabel > 0.35)
            _Evidence('debris or clog labels', debrisLabel),
          if (downspoutLabel > 0.40 && !isEaveOverflowMode)
            _Evidence('downspout labels', downspoutLabel),
          if (gutterVotes >= 2)
            _Evidence('eave cues in $gutterVotes photos', 0.75),
        ],
      ];
      final presenceForConf = isGroundMode
          ? groundDischargePresence
          : eaveLinePresence;
      final defectForConf = isGroundMode
          ? groundDischargeDefect
          : (isEaveOverflowMode ? overflowDefect : eaveLinePresence * 0.40);
      var conf = _confidence(
        presence: presenceForConf,
        defect: defectForConf,
        evidence: evidence,
        labelHits: labelHits([
          'gutter',
          'downspout',
          'drain',
          'eaves',
          'debris',
          'pipe',
          'outlet',
        ]),
        photoVotes: isGroundMode ? max(gutterVotes, groundVotes) : gutterVotes,
        photoCount: photoCount,
        visionMode: visionMode,
        categoryWeight: 0.85,
      );
      // Conservative: do not sound certain on zone-only / soft drainage claims.
      if (isEaveOverflowMode && conf < 82) {
        conf = min(conf, 78);
      }
      if (isGroundMode) {
        // Ground discharge is often a zone estimate — keep confidence honest.
        // Cap under later label boosts (+2) so UI stays ≤ ~84.
        conf = min(conf, visionMode ? 80 : 76);
        if (eaveLinePresence < 0.30 && downspoutLabel < 0.55) {
          conf = min(conf, 74);
        }
      }
      if (!isGroundMode && !isEaveOverflowMode) {
        conf = min(conf, 78);
      }

      final useOverflowTitle =
          isEaveOverflowMode &&
          conf >= 78 &&
          (labeledOverflow ||
              geometryOverflow ||
              (eaveStructureLabel > 0.55 &&
                  debrisLabel > 0.45 &&
                  overflowDefect > 0.44));
      final useGroundTitle =
          groundSceneOk &&
          isGroundMode &&
          conf >= 66 &&
          groundDischargeDefect > 0.38 &&
          (downspoutLabel > 0.34 ||
              gradeCloseupFrames >= 1 ||
              pipeOutletLabels ||
              bestGroundFrame > 0.40);

      // Roof-only / no grade host: stay in the roof domain. Do not mint
      // ground-discharge or a soft drainage check from vent-pipe labels.
      if ((isGroundMode && !groundSceneOk) ||
          (roofDominantScene && !groundSceneOk && !isEaveOverflowMode)) {
        // skip gutter candidate
      } else {
      final String title;
      final String location;
      final String severity;
      final String cost;
      final String finding;
      final String whyItMatters;
      final String action;
      if (useGroundTitle) {
        title = 'Water May Be Dumping Near Foundation';
        location = 'Downspout outlets & soil at grade';
        severity = 'Medium';
        cost = r'$280 – $900';
        finding =
            'Photos look more like water leaving near the foundation than a clogged gutter at the roof edge';
        whyItMatters =
            'Water that pools at the base can wet the foundation, stain siding, and feed basement or crawlspace dampness';
        action =
            'Extend downspouts 4–6 ft from the house, clear outlet ends, and check that soil slopes away after rain';
      } else if (useOverflowTitle) {
        title = 'Possible Gutter Overflow';
        location = 'Roof edge / gutters';
        severity = 'Medium';
        cost = r'$450 – $1,200';
        finding =
            'Photos suggest gutters may be clogged or overflowing at the roof edge';
        whyItMatters =
            'Overflow can soak fascia boards and send water down the wall or toward the foundation';
        action =
            'Clean gutters and hangers, then check that water runs to the outlets and away from the house';
      } else {
        title = 'Drainage Check';
        location = isGroundMode
            ? 'Downspouts & ground outlets'
            : 'Roof edge drainage';
        severity = 'Low';
        cost = r'$220 – $680';
        finding = isGroundMode
            ? 'Drainage parts show near the ground; these photos do not clearly prove a clogged roof gutter'
            : 'Drainage parts may be present; these photos do not clearly prove clogging or overflow';
        whyItMatters =
            'Even clean gutters fail if water is sent back toward the home at the outlet';
        action = isGroundMode
            ? 'After rain, check whether water leaves near the foundation and add extensions if it does'
            : 'Check that gutters slope to outlets and water clears the foundation line';
      }

      var gutterScore =
          (presenceForConf * 0.34 +
                  defectForConf * 0.42 +
                  (useOverflowTitle || useGroundTitle ? 0.18 : 0) +
                  (labeledOverflow && !isGroundMode ? 0.14 : 0) +
                  (useGroundTitle ? 0.12 : 0) +
                  (eaveStructureLabel > 0.55 && !isGroundMode ? 0.10 : 0) +
                  (downspoutLabel > 0.55 && isGroundMode ? 0.10 : 0) +
                  (gutterVotes >= 2 || groundVotes >= 2 ? 0.06 : 0) +
                  (useOverflowTitle || useGroundTitle ? 0.08 : 0) +
                  // Geometry-only grade/outlet frames need a score floor so
                  // multi+mild demotion does not erase real discharge evidence.
                  (isGroundMode && gradeCloseupFrames >= 1 ? 0.10 : 0) +
                  (isGroundMode && pipeOutletLabels ? 0.08 : 0))
              .clamp(0.0, 1.0);
      if (useGroundTitle) {
        gutterScore = max(gutterScore, 0.58);
      }

      candidates.add(
        _ScoredIssue(
          category: 'gutter',
          criticality: 0.75,
          score: gutterScore,
          issue: AnalysisIssue(
            title: title,
            location: location,
            severity: severity,
            cost: cost,
            confidence: conf,
            insight: _reasonedInsight(
              finding: finding,
              evidence: evidence,
              confidence: conf,
              whyItMatters: whyItMatters,
              action: action,
            ),
          ),
        ),
      );
      } // roof-dominant scene gate
    }

    // ── Siding / cladding ─────────────────────────────────────────────────
    // True cladding materials (not generic house/building — those fire on
    // grade/outlet Quick Scans and must not mint wall-crack findings alone).
    final claddingMaterialLabel = maxLabel([
      'siding',
      'facade',
      'brick',
      'stucco',
      'vinyl',
      'clapboard',
      'masonry',
    ]);
    // Board/panel cladding systems — not bare brick beside a window.
    final trueCladdingLabel = maxLabel([
      'siding',
      'cladding',
      'vinyl',
      'clapboard',
      'fiber cement',
      'fiber-cement',
      'hardie',
      'facade',
    ]);
    final wallStructureLabel = maxLabel([
      'wall',
      'house',
      'building',
      'exterior',
    ]);
    // Presence may use structure labels; crack claims need cladding or real wall.
    final sidingLabel = max(claddingMaterialLabel, wallStructureLabel);
    final crackLabel = maxLabel([
      'crack',
      'broken',
      'damage',
      'hole',
      'fracture',
      'chip',
    ]);
    // Explicit patch / mismatch language (Vision, captions, soft geometry priors).
    final patchLabel = maxLabel([
      'patch',
      'repair',
      'mismatched',
      'discoloration',
      'replacement',
      'plywood',
    ]);
    final sidingPresence = max(fused.wallPresence, sidingLabel * 0.9);
    // Grade / outlet / soil / pipe / mulch frames must not invent cladding cracks.
    final sidingGradeObjectLabel = maxLabel([
      'pipe',
      'drain',
      'outlet',
      'soil',
      'mulch',
      'gravel',
      'downspout',
      'sidewalk',
    ]);
    // Window / glass close-ups must not invent "siding cracks" from shatter lines.
    final windowGlassLabel = maxLabel([
      'window',
      'glass',
      'pane',
      'glazing',
      'sill',
      'shutter',
    ]);
    final glassSceneDominant =
        windowGlassLabel >= 0.55 &&
        trueCladdingLabel < 0.52 &&
        windowGlassLabel + 0.06 >= trueCladdingLabel &&
        !hasAny(['siding', 'clapboard', 'vinyl siding', 'cladding']);
    final sidingGradeCaptionDominant =
        sidingGradeObjectLabel >= 0.55 &&
        claddingMaterialLabel < 0.55 &&
        (fused.foundationPresence + sidingGradeObjectLabel) >
            (fused.wallPresence + claddingMaterialLabel * 0.5 + 0.05);
    final sidingGradeFramesOnly =
        features.isNotEmpty &&
        features.every(
          (f) =>
              f.foundationSignal > 0.42 &&
              f.wallSignal < 0.48 &&
              f.crackLineScore < 0.50 &&
              (f.lowerThirdDark > 0.40 ||
                  f.botEdgeDensity > 0.18 ||
                  f.moistureStainScore > 0.30),
        );
    final weakSidingOnGrade =
        glassSceneDominant ||
        sidingGradeFramesOnly ||
        sidingGradeCaptionDominant ||
        (sidingGradeObjectLabel >= 0.55 &&
            fused.wallPresence < 0.48 &&
            claddingMaterialLabel < 0.55 &&
            fused.foundationPresence + sidingGradeObjectLabel >
                fused.wallPresence + 0.10) ||
        (fused.foundationPresence > fused.wallPresence + 0.14 &&
            fused.wallPresence < 0.46 &&
            claddingMaterialLabel < 0.52 &&
            sidingGradeObjectLabel >= 0.48);
    // Clapboard courses create mid-wall edges — do not treat that as cracks
    // without real crackLineScore or crack labels.
    // On grade-dominant frames, crack labels apply to soil/pipe — not cladding.
    final crackDefect = _maxN([
      weakSidingOnGrade ? fused.crackDefect * 0.25 : fused.crackDefect,
      crackLabel *
          (weakSidingOnGrade
              ? 0.12
              : sidingPresence > 0.40 && fused.wallPresence > 0.40
              ? 0.92
              : 0.35),
      if (!weakSidingOnGrade &&
          agg.crackLineScore > 0.46 &&
          fused.wallPresence > 0.40)
        0.52
      else
        0.0,
      if (!weakSidingOnGrade &&
          agg.crackLineScore > 0.40 &&
          agg.midEdgeDensity > 0.22 &&
          agg.contrast > 56 &&
          fused.wallPresence > 0.40)
        0.40
      else
        0.0,
    ]);
    final moistureDefect = _maxN([
      weakSidingOnGrade ? fused.moistureDefect * 0.30 : fused.moistureDefect,
      maxLabel([
        'mold',
        'mildew',
        'stain',
        'algae',
        'moss',
        'water damage',
        'efflorescence',
        'damp',
      ]) *
          (weakSidingOnGrade ? 0.20 : 1.0),
      // Prefer lower-wall moisture, not global green (trees).
      // Note: bare "discoloration" is handled by patch/mismatch path below so
      // white replacement boards are not forced into moisture staining.
      if (!weakSidingOnGrade &&
          agg.moistureStainScore > 0.32 &&
          agg.greenDominance < 0.45)
        0.44
      else
        0.0,
      if (!weakSidingOnGrade &&
          agg.lowerThirdDark > 0.32 &&
          agg.greenDominance > 0.10 &&
          agg.greenDominance < 0.42)
        0.38
      else
        0.0,
      if (!weakSidingOnGrade &&
          agg.darkPatchRatio > 0.20 &&
          fused.wallPresence > 0.36 &&
          agg.moistureStainScore > 0.28)
        0.36
      else
        0.0,
    ]);
    // Color-block / replacement-board signal (white patches on weathered walls).
    final patchDefect = _maxN([
      patchLabel *
          (weakSidingOnGrade
              ? 0.12
              : sidingPresence > 0.40
              ? 0.95
              : 0.40),
      if (!weakSidingOnGrade &&
          agg.highLuminanceVariance > 0.58 &&
          fused.wallPresence > 0.46 &&
          agg.peelingScore < 0.48)
        0.58
      else
        0.0,
      if (!weakSidingOnGrade &&
          agg.highLuminanceVariance > 0.52 &&
          agg.midEdgeDensity > 0.18 &&
          fused.wallPresence > 0.44 &&
          agg.peelingScore < 0.46)
        0.48
      else
        0.0,
      if (!weakSidingOnGrade &&
          agg.darkPatchRatio > 0.14 &&
          agg.highLuminanceVariance > 0.50 &&
          fused.wallPresence > 0.44)
        0.42
      else
        0.0,
    ]);
    final wallVotes = photoVotes(
      (s) =>
          !weakSidingOnGrade &&
          (s.crackDefect > 0.34 ||
              s.moistureDefect > 0.34 ||
              s.wallPresence > 0.45),
    );
    final patchVotes = photoVotes(
      (s) =>
          !weakSidingOnGrade &&
          s.wallPresence > 0.42 &&
          (s.peelDefect > 0.28 ||
              s.crackDefect > 0.28 ||
              s.wallPresence > 0.50),
    );

    final wallColorBlock =
        !weakSidingOnGrade &&
        fused.wallPresence > 0.44 &&
        agg.highLuminanceVariance > 0.54 &&
        agg.peelingScore < 0.50;

    if (!weakSidingOnGrade &&
        (sidingPresence > 0.38 ||
            crackDefect > 0.48 ||
            moistureDefect > 0.46 ||
            patchDefect > 0.46 ||
            wallColorBlock)) {
      // Prefer true wall cracks over generic "damage/crack" labels that also
      // apply to roofs/foundations — require linear crack structure, not just
      // clapboard edges or paint patch variance.
      // When the frame is roof-dominated, do not invent cladding cracks.
      // Guided wall captions/labels override roof-dominated suppression.
      final wallLabelBacked =
          claddingMaterialLabel > 0.55 ||
          (wallStructureLabel > 0.60 && fused.wallPresence > 0.46) ||
          crackLabel >= 0.55 ||
          patchLabel >= 0.50;
      final foundationLabelCtx =
          maxLabel([
            'foundation',
            'concrete',
            'settlement',
            'settling',
            'spall',
            'honeycomb',
          ]) >
          0.58;
      // Crack labels from foundation / grade CUs must not invent cladding damage.
      // Use cladding materials (not house/building) so grade+house tags stay blocked.
      final foundationCrackContext =
          (foundationLabelCtx || sidingGradeObjectLabel >= 0.55) &&
          hasAny(['crack', 'settling', 'settlement', 'fracture', 'chip']) &&
          claddingMaterialLabel < 0.58;
      final roofDominated =
          !wallLabelBacked &&
          ((fused.roofPresence > 0.48 && fused.wallPresence < 0.48) ||
              (agg.darkTopBias > 0.40 &&
                  fused.roofPresence > 0.40 &&
                  fused.wallPresence < 0.52) ||
              (agg.highTextureChaos &&
                  agg.darkTopBias > 0.36 &&
                  fused.roofPresence > 0.42));
      // Medium cracked siding — labels carry guided/true cases; pure geometry
      // is strict so healthy multi-angle clapboard edges do not invent cracks.
      final geometryCracked =
          !roofDominated &&
          !foundationCrackContext &&
          crackDefect > 0.66 &&
          agg.crackLineScore > 0.54 &&
          fused.wallPresence > 0.52 &&
          wallVotes >= 2 &&
          agg.peelingScore < 0.36 &&
          fused.roofPresence < 0.42;
      // Label cracks need cladding language or strong wall plane — never house
      // alone on a grade/outlet frame (chip/crack tags on soil/mulch).
      final labelCracked =
          !foundationCrackContext &&
          crackLabel >= 0.55 &&
          crackDefect > 0.42 &&
          (agg.crackLineScore > 0.34 || crackLabel >= 0.65) &&
          fused.wallPresence > 0.42 &&
          (claddingMaterialLabel > 0.55 ||
              (wallStructureLabel > 0.58 &&
                  fused.wallPresence > 0.48 &&
                  claddingMaterialLabel >= 0.40));
      final cracked = geometryCracked || labelCracked;
      // Mismatched / patched siding — obvious color-block replacement boards.
      // Do not invent from mild clapboard variance alone.
      final geometryPatched =
          !roofDominated &&
          !foundationCrackContext &&
          !cracked &&
          fused.wallPresence > 0.46 &&
          sidingPresence > 0.42 &&
          patchDefect > 0.50 &&
          agg.highLuminanceVariance > 0.54 &&
          agg.peelingScore < 0.50 &&
          agg.crackLineScore < 0.54 &&
          (agg.midEdgeDensity > 0.16 ||
              patchLabel >= 0.45 ||
              claddingMaterialLabel > 0.55) &&
          (wallVotes >= 1 || photoCount == 1);
      final labelPatched =
          !foundationCrackContext &&
          !cracked &&
          (claddingMaterialLabel > 0.48 ||
              (wallStructureLabel > 0.50 && fused.wallPresence > 0.42)) &&
          patchLabel >= 0.48 &&
          fused.wallPresence > 0.38 &&
          (agg.highLuminanceVariance > 0.40 ||
              patchLabel >= 0.55 ||
              hasAny([
                'patch',
                'mismatched',
                'repair',
                'replacement',
                'discoloration',
              ]));
      final patched = geometryPatched || labelPatched;
      // Moisture only if not primarily a crack or patch finding.
      final moisture =
          !cracked &&
          !patched &&
          !roofDominated &&
          moistureDefect > 0.48 &&
          fused.wallPresence > 0.42 &&
          (agg.moistureStainScore > 0.36 ||
              maxLabel(['mold', 'mildew', 'algae', 'stain']) > 0.45);
      // Soft condition review only with clear cladding language — not generic house.
      final reviewOnly =
          !cracked &&
          !patched &&
          !moisture &&
          sidingPresence > 0.50 &&
          claddingMaterialLabel > 0.55 &&
          fused.wallPresence > 0.45 &&
          agg.overallDistress > 0.28 &&
          !(agg.overallDistress < 0.32 && photoCount >= 3);

      if (cracked || patched || moisture || reviewOnly) {
        // High siding cracks need strong linear geometry — edge noise over-calls.
        final severity = cracked
            ? (crackDefect > 0.86 &&
                          agg.crackLineScore > 0.58 &&
                          photoCount >= 2 &&
                          fused.wallPresence > 0.50 ||
                      (wallVotes >= 2 &&
                          crackDefect > 0.76 &&
                          agg.crackLineScore > 0.58 &&
                          photoCount >= 3 &&
                          fused.wallPresence > 0.52)
                  ? 'High'
                  : 'Medium')
            : patched
            ? (patchDefect > 0.78 &&
                      agg.highLuminanceVariance > 0.68 &&
                      photoCount >= 2 &&
                      fused.wallPresence > 0.50
                  ? 'High'
                  : 'Medium')
            : moisture
            ? 'Medium'
            : 'Low';
        final evidence = <_Evidence>[
          if (fused.wallPresence > 0.35)
            _Evidence('wall / cladding structure', fused.wallPresence),
          if (cracked && agg.crackLineScore > 0.36)
            _Evidence('linear crack-like edges on walls', agg.crackLineScore),
          if (patched && agg.highLuminanceVariance > 0.45)
            _Evidence(
              'high wall brightness variance (color-block / patch)',
              agg.highLuminanceVariance,
            ),
          if (patched && patchLabel > 0.35)
            _Evidence('patch / repair / discoloration labels', patchLabel),
          if (moisture && agg.moistureStainScore > 0.3)
            _Evidence(
              'blotchy moisture / organic staining',
              agg.moistureStainScore,
            ),
          if (sidingLabel > 0.35)
            _Evidence('cladding materials identified', sidingLabel),
          if (crackLabel > 0.40) _Evidence('crack / damage labels', crackLabel),
          if (wallVotes >= 2)
            _Evidence('wall cues across $wallVotes photos', 0.8),
        ];
        var conf = _confidence(
          presence: sidingPresence,
          defect: cracked
              ? crackDefect
              : patched
              ? max(patchDefect, 0.52)
              : moisture
              ? moistureDefect
              : sidingPresence * 0.35,
          evidence: evidence,
          labelHits: labelHits([
            'siding',
            'vinyl',
            'stucco',
            'brick',
            'facade',
            'crack',
            'patch',
            'discoloration',
            'repair',
          ]),
          photoVotes: max(wallVotes, patchVotes),
          photoCount: photoCount,
          visionMode: visionMode,
          categoryWeight: 0.95,
        );
        // Soft cracked without labels needs solid conf for Medium.
        if (cracked && !labelCracked && conf < 84) {
          conf = min(conf, 78);
        }
        // Geometry-only patch: keep conf honest but still Medium-eligible.
        if (patched && !labelPatched && conf < 82) {
          conf = min(max(conf, 78), 84);
        }
        if (patched && (labelPatched || conf >= 80)) {
          conf = max(conf, 82);
        }

        final useCrackTitle =
            cracked &&
            (labelCracked ||
                (geometryCracked && conf >= 84 && agg.crackLineScore > 0.54));
        final usePatchTitle =
            !useCrackTitle &&
            patched &&
            (labelPatched ||
                (geometryPatched &&
                    conf >= 80 &&
                    agg.highLuminanceVariance > 0.52));

        candidates.add(
          _ScoredIssue(
            category: 'siding',
            criticality: useCrackTitle
                ? 0.95
                : usePatchTitle
                ? 0.90
                : 0.8,
            score:
                (sidingPresence * 0.26 +
                        (useCrackTitle
                            ? crackDefect * 0.40
                            : usePatchTitle
                            ? patchDefect * 0.38
                            : crackDefect * 0.18) +
                        (usePatchTitle
                            ? agg.highLuminanceVariance * 0.22
                            : moistureDefect * 0.22) +
                        (useCrackTitle ? 0.18 : 0) +
                        (usePatchTitle ? 0.16 : 0) +
                        (sidingLabel > 0.60 ? 0.10 : 0) +
                        (crackLabel >= 0.55 ? 0.10 : 0) +
                        (patchLabel >= 0.48 ? 0.10 : 0))
                    .clamp(0.0, 1.0),
            issue: AnalysisIssue(
              title: useCrackTitle
                  ? 'Cracked / Damaged Siding'
                  : usePatchTitle
                  ? 'Mismatched / Patched Siding'
                  : moisture
                  ? 'Moisture Staining on Cladding'
                  : 'Siding Condition Review',
              location: useCrackTitle
                  ? 'Wall faces, corners & butt joints'
                  : usePatchTitle
                  ? 'Wall faces with replacement / color-block boards'
                  : moisture
                  ? 'Shaded / lower wall elevations'
                  : 'Exterior wall cladding',
              severity: useCrackTitle || usePatchTitle
                  ? severity
                  : moisture
                  ? 'Medium'
                  : 'Low',
              cost: useCrackTitle
                  ? (severity == 'High'
                        ? '\$1,800 – \$4,200'
                        : '\$1,200 – \$3,200')
                  : usePatchTitle
                  ? (severity == 'High'
                        ? '\$1,600 – \$4,000'
                        : '\$900 – \$2,800')
                  : moisture
                  ? '\$550 – \$1,700'
                  : '\$300 – \$1,000',
              confidence: conf,
              insight: _reasonedInsight(
                finding: useCrackTitle
                    ? 'Cladding damage is supported by fracture-like linear structure and wall context or labels.'
                    : usePatchTitle
                    ? 'Patched or mismatched cladding is supported by wall color-block variance and cladding context (replacement boards, not uniform aging).'
                    : moisture
                    ? 'Moisture staining is supported by blotchy organic/dark patterns on wall regions (not just landscaping green).'
                    : 'Cladding is readable; clear crack damage was not confirmed from these photos.',
                evidence: evidence,
                confidence: conf,
                whyItMatters: useCrackTitle
                    ? 'Open cladding lets water behind the wall assembly, risking sheathing rot and insulation loss.'
                    : usePatchTitle
                    ? 'Mismatched patches often mark prior repairs or incomplete elevations; open joints at board edges can still admit water.'
                    : moisture
                    ? 'Organic growth holds moisture against cladding and can signal poor drying or leak paths.'
                    : 'Routine cladding checks catch problems before a full elevation replacement is needed.',
                action: useCrackTitle
                    ? 'Open joints invite water behind the system — replace damaged courses and reseal penetrations.'
                    : usePatchTitle
                    ? 'Match courses and color on the full elevation where practical; seal board edges and re-check after rain.'
                    : moisture
                    ? 'Soft-wash, improve airflow, and keep irrigation off the siding.'
                    : 'Monitor UV elevations and butt joints for early buckling or film failure.',
              ),
            ),
          ),
        );
      }
    }

    // ── Exterior wiring / cable clutter ───────────────────────────────────
    // Prominent surface cable runs on exterior walls — label-first so indoor
    // cords and clapboard edges do not invent findings.
    final wiringLabel = maxLabel([
      'wiring',
      'cable',
      'wire',
      'electrical',
      'conduit',
      'power line',
      'utility line',
      'extension cord',
    ]);
    final wiringPresence = _maxN([
      wiringLabel,
      if (fused.wallPresence > 0.46 &&
          wiringLabel > 0.30 &&
          agg.verticalBanding > 0.28)
        wiringLabel * 0.95
      else
        0.0,
      // Strong multi-photo wall cable clutter without labels is rare; keep bar high.
      if (fused.wallPresence > 0.52 &&
          agg.verticalBanding > 0.40 &&
          agg.midEdgeDensity > 0.26 &&
          agg.edgeDensity > 0.20 &&
          agg.horizontalBanding < agg.verticalBanding &&
          fused.roofPresence < 0.48 &&
          photoCount >= 2 &&
          sidingPresence > 0.45)
        0.46
      else
        0.0,
    ]);
    final wiringVotes = photoVotes(
      (s) =>
          s.wallPresence > 0.48 &&
          (s.crackDefect > 0.20 || s.wallPresence > 0.55),
    );
    final labelWiring =
        wiringLabel >= 0.48 &&
        fused.wallPresence > 0.36 &&
        (sidingPresence > 0.38 ||
            maxLabel(['house', 'building', 'exterior', 'siding']) > 0.45);
    final geometryWiring =
        !labelWiring &&
        wiringPresence >= 0.46 &&
        fused.wallPresence > 0.52 &&
        agg.verticalBanding > 0.40 &&
        photoCount >= 2 &&
        wiringVotes >= 2;
    final wiringEligible = labelWiring || geometryWiring;

    if (wiringEligible) {
      final severe =
          wiringLabel >= 0.72 ||
          (wiringLabel >= 0.58 && fused.wallPresence > 0.48) ||
          (geometryWiring && agg.verticalBanding > 0.48);
      final evidence = <_Evidence>[
        if (wiringLabel > 0.35)
          _Evidence('cable / wiring / electrical labels', wiringLabel),
        if (fused.wallPresence > 0.35)
          _Evidence('exterior wall structure', fused.wallPresence),
        if (agg.verticalBanding > 0.30)
          _Evidence('vertical linear runs on walls', agg.verticalBanding),
        if (wiringVotes >= 2)
          _Evidence('wall cues across $wiringVotes photos', 0.75),
      ];
      var conf = _confidence(
        presence: max(wiringPresence, fused.wallPresence * 0.7),
        defect: severe ? 0.62 : 0.48,
        evidence: evidence,
        labelHits: labelHits([
          'wiring',
          'cable',
          'wire',
          'electrical',
          'conduit',
        ]),
        photoVotes: max(1, wiringVotes),
        photoCount: photoCount,
        visionMode: visionMode,
        categoryWeight: 0.78,
      );
      if (labelWiring) conf = max(conf, 84);
      if (geometryWiring && conf < 82) conf = min(conf, 80);

      candidates.add(
        _ScoredIssue(
          category: 'wiring',
          criticality: 0.72,
          score:
              (wiringPresence * 0.42 +
                      (labelWiring ? 0.18 : 0) +
                      (severe ? 0.12 : 0) +
                      fused.wallPresence * 0.18 +
                      (agg.verticalBanding > 0.32
                          ? agg.verticalBanding * 0.14
                          : 0))
                  .clamp(0.0, 1.0),
          issue: AnalysisIssue(
            title: severe
                ? 'Heavy Exterior Wiring / Cable Clutter'
                : 'Exterior Wiring / Surface Cables',
            location: 'Wall faces, corners & utility penetrations',
            severity: severe ? 'Medium' : 'Medium',
            cost: severe ? '\$350 – \$1,400' : '\$250 – \$900',
            confidence: conf,
            insight: _reasonedInsight(
              finding: labelWiring
                  ? 'Surface cable / wiring cues appear on exterior wall elevations with supporting structure labels.'
                  : 'Dense vertical linear runs on exterior walls are consistent with surface cable clutter (confirm on-site).',
              evidence: evidence,
              confidence: conf,
              whyItMatters:
                  'Surface cable runs clutter elevations, can snag, and often mark ad-hoc exterior work that needs clean routing or conduit.',
              action:
                  'Have a licensed electrician secure, consolidate, or conduit-route exterior runs; do not cut unknown cables.',
            ),
          ),
        ),
      );
    }

    // ── Paint ─────────────────────────────────────────────────────────────
    // Medium "Peeling / Failing Exterior Paint" needs clear coating failure on
    // walls / trim / fascia — never invent peel from wet soil, pipe, mulch, or
    // grade-only close-ups. Prefer dropping weak paint over false positives.
    final paintLabel = maxLabel([
      'paint',
      'coating',
      'varnish',
      'peel',
      'flake',
      'blister',
    ]);
    // Bare "chip" alone is mulch/wood-chip noise — only count with paint language.
    final peelCoreLabel = maxLabel(['peel', 'flake', 'blister']);
    final chipLabel = maxLabel(['chip']);
    final peelWordLabel = max(
      peelCoreLabel,
      (paintLabel >= 0.55 && chipLabel >= 0.50) ? chipLabel * 0.85 : 0.0,
    );
    // Wall / trim / fascia structure that can legitimately host coating failure.
    final paintHostLabel = maxLabel([
      'wall',
      'siding',
      'cladding',
      'trim',
      'fascia',
      'clapboard',
      'brick',
      'house',
      'building',
    ]);
    final gradeObjectLabel = maxLabel([
      'pipe',
      'drain',
      'outlet',
      'soil',
      'mulch',
      'gravel',
      'downspout',
      'sidewalk',
    ]);
    final wallPaintHost =
        fused.wallPresence > 0.40 ||
        (paintHostLabel > 0.55 && fused.wallPresence > 0.30);
    final peelDefect = _maxN([
      // Geometry peel only counts on wall/trim frames — not grade soil texture.
      wallPaintHost ? fused.peelDefect : fused.peelDefect * 0.35,
      // Peel-word labels only count with wall / coating host presence.
      peelWordLabel * (wallPaintHost ? 0.90 : 0.22),
      // Texture peel needs a high peelingScore on a real wall plane.
      if (agg.peelingScore > 0.50 && wallPaintHost && fused.wallPresence > 0.40)
        0.52
      else
        0.0,
      // Luminance variance alone is weak (shadows, windows, texture).
      if (agg.peelingScore > 0.42 &&
          agg.highLuminanceVariance > 0.62 &&
          agg.contrast > 50 &&
          wallPaintHost &&
          fused.wallPresence > 0.42)
        0.38
      else
        0.0,
    ]);
    final paintVotes = photoVotes(
      (s) =>
          s.peelDefect > 0.42 &&
          s.wallPresence > 0.40 &&
          // Per-photo: do not count grade-dominant frames as paint votes.
          !(s.foundationPresence > s.wallPresence + 0.12 &&
              s.peelDefect < 0.50),
    );
    // Wall-caption / siding-primary frames often have peel-like texture that
    // is cladding variance, not film failure — require paint language.
    final wallCaptionDominant =
        maxLabel(['wall', 'siding', 'cladding', 'brick']) > 0.58 &&
        !hasAny(['peel', 'paint', 'flake', 'blister', 'film', 'coating']);
    // Foundation CUs with spall/moisture texture must not invent paint peel.
    final foundationCaptionDominant =
        maxLabel(['foundation', 'concrete', 'settlement', 'settling']) > 0.58 &&
        paintLabel < 0.55;
    // Grade / outlet / soil / vegetation close-ups must not mint paint peel.
    final gradeCaptionDominant =
        gradeObjectLabel >= 0.55 &&
        paintLabel < 0.62 &&
        peelWordLabel < 0.55 &&
        (fused.foundationPresence + gradeObjectLabel) >
            (fused.wallPresence + paintHostLabel * 0.5);
    // Photos that are all grade-like (pipe/soil) with weak wall peel → no paint.
    final gradeFramesOnly =
        features.isNotEmpty &&
        features.every(
          (f) =>
              f.foundationSignal > 0.42 &&
              f.wallSignal < 0.48 &&
              f.peelingScore < 0.42 &&
              f.lowerThirdDark > 0.40,
        );
    final weakPaintOnGrade =
        !wallPaintHost ||
        gradeFramesOnly ||
        (fused.foundationPresence > fused.wallPresence + 0.14 &&
            agg.peelingScore < 0.48 &&
            peelWordLabel < 0.55);

    // Emit only for real peel (Medium) or strong labeled aging — never soft
    // "Paint Film Aging" from healthy elevation texture noise alone.
    final paintEligible =
        !wallCaptionDominant &&
        !foundationCaptionDominant &&
        !gradeCaptionDominant &&
        !weakPaintOnGrade &&
        (peelDefect > 0.55 ||
            (paintLabel > 0.62 && peelWordLabel > 0.50 && wallPaintHost) ||
            (paintLabel > 0.72 && peelDefect > 0.40 && wallPaintHost));

    if (paintEligible) {
      // Medium peeling title — geometry alone is strict; labels carry real cases.
      final geometryPeeling =
          peelDefect > 0.64 &&
          agg.peelingScore > 0.54 &&
          fused.wallPresence > 0.42 &&
          wallPaintHost &&
          paintVotes >= 2 &&
          paintLabel > 0.35;
      final labelPeeling =
          paintLabel >= 0.68 &&
          peelWordLabel >= 0.55 &&
          peelDefect >= 0.40 &&
          wallPaintHost &&
          (agg.peelingScore >= 0.32 || peelWordLabel >= 0.65);
      final strongSinglePeel =
          peelDefect > 0.66 &&
          agg.peelingScore > 0.55 &&
          fused.wallPresence > 0.44 &&
          wallPaintHost &&
          paintLabel > 0.50 &&
          peelWordLabel > 0.40;
      final peeling = geometryPeeling || labelPeeling || strongSinglePeel;

      final evidence = <_Evidence>[
        if (agg.peelingScore > 0.40 && wallPaintHost)
          _Evidence('patchy luminance consistent with peel', agg.peelingScore),
        if (agg.highLuminanceVariance > 0.55 &&
            agg.peelingScore > 0.38 &&
            wallPaintHost)
          _Evidence(
            'high brightness variance on wall surfaces',
            agg.highLuminanceVariance,
          ),
        if (paintLabel > 0.4) _Evidence('paint/finish labels', paintLabel),
        if (peelWordLabel > 0.4)
          _Evidence('peel / flake labels', peelWordLabel),
        if (wallPaintHost && fused.wallPresence > 0.36)
          _Evidence('wall / trim structure for coating', fused.wallPresence),
        if (paintVotes >= 2) _Evidence('peel cues in $paintVotes photos', 0.78),
      ];
      var conf = _confidence(
        presence: max(fused.wallPresence, paintLabel > 0 ? paintLabel : 0.42),
        defect: peeling
            ? max(peelDefect, peelWordLabel > 0.60 ? 0.58 : 0)
            : peelDefect * 0.45,
        evidence: evidence,
        labelHits: labelHits(['paint', 'peel', 'coating', 'flake', 'blister']),
        photoVotes: paintVotes,
        photoCount: photoCount,
        visionMode: visionMode,
        categoryWeight: 0.8,
      );
      // Medium peel needs solid confidence.
      if (peeling && conf < 82) {
        conf = min(conf, 78);
      }

      final usePeelTitle =
          peeling &&
          conf >= 84 &&
          wallPaintHost &&
          (peelWordLabel >= 0.52 ||
              (agg.peelingScore >= 0.54 &&
                  peelDefect >= 0.58 &&
                  paintVotes >= 2 &&
                  paintLabel > 0.40) ||
              (visionMode && peelWordLabel >= 0.48 && paintLabel >= 0.55));

      // Low "Paint Film Aging" only with explicit paint language — not texture.
      // Healthy multi-angle homes must not get residual Low aging notes.
      final useAgingTitle =
          !usePeelTitle &&
          paintLabel >= 0.68 &&
          peelWordLabel < 0.45 &&
          peelDefect >= 0.42 &&
          paintVotes >= 2 &&
          wallPaintHost &&
          fused.wallPresence > 0.42;

      if (usePeelTitle || useAgingTitle) {
        final paintScore =
            (peelDefect * 0.55 +
                    (usePeelTitle ? 0.16 : 0) +
                    (paintLabel > 0.55 ? paintLabel * 0.32 : 0) +
                    (peelWordLabel > 0.50 ? 0.12 : 0) +
                    (paintVotes >= 2 ? 0.06 : 0) -
                    (useAgingTitle ? 0.12 : 0))
                .clamp(0.0, 1.0);
        candidates.add(
          _ScoredIssue(
            category: 'paint',
            criticality: 0.7,
            score: paintScore,
            issue: AnalysisIssue(
              title: usePeelTitle
                  ? 'Peeling / Failing Exterior Paint'
                  : 'Paint Film Aging',
              location: usePeelTitle
                  ? 'Sun-exposed walls, trim & fascia'
                  : 'Facade film & wood trim',
              severity: usePeelTitle ? 'Medium' : 'Low',
              cost: usePeelTitle ? '\$1,100 – \$2,900' : '\$400 – \$1,250',
              confidence: conf,
              insight: _reasonedInsight(
                finding: usePeelTitle
                    ? 'Failing film is indicated by peel-like patch variance and supporting paint language on wall or trim surfaces.'
                    : 'Finish may be UV-aged; clear peel was not confirmed from these photos.',
                evidence: evidence,
                confidence: conf,
                whyItMatters: usePeelTitle
                    ? 'Bare substrate absorbs water quickly and can rot or corrode under failing paint.'
                    : 'Thin film still protects the surface but UV will open the next peel cycle soon.',
                action: usePeelTitle
                    ? 'Scrape failed film, prime bare wood/metal, and recoat with exterior-grade paint before wet weather.'
                    : 'Prioritize south/west elevations first — UV shortens film life there. Retake a close-up if film is lifting.',
              ),
            ),
          ),
        );

        // Peel texture is frequently misread as cladding cracks. When paint
        // labels/captions clearly support peel, demote opportunistic siding.
        if (usePeelTitle && paintLabel > 0.55 && paintScore >= 0.48) {
          for (var i = 0; i < candidates.length; i++) {
            final c = candidates[i];
            if (c.category != 'siding') continue;
            if (!c.issue.title.toLowerCase().contains('crack')) continue;
            if (c.score > paintScore * 1.15) continue;
            candidates[i] = _ScoredIssue(
              category: c.category,
              criticality: c.criticality,
              score: c.score * 0.72,
              issue: c.issue.copyWith(
                severity: 'Low',
                confidence: min(c.issue.confidence, 74),
              ),
            );
          }
        }
      }
    }

    // ── Foundation ────────────────────────────────────────────────────────
    // Prefer NO foundation finding over a false "Foundation Crack / Settlement".
    // Requires clear crack-line + lower structure + high confidence co-support.
    // Dark soil / lawn bands alone never invent settlement claims.
    final foundationLabel = maxLabel([
      'foundation',
      'concrete',
      'basement',
      'crawl',
      'masonry',
      'retaining',
      // Intentionally omit bare "soil" / "sidewalk" — too common on elevations.
    ]);
    final foundationPresence = max(
      fused.foundationPresence,
      foundationLabel * 0.92,
    );
    final foundationCrackLabel = maxLabel([
      'crack',
      'settling',
      'settlement',
      'shift',
      'fracture',
    ]);
    final foundationDefect = _maxN([
      fused.foundationDefect,
      // Crack labels only count with strong base context (not lawn texture).
      foundationCrackLabel *
          (foundationPresence > 0.62
              ? 0.78
              : foundationPresence > 0.50
              ? 0.22
              : 0.04),
      // Explicit foundation+crack dual labels (captions / Vision).
      if (foundationLabel >= 0.78 && foundationCrackLabel >= 0.64)
        foundationCrackLabel * 0.70
      else
        0.0,
      // Linear crack near grade — co-signals only; no soil-shadow shortcuts.
      if (agg.crackLineScore > 0.58 &&
          fused.foundationPresence > 0.56 &&
          agg.lowerThirdDark > 0.54 &&
          agg.botEdgeDensity > 0.16)
        0.48
      else
        0.0,
    ]);
    final foundationVotes = photoVotes(
      (s) =>
          s.foundationDefect > 0.58 ||
          (s.foundationPresence > 0.60 &&
              s.foundationDefect > 0.48 &&
              s.crackDefect > 0.42),
    );

    // Soft roof-slot labels alone must not be drowned by soil-band foundation.
    final roofLabelDominant =
        maxLabel(['roof', 'shingle', 'asphalt']) > 0.58 &&
        foundationLabel < 0.58 &&
        (agg.darkTopBias > 0.28 || fused.roofPresence > 0.40);

    final hasCrackWords = hasAny([
      'crack',
      'settling',
      'settlement',
      'fracture',
    ]);
    // Roof plane dominance only applies when foundation is NOT label-backed.
    final roofDominatesGrade =
        foundationLabel < 0.66 &&
        fused.roofPresence > 0.44 &&
        (agg.darkTopBias > 0.30 || fused.roofDefect > 0.36) &&
        fused.foundationPresence < fused.roofPresence + 0.06;
    // Elevations often have siding/window linear texture — not foundation cracks.
    final upperPlaneDominates =
        foundationLabel < 0.62 &&
        ((fused.roofPresence > fused.foundationPresence + 0.05 &&
                (agg.darkTopBias > 0.26 || fused.roofDefect > 0.32)) ||
            (fused.wallPresence > fused.foundationPresence + 0.06 &&
                agg.midEdgeDensity > agg.botEdgeDensity + 0.015));
    // Geometry-only crack bar is intentionally very high (false-positive control).
    final clearCrackLine = agg.crackLineScore >= 0.60;
    final strongLowerStructure =
        agg.lowerThirdDark >= 0.56 &&
        (fused.foundationPresence > 0.56 || foundationLabel > 0.64) &&
        agg.botEdgeDensity >= 0.17;

    // Medium "Foundation Crack / Settlement" — significantly raised bar.
    // Geometry alone never invents a crack (siding edges max out crackLine).
    // Prefer no finding when the photo does not clearly support settlement.
    final geometryBackedCrack =
        !roofDominatesGrade &&
        !upperPlaneDominates &&
        foundationDefect > 0.86 &&
        clearCrackLine &&
        strongLowerStructure &&
        foundationPresence > 0.64 &&
        foundationVotes >= 2 &&
        foundationLabel > 0.60 &&
        foundationCrackLabel > 0.52 &&
        agg.crackLineScore >= 0.62 &&
        agg.lowerThirdDark >= 0.56;
    // Caption/Vision path: foundation + crack language with defect co-support.
    // Strong dual labels cover labeled close-ups (calibration / Vision).
    // Soil-band elevations without crack labels still do not invent settlement.
    final dualLabelSettlement =
        foundationLabel >= 0.78 &&
        foundationCrackLabel >= 0.66 &&
        hasCrackWords &&
        foundationPresence > 0.52 &&
        foundationDefect >= 0.40 &&
        !roofDominatesGrade &&
        !upperPlaneDominates;
    final labelBackedCrack =
        dualLabelSettlement ||
        (foundationLabel >= 0.76 &&
            hasCrackWords &&
            foundationCrackLabel >= 0.64 &&
            foundationPresence > 0.56 &&
            foundationDefect >= 0.52 &&
            agg.crackLineScore >= 0.46 &&
            !roofDominatesGrade &&
            !upperPlaneDominates &&
            (strongLowerStructure || foundationLabel >= 0.80));
    final multiPhotoCrack =
        !roofDominatesGrade &&
        !upperPlaneDominates &&
        foundationVotes >= 2 &&
        foundationDefect > 0.82 &&
        clearCrackLine &&
        strongLowerStructure &&
        foundationLabel > 0.60 &&
        foundationCrackLabel > 0.52 &&
        agg.crackLineScore >= 0.58;
    final cracking = geometryBackedCrack || labelBackedCrack || multiPhotoCrack;

    // Emit ONLY with proven cracking, or a very strong multi-cue grade review.
    // Weak soil bands / vague base texture → no foundation finding at all.
    final strongGradeReviewOnly =
        !cracking &&
        !roofLabelDominant &&
        !upperPlaneDominates &&
        !roofDominatesGrade &&
        foundationLabel > 0.78 &&
        foundationPresence > 0.66 &&
        foundationDefect > 0.58 &&
        strongLowerStructure &&
        foundationVotes >= 2 &&
        agg.crackLineScore < 0.52; // not crack-shaped → grade note, not crack
    final foundationEligible =
        !roofLabelDominant && (cracking || strongGradeReviewOnly);

    if (foundationEligible) {
      final evidence = <_Evidence>[
        if (fused.foundationPresence > 0.52)
          _Evidence(
            'grade-line / base-of-wall structure',
            fused.foundationPresence,
          ),
        if (agg.lowerThirdDark > 0.54)
          _Evidence('darker lower-third band', agg.lowerThirdDark),
        if (cracking && agg.botEdgeDensity > 0.16)
          _Evidence('elevated edges at grade', agg.botEdgeDensity),
        if (cracking && agg.crackLineScore > 0.52)
          _Evidence('linear crack structure near grade', agg.crackLineScore),
        if (foundationLabel > 0.60)
          _Evidence('foundation/concrete labels', foundationLabel),
        if (foundationCrackLabel > 0.55)
          _Evidence('crack / settlement labels', foundationCrackLabel),
        if (foundationVotes >= 2)
          _Evidence('base cues in $foundationVotes photos', 0.8),
      ];
      var conf = _confidence(
        presence: foundationPresence,
        defect: cracking ? foundationDefect : foundationPresence * 0.32,
        evidence: evidence,
        labelHits: labelHits(['foundation', 'concrete', 'masonry', 'basement']),
        photoVotes: foundationVotes,
        photoCount: photoCount,
        visionMode: visionMode,
        categoryWeight: 1.0,
      );
      // Soft crack claims: keep conf honest but do not crush caption dual-labels
      // below the medium emit bar (prefer omit later via useCrackTitle).
      if (cracking && conf < 84 && !dualLabelSettlement) {
        conf = min(conf, 78);
      }

      // High foundation claims need multi-photo + strong crack geometry.
      final foundationHigh =
          cracking &&
          conf >= 92 &&
          photoCount >= 3 &&
          foundationVotes >= 2 &&
          agg.crackLineScore >= 0.62 &&
          (foundationDefect > 0.90 &&
                  agg.lowerThirdDark > 0.58 &&
                  agg.botEdgeDensity > 0.17 ||
              (visionMode &&
                  foundationLabel > 0.88 &&
                  foundationCrackLabel > 0.74 &&
                  foundationDefect > 0.86 &&
                  agg.crackLineScore > 0.58 &&
                  agg.lowerThirdDark > 0.54));

      // Crack title only when medium+ evidence is clearly present.
      // Soft confidence → no crack title (prefer omit over over-call).
      final captionStrongSettlement = dualLabelSettlement;
      final crackMediumOk =
          cracking &&
          (captionStrongSettlement ||
              (conf >= 80 &&
                  agg.crackLineScore >= 0.50 &&
                  strongLowerStructure &&
                  (visionMode
                      ? (foundationCrackLabel >= 0.58 ||
                            agg.crackLineScore >= 0.56)
                      : (foundationCrackLabel >= 0.64 ||
                            agg.crackLineScore >= 0.58))));
      // Dual-label settlement (captions / Vision) always uses crack title.
      // Soft geometry-only candidates without the medium bar → omit.
      final useCrackTitle = crackMediumOk;
      if (useCrackTitle || strongGradeReviewOnly) {
        // Dual-label path: floor confidence so Medium filter can keep it.
        if (captionStrongSettlement && conf < 84) {
          conf = max(conf, 84);
        }
        final severity = !useCrackTitle
            ? 'Low'
            : (foundationHigh ? 'High' : 'Medium');

        final gradeDominant =
            agg.lowerThirdDark > 0.54 &&
            fused.foundationPresence > 0.54 &&
            fused.roofPresence < 0.46;
        candidates.add(
          _ScoredIssue(
            category: 'foundation',
            criticality: 1.0,
            score:
                (foundationPresence * 0.16 +
                        foundationDefect * 0.50 +
                        (useCrackTitle ? 0.14 : 0) +
                        (gradeDominant && useCrackTitle ? 0.05 : 0) +
                        (foundationVotes >= 2 ? 0.04 : 0) +
                        (foundationLabel > 0.78 ? 0.08 : 0) +
                        (foundationCrackLabel > 0.66 ? 0.08 : 0) +
                        (agg.crackLineScore > 0.58 ? 0.06 : 0))
                    .clamp(0.0, 1.0),
            issue: AnalysisIssue(
              title: useCrackTitle
                  ? 'Foundation Crack / Settlement Signs'
                  : 'Foundation & Grade Review',
              location: useCrackTitle
                  ? 'Lower wall / grade line & corners'
                  : 'Foundation perimeter & soil grade',
              severity: severity,
              cost: useCrackTitle
                  ? (foundationHigh ? '\$2,000 – \$6,500' : '\$1,400 – \$4,800')
                  : '\$350 – \$1,400',
              confidence: conf,
              insight: _reasonedInsight(
                finding: useCrackTitle
                    ? 'Settlement/crack risk is elevated by clear linear structure at the base plus supporting grade context or labels.'
                    : 'Base-of-wall and grade features are visible; drainage and clearance drive long-term risk more than active cracking.',
                evidence: evidence,
                confidence: conf,
                whyItMatters: useCrackTitle
                    ? 'Growing foundation cracks can open water paths and signal structural movement that worsens seasonally.'
                    : 'Poor grade and trapped moisture at the base often precede real foundation damage.',
                action: useCrackTitle
                    ? 'Document crack width/length, check soil slope toward the house, and consult a foundation pro for stair-step or horizontal cracks.'
                    : 'Keep soil/mulch 6+ inches below siding and recheck after wet seasons for new hairline cracks.',
              ),
            ),
          ),
        );
      }
    }

    // ── Windows ───────────────────────────────────────────────────────────
    final windowLabel = maxLabel([
      'window',
      'glass',
      'frame',
      'door',
      'shutter',
      'pane',
      'glazing',
    ]);
    final windowPresence = max(windowLabel, fused.windowPresence);
    // Broken / shattered pane language — not cladding board cracks.
    final glassDamageLabel = maxLabel([
      'glass',
      'pane',
      'glazing',
      'window',
    ]);
    final glassBreakCue =
        hasAny([
          'broken glass',
          'shattered',
          'shatter',
          'cracked glass',
          'broken window',
        ]) ||
        (glassDamageLabel >= 0.55 &&
            hasAny(['broken', 'shatter', 'damage', 'hole']) &&
            trueCladdingLabel < 0.50);
    // Do not treat global wall color variance (patched siding) as seal failure.
    final sealDefect = _maxN([
      if (windowPresence > 0.36 &&
          windowLabel > 0.40 &&
          agg.moistureStainScore > 0.36)
        0.45
      else
        0.0,
      maxLabel(['fog', 'condensation', 'leak']),
      if (windowLabel > 0.48 &&
          windowPresence > 0.40 &&
          agg.edgeDensity > 0.18 &&
          agg.highLuminanceVariance > 0.55 &&
          maxLabel(['fog', 'condensation', 'leak', 'stain']) > 0.30)
        0.4
      else
        0.0,
      if (glassBreakCue) 0.62 else 0.0,
    ]);

    if (windowPresence > 0.36 || windowLabel > 0.42 || glassBreakCue) {
      final glassDamage = glassBreakCue && glassDamageLabel >= 0.48;
      final sealRisk =
          !glassDamage &&
          (sealDefect > 0.38 ||
              (windowLabel > 0.48 && hasAny(['fog', 'condensation', 'leak'])) ||
              (windowLabel > 0.55 &&
                  hasAny(['crack', 'rust', 'stain']) &&
                  agg.moistureStainScore > 0.30));
      final evidence = <_Evidence>[
        if (windowLabel > 0.35)
          _Evidence('window/door objects detected', windowLabel),
        if (fused.windowPresence > 0.3)
          _Evidence('rectangular opening edge structure', fused.windowPresence),
        if (glassDamage)
          _Evidence('broken or damaged glazing cues', glassDamageLabel),
        if (sealRisk && agg.moistureStainScore > 0.3)
          _Evidence('staining near openings', agg.moistureStainScore),
      ];
      final conf = _confidence(
        presence: max(windowPresence, glassDamage ? glassDamageLabel : 0),
        defect: glassDamage
            ? 0.58
            : sealRisk
            ? sealDefect
            : 0.3,
        evidence: evidence,
        labelHits: labelHits([
          'window',
          'glass',
          'frame',
          'door',
          'pane',
          'broken',
        ]),
        photoVotes: photoVotes((s) => s.windowPresence > 0.35),
        photoCount: photoCount,
        visionMode: visionMode,
        categoryWeight: 0.7,
      );

      candidates.add(
        _ScoredIssue(
          category: 'window',
          criticality: glassDamage ? 0.78 : 0.65,
          score:
              windowPresence +
              (glassDamage ? 0.28 : 0) +
              (sealRisk ? 0.15 : 0),
          issue: AnalysisIssue(
            title: glassDamage
                ? 'Broken / Damaged Window Glass'
                : sealRisk
                ? 'Window Seal / Flashing Concern'
                : 'Window & Opening Inspection',
            location: glassDamage
                ? 'Window glass, sash & frame'
                : 'Sills, heads & perimeter caulk',
            severity: glassDamage
                ? 'Medium'
                : sealRisk
                ? 'Medium'
                : 'Low',
            cost: glassDamage
                ? '\$350 – \$1,800'
                : sealRisk
                ? '\$400 – \$1,500'
                : '\$180 – \$700',
            confidence: conf,
            insight: _reasonedInsight(
              finding: glassDamage
                  ? 'Glazing damage is indicated by broken or shattered glass cues on a window opening.'
                  : sealRisk
                  ? 'Opening distress often means failed glazing seals, open caulk, or weak flashing.'
                  : 'Openings are present without strong seal-failure cues.',
              evidence: evidence,
              confidence: conf,
              whyItMatters: glassDamage
                  ? 'Broken glass is a safety and weather issue — water and debris can enter until the pane is secured.'
                  : sealRisk
                  ? 'Failed seals let water into the rough opening and wall cavity — a common hidden rot path.'
                  : 'Healthy openings still need intact caulk and flashing to keep bulk water out.',
              action: glassDamage
                  ? 'Safely board or temporary-seal if needed, then schedule glass or full unit replacement with a glazier.'
                  : sealRisk
                  ? 'Check for fogged panes and water tracks under sills — common active leak paths.'
                  : 'Verify continuous caulking and that sill pans shed water clear of cladding.',
            ),
          ),
        ),
      );
    }

    // ── Chimney ───────────────────────────────────────────────────────────
    final chimneyLabel = maxLabel(['chimney', 'flue', 'fireplace', 'vent']);
    if (chimneyLabel > 0.38 ||
        (fused.roofPresence > 0.4 &&
            agg.verticalBanding > 0.24 &&
            agg.darkTopBias > 0.32)) {
      final score = max(chimneyLabel, 0.42);
      final elevated = score > 0.7 || hasAny(['crack', 'damage', 'rust']);
      final evidence = <_Evidence>[
        if (chimneyLabel > 0.35)
          _Evidence('chimney/vent identified', chimneyLabel),
        if (fused.roofPresence > 0.35)
          _Evidence('roof plane context', fused.roofPresence),
      ];
      final conf = _confidence(
        presence: score,
        defect: elevated ? 0.55 : 0.3,
        evidence: evidence,
        labelHits: labelHits(['chimney', 'flue', 'masonry', 'vent']),
        photoVotes: chimneyLabel > 0.35
            ? max(1, labelHits(['chimney', 'flue']))
            : 1,
        photoCount: photoCount,
        visionMode: visionMode,
        categoryWeight: 0.75,
      );

      candidates.add(
        _ScoredIssue(
          category: 'chimney',
          criticality: 0.85,
          score: score * 0.7,
          issue: AnalysisIssue(
            title: 'Chimney & Step-Flashing Check',
            location: 'Chimney base / roof intersection',
            severity: elevated ? 'Medium' : 'Low',
            cost: '\$500 – \$2,400',
            confidence: conf,
            insight: _reasonedInsight(
              finding:
                  'Chimney or roof-penetration features are in frame — step flashing is a frequent leak origin.',
              evidence: evidence,
              confidence: conf,
              whyItMatters:
                  'Step-flashing failures are among the top exterior leak sources and often show first as interior stains.',
              action:
                  'Inspect mortar, crown, counter-flashing, and where the chimney meets shingles after wind-driven rain.',
            ),
          ),
        ),
      );
    }

    // ── Vegetation ────────────────────────────────────────────────────────
    final vegLabel = maxLabel([
      'tree',
      'plant',
      'vegetation',
      'branch',
      'leaf',
      'bush',
      'ivy',
      'foliage',
      'shrub',
    ]);
    // Strong green alone is landscaping — need near-structure context.
    final vegPresence = _maxN([
      if (agg.vegetationNear > 0.3 && fused.wallPresence > 0.28)
        agg.vegetationNear
      else
        0.0,
      if (agg.greenDominance > 0.22 && fused.roofPresence > 0.3)
        agg.greenDominance * 0.9
      else
        0.0,
      vegLabel *
          (fused.wallPresence > 0.28 || fused.roofPresence > 0.28 ? 1.0 : 0.4),
    ]);
    if (vegPresence > 0.34) {
      final severe =
          vegPresence > 0.52 ||
          (vegLabel > 0.55 && fused.wallPresence > 0.4) ||
          agg.vegetationNear > 0.48;
      final evidence = <_Evidence>[
        if (agg.greenDominance > 0.16)
          _Evidence('elevated green-channel coverage', agg.greenDominance),
        if (agg.vegetationNear > 0.28)
          _Evidence('organic texture near structure', agg.vegetationNear),
        if (vegLabel > 0.3) _Evidence('plant/tree labels', vegLabel),
      ];
      final conf = _confidence(
        presence: vegPresence,
        defect: severe ? 0.55 : 0.35,
        evidence: evidence,
        labelHits: labelHits(['tree', 'vegetation', 'plant', 'branch']),
        photoVotes: photoVotes((s) => s.vegetationNear > 0.3),
        photoCount: photoCount,
        visionMode: visionMode,
        categoryWeight: 0.55,
      );

      candidates.add(
        _ScoredIssue(
          category: 'vegetation',
          criticality: 0.45,
          score: vegPresence + (severe ? 0.1 : 0),
          issue: AnalysisIssue(
            title: severe
                ? 'Vegetation Encroaching on Structure'
                : 'Landscape Clearance Recommended',
            location: 'Near roofline, siding & foundation',
            severity: severe ? 'Medium' : 'Low',
            cost: severe ? '\$250 – \$950' : '\$120 – \$450',
            confidence: conf,
            insight: _reasonedInsight(
              finding: severe
                  ? 'Encroachment is indicated when strong vegetation signals sit against wall/roof structure (moisture + debris risk).'
                  : 'Plants are near the envelope; clearance will help walls dry and keep roots off the foundation.',
              evidence: evidence,
              confidence: conf,
              whyItMatters: severe
                  ? 'Branches and vines trap moisture, clog gutters, and can abrade roofing and cladding in wind.'
                  : 'Clearance keeps siding dry and reduces pest/bridge paths to the structure.',
              action: severe
                  ? 'Trim branches 6–10 ft from roof/walls and clear vines from cladding.'
                  : 'Maintain clearance so siding can dry and irrigation stays off the foundation.',
            ),
          ),
        ),
      );
    }

    // ── Rust ──────────────────────────────────────────────────────────────
    final rustLabel = maxLabel([
      'rust',
      'corrosion',
      'metal',
      'iron',
      'steel',
      'rust stain',
    ]);
    final rustDefect = _maxN([
      agg.rustDominance * 2.4,
      rustLabel,
      if (agg.rustDominance > 0.09 && agg.edgeDensity > 0.1) 0.28 else 0.0,
    ]);
    // Soft color-only rust on grade/outlet frames is secondary to drainage —
    // pipe elbows often read orange-brown without being the primary finding.
    final gradeOutletContext =
        gradeCloseupFrames >= 1 ||
        downspoutLabel > 0.42 ||
        (agg.lowerThirdDark > 0.36 &&
            (hasAny(['pipe', 'outlet', 'downspout', 'discharge', 'drain']) ||
                bestGroundFrame > 0.40));
    final suppressSoftRustOnOutlet =
        gradeOutletContext && rustLabel < 0.50 && agg.rustDominance < 0.24;
    if ((rustDefect > 0.32 || agg.rustDominance > 0.11) &&
        !suppressSoftRustOnOutlet) {
      final evidence = <_Evidence>[
        if (agg.rustDominance > 0.09)
          _Evidence(
            'orange-brown rust-colored clusters',
            agg.rustDominance * 2,
          ),
        if (rustLabel > 0.3) _Evidence('corrosion-related labels', rustLabel),
      ];
      final conf = _confidence(
        presence: max(rustDefect, 0.4),
        defect: rustDefect,
        evidence: evidence,
        labelHits: labelHits(['rust', 'corrosion', 'metal']),
        photoVotes: photoVotes((s) => s.rustDominance > 0.09),
        photoCount: photoCount,
        visionMode: visionMode,
        categoryWeight: 0.6,
      );

      candidates.add(
        _ScoredIssue(
          category: 'rust',
          criticality: 0.55,
          score: rustDefect,
          issue: AnalysisIssue(
            title: 'Metal Corrosion / Rust Staining',
            location: 'Flashings, fasteners, vents or railings',
            severity: rustDefect > 0.52 || agg.rustDominance > 0.16
                ? 'Medium'
                : 'Low',
            cost: '\$300 – \$1,300',
            confidence: conf,
            insight: _reasonedInsight(
              finding:
                  'Active rust or rust bleed is indicated by warm orange-brown color clusters on metal details.',
              evidence: evidence,
              confidence: conf,
              action:
                  'Replace compromised fasteners/flashing and clean stains before they mark light siding permanently.',
            ),
          ),
        ),
      );
    }

    // ── Fascia / soffit ───────────────────────────────────────────────────
    // Medium "Moisture Risk" must not fire from normal eave shadow / dark
    // patches on healthy multi-angle elevations (common false positive).
    final fasciaLabel = maxLabel(['fascia', 'soffit', 'eaves', 'eave']);
    final eavePresence = _maxN([
      fused.gutterPresence,
      fasciaLabel,
      if (agg.gutterLineScore > 0.36) agg.gutterLineScore * 0.85 else 0.0,
      if (agg.horizontalBanding > 0.40 && agg.darkTopBias > 0.28) 0.36 else 0.0,
    ]);
    final moistureWord = hasAny([
      'rot',
      'mold',
      'mildew',
      'water damage',
      'stain',
      'decay',
      'soft wood',
    ]);
    final fasciaMoistureLabel = maxLabel([
      'rot',
      'mold',
      'mildew',
      'water damage',
      'stain',
      'decay',
    ]);

    // Strong wet signal: moisture stains + eave structure, not dark patches alone.
    // Healthy elevations often have eave shadow (dark patches) without wet wood.
    final geometryWetFascia =
        eavePresence > 0.48 &&
        agg.moistureStainScore > 0.50 &&
        agg.darkPatchRatio > 0.24 &&
        agg.gutterLineScore > 0.36 &&
        gutterVotes >= 2;
    final labelWetFascia =
        fasciaLabel >= 0.60 &&
        (moistureWord || fasciaMoistureLabel > 0.50) &&
        eavePresence > 0.38 &&
        (agg.moistureStainScore > 0.34 || moistureWord);
    // Overflow-backed: only when gutter overflow is already a competitive claim.
    final overflowBackedWet =
        candidates.any(
          (c) =>
              c.category == 'gutter' &&
              c.issue.severity != 'Low' &&
              c.issue.title.toLowerCase().contains('overflow') &&
              c.score >= 0.50,
        ) &&
        eavePresence > 0.40 &&
        agg.moistureStainScore > 0.36;

    final wetFascia = geometryWetFascia || labelWetFascia || overflowBackedWet;

    // Emit only with clear wet proof or strong labeled eave presence.
    // Do not mint fascia findings from soft eave geometry alone on elevations.
    final fasciaEligible =
        photoCount >= 2 &&
        (wetFascia ||
            (fasciaLabel > 0.55 &&
                eavePresence > 0.45 &&
                (agg.gutterLineScore > 0.40 || fasciaLabel > 0.65)));

    if (fasciaEligible) {
      final evidence = <_Evidence>[
        if (eavePresence > 0.32)
          _Evidence('eave / horizontal banding', eavePresence),
        if (agg.moistureStainScore > 0.34)
          _Evidence('moisture staining cues', agg.moistureStainScore),
        if (agg.gutterLineScore > 0.34)
          _Evidence('gutter / eave line structure', agg.gutterLineScore),
        if (fasciaLabel > 0.35)
          _Evidence('fascia / soffit labels', fasciaLabel),
        if (gutterVotes >= 2)
          _Evidence('eave cues in $gutterVotes photos', 0.75),
      ];
      var conf = _confidence(
        presence: max(eavePresence, fasciaLabel),
        defect: wetFascia
            ? max(0.52, agg.moistureStainScore * 0.9)
            : eavePresence * 0.35,
        evidence: evidence,
        labelHits: labelHits(['fascia', 'soffit', 'eaves', 'gutter']),
        photoVotes: gutterVotes,
        photoCount: photoCount,
        visionMode: visionMode,
        categoryWeight: 0.7,
      );
      // Medium moisture risk needs solid confidence.
      if (wetFascia && conf < 82) {
        conf = min(conf, 78);
      }

      final useWetTitle =
          wetFascia &&
          conf >= 86 &&
          (labelWetFascia ||
              geometryWetFascia ||
              (overflowBackedWet && agg.moistureStainScore > 0.38));

      candidates.add(
        _ScoredIssue(
          category: 'fascia',
          criticality: 0.7,
          score:
              (eavePresence * 0.36 +
                      (useWetTitle ? 0.18 : 0) +
                      (agg.moistureStainScore > 0.34
                          ? agg.moistureStainScore * 0.28
                          : 0) +
                      (fasciaLabel > 0.45 ? 0.10 : 0) +
                      (gutterVotes >= 2 ? 0.06 : 0))
                  .clamp(0.0, 1.0),
          issue: AnalysisIssue(
            title: useWetTitle
                ? 'Fascia / Soffit Moisture Risk'
                : 'Eave, Fascia & Soffit Review',
            location: 'Overhangs, fascia boards & soffit vents',
            severity: useWetTitle ? 'Medium' : 'Low',
            cost: useWetTitle ? '\$400 – \$1,400' : '\$220 – \$850',
            confidence: conf,
            insight: _reasonedInsight(
              finding: useWetTitle
                  ? 'Eave moisture is indicated by staining/darkening at the overhang with supporting eave structure or labels.'
                  : 'Eave lines are visible; clear fascia/soffit moisture was not confirmed from these photos.',
              evidence: evidence,
              confidence: conf,
              whyItMatters: useWetTitle
                  ? 'Wet fascia and soffit can rot, invite pests, and point to gutter overflow upstream.'
                  : 'Blocked soffit vents and open joints can still trap moisture even when boards look dry in photos.',
              action: useWetTitle
                  ? 'Probe soft boards, confirm drip edge, and fix gutters first so repairs do not re-rot.'
                  : 'Check soft wood, open joints, and blocked soffit vents that trap moisture.',
            ),
          ),
        ),
      );
    }

    // ── Residual distress (only if thin results) ──────────────────────────
    if (candidates.where((c) => c.issue.severity != 'Low').isEmpty &&
        agg.overallDistress > 0.42) {
      final score = max(
        maxLabel(['damage', 'crack', 'mold', 'stain', 'decay']),
        agg.overallDistress,
      );
      final evidence = <_Evidence>[
        if (agg.edgeDensity > 0.16)
          _Evidence('elevated edge texture', agg.edgeDensity),
        if (agg.darkPatchRatio > 0.16)
          _Evidence('dark patching', agg.darkPatchRatio),
        if (agg.highTextureChaos) const _Evidence('texture chaos patches', 0.7),
      ];
      final conf = _confidence(
        presence: 0.5,
        defect: score,
        evidence: evidence,
        labelHits: labelHits(['damage', 'crack', 'stain']),
        photoVotes: 1,
        photoCount: photoCount,
        visionMode: visionMode,
        categoryWeight: 0.5,
      );
      candidates.add(
        _ScoredIssue(
          category: 'general',
          criticality: 0.5,
          score: score,
          issue: AnalysisIssue(
            title: 'Surface Distress Detected',
            location: 'Multiple exterior zones',
            severity: score > 0.58 ? 'Medium' : 'Low',
            cost: '\$650 – \$2,200',
            confidence: conf,
            insight: _reasonedInsight(
              finding:
                  'General distress appears without a single dominant building system match.',
              evidence: evidence,
              confidence: conf,
              action:
                  'Walk roof edges, wall faces, and grade line; re-shoot the worst areas close-up for a sharper pass.',
            ),
          ),
        ),
      );
    }

    final limitedVisibility = _featuresSuggestLimitedVisibility(
      agg,
      photoCount: photoCount,
    );

    if (limitedVisibility) {
      // Always surface a retake note for dark / low-detail frames — even when
      // residual texture candidates exist (they usually filter out later).
      candidates.add(
        const _ScoredIssue(
          category: 'general',
          criticality: 0.35,
          score: 0.62,
          issue: AnalysisIssue(
            title: 'Limited Visibility — Closer Photo Needed',
            location: 'Capture conditions (light / detail)',
            severity: 'Medium',
            cost: 'TBD',
            confidence: 80,
            insight:
                'This photo is too dark, underexposed, or low-detail for a confident exterior screening. '
                'Retake in brighter daylight with a steady, closer frame of the area of concern before treating any condition score as definitive.',
            needsCloserPhoto: true,
          ),
        ),
      );
      // Soften other findings when the only frames are poorly lit.
      for (var i = 0; i < candidates.length; i++) {
        final c = candidates[i];
        if (c.issue.title.toLowerCase().contains('limited visibility')) {
          continue;
        }
        final conf = min(c.issue.confidence, 74);
        candidates[i] = _ScoredIssue(
          category: c.category,
          criticality: c.criticality,
          score: min(c.score, 0.62),
          issue: c.issue.copyWith(
            confidence: conf,
            severity: c.issue.severity == 'High' ? 'Medium' : c.issue.severity,
            needsCloserPhoto: true,
          ),
        );
      }
    } else if (candidates.isEmpty) {
      final top = labels.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topNames = top.take(3).map((e) => e.key).join(', ');
      final conf = _confidence(
        presence: 0.4,
        defect: 0.15,
        evidence: [
          _Evidence(
            photoCount >= 2
                ? 'reviewed $photoCount photos with limited defect clusters'
                : 'single-photo scan with limited defect clusters',
            0.35,
          ),
        ],
        labelHits: 0,
        photoVotes: 0,
        photoCount: photoCount,
        visionMode: visionMode,
        categoryWeight: 0.4,
      );
      candidates.add(
        _ScoredIssue(
          category: 'general',
          criticality: 0.2,
          score: 0.12,
          issue: AnalysisIssue(
            title: 'General Exterior Condition Scan',
            location: 'Full exterior envelope',
            severity: 'Low',
            cost: '\$200 – \$800',
            confidence: conf,
            insight: topNames.isEmpty
                ? 'Analysis completed on $photoCount photo(s) with limited defect signal (confidence $conf%). Capture closer shots of roof, gutters, siding joints, and foundation for higher-confidence findings.'
                : 'Top scene labels: $topNames. No high-priority defects mapped (confidence $conf%). Re-shoot problem areas if you suspect hidden damage.',
          ),
        ),
      );
    }

    // Cross-category boosts: related systems raise score when co-present.
    _boostRelatedFindings(candidates);

    // Caption / Vision labels decide the primary system on real phone photos
    // so soil bands don't outrank roof slots and vice versa.
    _lockPrimarySystemFromLabels(candidates, labels);

    // Prefer dominant system — suppress weak secondary Highs (credibility).
    _suppressSecondaryFalsePositives(candidates);

    // Real-photo noise filter: complex landscaping/texture often looks like
    // defects; demote soft Medium/High when overall distress is mild.
    _suppressCleanSceneNoise(
      candidates,
      photoCount: photoCount,
      overallDistress: agg.overallDistress,
      peelScore: agg.peelingScore,
      crackLine: agg.crackLineScore,
      lowerDark: agg.lowerThirdDark,
      darkTop: agg.darkTopBias,
      roofPresence: fused.roofPresence,
      roofDefect: fused.roofDefect,
      visionMode: visionMode,
    );

    // Calibrate severity: High needs solid defect + confidence or multi-photo.
    final calibrated = candidates
        .map((c) => _calibrateSeverity(c, photoCount: photoCount))
        .toList();

    // Rank by severity, criticality, detection score, confidence.
    calibrated.sort((a, b) {
      final sev =
          _severityRank(b.issue.severity) - _severityRank(a.issue.severity);
      if (sev != 0) return sev;
      final crit = b.criticality.compareTo(a.criticality);
      if (crit != 0) return crit;
      final sc = b.score.compareTo(a.score);
      if (sc != 0) return sc;
      return b.issue.confidence.compareTo(a.issue.confidence);
    });

    // Prefer 1–2 strong findings only (never a long weak list).
    // Precision comes from quality floors below, not from truncating the
    // correct primary defect when a secondary system is noisier.
    final maxIssues = min(calibrated.length, photoCount <= 1 ? 1 : 2);

    final minScore = visionMode ? 0.58 : 0.50;
    final minConfMedium = visionMode ? 86 : 80;
    final minConfAbsolute = visionMode ? 80 : 76;
    final minConfLowKeep = visionMode ? 88 : 82;
    final labelBackedFloor = visionMode ? 0.66 : 0.58;

    double labelSupportFor(_ScoredIssue c) {
      final needles = <String>[
        ...visionObjectNeedlesForCategory(c.category),
        if (c.category == 'gutter') ...[
          'gutter',
          'downspout',
          'debris',
          'leaf',
          'overflow',
          'clog',
          'eaves',
        ],
        if (c.category == 'paint') ...['paint', 'peeling', 'flaking'],
        if (c.category == 'foundation') ...['foundation', 'crack', 'concrete'],
        if (c.category == 'siding') ...[
          'siding',
          'crack',
          'cladding',
          'patch',
          'discoloration',
          'repair',
          'mismatched',
          'replacement',
        ],
        if (c.category == 'wiring') ...[
          'wiring',
          'cable',
          'wire',
          'electrical',
          'conduit',
        ],
        if (c.category == 'roof') ...['roof', 'shingle', 'damage', 'asphalt'],
      ];
      var best = 0.0;
      for (final e in labels.entries) {
        if (e.value < 0.34) continue;
        if (needles.any((n) => e.key.contains(n) || n.contains(e.key))) {
          best = max(best, e.value);
        }
      }
      return best;
    }

    // Re-rank: severity first, then label-backed score so primary defects
    // (e.g. gutter labels on a drainage scenario) are not crowded out.
    // Prefer roof/gutter over foundation when upper-plane cues dominate the set.
    double sceneBoost(_ScoredIssue c) {
      var boost =
          c.score + labelSupportFor(c) * 0.22 + c.issue.confidence / 500;
      if (c.category == 'roof' &&
          (agg.darkTopBias > 0.32 || fused.roofDefect > 0.40)) {
        boost += 0.14 + fused.roofDefect * 0.12 + agg.darkTopBias * 0.08;
      }
      if (c.category == 'foundation' &&
          fused.roofPresence > 0.42 &&
          agg.darkTopBias > 0.28 &&
          agg.lowerThirdDark < 0.58) {
        boost -= 0.28;
      }
      // Soft foundation crack on elevation sets ranks below other systems.
      // Prefer omitting weak settlement claims when another system is clearer.
      if (c.category == 'foundation' &&
          (c.issue.title.toLowerCase().contains('crack') ||
              c.issue.title.toLowerCase().contains('settlement')) &&
          (c.score < 0.72 || agg.crackLineScore < 0.56)) {
        boost -= 0.22;
      }
      if (c.category == 'foundation' &&
          c.issue.severity == 'Low' &&
          agg.crackLineScore < 0.52) {
        boost -= 0.18;
      }
      if (c.category == 'gutter' && fused.gutterPresence > 0.40) {
        boost += 0.10;
      }
      // Ground outlet / wet-soil drainage should lead over soft elevation noise.
      if (c.category == 'gutter' &&
          (c.issue.title.toLowerCase().contains('dumping') ||
              c.issue.title.toLowerCase().contains('foundation') ||
              c.issue.location.toLowerCase().contains('grade')) &&
          (agg.lowerThirdDark > 0.34 || fused.foundationPresence > 0.34)) {
        boost += 0.18;
      }
      // Soft color-only rust ranks below ground-outlet drainage.
      if (c.category == 'rust' &&
          (agg.lowerThirdDark > 0.34 || fused.foundationPresence > 0.34) &&
          maxLabel(['pipe', 'outlet', 'downspout', 'drain', 'discharge']) >
              0.40) {
        boost -= 0.20;
      }
      // Obvious wall patch / color-block work should lead over opportunistic windows.
      if (c.category == 'siding' &&
          (c.issue.title.toLowerCase().contains('patch') ||
              c.issue.title.toLowerCase().contains('mismatched')) &&
          fused.wallPresence > 0.42) {
        boost += 0.16 + agg.highLuminanceVariance * 0.10;
      }
      if (c.category == 'wiring' && fused.wallPresence > 0.40) {
        boost += 0.12;
      }
      // Soft window seals rank below clear wall patch or wiring clutter.
      if (c.category == 'window' &&
          (agg.highLuminanceVariance > 0.52 ||
              maxLabel(['patch', 'wiring', 'cable', 'siding']) > 0.50)) {
        boost -= 0.14;
      }
      return boost;
    }

    calibrated.sort((a, b) {
      final sev =
          _severityRank(b.issue.severity) - _severityRank(a.issue.severity);
      if (sev != 0) return sev;
      final sc = sceneBoost(b).compareTo(sceneBoost(a));
      if (sc != 0) return sc;
      return b.issue.confidence.compareTo(a.issue.confidence);
    });

    final filtered = <_ScoredIssue>[];
    for (final c in calibrated) {
      if (filtered.length >= maxIssues) break;
      final labelHit = labelSupportFor(c);
      final labelBacked = labelHit >= labelBackedFloor;

      // Hard floor: weak detections never make the report.
      if (c.score < minScore && c.issue.severity != 'High' && !labelBacked) {
        continue;
      }
      if (c.issue.confidence < minConfAbsolute &&
          c.issue.severity != 'High' &&
          !labelBacked) {
        continue;
      }
      // Foundation crack/settlement without support → omit.
      // Prefer empty / insufficient evidence over false settlement findings.
      // Exception: high-confidence dual-label settlement (captions / Vision).
      final fTitle = c.issue.title.toLowerCase();
      final isFoundationCrack =
          c.category == 'foundation' &&
          (fTitle.contains('crack') || fTitle.contains('settlement'));
      if (isFoundationCrack) {
        final strongLabelSettlement =
            c.issue.confidence >= 78 && c.score >= 0.52;
        final geometryOk =
            agg.crackLineScore >= 0.46 && agg.lowerThirdDark >= 0.44;
        if (c.issue.confidence < 76) continue;
        if (!geometryOk && !strongLabelSettlement) continue;
        if (c.score < minScore - 0.04 && c.issue.severity != 'High') {
          continue;
        }
      }
      if (c.category == 'foundation' &&
          c.issue.severity == 'Low' &&
          !isFoundationCrack &&
          (c.score < 0.58 || agg.lowerThirdDark < 0.52)) {
        continue;
      }

      // Drop Low noise when anything stronger exists (almost always).
      // Prefer label-backed Low over unrelated Low bleed (e.g. wall moisture
      // when roof is the labeled system).
      if (c.issue.severity == 'Low') {
        if (filtered.isNotEmpty) continue;
        if (c.score < 0.52 || c.issue.confidence < minConfLowKeep) continue;
        // Lone Low only if label-backed or very solid score.
        if (!labelBacked && c.score < 0.55) continue;
        // Skip Low secondaries when a stronger label-backed system exists
        // later in the ranked list (avoid locking the report on bleed).
        final betterLabelExists = calibrated.any(
          (o) =>
              o.category != c.category &&
              labelSupportFor(o) >= labelBackedFloor &&
              (o.issue.severity != 'Low' || o.score > c.score + 0.06),
        );
        if (betterLabelExists && !labelBacked) continue;
      }

      // Drop borderline Medium without solid score/confidence — unless labels
      // clearly support this exterior system.
      // Limited-visibility retake notes are intentional Medium screening items.
      final limitedVisTitle =
          c.issue.title.toLowerCase().contains('limited visibility') ||
          c.issue.title.toLowerCase().contains('closer photo needed');
      if (c.issue.severity == 'Medium' &&
          !labelBacked &&
          !limitedVisTitle &&
          (c.issue.confidence < minConfMedium || c.score < minScore + 0.06)) {
        continue;
      }

      // After the first finding, only keep stronger follow-ups.
      if (filtered.isNotEmpty && c.issue.severity == 'Medium') {
        final lead = filtered.first;
        // Second Medium must clear a higher bar than the first slot.
        if (!labelBacked &&
            (c.issue.confidence < minConfMedium + 6 ||
                c.score < minScore + 0.12)) {
          continue;
        }
        // Don't stack weak mediums under a High.
        if (lead.issue.severity == 'High' &&
            (c.issue.confidence < 90 || c.score < 0.66) &&
            !labelBacked) {
          continue;
        }
        // Prefer one primary defect: second Medium needs competitive score.
        if (c.score < lead.score * 0.92 && !labelBacked) {
          continue;
        }
      }

      // Drop medium noise when a high-confidence issue already listed.
      if (filtered.isNotEmpty &&
          c.issue.severity == 'Medium' &&
          !labelBacked &&
          c.issue.confidence < 90 &&
          c.score < 0.62 &&
          filtered.any((f) => f.issue.confidence >= 88)) {
        continue;
      }

      // Drop High that barely earned it when already have a stronger High.
      if (filtered.isNotEmpty &&
          c.issue.severity == 'High' &&
          c.score < 0.74 &&
          filtered.any((f) => f.issue.severity == 'High')) {
        continue;
      }

      // Vision mode: secondary soft findings need label/object support.
      if (visionMode &&
          filtered.isNotEmpty &&
          c.issue.severity != 'High' &&
          c.score < 0.68 &&
          !labelBacked) {
        continue;
      }

      // Prefer actionable defects over generic "review" when both exist.
      // Limited-visibility retake notes are intentional general findings.
      if (c.category == 'general') {
        final limitedGeneral =
            c.issue.title.toLowerCase().contains('limited visibility') ||
            c.issue.title.toLowerCase().contains('closer photo needed');
        if (filtered.isNotEmpty && !limitedGeneral) continue;
        if (limitedGeneral) {
          if (c.score < 0.50 || c.issue.confidence < 70) continue;
        } else if (c.score < 0.50 ||
            c.issue.confidence < minConfLowKeep) {
          continue;
        }
      }
      // Scene–category gate: no foundation-water finding without grade support.
      if (_isGroundDrainageIssue(c.issue) && !groundSceneOk) continue;

      // One issue per category.
      if (filtered.any((f) => f.category == c.category)) continue;
      filtered.add(c);
    }

    // Only seed a single finding when it is actually strong enough.
    if (filtered.isEmpty && calibrated.isNotEmpty) {
      final best = calibrated.first;
      final backed = labelSupportFor(best) >= labelBackedFloor;
      final seedOk = (best.score >= minScore || backed) &&
          best.issue.confidence >= (visionMode ? 80 : 78) &&
          best.issue.severity != 'Low';
      // Never seed a foundation-water finding without a drainage-domain photo.
      if (seedOk &&
          !(_isGroundDrainageIssue(best.issue) && !groundSceneOk)) {
        filtered.add(best);
      }
    }

    // Bind each finding to the best matching capture photo + honesty flags.
    // Drop paint / siding when the capture set has no wall host (grade-only).
    final bound = <AnalysisIssue>[];
    for (final c in filtered) {
      if (c.category == 'paint' &&
          capturePhotos.isNotEmpty &&
          !_hasWallTrimPaintHostPhoto(capturePhotos, features)) {
        // Prefer no paint finding over binding soil/pipe as coating failure.
        continue;
      }
      if (c.category == 'siding' &&
          capturePhotos.isNotEmpty &&
          !_hasWallCladdingHostPhoto(capturePhotos, features)) {
        // Prefer no cladding finding over binding grade/pipe as siding cracks.
        continue;
      }
      final issue = _bindIssueToPhoto(
        scored: c,
        capturePhotos: capturePhotos,
        features: features,
        visionBoxes: visionBoxes,
      );
      // Safety: paint primary must be wall/trim/fascia — never grade/outlet/soil.
      // Unbound paint (no wall host) is dropped rather than UI-falling back to
      // Problem close-up dirt/pipe frames.
      if (c.category == 'paint' && capturePhotos.isNotEmpty) {
        final pi = issue.photoIndex;
        if (pi == null || pi < 0 || pi >= capturePhotos.length) {
          continue;
        }
        final p = capturePhotos[pi];
        final f = pi < features.length ? features[pi] : null;
        if (_isGradeOutletSoilPhoto(p, f) || !_isWallTrimPaintHostPhoto(p, f)) {
          continue;
        }
      }
      // Safety: never keep siding pinned to a grade/outlet/soil caption.
      if (c.category == 'siding' &&
          capturePhotos.isNotEmpty &&
          issue.photoIndex != null) {
        final pi = issue.photoIndex!;
        if (pi >= 0 && pi < capturePhotos.length) {
          final p = capturePhotos[pi];
          final f = pi < features.length ? features[pi] : null;
          if (_isGradeOutletSoilPhoto(p, f)) {
            continue;
          }
        }
      }
      if (_isGroundDrainageIssue(issue)) {
        if (!groundSceneOk) continue;
        if (capturePhotos.isNotEmpty) {
          final pi = issue.photoIndex;
          if (pi == null || pi < 0 || pi >= capturePhotos.length) {
            // No supporting frame — drop rather than keep an unbound claim.
            continue;
          }
          final p = capturePhotos[pi];
          final f = pi < features.length ? features[pi] : null;
          if (_isRoofFieldOnlyPhoto(p, f) ||
              (_isRoofHostPhoto(p, f) && !_isGradeOutletSoilPhoto(p, f))) {
            continue;
          }
        }
      }
      bound.add(issue);
    }
    return bound;
  }

  /// Prefer guided slot match, then per-photo defect signal for the category.
  AnalysisIssue _bindIssueToPhoto({
    required _ScoredIssue scored,
    required List<CapturePhoto> capturePhotos,
    required List<_ImageFeatures> features,
    List<_VisionObjectBox> visionBoxes = const [],
  }) {
    final issue = scored.issue;
    if (capturePhotos.isEmpty) {
      final honest = _applyHonesty(
        issue.copyWith(photoIndex: null, sourcePhotoLabel: ''),
      );
      return _attachVisionHighlight(
        honest,
        category: scored.category,
        visionBoxes: visionBoxes,
        photoIndex: null,
      );
    }

    final preferred = _preferredSlotsForCategory(
      scored.category,
      issue: scored.issue,
    );
    var bestIndex = -1;
    var bestScore = -1.0;

    for (var i = 0; i < capturePhotos.length; i++) {
      final photo = capturePhotos[i];
      final feat = i < features.length ? features[i] : null;
      var score = 0.0;
      if (_isNonExteriorCapturePhoto(photo)) continue;

      // Paint/siding: grade / outlet / soil frames are never evidence candidates.
      // Device Problem close-ups of dirt/plants/pipe often win peel texture races
      // unless we hard-veto them before slot/feature/vision boosts.
      final gradeOutletFrame = _isGradeOutletSoilPhoto(photo, feat);
      if ((scored.category == 'paint' || scored.category == 'siding') &&
          gradeOutletFrame) {
        continue;
      }
      // Roof / chimney must never use ground outlet / soil as primary evidence.
      if ((scored.category == 'roof' || scored.category == 'chimney') &&
          gradeOutletFrame) {
        continue;
      }
      // Ground drainage must not bind to a roof / ridge / upper-plane frame.
      final groundDrainIssue = scored.category == 'gutter' &&
          _isGroundDrainageIssue(scored.issue);
      if (groundDrainIssue &&
          (_isRoofFieldOnlyPhoto(photo, feat) ||
              (_isRoofHostPhoto(photo, feat) && !gradeOutletFrame))) {
        continue;
      }

      // Slot preference (strong signal from guided capture).
      final slot = photo.slotId;
      if (slot != null) {
        final prefIdx = preferred.indexOf(slot);
        if (prefIdx >= 0) {
          score += 1.2 - (prefIdx * 0.12);
        } else if (slot == CaptureShotId.problemCloseup) {
          // Close-ups help most defect types — wall/trim paint CUs only.
          if (scored.category == 'paint' &&
              !_isWallTrimPaintHostPhoto(photo, feat)) {
            score -= 0.85;
          } else if (scored.category == 'siding' && gradeOutletFrame) {
            score -= 0.85;
          } else if ((scored.category == 'roof' ||
                  scored.category == 'chimney') &&
              !_isRoofHostPhoto(photo, feat)) {
            score -= 1.15;
          } else {
            score += 0.35;
          }
        }
      }

      // Feature support on this frame.
      if (feat != null) {
        score += _categoryFeatureScore(scored.category, feat);
      }

      // Prefer photos with real Vision object localization for this category.
      // Structure-only (house/building) is a weak fallback for photo pick.
      // Skip Vision boosts on grade frames for paint (partial wall in outlet CUs).
      // Vent-pipe / "roof" objects on a ridge shot must not win ground drainage.
      final roofHostNoGrade =
          _isRoofHostPhoto(photo, feat) && !gradeOutletFrame;
      final hasSpecificBox = !gradeOutletFrame &&
          !(groundDrainIssue && roofHostNoGrade) &&
          visionBoxes.any(
            (b) =>
                b.imageIndex == i &&
                _visionBoxMatchesCategory(b, scored.category) &&
                isSpecificObjectForCategory(b.name, scored.category) &&
                b.score >= 0.24,
          );
      final hasStructureBox = !gradeOutletFrame &&
          visionBoxes.any(
            (b) =>
                b.imageIndex == i &&
                _visionBoxMatchesCategory(b, scored.category) &&
                isLargeStructureObject(b.name) &&
                b.score >= 0.68,
          );
      if (hasSpecificBox) {
        score += 1.85; // real object localization strongly preferred
      } else if (hasStructureBox) {
        score += 0.04; // structure is last resort for surface mapping
      }

      // Foundation cues live in lower third of elevations.
      if (scored.category == 'foundation' && feat != null) {
        score += feat.lowerThirdDark * 0.25 + feat.botEdgeDensity * 0.2;
      }
      if (scored.category == 'roof' && feat != null) {
        score += feat.darkTopBias * 0.2 + feat.topEdgeDensity * 0.15;
        if (_isRoofHostPhoto(photo, feat)) score += 0.85;
        if (gradeOutletFrame) score -= 2.40;
      }
      if (groundDrainIssue) {
        if (gradeOutletFrame) score += 1.15;
        final caption = '${photo.label} ${photo.file.name}'.toLowerCase();
        if (caption.contains('soil') ||
            caption.contains('outlet') ||
            caption.contains('discharge') ||
            caption.contains('pipe') ||
            caption.contains('grade')) {
          score += 0.70;
        }
        if (slot == CaptureShotId.problemCloseup && !gradeOutletFrame) {
          score += 0.20;
        }
      }
      if ((scored.category == 'gutter' || scored.category == 'fascia') &&
          feat != null) {
        final groundDrain = _isGroundDrainageIssue(scored.issue);
        if (groundDrain) {
          // Prefer grade / outlet photos — not roof eave strips.
          score +=
              feat.lowerThirdDark * 0.45 +
              feat.botEdgeDensity * 0.28 +
              feat.moistureStainScore * 0.22 +
              feat.foundationSignal * 0.18;
          score -= feat.gutterLineScore * 0.35 + feat.darkTopBias * 0.15;
          if (slot == CaptureShotId.roof) score -= 0.55;
        } else {
          // Eave overflow: demote pure grade/pipe frames so they are not evidence.
          score += feat.gutterLineScore * 0.40 + feat.horizontalBanding * 0.18;
          if (feat.lowerThirdDark > 0.48 && feat.gutterLineScore < 0.30) {
            score -= 0.55;
          }
          if (feat.foundationSignal > 0.50 && feat.gutterLineScore < 0.28) {
            score -= 0.35;
          }
        }
      }

      // Paint must bind to wall / trim elevations — never soil/pipe/grade primary.
      if (scored.category == 'paint') {
        if (_isGradeOutletSoilPhoto(photo, feat)) {
          score -= 2.40;
        } else if (feat != null) {
          score +=
              feat.wallSignal * 0.55 +
              feat.peelingScore * 0.70 +
              (feat.wallSignal > 0.42 && feat.peelingScore > 0.36 ? 0.35 : 0);
          // Soft demote pure roof fields for paint.
          if (feat.roofSignal > 0.52 && feat.wallSignal < 0.36) {
            score -= 0.45;
          }
        }
        final caption = '${photo.label} ${photo.file.name}'.toLowerCase();
        if (caption.contains('wall') ||
            caption.contains('siding') ||
            caption.contains('trim') ||
            caption.contains('paint') ||
            caption.contains('elevation') ||
            caption.contains('clapboard') ||
            caption.contains('fascia')) {
          score += 0.55;
        }
      }

      // Siding / cladding must bind to wall elevations — never grade/pipe primary.
      if (scored.category == 'siding') {
        if (_isGradeOutletSoilPhoto(photo, feat)) {
          score -= 2.40;
        } else if (feat != null) {
          score +=
              feat.wallSignal * 0.60 +
              feat.crackLineScore * 0.35 +
              (feat.wallSignal > 0.48 && feat.foundationSignal < feat.wallSignal
                  ? 0.30
                  : 0);
          if (feat.roofSignal > 0.52 && feat.wallSignal < 0.36) {
            score -= 0.45;
          }
        }
        final caption = '${photo.label} ${photo.file.name}'.toLowerCase();
        if (caption.contains('wall') ||
            caption.contains('siding') ||
            caption.contains('cladding') ||
            caption.contains('elevation') ||
            caption.contains('clapboard') ||
            caption.contains('brick') ||
            caption.contains('patch')) {
          score += 0.55;
        }
        if (caption.contains('pipe') ||
            caption.contains('soil') ||
            caption.contains('mulch') ||
            caption.contains('outlet') ||
            caption.contains('discharge') ||
            caption.contains('grade')) {
          score -= 1.20;
        }
      }

      // Slight preference for earlier checklist order when tied.
      score += (capturePhotos.length - i) * 0.001;

      if (score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }

    // No eligible photo scored (e.g. paint/siding with only grade frames skipped).
    if (bestIndex < 0) {
      if (scored.category == 'paint') {
        final wallIdx = _bestWallTrimPaintPhotoIndex(capturePhotos, features);
        if (wallIdx == null) {
          final honest = _applyHonesty(
            issue.copyWith(photoIndex: null, sourcePhotoLabel: ''),
          );
          return honest.copyWith(
            confidence: min(honest.confidence, 62),
            insight:
                '${honest.insight} Screening note: no clear wall/trim paint photo '
                'was available — retake a straight-on wall or trim close-up.',
          );
        }
        bestIndex = wallIdx;
      } else if (scored.category == 'siding') {
        final wallIdx = _bestWallCladdingPhotoIndex(capturePhotos, features);
        if (wallIdx == null) {
          final honest = _applyHonesty(
            issue.copyWith(photoIndex: null, sourcePhotoLabel: ''),
          );
          return honest.copyWith(
            confidence: min(honest.confidence, 62),
            insight:
                '${honest.insight} Screening note: no clear wall/siding photo '
                'was available — retake a straight-on cladding elevation.',
          );
        }
        bestIndex = wallIdx;
      } else {
        bestIndex = _fallbackPhotoIndexForCategory(
              scored,
              capturePhotos: capturePhotos,
              features: features,
            ) ??
            -1;
      }
    }
    if (bestIndex < 0) {
      final honest = _applyHonesty(
        issue.copyWith(photoIndex: null, sourcePhotoLabel: ''),
      );
      return _attachVisionHighlight(
        honest,
        category: scored.category,
        visionBoxes: visionBoxes,
        photoIndex: null,
      );
    }

    final chosen = capturePhotos[bestIndex.clamp(0, capturePhotos.length - 1)];
    final feat = bestIndex < features.length ? features[bestIndex] : null;

    // Paint with only grade/outlet evidence → drop binding (no false primary).
    // Caller filter will omit unbound weak paint; prefer honesty over mismatch.
    if (scored.category == 'paint' &&
        (_isGradeOutletSoilPhoto(chosen, feat) ||
            !_isWallTrimPaintHostPhoto(chosen, feat)) &&
        !_hasWallTrimPaintHostPhoto(capturePhotos, features)) {
      final honest = _applyHonesty(
        issue.copyWith(photoIndex: null, sourcePhotoLabel: ''),
      );
      // Mark as needs closer photo — do not pin soil/pipe as paint evidence.
      return honest.copyWith(
        confidence: min(honest.confidence, 62),
        insight:
            '${honest.insight} Screening note: no clear wall/trim paint photo '
            'was available — retake a straight-on wall or trim close-up.',
      );
    }
    // Siding with only grade/outlet evidence → drop binding (no false primary).
    if (scored.category == 'siding' &&
        _isGradeOutletSoilPhoto(chosen, feat) &&
        !_hasWallCladdingHostPhoto(capturePhotos, features)) {
      final honest = _applyHonesty(
        issue.copyWith(photoIndex: null, sourcePhotoLabel: ''),
      );
      return honest.copyWith(
        confidence: min(honest.confidence, 62),
        insight:
            '${honest.insight} Screening note: no clear wall/siding photo '
            'was available — retake a straight-on cladding elevation.',
      );
    }
    // If best score landed on grade but a wall host exists, force wall photo.
    var boundIndex = bestIndex.clamp(0, capturePhotos.length - 1);
    var boundPhoto = chosen;
    var boundFeat = feat;
    if (scored.category == 'paint' &&
        (_isGradeOutletSoilPhoto(chosen, feat) ||
            !_isWallTrimPaintHostPhoto(chosen, feat))) {
      final wallIdx = _bestWallTrimPaintPhotoIndex(capturePhotos, features);
      if (wallIdx != null) {
        boundIndex = wallIdx;
        boundPhoto = capturePhotos[wallIdx];
        boundFeat = wallIdx < features.length ? features[wallIdx] : null;
      }
    }
    if (scored.category == 'siding' &&
        _isGradeOutletSoilPhoto(chosen, feat)) {
      final wallIdx = _bestWallCladdingPhotoIndex(capturePhotos, features);
      if (wallIdx != null) {
        boundIndex = wallIdx;
        boundPhoto = capturePhotos[wallIdx];
        boundFeat = wallIdx < features.length ? features[wallIdx] : null;
      }
    }
    if ((scored.category == 'roof' || scored.category == 'chimney') &&
        !_isRoofHostPhoto(boundPhoto, boundFeat)) {
      final roofIdx = _bestRoofHostPhotoIndex(capturePhotos, features);
      if (roofIdx != null) {
        boundIndex = roofIdx;
        boundPhoto = capturePhotos[roofIdx];
        boundFeat = roofIdx < features.length ? features[roofIdx] : null;
      }
    }
    if (scored.category == 'gutter' &&
        _isGroundDrainageIssue(issue) &&
        (_isRoofFieldOnlyPhoto(boundPhoto, boundFeat) ||
            (_isRoofHostPhoto(boundPhoto, boundFeat) &&
                !_isGradeOutletSoilPhoto(boundPhoto, boundFeat)))) {
      final gradeIdx = _bestGradeDrainagePhotoIndex(capturePhotos, features);
      if (gradeIdx != null) {
        boundIndex = gradeIdx;
        boundPhoto = capturePhotos[gradeIdx];
        boundFeat = gradeIdx < features.length ? features[gradeIdx] : null;
      }
    }

    // Prefer a same-category Vision object box on a valid host photo.
    final visionIdx = _visionLocalizedHostIndex(
      scored: scored,
      capturePhotos: capturePhotos,
      features: features,
      visionBoxes: visionBoxes,
    );
    if (visionIdx != null) {
      final vPhoto = capturePhotos[visionIdx];
      final vFeat =
          visionIdx < features.length ? features[visionIdx] : null;
      final currentHasBox = visionBoxes.any(
        (b) =>
            b.imageIndex == boundIndex &&
            _visionBoxMatchesCategory(b, scored.category) &&
            isSpecificObjectForCategory(b.name, scored.category),
      );
      if (!currentHasBox) {
        boundIndex = visionIdx;
        boundPhoto = vPhoto;
        boundFeat = vFeat;
      }
    }

    // Vision vent-pipe / ridge boxes must not keep ground drainage on a roof.
    if (scored.category == 'gutter' &&
        _isGroundDrainageIssue(issue) &&
        (_isRoofFieldOnlyPhoto(boundPhoto, boundFeat) ||
            (_isRoofHostPhoto(boundPhoto, boundFeat) &&
                !_isGradeOutletSoilPhoto(boundPhoto, boundFeat)))) {
      final gradeIdx = _bestGradeDrainagePhotoIndex(capturePhotos, features);
      if (gradeIdx != null) {
        boundIndex = gradeIdx;
        boundPhoto = capturePhotos[gradeIdx];
        boundFeat = gradeIdx < features.length ? features[gradeIdx] : null;
      }
    }
    if ((scored.category == 'roof' || scored.category == 'chimney') &&
        !_isRoofHostPhoto(boundPhoto, boundFeat)) {
      final roofIdx = _bestRoofHostPhotoIndex(capturePhotos, features);
      if (roofIdx != null) {
        boundIndex = roofIdx;
        boundPhoto = capturePhotos[roofIdx];
        boundFeat = roofIdx < features.length ? features[roofIdx] : null;
      }
    }

    // If primary evidence photo is grade/pipe-like, reclassify eave overflow copy.
    final aligned = scored.category == 'gutter'
        ? _alignDrainageIssueToPhoto(issue, boundFeat, boundPhoto)
        : issue;
    final bound = aligned.copyWith(
      photoIndex: boundIndex,
      sourcePhotoLabel: boundPhoto.label,
    );
    final honest = _applyHonesty(bound);
    final withBox = _attachVisionHighlight(
      honest,
      category: scored.category,
      visionBoxes: visionBoxes,
      photoIndex: boundIndex,
    );
    // Zone-only drainage: cap confidence — do not invent tight-object certainty.
    if (scored.category == 'gutter' &&
        !withBox.hasLocalizedHighlight &&
        withBox.confidence > 78) {
      return withBox.copyWith(confidence: 78);
    }
    // Paint still on grade / non-wall host after rebind → drop photo binding.
    // Caller drops unbound paint so UI cannot fall back to Problem close-up soil.
    if (scored.category == 'paint' &&
        (_isGradeOutletSoilPhoto(boundPhoto, boundFeat) ||
            !_isWallTrimPaintHostPhoto(boundPhoto, boundFeat))) {
      return withBox.copyWith(
        photoIndex: null,
        sourcePhotoLabel: '',
        confidence: min(withBox.confidence, 64),
      );
    }
    // Siding still on grade photo after rebind attempt → drop photo binding.
    if (scored.category == 'siding' &&
        _isGradeOutletSoilPhoto(boundPhoto, boundFeat)) {
      return withBox.copyWith(
        photoIndex: null,
        sourcePhotoLabel: '',
        confidence: min(withBox.confidence, 64),
      );
    }
    // Roof still on soil/outlet after rebind → unbind (UI rematches; never soil).
    if ((scored.category == 'roof' || scored.category == 'chimney') &&
        _isGradeOutletSoilPhoto(boundPhoto, boundFeat)) {
      return withBox.copyWith(
        photoIndex: null,
        sourcePhotoLabel: '',
      );
    }
    // Person / indoor frames are never primary evidence.
    if (_isNonExteriorCapturePhoto(boundPhoto)) {
      return withBox.copyWith(
        photoIndex: null,
        sourcePhotoLabel: '',
      );
    }
    return withBox;
  }

  /// True when a capture looks like ground outlet / soil / pipe (not wall paint).
  ///
  /// Device Problem close-ups often use the generic "Problem close-up" label with
  /// dirt, plants, and downspout pipe in frame — geometry must catch those.
  bool _isGradeOutletSoilPhoto(CapturePhoto photo, _ImageFeatures? feat) {
    // Pure roof / shingle / ridge / vent frames are never grade hosts —
    // vent "pipe" in a filename or Vision box must not flip the domain.
    if (_isRoofFieldCaptionWithoutGrade(photo) &&
        (feat == null ||
            (feat.foundationSignal < 0.36 && feat.lowerThirdDark < 0.40))) {
      return false;
    }
    if (photo.slotId == CaptureShotId.roof &&
        (feat == null ||
            (feat.roofSignal > 0.44 &&
                feat.foundationSignal < 0.36 &&
                feat.lowerThirdDark < 0.40))) {
      return false;
    }
    final caption = '${photo.label} ${photo.file.name}'.toLowerCase();
    final captionGrade =
        caption.contains('pipe') ||
        caption.contains('outlet') ||
        caption.contains('discharge') ||
        caption.contains('grade') ||
        caption.contains('soil') ||
        caption.contains('mulch') ||
        caption.contains('gravel') ||
        caption.contains('dirt') ||
        caption.contains('lawn') ||
        caption.contains('downspout end') ||
        (caption.contains('downspout') &&
            (caption.contains('ground') ||
                caption.contains('base') ||
                caption.contains('foundation') ||
                caption.contains('grade'))) ||
        (caption.contains('foundation') &&
            (caption.contains('wet') ||
                caption.contains('soil') ||
                caption.contains('outlet') ||
                caption.contains('pipe'))) ||
        (caption.contains('plant') &&
            (caption.contains('ground') ||
                caption.contains('base') ||
                caption.contains('pipe') ||
                caption.contains('foundation')));
    final frameGrade = feat != null &&
        (
        // Classic grade outlet geometry.
        (feat.foundationSignal > 0.42 &&
            feat.wallSignal < 0.50 &&
            (feat.lowerThirdDark > 0.38 ||
                feat.botEdgeDensity > 0.16 ||
                feat.moistureStainScore > 0.28)) ||
        // Foundation-competitive lower frames (partial wall still visible).
        (feat.foundationSignal >= feat.wallSignal - 0.04 &&
            feat.lowerThirdDark > 0.42 &&
            feat.botEdgeDensity > 0.14 &&
            feat.wallSignal < 0.55) ||
        // Plants / mulch / dirt close-ups with weak mid-wall plane.
        (feat.vegetationNear > 0.18 &&
            feat.lowerThirdDark > 0.40 &&
            feat.wallSignal < 0.50 &&
            feat.midEdgeDensity < 0.24) ||
        // Bottom-heavy foundation frames without mid elevation.
        (feat.botEdgeDensity > 0.22 &&
            feat.foundationSignal > 0.44 &&
            feat.wallSignal < 0.48 &&
            feat.midEdgeDensity < feat.botEdgeDensity));
    // Strong paint wall frame is never grade-only — wall must clearly dominate
    // foundation/grade (soil peel texture alone must not claim wall host).
    final frameWallPaint =
        feat != null &&
        feat.wallSignal > 0.52 &&
        feat.peelingScore > 0.45 &&
        feat.foundationSignal < feat.wallSignal - 0.10 &&
        feat.lowerThirdDark < 0.50;
    // Strong cladding wall frame (cracks / patch geometry) is never grade-only.
    final frameWallCladding =
        feat != null &&
        feat.wallSignal > 0.52 &&
        feat.foundationSignal < feat.wallSignal - 0.06 &&
        feat.lowerThirdDark < 0.52 &&
        (feat.crackLineScore > 0.40 ||
            feat.highLuminanceVariance > 0.52 ||
            feat.midEdgeDensity > 0.22);
    if (frameWallPaint || frameWallCladding) return false;
    return captionGrade || frameGrade;
  }

  /// True when photo can host paint evidence (wall / trim / fascia elevation).
  bool _isWallTrimPaintHostPhoto(CapturePhoto photo, _ImageFeatures? feat) {
    if (_isGradeOutletSoilPhoto(photo, feat)) return false;
    final caption = '${photo.label} ${photo.file.name}'.toLowerCase();
    final captionWall =
        caption.contains('wall') ||
        caption.contains('siding') ||
        caption.contains('trim') ||
        caption.contains('paint') ||
        caption.contains('peel') ||
        caption.contains('fascia') ||
        caption.contains('elevation') ||
        caption.contains('clapboard') ||
        caption.contains('facade') ||
        caption.contains('façade') ||
        caption.contains('front') ||
        caption.contains('left') ||
        caption.contains('right') ||
        caption.contains('rear') ||
        // "side" in elevation labels — not "Problem close-up".
        (caption.contains('side') && !caption.contains('close-up'));
    if (feat == null) {
      // Caption-only host when no pixels (rare) — require wall language.
      return captionWall &&
          !caption.contains('pipe') &&
          !caption.contains('soil') &&
          !caption.contains('outlet');
    }
    // Require a real wall plane; foundation-dominant lower frames are not hosts.
    if (feat.wallSignal < 0.38) return false;
    if (feat.foundationSignal > feat.wallSignal + 0.10 &&
        feat.lowerThirdDark > 0.45) {
      return false;
    }
    // Elevation caption or solid wall geometry.
    return captionWall ||
        (feat.wallSignal >= 0.44 &&
            feat.foundationSignal < feat.wallSignal + 0.02);
  }

  bool _hasWallTrimPaintHostPhoto(
    List<CapturePhoto> capturePhotos,
    List<_ImageFeatures> features,
  ) {
    return _bestWallTrimPaintPhotoIndex(capturePhotos, features) != null;
  }

  bool _hasWallCladdingHostPhoto(
    List<CapturePhoto> capturePhotos,
    List<_ImageFeatures> features,
  ) {
    return _bestWallCladdingPhotoIndex(capturePhotos, features) != null;
  }

  int? _bestWallTrimPaintPhotoIndex(
    List<CapturePhoto> capturePhotos,
    List<_ImageFeatures> features,
  ) {
    var bestI = -1;
    var best = -1.0;
    for (var i = 0; i < capturePhotos.length; i++) {
      final photo = capturePhotos[i];
      final feat = i < features.length ? features[i] : null;
      if (_isNonExteriorCapturePhoto(photo)) continue;
      if (!_isWallTrimPaintHostPhoto(photo, feat)) continue;
      var s = 0.0;
      if (feat != null) {
        s += feat.wallSignal * 0.6 + feat.peelingScore * 0.75;
        // Soft boost for mid-wall plane over lower-third grade bleed.
        if (feat.midEdgeDensity > feat.botEdgeDensity) s += 0.12;
        if (feat.foundationSignal > feat.wallSignal) s -= 0.35;
      }
      final caption = photo.label.toLowerCase();
      if (caption.contains('wall') ||
          caption.contains('siding') ||
          caption.contains('trim') ||
          caption.contains('paint') ||
          caption.contains('peel') ||
          caption.contains('fascia') ||
          caption.contains('elevation') ||
          caption.contains('clapboard') ||
          caption.contains('front') ||
          caption.contains('left') ||
          caption.contains('right') ||
          caption.contains('rear') ||
          (caption.contains('side') && !caption.contains('close-up'))) {
        s += 0.4;
      }
      if (s > best) {
        best = s;
        bestI = i;
      }
    }
    return bestI >= 0 ? bestI : null;
  }

  int? _bestWallCladdingPhotoIndex(
    List<CapturePhoto> capturePhotos,
    List<_ImageFeatures> features,
  ) {
    var bestI = -1;
    var best = -1.0;
    for (var i = 0; i < capturePhotos.length; i++) {
      final photo = capturePhotos[i];
      final feat = i < features.length ? features[i] : null;
      if (_isNonExteriorCapturePhoto(photo)) continue;
      if (_isGradeOutletSoilPhoto(photo, feat)) continue;
      var s = 0.0;
      if (feat != null) {
        s +=
            feat.wallSignal * 0.65 +
            feat.crackLineScore * 0.40 +
            feat.midEdgeDensity * 0.20;
        if (feat.wallSignal < 0.36) continue;
      }
      final caption = photo.label.toLowerCase();
      if (caption.contains('wall') ||
          caption.contains('siding') ||
          caption.contains('cladding') ||
          caption.contains('elevation') ||
          caption.contains('clapboard') ||
          caption.contains('brick') ||
          caption.contains('front') ||
          caption.contains('side') ||
          caption.contains('rear')) {
        s += 0.45;
      }
      if (s > best) {
        best = s;
        bestI = i;
      }
    }
    return bestI >= 0 ? bestI : null;
  }

  /// Roof / chimney evidence host: roof slot, roof caption, or upper-plane geometry.
  bool _isRoofHostPhoto(CapturePhoto photo, _ImageFeatures? feat) {
    if (_isNonExteriorCapturePhoto(photo)) return false;
    if (_isGradeOutletSoilPhoto(photo, feat)) return false;
    if (photo.slotId == CaptureShotId.roof) return true;
    final caption = '${photo.label} ${photo.file.name}'.toLowerCase();
    if (caption.contains('roof') ||
        caption.contains('shingle') ||
        caption.contains('ridge') ||
        caption.contains('granule') ||
        caption.contains('asphalt') ||
        caption.contains('slope') ||
        (caption.contains('eave') && !caption.contains('grade'))) {
      return true;
    }
    if (feat == null) return false;
    return feat.roofSignal > 0.44 &&
        feat.darkTopBias > 0.22 &&
        feat.foundationSignal < 0.38 &&
        feat.lowerThirdDark < 0.40;
  }

  /// Pure roof-field frame — not suitable as ground-drainage primary evidence.
  bool _isRoofFieldOnlyPhoto(CapturePhoto photo, _ImageFeatures? feat) {
    if (_isGradeOutletSoilPhoto(photo, feat)) return false;
    if (photo.slotId == CaptureShotId.roof &&
        (feat == null || feat.foundationSignal < 0.36)) {
      return true;
    }
    if (feat == null) return false;
    return feat.roofSignal > 0.50 &&
        feat.foundationSignal < 0.32 &&
        feat.lowerThirdDark < 0.28;
  }

  int? _bestRoofHostPhotoIndex(
    List<CapturePhoto> capturePhotos,
    List<_ImageFeatures> features,
  ) {
    var bestI = -1;
    var best = -1.0;
    for (var i = 0; i < capturePhotos.length; i++) {
      final photo = capturePhotos[i];
      final feat = i < features.length ? features[i] : null;
      if (_isNonExteriorCapturePhoto(photo)) continue;
      if (!_isRoofHostPhoto(photo, feat)) continue;
      var s = 0.0;
      if (photo.slotId == CaptureShotId.roof) s += 0.80;
      if (feat != null) {
        s += feat.roofSignal * 0.70 + feat.darkTopBias * 0.25;
      }
      final caption = photo.label.toLowerCase();
      if (caption.contains('roof') || caption.contains('shingle')) s += 0.40;
      if (s > best) {
        best = s;
        bestI = i;
      }
    }
    return bestI >= 0 ? bestI : null;
  }

  int? _bestGradeDrainagePhotoIndex(
    List<CapturePhoto> capturePhotos,
    List<_ImageFeatures> features,
  ) {
    var bestI = -1;
    var best = -1.0;
    for (var i = 0; i < capturePhotos.length; i++) {
      final photo = capturePhotos[i];
      final feat = i < features.length ? features[i] : null;
      if (_isNonExteriorCapturePhoto(photo)) continue;
      if (_isRoofFieldOnlyPhoto(photo, feat) ||
          (_isRoofHostPhoto(photo, feat) &&
              !_isGradeOutletSoilPhoto(photo, feat))) {
        continue;
      }
      var s = 0.0;
      if (_isGradeOutletSoilPhoto(photo, feat)) s += 1.20;
      if (photo.slotId == CaptureShotId.problemCloseup) s += 0.45;
      if (feat != null) {
        s += feat.lowerThirdDark * 0.40 + feat.foundationSignal * 0.30;
        s -= feat.roofSignal * 0.25;
      }
      final caption = '${photo.label} ${photo.file.name}'.toLowerCase();
      if (caption.contains('soil') ||
          caption.contains('outlet') ||
          caption.contains('discharge') ||
          caption.contains('pipe') ||
          caption.contains('grade')) {
        s += 0.55;
      }
      if (s > best) {
        best = s;
        bestI = i;
      }
    }
    return bestI >= 0 ? bestI : null;
  }

  int? _fallbackPhotoIndexForCategory(
    _ScoredIssue scored, {
    required List<CapturePhoto> capturePhotos,
    required List<_ImageFeatures> features,
  }) {
    if (scored.category == 'roof' || scored.category == 'chimney') {
      return _bestRoofHostPhotoIndex(capturePhotos, features) ??
          _firstNonGradePhotoIndex(capturePhotos, features);
    }
    if (scored.category == 'gutter' &&
        _isGroundDrainageIssue(scored.issue)) {
      return _bestGradeDrainagePhotoIndex(capturePhotos, features);
    }
    return _firstNonGradePhotoIndex(capturePhotos, features);
  }

  int? _firstNonGradePhotoIndex(
    List<CapturePhoto> capturePhotos,
    List<_ImageFeatures> features,
  ) {
    for (var i = 0; i < capturePhotos.length; i++) {
      if (_isNonExteriorCapturePhoto(capturePhotos[i])) continue;
      final feat = i < features.length ? features[i] : null;
      if (!_isGradeOutletSoilPhoto(capturePhotos[i], feat)) return i;
    }
    return null;
  }

  int? _visionLocalizedHostIndex({
    required _ScoredIssue scored,
    required List<CapturePhoto> capturePhotos,
    required List<_ImageFeatures> features,
    required List<_VisionObjectBox> visionBoxes,
  }) {
    var bestI = -1;
    var bestScore = -1.0;
    for (final box in visionBoxes) {
      if (!isSpecificObjectForCategory(box.name, scored.category)) continue;
      if (!_visionBoxMatchesCategory(box, scored.category)) continue;
      if (box.score < 0.24) continue;
      final i = box.imageIndex;
      if (i < 0 || i >= capturePhotos.length) continue;
      final photo = capturePhotos[i];
      final feat = i < features.length ? features[i] : null;
      if (_isNonExteriorCapturePhoto(photo)) continue;
      if (scored.category == 'roof' || scored.category == 'chimney') {
        if (_isGradeOutletSoilPhoto(photo, feat)) continue;
      }
      if (scored.category == 'paint' &&
          !_isWallTrimPaintHostPhoto(photo, feat)) {
        continue;
      }
      if (scored.category == 'siding' &&
          _isGradeOutletSoilPhoto(photo, feat)) {
        continue;
      }
      if (scored.category == 'gutter' &&
          _isGroundDrainageIssue(scored.issue) &&
          (_isRoofFieldOnlyPhoto(photo, feat) ||
              (_isRoofHostPhoto(photo, feat) &&
                  !_isGradeOutletSoilPhoto(photo, feat)))) {
        continue;
      }
      if (box.score > bestScore) {
        bestScore = box.score;
        bestI = i;
      }
    }
    return bestI >= 0 ? bestI : null;
  }

  /// When the bound photo is ground/outlet evidence, rewrite eave overflow wording.
  AnalysisIssue _alignDrainageIssueToPhoto(
    AnalysisIssue issue,
    _ImageFeatures? feat,
    CapturePhoto photo,
  ) {
    if (_isGroundDrainageIssue(issue)) return issue;
    if (_isRoofHostPhoto(photo, feat) &&
        !_isGradeOutletSoilPhoto(photo, feat)) {
      return issue;
    }

    final caption = '${photo.label} ${photo.file.name}'.toLowerCase();
    final captionGround =
        caption.contains('pipe') ||
        caption.contains('outlet') ||
        caption.contains('downspout') ||
        caption.contains('discharge') ||
        caption.contains('grade') ||
        caption.contains('foundation') ||
        caption.contains('soil');
    final frameGround =
        feat != null &&
        feat.lowerThirdDark > 0.42 &&
        feat.gutterLineScore < 0.36 &&
        (feat.foundationSignal > 0.36 ||
            feat.moistureStainScore > 0.28 ||
            feat.botEdgeDensity > 0.16);
    final frameEave =
        feat != null &&
        (feat.gutterLineScore > 0.40 ||
            (feat.horizontalBanding > 0.40 && feat.darkTopBias > 0.22));

    final shouldGround =
        (frameGround && !frameEave) ||
        (captionGround &&
            (frameGround || feat == null || feat.gutterLineScore < 0.32));
    if (!shouldGround) return issue;

    final titleLow = issue.title.toLowerCase();
    final wasOverflow =
        titleLow.contains('overflow') ||
        titleLow.contains('clog') ||
        titleLow.contains('gutter');
    if (!wasOverflow && titleLow.contains('drainage check')) {
      // Soft drainage already ground-friendly enough if location is ground.
      if (issue.location.toLowerCase().contains('ground') ||
          issue.location.toLowerCase().contains('outlet')) {
        return issue;
      }
    }

    return issue.copyWith(
      title: 'Water May Be Dumping Near Foundation',
      location: 'Downspout outlets & soil at grade',
      severity: issue.severity == 'Low' ? 'Low' : 'Medium',
      insight:
          'Photos look more like water leaving near the foundation than a clogged gutter at the roof edge. '
          'This is photo screening only — a general area estimate, not a tight object box. '
          'Recommended next step: extend outlets 4–6 ft from the house and check soil slope after rain.',
      confidence: min(issue.confidence, 78),
    );
  }

  bool _visionBoxMatchesCategory(_VisionObjectBox box, String category) {
    final needles = visionObjectNeedlesForCategory(category);
    return needles.any(
      (n) => box.name == n || box.name.contains(n) || n.contains(box.name),
    );
  }

  /// Attach Vision localization (or refined house box) for surface overlay.
  ///
  /// Strongly prefers real Vision object polys over structure estimates.
  /// Large house/building boxes are only used when no specific object exists.
  AnalysisIssue _attachVisionHighlight(
    AnalysisIssue issue, {
    required String category,
    required List<_VisionObjectBox> visionBoxes,
    required int? photoIndex,
  }) {
    if (visionBoxes.isEmpty) return issue;

    final groundDrainage =
        category == 'gutter' && _isGroundDrainageIssue(issue);
    final needles = visionObjectNeedlesForCategory(
      category,
      groundDrainage: groundDrainage,
    );
    _VisionObjectBox? best;
    var bestRank = -1.0;
    _VisionObjectBox? bestSpecific;
    var bestSpecificRank = -1.0;

    for (final box in visionBoxes) {
      final specific = isSpecificObjectForCategory(box.name, category);
      final structure = isLargeStructureObject(box.name);

      // Same-photo localization heavily preferred for real phone accuracy.
      // Specific objects on another photo still beat structure on this photo.
      final photoBoost = photoIndex == null
          ? 0.40
          : box.imageIndex == photoIndex
          ? 1.0
          : (specific ? 0.18 : 0.02);

      var nameHit = 0.0;
      var exact = false;
      for (final n in needles) {
        if (box.name == n) {
          nameHit = 1.0;
          exact = true;
          break;
        }
        if (box.name.contains(n) || n.contains(box.name)) {
          nameHit = max(nameHit, 0.72);
        }
      }
      if (nameHit <= 0) continue;

      // Specific objects: accept modest scores; structure needs high confidence.
      if (specific && box.score < 0.22) continue;
      if (!specific && !structure && box.score < 0.48) continue;
      if (structure && box.score < 0.74) continue;

      // Massive preference for real object localization vs house/building.
      final specificity = specific
          ? 4.20
          : structure
          ? 0.02
          : 0.55;

      final area = box.width * box.height;
      // Penalize full-frame structure boxes and tiny noise.
      final areaScore = area > 0.70
          ? (structure ? 0.02 : 0.12)
          : area > 0.45
          ? (structure ? 0.06 : 0.48)
          : area < 0.010
          ? 0.18
          : 1.20;

      // Prefer compact high-confidence objects (typical window/roof patches).
      final compactBoost = specific && area > 0.010 && area < 0.40 ? 1.55 : 1.0;

      final rank =
          box.score *
          nameHit *
          (0.12 + 0.88 * photoBoost) *
          areaScore *
          specificity *
          compactBoost;
      final candidate = _VisionObjectBox(
        name: box.name,
        score: box.score,
        left: box.left,
        top: box.top,
        width: box.width,
        height: box.height,
        imageIndex: box.imageIndex,
        exactNameMatch: exact || specific,
      );
      if (rank > bestRank) {
        bestRank = rank;
        best = candidate;
      }
      if (specific && rank > bestSpecificRank) {
        bestSpecificRank = rank;
        bestSpecific = candidate;
      }
    }

    // Always prefer any usable specific object poly over structure estimates.
    // Structure bands are zone-like and should not win when a better box exists.
    if (bestSpecific != null && bestSpecificRank >= 0.05) {
      best = bestSpecific;
      bestRank = bestSpecificRank;
    }

    if (best == null) return issue;

    final structureOnly =
        isLargeStructureObject(best.name) &&
        !isSpecificObjectForCategory(best.name, category);
    // Structure-only boxes are a last resort — need strong rank + solid score.
    // Weak structure estimates become generic zone fallback (often hidden).
    if (structureOnly && (bestRank < 0.90 || best.score < 0.76)) return issue;
    if (!structureOnly && bestRank < 0.14) return issue;
    // Skip huge full-frame structure polys that cannot map a tight cue.
    if (structureOnly && best.width * best.height > 0.48) return issue;

    final useExactPoly =
        !isLargeStructureObject(best.name) &&
        (best.exactNameMatch ||
            isSpecificObjectForCategory(best.name, category));
    final refined = refineBoxForCategory(
      category,
      best.left,
      best.top,
      best.width,
      best.height,
      objectIsExactMatch: useExactPoly,
      groundDrainage: groundDrainage,
    );

    return issue.copyWith(
      highlightLeft: refined.l,
      highlightTop: refined.t,
      highlightWidth: refined.w,
      highlightHeight: refined.h,
    );
  }

  /// True when the finding is about water at grade / outlets, not roof-edge gutters.
  static bool _isGroundDrainageIssue(AnalysisIssue issue) {
    final key = '${issue.title} ${issue.location} ${issue.insight}'
        .toLowerCase();
    if (key.contains('dumping near foundation') ||
        key.contains('near foundation') ||
        key.contains('soil at grade') ||
        key.contains('ground outlets') ||
        key.contains('outlet ends') ||
        key.contains('water leaving near')) {
      return true;
    }
    // Downspout/outlet language without eave/overflow claims.
    final groundWords =
        key.contains('downspout') ||
        key.contains('outlet') ||
        key.contains('discharge') ||
        key.contains('at grade');
    final eaveWords =
        key.contains('eave') ||
        key.contains('roof edge') ||
        key.contains('overflow') ||
        key.contains('clog');
    return groundWords && !eaveWords;
  }

  bool _labelHas(
    Map<String, double> labels,
    List<String> needles, {
    double min = 0.34,
  }) {
    for (final e in labels.entries) {
      if (e.value < min) continue;
      final k = e.key.toLowerCase();
      for (final n in needles) {
        if (k == n || k.contains(n)) return true;
      }
    }
    return false;
  }

  /// True when the caption is a roof field / ridge / shingle shot with no
  /// soil / outlet / grade language.
  bool _isRoofFieldCaptionWithoutGrade(CapturePhoto photo) {
    final c = '${photo.label} ${photo.file.name}'.toLowerCase();
    if (c.contains('soil') ||
        c.contains('outlet') ||
        c.contains('discharge') ||
        c.contains('grade') ||
        c.contains('mulch') ||
        c.contains('gravel') ||
        c.contains('dirt')) {
      return false;
    }
    if (c.contains('roof & eave') || c.contains('roof and eave')) return true;
    if (c.contains('ridge') ||
        c.contains('shingle') ||
        c.contains('granule') ||
        c.contains('asphalt')) {
      return true;
    }
    if (c.contains('roof') &&
        !c.contains('gutter') &&
        !c.contains('outlet')) {
      return true;
    }
    return false;
  }

  /// Soil / grade / outlet / lower-wall support for foundation-water findings.
  ///
  /// Requires at least one photo in the drainage domain. Roof vents labeled
  /// "pipe" or a downspout glimpsed on a ridge shot are not enough.
  bool _sceneSupportsGroundDrainage({
    required List<_ImageFeatures> features,
    required List<CapturePhoto> photos,
    required Map<String, double> labels,
  }) {
    var hasDrainageHost = false;
    var hasNonRoofHost = photos.isEmpty;
    for (var i = 0; i < features.length; i++) {
      final f = features[i];
      final photo = i < photos.length ? photos[i] : null;
      final roofField = photo != null &&
          (_isRoofFieldOnlyPhoto(photo, f) ||
              (_isRoofHostPhoto(photo, f) &&
                  !_isGradeOutletSoilPhoto(photo, f)));
      if (roofField) continue;
      if (photo != null) hasNonRoofHost = true;
      if (photo != null && _isGradeOutletSoilPhoto(photo, f)) {
        hasDrainageHost = true;
        break;
      }
      // Foundation wall + lower elevation — not a roof plane.
      if (f.foundationSignal > 0.36 &&
          f.lowerThirdDark > 0.34 &&
          f.roofSignal < 0.42) {
        hasDrainageHost = true;
        break;
      }
    }
    if (hasDrainageHost) return true;
    if (_sceneIsRoofDominant(features: features, photos: photos)) {
      return false;
    }
    if (!hasNonRoofHost) return false;
    // Labels can corroborate a non-roof host. Do not treat downspout/pipe
    // alone as grade evidence (roof-edge downspouts, vent pipes).
    return _labelHas(labels, const [
      'soil',
      'outlet',
      'discharge',
      'grade',
      'mulch',
      'gravel',
      'foundation',
    ]);
  }

  /// Every frame is a roof field / ridge shot with no grade host.
  bool _sceneIsRoofDominant({
    required List<_ImageFeatures> features,
    required List<CapturePhoto> photos,
  }) {
    if (features.isEmpty) return false;
    var roofish = 0;
    for (var i = 0; i < features.length; i++) {
      final f = features[i];
      final photo = i < photos.length ? photos[i] : null;
      if (photo != null && _isGradeOutletSoilPhoto(photo, f)) return false;
      final roofPhoto =
          photo != null &&
          _isRoofHostPhoto(photo, f) &&
          !_isGradeOutletSoilPhoto(photo, f);
      final roofFeat =
          f.roofSignal > 0.50 &&
          f.foundationSignal < 0.28 &&
          f.lowerThirdDark < 0.30;
      if (roofPhoto || roofFeat) {
        roofish++;
      }
    }
    return roofish == features.length;
  }

  bool _sceneIsSoilOnly({
    required List<_ImageFeatures> features,
    required List<CapturePhoto> photos,
  }) {
    if (features.isEmpty) return false;
    var grade = 0;
    for (var i = 0; i < features.length; i++) {
      final f = features[i];
      final photo = i < photos.length ? photos[i] : null;
      if (photo != null && _isRoofHostPhoto(photo, f)) return false;
      if (f.roofSignal > 0.42 && f.darkTopBias > 0.24) return false;
      final gradePhoto = photo != null && _isGradeOutletSoilPhoto(photo, f);
      final gradeFeat =
          f.foundationSignal > 0.36 &&
          f.lowerThirdDark > 0.34 &&
          f.roofSignal < 0.36;
      if (gradePhoto || gradeFeat) grade++;
    }
    return grade == features.length;
  }

  bool _sceneSupportsRoofField({
    required List<_ImageFeatures> features,
    required List<CapturePhoto> photos,
    required Map<String, double> labels,
  }) {
    if (_sceneIsRoofDominant(features: features, photos: photos)) return true;
    for (var i = 0; i < features.length; i++) {
      final f = features[i];
      final photo = i < photos.length ? photos[i] : null;
      if (photo != null && _isRoofHostPhoto(photo, f)) return true;
      if (f.roofSignal > 0.42 && f.darkTopBias > 0.22) return true;
    }
    return _labelHas(labels, const [
      'roof',
      'shingle',
      'ridge',
      'asphalt',
      'tile',
      'granule',
    ]);
  }

  List<CaptureShotId> _preferredSlotsForCategory(
    String category, {
    AnalysisIssue? issue,
  }) {
    switch (category) {
      case 'roof':
      case 'chimney':
        return const [
          CaptureShotId.roof,
          CaptureShotId.front,
          CaptureShotId.rear,
          CaptureShotId.left,
          CaptureShotId.right,
          CaptureShotId.problemCloseup,
        ];
      case 'gutter':
      case 'fascia':
        // Ground discharge: prefer elevations / close-ups at grade, not roof CUs.
        if (issue != null && _isGroundDrainageIssue(issue)) {
          return const [
            CaptureShotId.problemCloseup,
            CaptureShotId.front,
            CaptureShotId.left,
            CaptureShotId.right,
            CaptureShotId.rear,
          ];
        }
        return const [
          CaptureShotId.roof,
          CaptureShotId.front,
          CaptureShotId.left,
          CaptureShotId.right,
          CaptureShotId.rear,
          CaptureShotId.problemCloseup,
        ];
      case 'foundation':
        return const [
          CaptureShotId.front,
          CaptureShotId.left,
          CaptureShotId.right,
          CaptureShotId.rear,
          CaptureShotId.problemCloseup,
          CaptureShotId.roof,
        ];
      case 'siding':
      case 'paint':
      case 'window':
        return const [
          CaptureShotId.front,
          CaptureShotId.left,
          CaptureShotId.right,
          CaptureShotId.rear,
          CaptureShotId.problemCloseup,
          CaptureShotId.roof,
        ];
      case 'vegetation':
        return const [
          CaptureShotId.left,
          CaptureShotId.right,
          CaptureShotId.rear,
          CaptureShotId.front,
          CaptureShotId.roof,
          CaptureShotId.problemCloseup,
        ];
      case 'rust':
        return const [
          CaptureShotId.roof,
          CaptureShotId.front,
          CaptureShotId.problemCloseup,
          CaptureShotId.left,
          CaptureShotId.right,
          CaptureShotId.rear,
        ];
      default:
        return const [
          CaptureShotId.problemCloseup,
          CaptureShotId.front,
          CaptureShotId.left,
          CaptureShotId.right,
          CaptureShotId.rear,
          CaptureShotId.roof,
        ];
    }
  }

  double _categoryFeatureScore(String category, _ImageFeatures f) {
    switch (category) {
      case 'roof':
      case 'chimney':
        return f.darkTopBias * 0.45 +
            f.topEdgeDensity * 0.35 +
            (f.highTextureChaos ? 0.25 : 0) +
            f.crackLineScore * 0.15;
      case 'gutter':
      case 'fascia':
        return f.midEdgeDensity * 0.2 +
            f.topEdgeDensity * 0.25 +
            f.vegetationNear * 0.2 +
            f.darkPatchRatio * 0.15;
      case 'foundation':
        return f.lowerThirdDark * 0.45 +
            f.botEdgeDensity * 0.35 +
            f.crackLineScore * 0.2;
      case 'siding':
        // Prefer mid-wall cladding; demote grade/soil frames.
        return (f.wallSignal * 0.45 +
                f.crackLineScore * 0.35 +
                f.moistureStainScore * 0.20 +
                f.midEdgeDensity * 0.15 -
                (f.foundationSignal > 0.48 &&
                        f.wallSignal < 0.48 &&
                        f.lowerThirdDark > 0.40
                    ? 0.55
                    : 0.0))
            .clamp(0.0, 1.5);
      case 'paint':
        // Prefer wall peel texture; demote grade/soil frames that lack peel.
        return (f.peelingScore * 0.55 +
                f.highLuminanceVariance * 0.22 +
                f.wallSignal * 0.30 -
                (f.foundationSignal > 0.48 &&
                        f.peelingScore < 0.42 &&
                        f.wallSignal < 0.48
                    ? 0.55
                    : 0.0))
            .clamp(0.0, 1.5);
      case 'window':
        return f.edgeDensity * 0.25 + f.moistureStainScore * 0.2;
      case 'vegetation':
        return f.vegetationNear * 0.5 + f.greenDominance * 0.35;
      case 'rust':
        return f.rustDominance * 2.0;
      default:
        return f.overallDistress * 0.4 + f.darkPatchRatio * 0.2;
    }
  }

  /// Dark, underexposed, or low-detail frames that should not score like a
  /// bright multi-angle healthy elevation set.
  static bool _featuresSuggestLimitedVisibility(
    _ImageFeatures f, {
    required int photoCount,
  }) {
    // Only demote thin coverage — multi-angle daylit sets stay honest.
    if (photoCount > 2) return false;
    return _isDarkCapture(f) || _isLowDetailCapture(f, photoCount: photoCount);
  }

  static bool _isDarkCapture(_ImageFeatures f) {
    return f.brightness < 72 ||
        (f.brightness < 92 && f.darkPatchRatio > 0.40) ||
        (f.darkPatchRatio > 0.52 && f.brightness < 105) ||
        (f.darkPatchRatio > 0.58 && f.contrast < 42 && f.brightness < 110);
  }

  static bool _isLowDetailCapture(
    _ImageFeatures f, {
    required int photoCount,
  }) {
    return photoCount == 1 &&
        f.edgeDensity < 0.095 &&
        f.contrast < 28 &&
        f.overallDistress < 0.28 &&
        // Daylit low-detail (weak ambiguous) is not the same as underexposed.
        f.brightness >= 90 &&
        f.darkPatchRatio < 0.35;
  }

  /// Demote over-confident severity and flag weak evidence honestly.
  AnalysisIssue _applyHonesty(AnalysisIssue issue) {
    var severity = issue.severity;
    var conf = issue.confidence;
    var insight = issue.insight;
    final titleLow = issue.title.toLowerCase();
    final limitedTitle =
        titleLow.contains('limited visibility') ||
        titleLow.contains('closer photo needed') ||
        titleLow.contains('retake');

    // Never claim High with weak confidence (screening honesty).
    if (severity == 'High' && conf < 88) {
      severity = 'Medium';
      conf = max(conf - 6, 58);
    }

    // Foundation / Missing Shingles Highs need stronger confidence still.
    if (severity == 'High' &&
        conf < 92 &&
        (titleLow.contains('foundation') ||
            titleLow.contains('missing') ||
            titleLow.contains('damaged shingle') ||
            titleLow.contains('settlement') ||
            titleLow.contains('structural'))) {
      severity = 'Medium';
      conf = max(conf - 5, 64);
    }

    // Zone-level ground drainage should not sound near-certain after boosts.
    if (titleLow.contains('dumping near foundation') ||
        (titleLow.contains('drainage check') &&
            issue.location.toLowerCase().contains('ground'))) {
      conf = min(conf, 84);
    }

    // Soft Medium with low conf becomes Low screening note.
    // Keep limited-visibility Medium so the retake CTA stays visible.
    if (severity == 'Medium' && conf < 72 && !limitedTitle) {
      severity = 'Low';
    }

    // Soft clapboard/wall crack claims without high confidence stay Low.
    if (severity == 'Medium' &&
        conf < 80 &&
        titleLow.contains('crack') &&
        !titleLow.contains('foundation') &&
        !titleLow.contains('settlement')) {
      severity = 'Low';
    }

    // Foundation crack/settlement Medium needs solid confidence; otherwise
    // treat as a Low screening note rather than a firm Medium claim.
    if (severity == 'Medium' &&
        conf < 82 &&
        (titleLow.contains('foundation crack') ||
            (titleLow.contains('foundation') &&
                titleLow.contains('settlement')))) {
      severity = 'Low';
    }

    // Low "review" items with modest confidence stay screening notes.
    // Also force closer-photo when the engine already flagged capture limits.
    final needsCloser =
        issue.needsCloserPhoto ||
        limitedTitle ||
        conf < 72 ||
        (severity == 'Low' &&
            conf < 80 &&
            (titleLow.contains('review') ||
                titleLow.contains('check') ||
                titleLow.contains('surface wear')));

    if (needsCloser) {
      conf = min(conf, limitedTitle ? 71 : 71);
      const tip =
          ' Screening note: retake a sharp close-up in good light before treating this as a firm diagnosis.';
      if (!insight.contains('Needs closer photos') &&
          !insight.contains('closer photos') &&
          !insight.contains('Screening note') &&
          !insight.contains('Retake in brighter')) {
        insight = insight.trimRight();
        if (!insight.endsWith('.')) insight = '$insight.';
        insight = '$insight$tip';
      }
    }

    // Soften absolute language in insight copy.
    insight = _injectScreeningTone(insight, severity: severity, conf: conf);

    // Hard ceiling: screening tools should not imply near-certainty.
    final maxConf = needsCloser
        ? 71
        : severity == 'High'
        ? 94
        : 92;

    final honestConf = conf.clamp(48, maxConf);
    final cost = _honestPlanningCost(
      baseCost: issue.cost,
      severity: severity,
      confidence: honestConf,
      needsCloserPhoto: needsCloser,
      title: issue.title,
    );

    return issue.copyWith(
      severity: severity,
      confidence: honestConf,
      insight: insight,
      needsCloserPhoto: needsCloser,
      cost: cost,
    );
  }

  /// Conservative planning ranges — hide weak evidence, shrink uncertain ones.
  String _honestPlanningCost({
    required String baseCost,
    required String severity,
    required int confidence,
    required bool needsCloserPhoto,
    required String title,
  }) {
    // Weak evidence: no dollar range (trust > generative estimates).
    if (needsCloserPhoto || confidence < 70) return 'TBD';
    // Low-severity cosmetic notes rarely need a firm planning number.
    if (severity == 'Low' && confidence < 82) return 'TBD';

    final match = RegExp(
      r'\$([0-9,]+)\s*[–-]\s*\$([0-9,]+)',
    ).firstMatch(baseCost);
    if (match == null) {
      final t = baseCost.trim();
      if (t.isEmpty || t.toUpperCase() == 'TBD') return 'TBD';
      return t;
    }

    var low = int.parse(match.group(1)!.replaceAll(',', ''));
    var high = int.parse(match.group(2)!.replaceAll(',', ''));
    if (low <= 0 && high <= 0) return 'TBD';

    // Overall conservatism: photo screening over-states scope vs bids.
    var scaleLow = 0.82;
    var scaleHigh = 0.72;
    if (confidence < 78) {
      scaleLow = 0.70;
      scaleHigh = 0.58;
    } else if (confidence < 85) {
      scaleLow = 0.78;
      scaleHigh = 0.66;
    }
    if (severity == 'Low') {
      scaleLow *= 0.75;
      scaleHigh *= 0.65;
    } else if (severity == 'Medium') {
      scaleHigh *= 0.90;
    }

    // Vegetation / paint watch-items: keep ranges modest.
    final key = title.toLowerCase();
    if (key.contains('vegetation') ||
        key.contains('landscape') ||
        key.contains('peeling') ||
        key.contains('paint')) {
      scaleHigh *= 0.88;
    }

    low = max(50, (low * scaleLow).round());
    high = max(low + 50, (high * scaleHigh).round());
    // Round to sensible planning steps.
    low = (low / 25).round() * 25;
    high = (high / 25).round() * 25;
    if (high <= low) high = low + 75;
    return '\$${_fmt(low)} – \$${_fmt(high)}';
  }

  /// Keep homeowner-facing copy from over-claiming certainty.
  String _injectScreeningTone(
    String insight, {
    required String severity,
    required int conf,
  }) {
    var text = insight.trim();
    if (text.isEmpty) return text;

    final lower = text.toLowerCase();
    if (!lower.contains('screening') &&
        !lower.contains('not a licensed') &&
        !lower.contains('not a final diagnosis') &&
        conf < 86) {
      if (!text.endsWith('.')) text = '$text.';
      text =
          '$text This is an AI exterior screening signal — confirm on-site before major work.';
    }

    // Soften "is supported" when confidence is only moderate.
    if (conf < 78) {
      text = text
          .replaceAll(' is supported by ', ' appears consistent with ')
          .replaceAll(' are supported by ', ' appear consistent with ');
    }

    if (severity == 'High' && conf < 88) {
      text = text.replaceAll(
        'worth planning around',
        'worth prioritizing after a quick on-site check',
      );
    }

    return text;
  }

  /// Demote landscaping/texture false alarms common on real exterior photos.
  void _suppressCleanSceneNoise(
    List<_ScoredIssue> candidates, {
    required int photoCount,
    required double overallDistress,
    required double peelScore,
    required double crackLine,
    required double lowerDark,
    required double darkTop,
    required double roofPresence,
    required double roofDefect,
    required bool visionMode,
  }) {
    if (candidates.isEmpty) return;
    // Real phone elevations often read as "busy"; treat slightly higher
    // aggregate distress as still mild for demoting soft Medium noise.
    final mild = overallDistress < 0.48;
    final multi = photoCount >= 2;
    final hasRoofCandidate = candidates.any(
      (x) =>
          x.category == 'roof' && x.issue.severity != 'Low' && x.score >= 0.42,
    );
    final roofPlaneDominant =
        hasRoofCandidate &&
        roofPresence > 0.42 &&
        (darkTop > 0.32 || roofDefect > 0.38) &&
        lowerDark < darkTop + 0.12;

    for (var i = 0; i < candidates.length; i++) {
      final c = candidates[i];
      var severity = c.issue.severity;
      var conf = c.issue.confidence;
      var score = c.score;
      final title = c.issue.title.toLowerCase();

      // Foundation Crack / Settlement — High/Medium need real support.
      // Prefer no finding / Low over false settlement on healthy elevations.
      final foundationCrackTitle =
          c.category == 'foundation' &&
          (title.contains('crack') || title.contains('settlement'));
      if (foundationCrackTitle) {
        final weakHigh =
            crackLine < 0.62 ||
            lowerDark < 0.56 ||
            score < 0.82 ||
            conf < 92 ||
            (!visionMode && !multi);
        if (severity == 'High' && weakHigh) {
          severity = (crackLine >= 0.56 && lowerDark >= 0.54 && score >= 0.66)
              ? 'Medium'
              : 'Low';
          conf = min(conf, severity == 'Low' ? 64 : 78);
          score *= severity == 'Low' ? 0.42 : 0.72;
        }

        // Medium foundation crack: require conf + either geometry or strong score
        // (caption/Vision dual-label). Soft elevation soil bands demote hard.
        if (severity == 'Medium') {
          final softMedium = !visionMode
              ? (conf < 80 ||
                    score < 0.52 ||
                    (crackLine < 0.42 && score < 0.62))
              : (conf < 78 ||
                    score < 0.50 ||
                    (crackLine < 0.40 && score < 0.58));
          if (softMedium) {
            severity = 'Low';
            conf = min(conf, 68);
            score *= 0.36;
          }
        }
        // Low crack titles without linear support → crush so filter drops them
        // unless score is already strong (labeled close-ups).
        if (severity == 'Low' && crackLine < 0.48 && score < 0.58) {
          score *= 0.28;
          conf = min(conf, 60);
        }
      }

      // Soft Low grade-review noise — drop score so filter can omit it.
      if (c.category == 'foundation' &&
          severity == 'Low' &&
          !foundationCrackTitle &&
          score < 0.58) {
        score *= 0.42;
        conf = min(conf, 62);
      }

      // Local-only foundation High is almost never justified without Vision.
      if (c.category == 'foundation' && severity == 'High' && !visionMode) {
        severity = (lowerDark > 0.60 && crackLine > 0.60 && score >= 0.84)
            ? 'Medium'
            : 'Low';
        conf = min(conf, severity == 'Low' ? 62 : 74);
        score *= 0.62;
      }

      // Vision foundation High still needs linear crack geometry, not soil band.
      if (c.category == 'foundation' &&
          severity == 'High' &&
          visionMode &&
          (crackLine < 0.60 || lowerDark < 0.56 || score < 0.82 || conf < 92)) {
        severity = crackLine >= 0.54 && lowerDark >= 0.52 ? 'Medium' : 'Low';
        conf = min(conf, severity == 'Low' ? 66 : 80);
        score *= 0.72;
      }

      // When a roof finding is competitive and the upper plane dominates,
      // demote grade-line foundation noise so roof owns the report.
      if (c.category == 'foundation' &&
          severity != 'Low' &&
          roofPlaneDominant &&
          (crackLine < 0.58 || lowerDark < darkTop + 0.12 || score < 0.76)) {
        severity = 'Low';
        conf = min(conf, 64);
        score *= 0.38;
      }

      // Soft Foundation & Grade Review Medium → Low without structure.
      if (c.category == 'foundation' &&
          severity == 'Medium' &&
          !foundationCrackTitle &&
          (lowerDark < 0.54 || crackLine < 0.36 || score < 0.62)) {
        severity = 'Low';
        conf = min(conf, 66);
        score *= 0.48;
      }

      // Paint Medium "Peeling / Failing" — need strong peel texture OR high score
      // from caption/label packs. Healthy multi-angle variance is not peel.
      final paintPeelTitle =
          c.category == 'paint' &&
          (title.contains('peel') || title.contains('failing'));
      if (paintPeelTitle && severity == 'Medium') {
        // Offline multi-angle mild scenes: variance is not peel without labels.
        if (!visionMode && multi && mild && (conf < 90 || peelScore < 0.56)) {
          severity = 'Low';
          conf = min(conf, 72);
          score *= 0.48;
        } else if (peelScore < 0.40 && score < 0.58) {
          severity = 'Low';
          conf = min(conf, 72);
          score *= 0.55;
        }
      }
      // Aging / non-peel paint without texture → keep Low and soft score.
      if (c.category == 'paint' &&
          severity != 'Low' &&
          peelScore < 0.48 &&
          !paintPeelTitle) {
        severity = 'Low';
        conf = min(conf, 74);
        score *= 0.72;
      }

      // Soft paint Medium without peel texture on mild multi → Low.
      if (c.category == 'paint' &&
          severity == 'Medium' &&
          multi &&
          mild &&
          peelScore < 0.48 &&
          conf < 88) {
        severity = 'Low';
        conf = min(conf, 72);
        score *= 0.60;
      }

      // Residual Low "Paint Film Aging" on healthy multi-angle — drop hard.
      // Healthy elevations must not surface UV-aging notes without paint labels.
      if (c.category == 'paint' &&
          severity == 'Low' &&
          !paintPeelTitle &&
          multi &&
          !visionMode &&
          (mild || peelScore < 0.50 || score < 0.55 || conf < 88)) {
        score *= 0.32;
        conf = min(conf, 62);
      }

      // Fascia / soffit Medium moisture — demote soft eave-shadow claims.
      // Healthy multi-angle homes often darken at eaves without real wet boards.
      final fasciaWetTitle =
          c.category == 'fascia' &&
          (title.contains('moisture') || title.contains('soffit moisture'));
      if (fasciaWetTitle && severity == 'Medium' && !visionMode) {
        // Offline Medium fascia is rarely justified without very high conf.
        if (conf < 90 || score < 0.60 || multi) {
          // Keep only single-photo / high-score offline if conf is rock solid.
          if (!(conf >= 90 && score >= 0.62 && !multi)) {
            severity = 'Low';
            conf = min(conf, 70);
            score *= 0.45;
          }
        }
      }
      // Low fascia noise — soft score so filter can drop empty eave reviews.
      if (c.category == 'fascia' && severity == 'Low' && multi) {
        score *= 0.50;
        conf = min(conf, 68);
      }

      // Drainage Medium — demote soft eave/landscaping noise offline.
      // Keep caption/label-backed or high-score overflow (gutter calibration).
      // Ground outlet / wet-soil dumping must NOT be demoted by multi+mild
      // filters — that under-call is the field-fixture failure mode.
      final groundDumpTitle =
          c.category == 'gutter' &&
          (title.contains('dumping near foundation') ||
              title.contains('ground outlets') ||
              (title.contains('drainage check') && lowerDark > 0.34));
      final gutterOverflowTitle =
          c.category == 'gutter' &&
          (title.contains('overflow') ||
              title.contains('clogging') ||
              title.contains('dumping near foundation'));
      if (gutterOverflowTitle &&
          severity == 'Medium' &&
          !visionMode &&
          !groundDumpTitle) {
        if (multi && mild && conf < 86 && score < 0.55) {
          severity = 'Low';
          conf = min(conf, 72);
          score *= 0.48;
        } else if (conf < 78 || score < 0.42) {
          severity = 'Low';
          conf = min(conf, 70);
          score *= 0.52;
        }
      }
      // Ground dump with grade evidence: keep Medium and score floor so filter keeps it.
      if (groundDumpTitle && severity != 'High' && lowerDark > 0.34) {
        if (severity == 'Low' && score >= 0.36) {
          severity = 'Medium';
        }
        score = max(score, 0.56);
        conf = max(conf, 78);
      }
      // Soft Low overflow titles on mild multi without score → drop filter weight.
      if (gutterOverflowTitle &&
          !groundDumpTitle &&
          severity == 'Low' &&
          multi &&
          mild &&
          score < 0.45) {
        score *= 0.45;
        conf = min(conf, 68);
      }
      // Low alignment-only gutters on clean multi-angle — soft filter bait.
      if (c.category == 'gutter' &&
          severity == 'Low' &&
          !gutterOverflowTitle &&
          !groundDumpTitle &&
          multi &&
          mild &&
          score < 0.48) {
        score *= 0.50;
        conf = min(conf, 68);
      }

      // Multi-angle: demote invented High roofs on clean / mild elevations.
      // Keep true "Missing / Damaged Shingles" at least Medium when score is solid.
      final hardRoofTitle =
          title.contains('missing') ||
          title.contains('damaged shingle') ||
          title.contains('granule');
      final softRoofTitle =
          title.contains('possible impact') || title.contains('surface wear');
      if (c.category == 'roof' && severity == 'High' && multi) {
        if (hardRoofTitle && score >= 0.62) {
          // Hard damage: drop High→Medium on mild aggregate distress or soft conf.
          if (mild && (score < 0.86 || conf < 92)) {
            severity = 'Medium';
            conf = min(conf, 86);
            score = max(score * 0.88, 0.58);
          } else if (!visionMode && (score < 0.82 || conf < 90)) {
            severity = 'Medium';
            conf = min(conf, 86);
            score = max(score * 0.90, 0.58);
          } else if (score < 0.80 || conf < 90) {
            severity = 'Medium';
            conf = min(conf, 88);
            score = max(score * 0.92, 0.60);
          }
        } else if (score < 0.84 || conf < 92 || mild) {
          severity = mild ? 'Low' : 'Medium';
          conf = min(conf, mild ? 74 : 84);
          score *= mild ? 0.62 : 0.84;
        }
      }

      // Soft roof Medium ("surface wear / possible impact") on multi-angle
      // scenes → Low unless hard damage title or strong upper-plane signal.
      // Healthy elevations often invent soft Medium roofs without shingle damage.
      if (c.category == 'roof' &&
          severity == 'Medium' &&
          multi &&
          softRoofTitle &&
          !hardRoofTitle &&
          (mild || conf < 88 || score < 0.72) &&
          (!visionMode || score < 0.78) &&
          darkTop < 0.36) {
        severity = 'Low';
        conf = min(conf, 74);
        score *= 0.62;
      } else if (c.category == 'roof' &&
          severity == 'Medium' &&
          mild &&
          multi &&
          !visionMode &&
          darkTop < 0.30 &&
          (softRoofTitle || score < 0.62) &&
          !hardRoofTitle) {
        severity = 'Low';
        conf = min(conf, 74);
        score *= 0.72;
      }

      // Soft gutter on multi-angle mild scenes → Low (unless strong overflow
      // or ground-outlet / wet-soil dumping evidence).
      if (c.category == 'gutter' &&
          severity != 'Low' &&
          multi &&
          mild &&
          score < 0.64 &&
          !visionMode &&
          !groundDumpTitle &&
          lowerDark < 0.40) {
        severity = 'Low';
        conf = min(conf, 74);
        score *= 0.72;
      }

      // Soft paint peel on multi-angle mild scenes without strong peel score.
      if (c.category == 'paint' &&
          severity == 'Medium' &&
          multi &&
          mild &&
          peelScore < 0.52 &&
          score < 0.70 &&
          !visionMode) {
        // Keep explicit peel titles only when score is solid.
        if (score < 0.58) {
          severity = 'Low';
          conf = min(conf, 74);
          score *= 0.72;
        }
      }

      // Cracks without strong linear score → Low (or drop).
      if (c.category == 'siding' &&
          title.contains('crack') &&
          crackLine < 0.48 &&
          severity != 'Low') {
        severity = 'Low';
        conf = min(conf, 72);
        score *= 0.55;
      }

      // Soft siding Medium on mild multi-angle → Low.
      // Keep mismatched / patched siding when wall variance or labels are solid.
      final sidingPatchTitle =
          c.category == 'siding' &&
          (title.contains('patch') || title.contains('mismatched'));
      if (c.category == 'siding' &&
          severity == 'Medium' &&
          title.contains('crack') &&
          multi &&
          !visionMode &&
          (mild || crackLine < 0.52) &&
          (score < 0.70 || conf < 88 || crackLine < 0.52)) {
        severity = 'Low';
        conf = min(conf, 72);
        score *= 0.50;
      }
      // Soft patched Medium without solid score → Low (avoid dirt stains).
      if (sidingPatchTitle &&
          severity == 'Medium' &&
          !visionMode &&
          multi &&
          mild &&
          conf < 80 &&
          score < 0.50) {
        severity = 'Low';
        conf = min(conf, 72);
        score *= 0.55;
      }
      // Strong patched findings must not be demoted by mild-scene filters.
      if (sidingPatchTitle &&
          severity == 'Medium' &&
          score >= 0.52 &&
          conf >= 80) {
        score = max(score, 0.56);
        conf = max(conf, 82);
      }

      // Soft Low "cracked siding" on healthy multi-angle — clapboard noise.
      // Prefer filter drop over showing a cracked title with no firm evidence.
      if (c.category == 'siding' &&
          title.contains('crack') &&
          severity == 'Low' &&
          multi &&
          !visionMode &&
          (mild || crackLine < 0.54 || score < 0.58 || conf < 88)) {
        score *= 0.38;
        conf = min(conf, 66);
      }

      // Soft Low siding review on clean multi-angle.
      if (c.category == 'siding' &&
          severity == 'Low' &&
          !title.contains('crack') &&
          !title.contains('moisture') &&
          !sidingPatchTitle &&
          multi &&
          mild &&
          score < 0.52) {
        score *= 0.45;
        conf = min(conf, 66);
      }

      // Exterior wiring Medium — keep label-backed; demote soft geometry-only.
      final wiringTitle =
          c.category == 'wiring' ||
          title.contains('wiring') ||
          title.contains('cable clutter');
      if (wiringTitle && severity == 'Medium') {
        if (score >= 0.50 && conf >= 80) {
          score = max(score, 0.54);
          conf = max(conf, 82);
        } else if (!visionMode && multi && mild && conf < 82 && score < 0.50) {
          severity = 'Low';
          conf = min(conf, 72);
          score *= 0.55;
        }
      }

      // Soft roof wear on mild multi-angle healthy elevations → Low.
      if (c.category == 'roof' &&
          severity == 'Medium' &&
          mild &&
          multi &&
          !visionMode &&
          (title.contains('wear') ||
              title.contains('possible') ||
              score < 0.62) &&
          !title.contains('missing') &&
          !title.contains('damaged shingle') &&
          !title.contains('granule')) {
        severity = 'Low';
        conf = min(conf, 74);
        score *= 0.70;
      }

      // Soft roof Medium that is only weak texture → Low when multi-angle mild
      // and title is not hard damage (already handled). Boost hard roof score
      // so it is not dropped by the weak-Low filter.
      if (c.category == 'roof' &&
          hardRoofTitle &&
          severity == 'Medium' &&
          score < 0.50) {
        score = 0.55;
        conf = max(conf, 80);
      }

      // Moisture staining soft without multi-photo → Low.
      if (c.category == 'siding' &&
          title.contains('moisture') &&
          severity == 'Medium' &&
          conf < 86) {
        severity = multi ? 'Low' : severity;
        conf = min(conf, 74);
      }

      // Soft gutter overflow on ordinary eaves.
      if (c.category == 'gutter' &&
          title.contains('overflow') &&
          score < 0.58 &&
          !visionMode) {
        severity = 'Low';
        conf = min(conf, 72);
      }

      // Window seal soft claims without Vision → Low on multi-angle.
      if (c.category == 'window' && severity == 'Medium' && !visionMode) {
        severity = 'Low';
        conf = min(conf, 74);
      }

      // On multi-angle local-only, demote soft Mediums for non-critical systems.
      if (!visionMode &&
          multi &&
          severity == 'Medium' &&
          c.criticality < 0.92 &&
          conf < 88 &&
          score < 0.62) {
        severity = 'Low';
        conf = min(conf, 74);
      }

      if (severity == c.issue.severity &&
          conf == c.issue.confidence &&
          score == c.score) {
        continue;
      }
      candidates[i] = _ScoredIssue(
        category: c.category,
        criticality: c.criticality,
        score: score.clamp(0.0, 1.0),
        issue: c.issue.copyWith(severity: severity, confidence: conf),
      );
    }

    // Cap Medium pile-up: keep top 2 Mediums by score; demote the rest.
    final mediums = <int>[];
    for (var i = 0; i < candidates.length; i++) {
      if (candidates[i].issue.severity == 'Medium') mediums.add(i);
    }
    if (mediums.length > 2) {
      mediums.sort(
        (a, b) => candidates[b].score.compareTo(candidates[a].score),
      );
      for (final idx in mediums.skip(2)) {
        final c = candidates[idx];
        // Never demote explicit peeling / missing-shingle / foundation crack
        // titles — caption-backed real-phone primaries must stay Medium+.
        final t = c.issue.title.toLowerCase();
        if (t.contains('peel') ||
            t.contains('missing') ||
            t.contains('damaged shingle') ||
            t.contains('settlement') ||
            t.contains('mismatched') ||
            t.contains('patched') ||
            t.contains('wiring') ||
            t.contains('cable') ||
            (t.contains('foundation') && t.contains('crack'))) {
          continue;
        }
        candidates[idx] = _ScoredIssue(
          category: c.category,
          criticality: c.criticality,
          score: c.score * 0.7,
          issue: c.issue.copyWith(
            severity: 'Low',
            confidence: min(c.issue.confidence, 72),
          ),
        );
      }
    }

    // Restore caption-backed peeling paint if earlier noise filters dropped it.
    // Require solid score so wall texture does not re-promote soft peels.
    for (var i = 0; i < candidates.length; i++) {
      final c = candidates[i];
      final t = c.issue.title.toLowerCase();
      if (c.category == 'paint' &&
          c.issue.severity == 'Low' &&
          (t.contains('peel') || t.contains('failing')) &&
          c.score >= 0.52) {
        candidates[i] = _ScoredIssue(
          category: c.category,
          criticality: c.criticality,
          score: max(c.score, 0.55),
          issue: c.issue.copyWith(
            severity: 'Medium',
            confidence: max(c.issue.confidence, 80),
          ),
        );
      }
    }
  }

  /// Prefer the system backed by caption/slot/Vision labels when pixel cues fight.
  /// Real elevations often fire grade + roof texture together; labels break ties.
  void _lockPrimarySystemFromLabels(
    List<_ScoredIssue> candidates,
    Map<String, double> labels,
  ) {
    if (candidates.isEmpty || labels.isEmpty) return;

    double lab(List<String> keys) {
      var best = 0.0;
      for (final e in labels.entries) {
        if (e.value < 0.30) continue;
        for (final k in keys) {
          if (e.key.contains(k) || k.contains(e.key)) {
            best = max(best, e.value);
          }
        }
      }
      return best;
    }

    final roofLab = lab(const ['roof', 'shingle', 'asphalt', 'granule']);
    final foundLab = lab(const [
      'foundation',
      'concrete',
      'settling',
      'settlement',
      'spall',
      'honeycomb',
    ]);
    final paintLab = lab(const ['paint', 'peel', 'flake', 'film']);
    final sidingLab = lab(const [
      'siding',
      'cladding',
      'vinyl',
      'stucco',
      'patch',
      'discoloration',
      'repair',
    ]);
    final wiringLab = lab(const [
      'wiring',
      'cable',
      'wire',
      'electrical',
      'conduit',
    ]);
    // Include ground-outlet synonyms — pipe/outlet captions are drainage, not
    // "soft gutter noise" to demote under foundation foundation labels.
    final gutterLab = lab(const [
      'gutter',
      'downspout',
      'overflow',
      'debris',
      'pipe',
      'outlet',
      'drain',
      'discharge',
    ]);
    final hasGroundDumpCandidate = candidates.any((c) {
      if (c.category != 'gutter') return false;
      final t = c.issue.title.toLowerCase();
      final loc = c.issue.location.toLowerCase();
      return t.contains('dumping near foundation') ||
          t.contains('drainage check') ||
          loc.contains('grade') ||
          loc.contains('ground outlet');
    });

    void demoteCategory(String cat, {bool forceLow = false}) {
      for (var i = 0; i < candidates.length; i++) {
        final c = candidates[i];
        if (c.category != cat) continue;
        // Never force-low a ground-outlet drainage finding for foundation
        // caption competition — that was the field under-call failure.
        if (cat == 'gutter' && hasGroundDumpCandidate) continue;
        if (c.issue.severity == 'Low' && !forceLow) continue;
        candidates[i] = _ScoredIssue(
          category: c.category,
          criticality: c.criticality * 0.7,
          score: c.score * 0.55,
          issue: c.issue.copyWith(
            severity: forceLow
                ? 'Low'
                : (c.issue.severity == 'High' ? 'Medium' : 'Low'),
            confidence: min(c.issue.confidence, forceLow ? 70 : 78),
          ),
        );
      }
    }

    void boostCategory(String cat, {double add = 0.14}) {
      for (var i = 0; i < candidates.length; i++) {
        final c = candidates[i];
        if (c.category != cat) continue;
        candidates[i] = _ScoredIssue(
          category: c.category,
          criticality: min(1.0, c.criticality + 0.05),
          score: min(1.0, c.score + add),
          issue: c.issue.copyWith(confidence: min(94, c.issue.confidence + 2)),
        );
      }
    }

    // Roof-labeled walkthrough: demote grade-line, wall moisture, soft gutters.
    if (roofLab >= 0.58 && foundLab < roofLab - 0.08) {
      boostCategory('roof', add: 0.24);
      demoteCategory('foundation', forceLow: true);
      demoteCategory('siding', forceLow: true);
      demoteCategory('paint', forceLow: paintLab < 0.55);
      if (gutterLab < roofLab - 0.05 && !hasGroundDumpCandidate) {
        demoteCategory('gutter', forceLow: true);
      }
    }
    // Foundation-labeled CUs: demote soft roof wear invented from texture.
    // Outlet / wet-soil drainage often shares "foundation" caption language —
    // boost drainage when pipe/outlet labels are present instead of demoting it.
    if (foundLab >= 0.58 && roofLab < foundLab - 0.08) {
      if (hasGroundDumpCandidate || gutterLab >= 0.52) {
        boostCategory('gutter', add: 0.16);
        // Soft foundation review still OK; hard crack may coexist.
        if (gutterLab + 0.04 >= foundLab) {
          demoteCategory('foundation', forceLow: true);
        }
      } else {
        boostCategory('foundation', add: 0.18);
      }
      demoteCategory('roof', forceLow: true);
      if (gutterLab < foundLab - 0.05 &&
          gutterLab < 0.50 &&
          !hasGroundDumpCandidate) {
        demoteCategory('gutter', forceLow: true);
      }
    }
    // Paint / siding / gutter labeled primaries.
    if (paintLab >= 0.58 && roofLab < 0.50 && foundLab < paintLab - 0.05) {
      boostCategory('paint', add: 0.14);
      demoteCategory('foundation', forceLow: foundLab < 0.45);
    }
    if (sidingLab >= 0.58 && foundLab < sidingLab - 0.05 && roofLab < 0.50) {
      boostCategory('siding', add: 0.14);
      demoteCategory('foundation', forceLow: foundLab < 0.45);
      // Wall patch work should outrank opportunistic window seal notes.
      demoteCategory('window', forceLow: true);
    }
    if (wiringLab >= 0.50 && roofLab < 0.55 && foundLab < 0.55) {
      boostCategory('wiring', add: 0.16);
      demoteCategory('window', forceLow: true);
    }
    // Boost gutters when outlet/drainage labels lead or match foundation.
    if (gutterLab >= 0.55 &&
        gutterLab >= roofLab - 0.02 &&
        (gutterLab >= foundLab - 0.08 || hasGroundDumpCandidate)) {
      boostCategory('gutter', add: 0.12);
    }
  }

  /// When one system dominates evidence, demote weak secondary Highs so reports
  /// stay focused and scores stay trustworthy (golden-set calibrated).
  void _suppressSecondaryFalsePositives(List<_ScoredIssue> candidates) {
    if (candidates.length < 2) return;

    _ScoredIssue? bestOf(String cat) {
      _ScoredIssue? best;
      for (final c in candidates) {
        if (c.category != cat) continue;
        if (best == null || c.score > best.score) best = c;
      }
      return best;
    }

    final roof = bestOf('roof');
    final siding = bestOf('siding');
    final paint = bestOf('paint');
    final foundation = bestOf('foundation');
    final window = bestOf('window');
    final fascia = bestOf('fascia');
    final gutter = bestOf('gutter');
    final wiring = bestOf('wiring');

    void demote(_ScoredIssue? c, {double minScoreKeepHigh = 0.70}) {
      if (c == null) return;
      if (c.issue.severity != 'High' && c.issue.severity != 'Medium') return;
      // minScoreKeepHigh >= 0.99 means force-demote (always lower severity).
      final force = minScoreKeepHigh >= 0.99;
      if (!force &&
          c.issue.severity == 'High' &&
          c.score >= minScoreKeepHigh &&
          c.issue.confidence >= 86) {
        return;
      }
      final i = candidates.indexWhere((x) => x.category == c.category);
      if (i < 0) return;
      final cur = candidates[i];
      if (cur.issue.severity == 'Low') return;
      candidates[i] = _ScoredIssue(
        category: cur.category,
        criticality: cur.criticality,
        score: cur.score * 0.92,
        issue: cur.issue.copyWith(
          severity: cur.issue.severity == 'High' ? 'Medium' : 'Low',
          confidence: min(cur.issue.confidence, 84),
        ),
      );
    }

    // Strong roof damage often bleeds texture chaos into walls/windows/paint.
    // Prefer solid roof findings so real shingle photos surface over wall bleed.
    final roofTitle = roof?.issue.title.toLowerCase() ?? '';
    // "Possible impact" / surface wear are soft — do not treat as hard damage.
    final roofIsHardDamage =
        roofTitle.contains('missing') ||
        roofTitle.contains('damaged shingle') ||
        roofTitle.contains('granule') ||
        roofTitle.contains('aging') ||
        (roofTitle.contains('impact') && !roofTitle.contains('possible'));
    final roofIsSoftWear =
        roofTitle.contains('wear') ||
        roofTitle.contains('possible') ||
        roofTitle.contains('surface');
    // Treat solid roof wear/aging as primary when score is competitive so
    // wall/grade bleed does not crowd out the actual roof problem.
    final roofPrimary =
        roof != null &&
        roof.issue.severity != 'Low' &&
        roof.score >= 0.48 &&
        (roofIsHardDamage ||
            roof.issue.severity == 'High' ||
            roof.score >= 0.58 ||
            (roofIsSoftWear && roof.score >= 0.54));
    final roofStrong =
        roof != null &&
        roof.score >= 0.50 &&
        roof.issue.severity != 'Low' &&
        (roof.issue.severity == 'High' ||
            roofIsHardDamage ||
            roof.score >= 0.60 ||
            (roofIsSoftWear && roof.score >= 0.56));
    // Strong wall patch / wiring should demote soft window seals.
    final sidingTitle = siding?.issue.title.toLowerCase() ?? '';
    final sidingIsPatch =
        siding != null &&
        siding.issue.severity != 'Low' &&
        siding.score >= 0.50 &&
        (sidingTitle.contains('patch') ||
            sidingTitle.contains('mismatched') ||
            sidingTitle.contains('crack'));
    if (sidingIsPatch ||
        (wiring != null &&
            wiring.issue.severity != 'Low' &&
            wiring.score >= 0.50)) {
      if (window != null && window.score < 0.62) {
        demote(window, minScoreKeepHigh: 0.99);
      }
    }

    if (roofStrong || roofPrimary) {
      final r = bestOf('roof')!;
      // Keep competitive wall patch findings when roof is only soft wear.
      final keepSidingPatch =
          siding != null &&
          (siding.issue.title.toLowerCase().contains('patch') ||
              siding.issue.title.toLowerCase().contains('mismatched')) &&
          siding.score >= r.score * 0.92;
      if (siding != null && siding.score < r.score * 1.05 && !keepSidingPatch) {
        demote(siding, minScoreKeepHigh: 0.90);
      }
      if (window != null && window.score < 0.58) {
        demote(window, minScoreKeepHigh: 0.86);
      }
      if (fascia != null && fascia.score < 0.58) {
        demote(fascia, minScoreKeepHigh: 0.86);
      }
      if (paint != null && paint.score < r.score * 1.05) {
        demote(paint, minScoreKeepHigh: 0.90);
      }
      if (gutter != null && gutter.score < r.score * 1.02) {
        demote(gutter, minScoreKeepHigh: 0.88);
      }
      // Grade/soil bands often fire on roof elevations — demote soft grade notes.
      // Hard foundation crack titles only keep rank when clearly stronger than roof.
      if (foundation != null) {
        final fTitle = foundation.issue.title.toLowerCase();
        final foundationHard =
            fTitle.contains('crack') || fTitle.contains('settlement');
        if (!foundationHard && foundation.score <= r.score * 1.08) {
          demote(foundation, minScoreKeepHigh: 0.94);
        } else if (foundationHard &&
            roofIsHardDamage &&
            foundation.score < r.score * 1.15) {
          // Roof is the labeled/primary system — do not let grade-line noise win.
          demote(foundation, minScoreKeepHigh: 0.99);
        } else if (foundationHard && foundation.score <= r.score) {
          demote(foundation, minScoreKeepHigh: 0.96);
        }
      }
      // Nudge roof score so it survives max-issues filtering on real phones.
      final ri = candidates.indexWhere((x) => x.category == 'roof');
      if (ri >= 0) {
        final cur = candidates[ri];
        candidates[ri] = _ScoredIssue(
          category: cur.category,
          criticality: cur.criticality,
          score: min(1.0, cur.score + (roofIsHardDamage ? 0.16 : 0.12)),
          issue: cur.issue,
        );
      }
    }

    // Strong foundation / settlement claims: demote wall crack bleed from grade.
    // Do not let foundation crowd out a competitive paint/siding primary.
    final foundationTitle = foundation?.issue.title.toLowerCase() ?? '';
    final foundationStrong =
        foundation != null &&
        foundation.issue.severity != 'Low' &&
        foundation.score >= 0.54 &&
        (foundationTitle.contains('crack') ||
            foundationTitle.contains('settlement') ||
            foundationTitle.contains('foundation') ||
            foundation.score >= 0.64);
    final paintStrong =
        paint != null &&
        paint.issue.severity != 'Low' &&
        paint.score >= 0.52 &&
        (paint.issue.title.toLowerCase().contains('peel') ||
            paint.issue.title.toLowerCase().contains('paint') ||
            paint.score >= 0.58);
    final sidingStrong =
        siding != null &&
        siding.issue.severity != 'Low' &&
        siding.score >= 0.52 &&
        (siding.issue.title.toLowerCase().contains('crack') ||
            siding.issue.title.toLowerCase().contains('siding') ||
            siding.score >= 0.58);
    final foundationHardTitle =
        foundationTitle.contains('crack') ||
        foundationTitle.contains('settlement');
    if (foundationStrong && !roofStrong) {
      final f = bestOf('foundation')!;
      // Only demote wall systems when foundation is clearly stronger.
      if (siding != null && siding.score < f.score * 0.92) {
        demote(siding, minScoreKeepHigh: 0.94);
      }
      if (paint != null && paint.score < f.score * 0.92) {
        demote(paint, minScoreKeepHigh: 0.94);
      }
      // Soft grade-review foundation can yield to competitive paint/siding.
      // Hard crack/settlement titles keep rank (real foundation CUs).
      if (!foundationHardTitle &&
          ((paintStrong && paint.score >= f.score * 0.95) ||
              (sidingStrong && siding.score >= f.score * 0.95))) {
        demote(foundation, minScoreKeepHigh: 0.99);
      } else {
        final fi = candidates.indexWhere((x) => x.category == 'foundation');
        if (fi >= 0) {
          final cur = candidates[fi];
          candidates[fi] = _ScoredIssue(
            category: cur.category,
            criticality: cur.criticality,
            score: min(1.0, cur.score + 0.10),
            issue: cur.issue,
          );
        }
      }
    }
    // Paint primary: demote soft foundation grade bleed on wall CUs only.
    if (paintStrong && !roofStrong && !foundationHardTitle) {
      final p = bestOf('paint')!;
      if (foundation != null &&
          !foundationHardTitle &&
          foundation.score <= p.score * 1.08) {
        demote(foundation, minScoreKeepHigh: 0.99);
      }
      final pi = candidates.indexWhere((x) => x.category == 'paint');
      if (pi >= 0) {
        final cur = candidates[pi];
        candidates[pi] = _ScoredIssue(
          category: cur.category,
          criticality: cur.criticality,
          score: min(1.0, cur.score + 0.12),
          issue: cur.issue,
        );
      }
    }
    // Siding primary: demote soft foundation grade bleed on wall CUs only.
    if (sidingStrong && !roofStrong && !foundationHardTitle) {
      final s = bestOf('siding')!;
      if (foundation != null && foundation.score <= s.score * 1.08) {
        demote(foundation, minScoreKeepHigh: 0.99);
      }
      final si = candidates.indexWhere((x) => x.category == 'siding');
      if (si >= 0) {
        final cur = candidates[si];
        candidates[si] = _ScoredIssue(
          category: cur.category,
          criticality: cur.criticality,
          score: min(1.0, cur.score + 0.12),
          issue: cur.issue,
        );
      }
    }

    // Gutter/overflow primary: demote wall cracks invented from eave texture.
    // Skip when cracked siding already has solid wall evidence (wall CUs).
    final gutterStrong =
        gutter != null &&
        gutter.score >= 0.52 &&
        gutter.issue.severity != 'Low' &&
        (gutter.issue.title.toLowerCase().contains('overflow') ||
            gutter.issue.title.toLowerCase().contains('gutter')) &&
        !(siding != null &&
            siding.issue.severity != 'Low' &&
            siding.score >= 0.50 &&
            (siding.issue.title.toLowerCase().contains('crack') ||
                siding.issue.title.toLowerCase().contains('siding')));
    if (gutterStrong && !roofStrong) {
      final gi = candidates.indexWhere((x) => x.category == 'gutter');
      if (gi >= 0) {
        final cur = candidates[gi];
        candidates[gi] = _ScoredIssue(
          category: cur.category,
          criticality: cur.criticality,
          score: min(1.0, cur.score + 0.08),
          issue: cur.issue,
        );
      }
      if (siding != null && siding.score < gutter.score) {
        demote(siding, minScoreKeepHigh: 0.86);
      }
      if (paint != null && paint.score < gutter.score) {
        demote(paint, minScoreKeepHigh: 0.86);
      }
    }

    // Paint peel should not also claim cracked siding High without crack score.
    if (paint != null &&
        paint.score >= 0.48 &&
        siding != null &&
        siding.issue.title.toLowerCase().contains('crack') &&
        siding.score < paint.score * 1.05) {
      demote(siding, minScoreKeepHigh: 0.84);
      if (roof != null &&
          !roofStrong &&
          roof.score < paint.score * 0.90 &&
          !roofIsHardDamage) {
        demote(roof, minScoreKeepHigh: 0.82);
      }
    }

    // Grade-primary: foundation crack/settlement should beat soft roof wear.
    final foundationPrimary =
        foundation != null &&
        foundation.score >= 0.50 &&
        foundation.issue.severity != 'Low' &&
        (foundationTitle.contains('foundation') ||
            foundationTitle.contains('settlement') ||
            foundationTitle.contains('crack'));
    if (foundationPrimary) {
      final fi = candidates.indexWhere((x) => x.category == 'foundation');
      if (fi >= 0) {
        final cur = candidates[fi];
        candidates[fi] = _ScoredIssue(
          category: cur.category,
          criticality: cur.criticality,
          score: min(1.0, cur.score + 0.14),
          issue: cur.issue,
        );
      }
      final fScore = bestOf('foundation')?.score ?? foundation.score;
      if (siding != null && siding.score < fScore * 1.05) {
        demote(siding, minScoreKeepHigh: 0.86);
      }
      if (paint != null && paint.score < fScore * 1.05) {
        demote(paint, minScoreKeepHigh: 0.86);
      }
      // Soft roof wear / possible-impact often bleeds from grade texture.
      if (roof != null &&
          (roofIsSoftWear || !roofIsHardDamage || !roofStrong) &&
          roof.score <= fScore * 1.12) {
        demote(roof, minScoreKeepHigh: 0.90);
      }
    }

    // Paint-primary BEFORE siding: peel cues beat opportunistic crack bleed.
    final paintTitle = paint?.issue.title.toLowerCase() ?? '';
    final paintPrimary =
        paint != null &&
        paint.score >= 0.48 &&
        paint.issue.severity != 'Low' &&
        (paintTitle.contains('paint') ||
            paintTitle.contains('peel') ||
            paintTitle.contains('film')) &&
        !foundationPrimary &&
        !roofStrong;
    if (paintPrimary) {
      final pi = candidates.indexWhere((x) => x.category == 'paint');
      if (pi >= 0) {
        final cur = candidates[pi];
        candidates[pi] = _ScoredIssue(
          category: cur.category,
          criticality: cur.criticality,
          score: min(1.0, cur.score + 0.16),
          issue: cur.issue,
        );
      }
      final pScore = bestOf('paint')?.score ?? paint.score;
      // Peel texture is frequently misread as cladding cracks.
      if (siding != null && siding.score <= pScore * 1.15) {
        demote(siding, minScoreKeepHigh: 0.92);
      }
      if (roof != null &&
          (roofIsSoftWear || !roofIsHardDamage) &&
          roof.score <= pScore * 1.10) {
        demote(roof, minScoreKeepHigh: 0.88);
      }
    }

    // Siding/masonry primary: demote weak roof/gutter/paint from wall texture.
    final sidingPrimary =
        siding != null &&
        siding.score >= 0.48 &&
        siding.issue.severity != 'Low' &&
        (sidingTitle.contains('siding') ||
            sidingTitle.contains('cladding') ||
            sidingTitle.contains('crack') ||
            sidingTitle.contains('moisture') ||
            sidingTitle.contains('patch') ||
            sidingTitle.contains('mismatched')) &&
        !paintPrimary;
    if (sidingPrimary && !roofStrong && !foundationPrimary) {
      final si = candidates.indexWhere((x) => x.category == 'siding');
      if (si >= 0) {
        final cur = candidates[si];
        candidates[si] = _ScoredIssue(
          category: cur.category,
          criticality: cur.criticality,
          score: min(1.0, cur.score + 0.14),
          issue: cur.issue,
        );
      }
      final sScore = bestOf('siding')?.score ?? siding.score;
      if (roof != null &&
          (roofIsSoftWear || !roofIsHardDamage) &&
          roof.score <= sScore * 1.08) {
        demote(roof, minScoreKeepHigh: 0.88);
      }
      if (gutter != null && gutter.score <= sScore * 1.12) {
        demote(gutter, minScoreKeepHigh: 0.90);
      }
      // Wall crack frames often invent peel — demote soft paint under siding.
      if (paint != null &&
          paint.score <= sScore * 1.10 &&
          !paintTitle.contains('peel')) {
        demote(paint, minScoreKeepHigh: 0.88);
      } else if (paint != null &&
          paint.score < sScore &&
          paintTitle.contains('peel')) {
        // Even peel titles lose to cracked siding when wall cues dominate.
        demote(paint, minScoreKeepHigh: 0.86);
      }
    } else if (!roofStrong &&
        !paintPrimary &&
        siding != null &&
        (siding.issue.severity == 'High' || siding.score >= 0.58) &&
        roof != null &&
        roof.score < siding.score * 0.90) {
      if (!roofIsHardDamage) {
        demote(roof, minScoreKeepHigh: 0.84);
      }
    }

    // Foundation primary: demote weak secondary Highs, but keep hard roof
    // damage (labeled shingle failure) which co-occurs with grade notes.
    if (foundation != null &&
        (foundation.issue.severity == 'High' || foundation.score >= 0.55)) {
      for (final c in List<_ScoredIssue>.from(candidates)) {
        if (c.category == 'foundation') continue;
        if (c.issue.severity != 'High') continue;
        final t = c.issue.title.toLowerCase();
        if (c.category == 'roof' &&
            (t.contains('missing') ||
                t.contains('damaged shingle') ||
                t.contains('impact') ||
                c.score >= 0.70)) {
          continue;
        }
        demote(c, minScoreKeepHigh: 0.99);
      }
    }

    // Cap: if 2+ Highs without a clear multi-system compound, demote extras.
    var highs = candidates.where((c) => c.issue.severity == 'High').toList()
      ..sort((a, b) => a.score.compareTo(b.score));
    var guard = 0;
    while (highs.length > 1 && guard++ < 8) {
      // Allow 2 Highs only for roof+foundation or roof+siding both strong.
      if (highs.length == 2) {
        final cats = highs.map((h) => h.category).toSet();
        final compound =
            (cats.contains('roof') && cats.contains('foundation')) ||
            (cats.contains('roof') &&
                cats.contains('siding') &&
                highs.every((h) => h.score >= 0.70));
        if (compound) break;
      }
      demote(highs.first, minScoreKeepHigh: 0.99);
      highs = candidates.where((c) => c.issue.severity == 'High').toList()
        ..sort((a, b) => a.score.compareTo(b.score));
    }
  }

  /// When related systems both fire, boost detection scores (accuracy lever).
  void _boostRelatedFindings(List<_ScoredIssue> candidates) {
    if (candidates.length < 2) return;

    bool has(String cat) => candidates.any((c) => c.category == cat);
    double scoreOf(String cat) => candidates
        .where((c) => c.category == cat)
        .map((c) => c.score)
        .fold<double>(0, max);

    // Roof + gutter/fascia often travel together after storms.
    if (has('roof') && (has('gutter') || has('fascia'))) {
      _nudgeCategory(candidates, 'roof', 0.06);
      _nudgeCategory(candidates, 'gutter', 0.05);
      _nudgeCategory(candidates, 'fascia', 0.04);
    }
    // Gutter overflow feeds foundation moisture risk.
    if (has('gutter') && has('foundation') && scoreOf('gutter') > 0.35) {
      _nudgeCategory(candidates, 'foundation', 0.07);
    }
    // Wall moisture + paint peel often co-occur on weathered elevations.
    if (has('siding') && has('paint')) {
      _nudgeCategory(candidates, 'siding', 0.04);
      _nudgeCategory(candidates, 'paint', 0.04);
    }
    // Chimney issues strengthen roof leak narrative.
    if (has('chimney') && has('roof')) {
      _nudgeCategory(candidates, 'chimney', 0.05);
      _nudgeCategory(candidates, 'roof', 0.03);
    }
    // Vegetation against walls increases moisture/siding risk.
    if (has('vegetation') && (has('siding') || has('gutter'))) {
      _nudgeCategory(candidates, 'vegetation', 0.04);
      _nudgeCategory(candidates, 'siding', 0.03);
    }
  }

  void _nudgeCategory(List<_ScoredIssue> list, String category, double delta) {
    for (var i = 0; i < list.length; i++) {
      final c = list[i];
      if (c.category != category) continue;
      list[i] = _ScoredIssue(
        category: c.category,
        criticality: c.criticality,
        score: (c.score + delta).clamp(0.0, 1.0),
        issue: c.issue,
      );
    }
  }

  /// High severity must be earned; weak High claims demote to Medium.
  _ScoredIssue _calibrateSeverity(_ScoredIssue c, {required int photoCount}) {
    final issue = c.issue;
    var severity = issue.severity;
    var conf = issue.confidence;
    final titleLower = issue.title.toLowerCase();

    // Single-photo or modest-score High → Medium (real-phone over-call fix).
    if (severity == 'High' && (photoCount < 3 || c.score < 0.80 || conf < 90)) {
      severity = 'Medium';
      conf = max(conf - 8, 62);
    }

    // Foundation / missing-shingle / structural Highs need stronger multi-signal.
    if (severity == 'High' &&
        (titleLower.contains('foundation') ||
            titleLower.contains('missing') ||
            titleLower.contains('damaged shingle') ||
            titleLower.contains('settlement') ||
            titleLower.contains('structural')) &&
        (c.score < 0.84 || conf < 92 || photoCount < 3)) {
      severity = 'Medium';
      conf = max(conf - 8, 64);
    }

    // Soft confidence cap when evidence is only Medium/weak.
    if (severity == 'Medium' && conf > 88 && c.score < 0.68) {
      conf = 86;
    }

    // Medium with very strong multi-signal score can promote to High.
    // Do not promote aging/granule/wear/possible-impact language.
    // Promotion bar is deliberately high — prefer fewer Highs.
    final isAgingOrSoft =
        titleLower.contains('granule') ||
        titleLower.contains('aging') ||
        titleLower.contains('wear') ||
        titleLower.contains('possible impact') ||
        titleLower.contains('review') ||
        titleLower.contains('film') ||
        titleLower.contains('grade review');
    if (severity == 'Medium' &&
        !isAgingOrSoft &&
        c.score >= 0.96 &&
        conf >= 96 &&
        photoCount >= 4 &&
        c.criticality >= 0.99) {
      severity = 'High';
    }

    // Low with near-zero score should stay low; never claim near-certainty.
    if (severity == 'Low' && conf > 84) {
      conf = 82;
    }
    if (severity == 'Low' && c.score < 0.28 && conf > 80) {
      conf = 76;
    }

    if (severity == issue.severity && conf == issue.confidence) return c;

    return _ScoredIssue(
      category: c.category,
      criticality: c.criticality,
      score: c.score,
      issue: issue.copyWith(severity: severity, confidence: conf),
    );
  }

  // ---------------------------------------------------------------------------
  // Confidence, insights, scoring
  // ---------------------------------------------------------------------------

  /// Multi-factor confidence: presence × defect × evidence × agreement.
  int _confidence({
    required double presence,
    required double defect,
    required List<_Evidence> evidence,
    required int labelHits,
    required int photoVotes,
    required int photoCount,
    required bool visionMode,
    required double categoryWeight,
  }) {
    final p = presence.clamp(0.0, 1.0);
    final d = defect.clamp(0.0, 1.0);

    // Dual-gate: both presence and defect needed for high certainty.
    final dualGate = (p * 0.42 + d * 0.58).clamp(0.0, 1.0);
    final agreement = photoCount <= 1
        ? 0.55
        : (photoVotes / photoCount).clamp(0.0, 1.0);

    final strengths = evidence.map((e) => e.strength.clamp(0.0, 1.0)).toList();
    final evidenceStrength = strengths.isEmpty
        ? 0.22
        : (strengths.reduce(max) * 0.5 +
                  strengths.reduce((a, b) => a + b) / strengths.length * 0.35 +
                  min(1.0, strengths.length / 4) * 0.15)
              .clamp(0.0, 1.0);

    // Base 52–88 from dual-gate + evidence + multi-photo agreement.
    // Ceiling stays below "near certain" — this is a screening tool.
    var conf = 52.0 + dualGate * 22 + evidenceStrength * 13 + agreement * 7;

    // Independent photo votes are the strongest accuracy lever.
    if (photoVotes >= 2) conf += 3.0 + min(5.0, (photoVotes - 2) * 2.0);
    if (photoCount >= 3 && photoVotes >= 2) conf += 1.5;
    if (photoCount >= 4 && dualGate > 0.55) conf += 1.5;

    // Single-angle uncertainty — lighter when Cloud Vision backs the frame.
    if (photoCount == 1) {
      conf -= visionMode ? 2.0 : 4.0;
      if (d < 0.45) conf -= visionMode ? 1.5 : 3.0;
    }

    // Vision labels across photos (primary path when API key is present).
    conf += min(6.0, max(0, labelHits) * 1.5);
    if (visionMode) {
      if (labelHits > 0 || d > 0.48) conf += 3.0;
      if (labelHits >= 2 && d > 0.42) conf += 1.5;
      if (labelHits >= 1 && p > 0.45) conf += 1.0;
    } else {
      conf -= 2.0; // local-only is less certain
    }

    // Strong convergent evidence
    if (p > 0.55 && d > 0.55 && evidence.length >= 2) conf += 3.0;
    if (p > 0.62 && d > 0.62 && photoVotes >= 2) conf += 1.8;

    // Weak / conflicting signals
    if (p < 0.34 || (d < 0.28 && evidenceStrength < 0.38)) conf -= 10;
    if (evidence.length <= 1 && d < 0.42) conf -= 4.5;
    if (d > 0.7 && p < 0.3) conf -= 5; // defect without presence is suspect
    if (d < 0.35 && evidence.length <= 2) conf -= 2.5; // soft findings

    conf *= 0.88 + categoryWeight * 0.10;

    // Stable micro-jitter from signal (same photos → same score).
    conf += ((dualGate * 19 + evidenceStrength * 7).round() % 3) - 1;

    // Hard caps: never imply medical/inspection certainty.
    // Vision path may reach slightly higher when multi-photo + labels agree.
    final cap = visionMode
        ? (photoVotes >= 2 && d > 0.55
              ? 94
              : (labelHits > 0 && d > 0.5 ? 92 : 91))
        : (photoVotes >= 2 && d > 0.55 ? 92 : 88);
    return conf.round().clamp(52, cap);
  }

  /// Structured insight: what we found → why it matters → next step.
  /// Written for homeowner storytelling (not a raw evidence dump).
  String _reasonedInsight({
    required String finding,
    required List<_Evidence> evidence,
    required int confidence,
    required String action,
    String? whyItMatters,
  }) {
    final bits = evidence.where((e) => e.label.trim().isNotEmpty).toList()
      ..sort((a, b) => b.strength.compareTo(a.strength));

    final confBand = confidence >= 90
        ? 'strong screening'
        : confidence >= 80
        ? 'solid screening'
        : confidence >= 70
        ? 'moderate screening'
        : 'limited screening';

    final avgStrength = bits.isEmpty
        ? 0.0
        : bits.map((e) => e.strength).reduce((a, b) => a + b) / bits.length;

    final hasLabelCue = bits.any((e) {
      final l = e.label.toLowerCase();
      return l.contains('label') ||
          l.contains('vision') ||
          l.contains('materials labeled') ||
          l.contains('gutter/downspout labels');
    });

    final certainty = avgStrength >= 0.7
        ? (hasLabelCue
              ? 'Photo structure and AI scene labels align, so this is worth planning around after on-site confirmation.'
              : 'Several photo cues point the same way, so this is worth planning around after on-site confirmation.')
        : avgStrength >= 0.5
        ? 'Cues are consistent enough to flag for a closer look or contractor walkthrough.'
        : bits.isEmpty
        ? 'Signal is thin — treat this as a screening note, not a final diagnosis.'
        : 'Cues are present but not definitive; a closer photo would tighten the screening call.';

    final what = finding.trim();
    final buf = StringBuffer(what);
    if (!what.endsWith('.')) buf.write('.');
    buf.write(' $certainty');

    if (bits.isNotEmpty) {
      final top = bits.take(3).map((e) => e.label).join(', ');
      buf.write(' Main signals: $top.');
    }

    if (whyItMatters != null && whyItMatters.trim().isNotEmpty) {
      var why = whyItMatters.trim();
      if (!why.endsWith('.')) why = '$why.';
      buf.write(' Impact if delayed: $why');
    }

    buf.write(' Confidence: $confBand ($confidence%).');
    final act = action.trim();
    buf.write(' Recommended next step: $act');
    if (!act.endsWith('.')) buf.write('.');

    return buf.toString();
  }

  double _maxN(List<double> values) {
    if (values.isEmpty) return 0;
    return values.map((v) => v.clamp(0.0, 1.5)).reduce(max).clamp(0.0, 1.0);
  }

  /// Overall score: severity × confidence × system criticality, with
  /// diminishing multi-issue penalties, compound risk, and residual distress.
  AnalysisReport _buildReport({
    required List<AnalysisIssue> issues,
    required int photoCount,
    required _ImageFeatures features,
    required String source,
  }) {
    final limitedVisibility = _featuresSuggestLimitedVisibility(
      features,
      photoCount: photoCount,
    );

    final darkCapture = _isDarkCapture(features);
    // Healthy baseline — multi-angle coverage adds a small quality credit.
    // Dark single frames start lower; low-detail daylit frames get a milder cut.
    var score = darkCapture
        ? 84.0 + min(2.0, (photoCount - 1) * 0.4)
        : limitedVisibility
        ? 90.0 + min(2.0, (photoCount - 1) * 0.4)
        : 95.5 + min(2.5, (photoCount - 1) * 0.45);

    // Sort highest impact first so diminishing returns apply in order.
    final ranked = [...issues]
      ..sort((a, b) {
        final s = _severityRank(b.severity) - _severityRank(a.severity);
        if (s != 0) return s;
        return b.confidence.compareTo(a.confidence);
      });

    var highCount = 0;
    var mediumCount = 0;
    var lowCount = 0;

    double systemWeightFor(AnalysisIssue issue) {
      final title = issue.title.toLowerCase();
      // Hard damage titles (even Medium) must pull the overall score down.
      if (title.contains('missing') || title.contains('damaged shingle')) {
        return 1.48;
      }
      if (title.contains('roof') || title.contains('shingle')) return 1.22;
      if (title.contains('foundation') || title.contains('settlement')) {
        return 1.28;
      }
      if (title.contains('siding') ||
          title.contains('cladding') ||
          title.contains('crack') ||
          title.contains('mismatched') ||
          title.contains('patched')) {
        return 1.12;
      }
      if (title.contains('wiring') || title.contains('cable')) return 0.94;
      if (title.contains('gutter') || title.contains('fascia')) return 1.02;
      if (title.contains('chimney') || title.contains('flash')) return 1.08;
      if (title.contains('window') || title.contains('seal')) return 0.96;
      if (title.contains('paint') || title.contains('film')) {
        return issue.severity == 'Low' ? 0.70 : 0.88;
      }
      if (title.contains('vegetation') || title.contains('landscape')) {
        return 0.60;
      }
      if (title.contains('rust') || title.contains('corrosion')) return 0.76;
      if (title.contains('general') || title.contains('surface distress')) {
        return 0.68;
      }
      return 1.0;
    }

    for (final issue in ranked) {
      final confFactor = (issue.confidence / 100).clamp(0.48, 1.0);

      // Base impact by severity (higher confidence → fuller deduction).
      final baseImpact = switch (issue.severity) {
        'High' => 12.5 + confFactor * 6.5,
        'Medium' => 5.6 + confFactor * 3.2,
        _ => 1.4 + confFactor * 1.5,
      };

      final systemWeight = systemWeightFor(issue);

      // Diminishing returns: 2nd/3rd issue of same severity hits less hard.
      final sameSev = switch (issue.severity) {
        'High' => highCount++,
        'Medium' => mediumCount++,
        _ => lowCount++,
      };
      final diminish = switch (sameSev) {
        0 => 1.0,
        1 => 0.76,
        2 => 0.60,
        _ => 0.48,
      };

      // Soften single-photo High claims (uncertainty already in confidence).
      final singlePhotoSoft = photoCount == 1 && issue.severity == 'High'
          ? 0.88
          : 1.0;

      score -= baseImpact * systemWeight * diminish * singlePhotoSoft;
    }

    // Compound risk: related system failures stack worse than isolated ones.
    final titles = ranked.map((i) => i.title.toLowerCase()).toList();
    bool anyOf(List<String> keys) => titles.any((t) => keys.any(t.contains));
    final compoundPairs = <double>[
      if (anyOf(['roof', 'shingle']) && anyOf(['gutter', 'fascia'])) 2.2,
      if (anyOf(['gutter', 'overflow']) &&
          anyOf(['foundation', 'settlement', 'grade']))
        2.6,
      if (anyOf(['siding', 'cladding', 'moisture']) && anyOf(['paint', 'peel']))
        1.4,
      if (anyOf(['chimney', 'flash']) && anyOf(['roof', 'shingle'])) 1.8,
      if (anyOf(['vegetation']) && anyOf(['siding', 'gutter', 'roof'])) 1.1,
    ];
    if (compoundPairs.isNotEmpty) {
      score -= compoundPairs.reduce((a, b) => a + b).clamp(0.0, 7.0);
    }

    // Residual distress only when not already explained by solid findings.
    final explained = ranked
        .where((i) => i.severity != 'Low' && i.confidence >= 72)
        .length;
    final residual = (features.overallDistress - 0.24 - explained * 0.07).clamp(
      0.0,
      0.48,
    );
    if (residual > 0) {
      score -= residual * (explained >= 2 ? 4.0 : 8.0);
    }

    // Avg confidence slightly shapes score (uncertain findings hurt less already).
    final avgConf = issues.isEmpty
        ? 80.0
        : issues.map((i) => i.confidence).reduce((a, b) => a + b) /
              issues.length;
    if (avgConf >= 86 && highCount == 0) score += 0.8;
    if (avgConf < 68 && mediumCount + highCount >= 2) score += 1.2;

    // Multi-angle with no High → coverage quality credit (not for hard damage).
    final hardDamageMedium = ranked.any((i) {
      if (i.severity != 'Medium') return false;
      final t = i.title.toLowerCase();
      return t.contains('missing') ||
          t.contains('damaged shingle') ||
          t.contains('settlement') ||
          (t.contains('foundation') && t.contains('crack'));
    });
    if (photoCount >= 4 && highCount == 0 && !hardDamageMedium) score += 2.2;
    if (photoCount >= 3 &&
        highCount == 0 &&
        mediumCount <= 1 &&
        !hardDamageMedium) {
      score += 1.2;
    }

    // Very clean photo sets stay in the upper band (not when visibility is poor).
    final onlyLow =
        issues.isNotEmpty &&
        issues.every((i) => i.severity == 'Low') &&
        features.overallDistress < 0.36;
    if (onlyLow && !limitedVisibility) score = max(score, 87.5);

    // Floor/ceiling by worst severity for interpretability.
    if (highCount >= 2) {
      score = min(score, 60);
    } else if (highCount == 1) {
      score = min(score, 76);
    } else if (hardDamageMedium) {
      // Missing shingles / settlement Medium must not score like a healthy home.
      score = min(score, 86);
    } else if (mediumCount >= 3) {
      score = min(score, 79);
    }

    if (!limitedVisibility &&
        (issues.isEmpty ||
            (onlyLow &&
                features.overallDistress < 0.28 &&
                photoCount >= 2))) {
      score = max(score, 91);
    }

    // Dark / low-detail single frames: demote overall vs healthy multi-angle.
    if (limitedVisibility) {
      if (darkCapture) {
        score = min(score, 86.0);
        if (issues.isEmpty ||
            issues.every(
              (i) =>
                  i.needsCloserPhoto ||
                  i.confidence < 72 ||
                  i.title.toLowerCase().contains('limited visibility'),
            )) {
          score = min(score, 82.0);
        }
        if (features.brightness < 70 || features.darkPatchRatio > 0.55) {
          score = min(score, 80.0);
        }
      } else {
        // Low-detail daylit: mild demotion + retake note, stay ≥ golden weak band.
        score = min(score, 90.0);
        if (issues.any(
          (i) => i.title.toLowerCase().contains('limited visibility'),
        )) {
          score = min(score, 88.0);
        }
      }
    }

    final overall = score.round().clamp(34, 98);

    final high = highCount;
    final medium = mediumCount;

    // Rank findings so the report story leads with highest priority.
    final orderedIssues = [...issues]
      ..sort((a, b) {
        final s = b.severityRank - a.severityRank;
        if (s != 0) return s;
        return b.confidence.compareTo(a.confidence);
      });

    // Labels frame results as photo screening — never as a certified inspection.
    // Prefer naming the lead system when findings exist (less generic).
    final topTitle = orderedIssues.isEmpty
        ? ''
        : orderedIssues.first.storyTitle;
    final String label;
    if (limitedVisibility &&
        (orderedIssues.isEmpty ||
            orderedIssues.every(
              (i) =>
                  i.needsCloserPhoto ||
                  i.title.toLowerCase().contains('limited visibility'),
            ))) {
      label =
          'Limited visibility — retake in better light for a confident screening';
    } else if (orderedIssues.isEmpty) {
      label = photoCount == 1
          ? 'Good — No elevated defects from this single angle (screening)'
          : 'Excellent — Photos suggest a strong exterior (screening)';
    } else if (overall >= 93 && high == 0 && medium == 0) {
      label = 'Excellent — Photos suggest a strong exterior (screening)';
    } else if (overall >= 90 && high == 0 && medium <= 1) {
      label = medium == 1
          ? 'Good — Solid screening; note on $topTitle'
          : 'Good — Solid screening result with minor notes';
    } else if (overall >= 84 && high == 0) {
      label = medium >= 2
          ? 'Stable — Plan work on $topTitle and related items (screening)'
          : 'Good — Solid screening; plan around $topTitle';
    } else if (overall >= 72 && high == 0) {
      label = 'Stable — Schedule $topTitle this season (screening)';
    } else if (overall >= 58 || high == 1) {
      label = high > 0
          ? 'Attention needed — Prioritize $topTitle (screening)'
          : 'Attention needed — Closer review of $topTitle soon';
    } else {
      label = high >= 2 || (medium >= 3 && avgConf >= 78)
          ? 'Poor — Multiple high-priority items led by $topTitle'
          : 'Poor — Significant exterior work may be needed ($topTitle)';
    }

    return AnalysisReport(
      overallScore: overall,
      conditionLabel: label,
      issues: orderedIssues,
      estimatedRepairRange: _estimateRepairRange(orderedIssues),
      analysisSource: source,
      photoCount: photoCount,
    );
  }

  String _estimateRepairRange(List<AnalysisIssue> issues) {
    if (issues.isEmpty) return '\$0';
    var low = 0;
    var high = 0;
    var counted = 0;
    for (final issue in issues) {
      // Only sum confidence-worthy exterior planning ranges.
      if (issue.needsCloserPhoto || issue.confidence < 70) continue;
      final c = issue.cost.trim();
      if (c.isEmpty || c.toUpperCase() == 'TBD' || !c.contains('\$')) continue;
      final match = RegExp(r'\$([0-9,]+)\s*[–-]\s*\$([0-9,]+)').firstMatch(c);
      if (match != null) {
        low += int.parse(match.group(1)!.replaceAll(',', ''));
        high += int.parse(match.group(2)!.replaceAll(',', ''));
        counted++;
      }
    }
    if (counted == 0) {
      final anyListed = issues.any((i) => !i.needsCloserPhoto);
      return anyListed
          ? 'TBD — confirm scope on-site'
          : 'TBD — need clearer photos';
    }
    return '\$${_fmt(low)} – \$${_fmt(high)}';
  }

  String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  int _severityRank(String severity) {
    switch (severity) {
      case 'High':
        return 3;
      case 'Medium':
        return 2;
      default:
        return 1;
    }
  }
}

// =============================================================================
// Types
// =============================================================================

class _VisionLabel {
  final String description;
  final double score;
  const _VisionLabel({required this.description, required this.score});
}

/// One Vision API frame: labels + object localization boxes.
class _VisionFrameResult {
  final Map<String, double> labels;
  final List<_VisionObjectBox> objects;

  const _VisionFrameResult({required this.labels, required this.objects});

  const _VisionFrameResult.empty() : labels = const {}, objects = const [];
}

/// Normalized object box from Google Cloud Vision OBJECT_LOCALIZATION.
class _VisionObjectBox {
  final String name;
  final double score;
  final double left;
  final double top;
  final double width;
  final double height;
  final int imageIndex;
  final bool exactNameMatch;

  const _VisionObjectBox({
    required this.name,
    required this.score,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.imageIndex,
    this.exactNameMatch = false,
  });

  _VisionObjectBox withImageIndex(int index) => _VisionObjectBox(
    name: name,
    score: score,
    left: left,
    top: top,
    width: width,
    height: height,
    imageIndex: index,
    exactNameMatch: exactNameMatch,
  );
}

class _Evidence {
  final String label;
  final double strength;
  const _Evidence(this.label, this.strength);
}

class _ScoredIssue {
  final String category;
  final double criticality;
  final double score;
  final AnalysisIssue issue;

  const _ScoredIssue({
    required this.category,
    required this.criticality,
    required this.score,
    required this.issue,
  });
}

/// Per-photo category signals for voting / fusion.
class _CategorySignals {
  final double roofPresence;
  final double roofDefect;
  final double gutterPresence;
  final double gutterDefect;
  final double wallPresence;
  final double crackDefect;
  final double moistureDefect;
  final double peelDefect;
  final double foundationPresence;
  final double foundationDefect;
  final double windowPresence;
  final double vegetationNear;
  final double rustDominance;

  const _CategorySignals({
    required this.roofPresence,
    required this.roofDefect,
    required this.gutterPresence,
    required this.gutterDefect,
    required this.wallPresence,
    required this.crackDefect,
    required this.moistureDefect,
    required this.peelDefect,
    required this.foundationPresence,
    required this.foundationDefect,
    required this.windowPresence,
    required this.vegetationNear,
    required this.rustDominance,
  });

  factory _CategorySignals.fromFeatures(_ImageFeatures f) {
    final roofPresence = f.roofSignal;
    // Missing tabs / impact: chaos counts on classic roof planes OR full-frame
    // shingle fields (close-ups where dark-top bias is weak).
    final shingleCloseup =
        f.roofSignal > 0.42 &&
        f.horizontalBanding > 0.32 &&
        f.greyDominance > 0.22 &&
        f.vegetationNear < 0.24;
    // Scene landscaping chaos must not invent roof damage on clean elevations.
    final roofChaos =
        f.highTextureChaos &&
        (shingleCloseup ||
            (f.darkTopBias > 0.34 &&
                f.topEdgeDensity > 0.15 &&
                f.greyDominance > 0.20) ||
            (f.roofSignal > 0.52 &&
                f.darkPatchRatio > 0.14 &&
                f.topEdgeDensity > 0.14));
    final roofDefect =
        ((roofChaos ? 0.50 : 0.0) +
                (f.darkTopBias > 0.30
                    ? f.darkPatchRatio * 1.35
                    : f.darkPatchRatio * 0.22) +
                f.topEdgeDensity * 0.32 +
                (f.crackLineScore > 0.34 &&
                        (f.darkTopBias > 0.26 || shingleCloseup)
                    ? f.crackLineScore * 0.55
                    : 0.0) +
                (f.greyDominance > 0.30 &&
                        f.edgeDensity > 0.14 &&
                        f.roofSignal > 0.40
                    ? 0.20
                    : 0.0) +
                (f.darkTopBias > 0.40 && f.highLuminanceVariance > 0.50
                    ? 0.14
                    : 0.0) +
                // Tab peel / missing shingles on close-ups look like peel variance
                // on a grey granule field — count as roof defect not paint.
                (shingleCloseup && f.peelingScore > 0.38 ? 0.30 : 0.0) +
                (shingleCloseup && f.highTextureChaos ? 0.20 : 0.0))
            .clamp(0.0, 1.0);

    final gutterPresence =
        (f.gutterLineScore * 0.68 +
                f.horizontalBanding * 0.42 +
                f.topEdgeDensity * 0.12 +
                // Debris troughs: dark mid-band + moderate edge structure.
                (f.darkPatchRatio > 0.16 && f.horizontalBanding > 0.22
                    ? 0.22
                    : 0.0) +
                (f.moistureStainScore > 0.28 && f.edgeDensity > 0.12
                    ? 0.12
                    : 0.0))
            .clamp(0.0, 1.0);
    // Overflow risk: debris vegetation near eaves + dark staining at trough line.
    final gutterDefect =
        (gutterPresence > 0.20
                ? (f.vegetationNear * 0.50 +
                      f.darkPatchRatio * 0.48 +
                      f.moistureStainScore * 0.28 +
                      (f.gutterLineScore > 0.36 && f.darkPatchRatio > 0.12
                          ? 0.18
                          : 0) +
                      (f.rustDominance > 0.08 && f.darkPatchRatio > 0.14
                          ? 0.12
                          : 0) +
                      (f.highTextureChaos && f.horizontalBanding > 0.24
                          ? 0.14
                          : 0))
                : (f.darkPatchRatio > 0.22 && f.moistureStainScore > 0.25
                      ? 0.36
                      : 0.0))
            .clamp(0.0, 1.0);

    final wallPresence = f.wallSignal;
    // Hairline cracks need linear structure — high peel variance is paint, not crack.
    // Roof close-ups should not invent cladding cracks.
    final peelDominant = f.peelingScore > 0.42 && !shingleCloseup;
    // Clapboard / window edges inflate mid-wall density — require real crack lines.
    final crackDefect =
        (f.crackLineScore * 0.82 +
                (f.midEdgeDensity > 0.22 &&
                        f.contrast > 54 &&
                        f.crackLineScore > 0.36 &&
                        !peelDominant &&
                        !shingleCloseup
                    ? 0.22
                    : 0.0) +
                (f.edgeDensity > 0.24 &&
                        f.highLuminanceVariance > 0.55 &&
                        f.crackLineScore > 0.38 &&
                        !peelDominant &&
                        !shingleCloseup
                    ? 0.12
                    : 0.0) +
                (f.verticalBanding > 0.40 && f.crackLineScore > 0.40
                    ? 0.10
                    : 0.0) -
                (peelDominant ? 0.22 : 0.0) -
                (shingleCloseup ? 0.30 : 0.0))
            .clamp(0.0, 1.0);

    // Algae / mildew / water stains on walls — not pure lawn green.
    final moistureDefect =
        (f.moistureStainScore * 0.78 +
                (f.lowerThirdDark > 0.28 && f.greenDominance > 0.08
                    ? 0.28
                    : 0.0) +
                (f.greenDominance > 0.10 &&
                        f.greenDominance < 0.40 &&
                        f.wallLikely
                    ? f.greenDominance * 0.55
                    : 0.0) +
                (f.darkPatchRatio > 0.18 && f.wallLikely ? 0.12 : 0.0))
            .clamp(0.0, 1.0);

    // Peeling paint: need real peelingScore. Luminance variance alone (shadows,
    // windows, clapboard) must not invent film failure on healthy walls.
    final peelDefect =
        (f.peelingScore * 0.80 +
                (f.peelingScore > 0.42 &&
                        f.highLuminanceVariance > 0.58 &&
                        f.contrast > 48
                    ? 0.18
                    : 0.0) +
                (f.wallLikely && !shingleCloseup && f.peelingScore > 0.36
                    ? 0.08
                    : 0.0) +
                (f.midToneDominance > 0.35 && f.peelingScore > 0.40
                    ? 0.08
                    : 0.0) -
                (shingleCloseup ? 0.35 : 0.0) -
                (f.roofSignal > 0.50 && f.greyDominance > 0.24 ? 0.20 : 0.0))
            .clamp(0.0, 1.0);

    final foundationPresence = f.foundationSignal;
    // Defect needs clear linear crack + base context. Dark grade alone is
    // presence only — never a crack/settlement claim on healthy elevations.
    final foundationDefect =
        ((f.crackLineScore > 0.52 &&
                        (f.foundationLikely || f.foundationSignal > 0.50) &&
                        f.lowerThirdDark > 0.42
                    ? f.crackLineScore * 0.82
                    : 0.0) +
                (f.crackLineScore > 0.50 &&
                        f.botEdgeDensity > 0.17 &&
                        f.foundationSignal > 0.48
                    ? f.botEdgeDensity * 0.58
                    : 0.0) +
                // Close-up settlement cracks / honeycomb on concrete only.
                (f.greyDominance > 0.36 &&
                        f.crackLineScore > 0.52 &&
                        f.foundationSignal > 0.48 &&
                        f.lowerThirdDark > 0.40
                    ? 0.28
                    : 0.0) +
                (f.highTextureChaos &&
                        f.greyDominance > 0.38 &&
                        f.foundationSignal > 0.50 &&
                        f.crackLineScore > 0.50 &&
                        f.lowerThirdDark > 0.44
                    ? 0.12
                    : 0.0))
            .clamp(0.0, 1.0);

    final windowPresence =
        ((f.midEdgeDensity > 0.13 && f.contrast > 38 ? 0.42 : 0.0) +
                (f.edgeDensity > 0.12 && f.wallLikely ? 0.28 : 0.0) +
                f.verticalBanding * 0.22 +
                (f.highLuminanceVariance > 0.4 && f.midEdgeDensity > 0.12
                    ? 0.1
                    : 0.0))
            .clamp(0.0, 1.0);

    return _CategorySignals(
      roofPresence: roofPresence,
      roofDefect: roofDefect,
      gutterPresence: gutterPresence,
      gutterDefect: gutterDefect,
      wallPresence: wallPresence,
      crackDefect: crackDefect,
      moistureDefect: moistureDefect,
      peelDefect: peelDefect,
      foundationPresence: foundationPresence,
      foundationDefect: foundationDefect,
      windowPresence: windowPresence,
      vegetationNear: f.vegetationNear,
      rustDominance: f.rustDominance,
    );
  }

  /// Fuse per-photo signals: average presence, max defect, reward agreement.
  factory _CategorySignals.fuse(
    List<_CategorySignals> list,
    _ImageFeatures agg,
  ) {
    if (list.isEmpty) {
      return _CategorySignals.fromFeatures(agg);
    }
    if (list.length == 1) return list.first;

    double avg(double Function(_CategorySignals s) sel) =>
        list.map(sel).reduce((a, b) => a + b) / list.length;
    double mx(double Function(_CategorySignals s) sel) =>
        list.map(sel).reduce(max);

    // If ≥2 photos show defect, boost fused defect.
    double voteBoost(double Function(_CategorySignals s) sel, double thr) {
      final votes = list.where((s) => sel(s) > thr).length;
      final base = mx(sel);
      if (votes >= 2) return (base + 0.08 * (votes - 1)).clamp(0.0, 1.0);
      return base;
    }

    // Presence: max of avg and strongest frame so one clear close-up is not
    // diluted by unrelated elevations in the same capture set.
    double presence(double Function(_CategorySignals s) sel) {
      final a = avg(sel);
      final m = mx(sel);
      return max(a, m * 0.92);
    }

    return _CategorySignals(
      roofPresence: presence((s) => s.roofPresence),
      roofDefect: voteBoost((s) => s.roofDefect, 0.30),
      gutterPresence: presence((s) => s.gutterPresence),
      gutterDefect: voteBoost((s) => s.gutterDefect, 0.28),
      wallPresence: avg((s) => s.wallPresence),
      crackDefect: voteBoost((s) => s.crackDefect, 0.34),
      moistureDefect: voteBoost((s) => s.moistureDefect, 0.34),
      peelDefect: voteBoost((s) => s.peelDefect, 0.34),
      foundationPresence: presence((s) => s.foundationPresence),
      foundationDefect: voteBoost((s) => s.foundationDefect, 0.30),
      windowPresence: mx((s) => s.windowPresence),
      vegetationNear: mx((s) => s.vegetationNear),
      rustDominance: mx((s) => s.rustDominance),
    );
  }
}

/// Real pixel features from a downscaled decode of each photo.
class _ImageFeatures {
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
  final bool roofLikely;
  final bool wallLikely;
  final bool foundationLikely;
  final bool highTextureChaos;
  final int hashSeed;

  const _ImageFeatures({
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
    required this.roofLikely,
    required this.wallLikely,
    required this.foundationLikely,
    required this.highTextureChaos,
    required this.hashSeed,
  });

  static Future<_ImageFeatures> fromBytes(Uint8List bytes) async {
    if (bytes.isEmpty) return _ImageFeatures.empty(0);

    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 160,
        targetHeight: 160,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final w = image.width;
      final h = image.height;
      final bd = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();

      if (bd == null || w < 4 || h < 4) {
        return _ImageFeatures.fromCompressedProxy(bytes);
      }
      return _ImageFeatures.fromRgba(
        bd.buffer.asUint8List(),
        w,
        h,
        bytes.length,
      );
    } catch (_) {
      return _ImageFeatures.fromCompressedProxy(bytes);
    }
  }

  factory _ImageFeatures.empty(int seed) {
    return _ImageFeatures(
      brightness: 128,
      contrast: 0,
      edgeDensity: 0,
      topEdgeDensity: 0,
      midEdgeDensity: 0,
      botEdgeDensity: 0,
      horizontalBanding: 0,
      verticalBanding: 0,
      greenDominance: 0,
      greyDominance: 0,
      rustDominance: 0,
      darkPatchRatio: 0,
      darkTopBias: 0,
      lowerThirdDark: 0,
      midToneDominance: 0.5,
      highLuminanceVariance: 0,
      vegetationNear: 0,
      roofSignal: 0.2,
      wallSignal: 0.2,
      foundationSignal: 0.2,
      overallDistress: 0.15,
      crackLineScore: 0,
      peelingScore: 0,
      moistureStainScore: 0,
      gutterLineScore: 0,
      roofLikely: false,
      wallLikely: false,
      foundationLikely: false,
      highTextureChaos: false,
      hashSeed: seed,
    );
  }

  /// Inject golden-set / calibration profiles without decoding image bytes.
  factory _ImageFeatures.fromSnapshot(ExteriorFeatureSnapshot s) {
    return _ImageFeatures(
      brightness: s.brightness,
      contrast: s.contrast,
      edgeDensity: s.edgeDensity,
      topEdgeDensity: s.topEdgeDensity,
      midEdgeDensity: s.midEdgeDensity,
      botEdgeDensity: s.botEdgeDensity,
      horizontalBanding: s.horizontalBanding,
      verticalBanding: s.verticalBanding,
      greenDominance: s.greenDominance,
      greyDominance: s.greyDominance,
      rustDominance: s.rustDominance,
      darkPatchRatio: s.darkPatchRatio,
      darkTopBias: s.darkTopBias,
      lowerThirdDark: s.lowerThirdDark,
      midToneDominance: s.midToneDominance,
      highLuminanceVariance: s.highLuminanceVariance,
      vegetationNear: s.vegetationNear,
      roofSignal: s.roofSignal,
      wallSignal: s.wallSignal,
      foundationSignal: s.foundationSignal,
      overallDistress: s.overallDistress,
      crackLineScore: s.crackLineScore,
      peelingScore: s.peelingScore,
      moistureStainScore: s.moistureStainScore,
      gutterLineScore: s.gutterLineScore,
      roofLikely: s.roofLikely,
      wallLikely: s.wallLikely,
      foundationLikely: s.foundationLikely,
      highTextureChaos: s.highTextureChaos,
      hashSeed: s.hashSeed,
    );
  }

  factory _ImageFeatures.fromCompressedProxy(Uint8List bytes) {
    const samples = 360;
    final step = max(1, bytes.length ~/ samples);
    var sum = 0.0;
    var sumSq = 0.0;
    var count = 0;
    var seed = bytes.length;

    for (var i = 0; i < bytes.length; i += step) {
      final v = bytes[i].toDouble();
      sum += v;
      sumSq += v * v;
      count++;
      seed = 0x1fffffff & (seed * 31 + bytes[i]);
    }

    final mean = count == 0 ? 128.0 : sum / count;
    final variance = count == 0 ? 0.0 : ((sumSq / count) - (mean * mean)).abs();
    final contrast = sqrt(variance).clamp(0.0, 80.0);
    final edge = (contrast / 100).clamp(0.0, 0.4);

    return _ImageFeatures(
      brightness: mean,
      contrast: contrast,
      edgeDensity: edge,
      topEdgeDensity: edge * 0.9,
      midEdgeDensity: edge,
      botEdgeDensity: edge * 0.85,
      horizontalBanding: (contrast / 200).clamp(0.0, 0.35),
      verticalBanding: (contrast / 220).clamp(0.0, 0.3),
      greenDominance: 0.08,
      greyDominance: mean > 90 && mean < 160 ? 0.25 : 0.1,
      rustDominance: 0.05,
      darkPatchRatio: mean < 100 ? 0.2 : 0.08,
      darkTopBias: mean < 110 ? 0.3 : 0.1,
      lowerThirdDark: mean < 105 ? 0.4 : 0.15,
      midToneDominance: 0.4,
      highLuminanceVariance: variance > 1800 ? 1.0 : 0.0,
      vegetationNear: 0.1,
      roofSignal: mean < 120 ? 0.45 : 0.25,
      wallSignal: mean > 95 ? 0.4 : 0.25,
      foundationSignal: 0.3,
      overallDistress: (contrast / 100).clamp(0.1, 0.55),
      crackLineScore: edge > 0.2 ? 0.22 : 0.08,
      peelingScore: variance > 2000 ? 0.32 : 0.1,
      moistureStainScore: mean < 100 ? 0.22 : 0.08,
      gutterLineScore: (contrast / 250).clamp(0.0, 0.28),
      roofLikely: mean < 115,
      wallLikely: mean > 90,
      foundationLikely: true,
      highTextureChaos: variance > 2200,
      hashSeed: seed,
    );
  }

  factory _ImageFeatures.fromRgba(Uint8List rgba, int w, int h, int byteLen) {
    final n = w * h;
    final lum = Float64List(n);
    final isGreen = Uint8List(n);

    var sumL = 0.0;
    var sumL2 = 0.0;
    var greenish = 0;
    var greyish = 0;
    var rustish = 0;
    var dark = 0;
    var mid = 0;
    var seed = byteLen ^ w ^ h;

    for (var i = 0; i < n; i++) {
      final o = i * 4;
      final r = rgba[o].toDouble();
      final g = rgba[o + 1].toDouble();
      final b = rgba[o + 2].toDouble();
      final y = 0.299 * r + 0.587 * g + 0.114 * b;
      lum[i] = y;
      sumL += y;
      sumL2 += y * y;
      seed = 0x1fffffff & (seed * 33 + rgba[o] + rgba[o + 1] * 3);

      final maxC = max(r, max(g, b));
      final minC = min(r, min(g, b));
      final sat = maxC - minC;

      if (g > r + 12 && g > b + 8 && g > 50) {
        greenish++;
        isGreen[i] = 1;
      }
      if (sat < 28 && y > 40 && y < 200) greyish++;
      if (r > g + 15 && r > b + 20 && r > 70 && g > 30 && g < 160) rustish++;
      if (y < 55) dark++;
      if (y >= 70 && y <= 180) mid++;
    }

    final mean = sumL / n;
    final variance = max(0.0, (sumL2 / n) - (mean * mean));
    final contrast = sqrt(variance);

    var edgeSum = 0.0;
    var edgeCount = 0;
    var horizEnergy = 0.0;
    var vertEnergy = 0.0;
    var topEdge = 0.0, midEdge = 0.0, botEdge = 0.0;
    var topN = 0, midN = 0, botN = 0;
    var strongHorizRuns = 0;
    var strongVertRuns = 0;
    var strongEdge = 0;

    final yTop = h ~/ 3;
    final yBot = (h * 2) ~/ 3;

    for (var y = 0; y < h - 1; y++) {
      for (var x = 0; x < w - 1; x++) {
        final i = y * w + x;
        final dx = (lum[i + 1] - lum[i]).abs();
        final dy = (lum[i + w] - lum[i]).abs();
        final mag = dx + dy;
        edgeSum += mag;
        edgeCount++;
        horizEnergy += dx;
        vertEnergy += dy;

        if (mag > 28) {
          strongEdge++;
          if (dx > dy * 1.35 && dx > 18) strongHorizRuns++;
          if (dy > dx * 1.35 && dy > 18) strongVertRuns++;
        }

        if (y < yTop) {
          topEdge += mag;
          topN++;
        } else if (y >= yBot) {
          botEdge += mag;
          botN++;
        } else {
          midEdge += mag;
          midN++;
        }
      }
    }

    final edgeDensity = edgeCount == 0
        ? 0.0
        : (edgeSum / edgeCount / 80).clamp(0.0, 1.0);
    final topEdgeDensity = topN == 0
        ? 0.0
        : (topEdge / topN / 80).clamp(0.0, 1.0);
    final midEdgeDensity = midN == 0
        ? 0.0
        : (midEdge / midN / 80).clamp(0.0, 1.0);
    final botEdgeDensity = botN == 0
        ? 0.0
        : (botEdge / botN / 80).clamp(0.0, 1.0);

    final totalEnergy = horizEnergy + vertEnergy + 1e-6;
    final horizontalBanding = (horizEnergy / totalEnergy * edgeDensity * 1.45)
        .clamp(0.0, 1.0);
    final verticalBanding = (vertEnergy / totalEnergy * edgeDensity * 1.45)
        .clamp(0.0, 1.0);

    final crackLineScore =
        ((strongHorizRuns + strongVertRuns) /
                    (strongEdge + 1) *
                    edgeDensity *
                    2.2 +
                (max(strongHorizRuns, strongVertRuns) / (edgeCount + 1) * 40)
                    .clamp(0.0, 0.5))
            .clamp(0.0, 1.0);

    var upperMidHoriz = 0.0;
    var upperMidN = 0;
    final yG0 = max(1, h ~/ 5);
    final yG1 = min(h - 2, (h * 3) ~/ 5);
    for (var y = yG0; y < yG1; y++) {
      for (var x = 0; x < w - 1; x++) {
        final i = y * w + x;
        upperMidHoriz += (lum[i + 1] - lum[i]).abs();
        upperMidN++;
      }
    }
    final gutterLineScore =
        ((upperMidN == 0 ? 0.0 : upperMidHoriz / upperMidN / 40) * 0.7 +
                horizontalBanding * 0.45 +
                topEdgeDensity * 0.2)
            .clamp(0.0, 1.0);

    var topSum = 0.0, botSum = 0.0;
    var topCnt = 0, botCnt = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final v = lum[y * w + x];
        if (y < yTop) {
          topSum += v;
          topCnt++;
        } else if (y >= yBot) {
          botSum += v;
          botCnt++;
        }
      }
    }
    final topMean = topCnt == 0 ? mean : topSum / topCnt;
    final botMean = botCnt == 0 ? mean : botSum / botCnt;
    final darkTopBias = ((mean - topMean) / 80 + (topMean < 100 ? 0.25 : 0))
        .clamp(0.0, 1.0);
    final lowerThirdDark = ((mean - botMean) / 70 + (botMean < 95 ? 0.3 : 0))
        .clamp(0.0, 1.0);

    var chaotic = 0, peelPatches = 0, moisturePatches = 0, patchCount = 0;
    const patch = 10;
    for (var py = 0; py < h - patch; py += patch) {
      for (var px = 0; px < w - patch; px += patch) {
        var pSum = 0.0, pSum2 = 0.0, pN = 0, pGreen = 0, pDark = 0;
        for (var y = py; y < py + patch; y++) {
          for (var x = px; x < px + patch; x++) {
            final i = y * w + x;
            final v = lum[i];
            pSum += v;
            pSum2 += v * v;
            pN++;
            if (isGreen[i] == 1) pGreen++;
            if (v < 60) pDark++;
          }
        }
        final pMean = pSum / pN;
        final pVar = (pSum2 / pN) - (pMean * pMean);
        if (pVar > 900) chaotic++;
        if (pVar > 1600 && pMean > 60 && pMean < 200) peelPatches++;
        if ((pGreen / pN > 0.35 || pDark / pN > 0.4) && pVar > 400) {
          moisturePatches++;
        }
        patchCount++;
      }
    }
    final chaosRatio = patchCount == 0 ? 0.0 : chaotic / patchCount;
    final peelingScore = patchCount == 0
        ? 0.0
        : ((peelPatches / patchCount) * 1.8 +
                  (variance > 1400 ? 0.25 : 0) +
                  (contrast > 50 ? 0.15 : 0))
              .clamp(0.0, 1.0);
    final moistureStainScore = patchCount == 0
        ? 0.0
        : ((moisturePatches / patchCount) * 1.6 +
                  (greenish / n) * 0.55 +
                  (lowerThirdDark > 0.3 ? 0.15 : 0))
              .clamp(0.0, 1.0);

    final greenDominance = greenish / n;
    final greyDominance = greyish / n;
    final rustDominance = rustish / n;
    final darkPatchRatio = dark / n;
    final midToneDominance = mid / n;
    final highLuminanceVariance = variance > 1400 ? 1.0 : variance / 1400;

    final vegetationNear =
        (greenDominance * 1.45 +
                (greenDominance > 0.12 ? edgeDensity * 0.3 : 0))
            .clamp(0.0, 1.0);

    // Full-frame asphalt fields (close-ups) lack dark-top bias; use course
    // banding + grey granule tones + texture chaos as roof-plane evidence.
    final shingleFieldCue =
        ((horizontalBanding > 0.28 && greyDominance > 0.18 ? 0.34 : 0.0) +
                (horizontalBanding > 0.34 && chaosRatio > 0.18 ? 0.22 : 0.0) +
                (greyDominance > 0.22 &&
                        highLuminanceVariance > 0.45 &&
                        midToneDominance > 0.30
                    ? 0.18
                    : 0.0) +
                (edgeDensity > 0.16 &&
                        horizontalBanding > verticalBanding * 1.05 &&
                        greyDominance > 0.16
                    ? 0.14
                    : 0.0))
            .clamp(0.0, 0.72);

    final roofSignal =
        (darkTopBias * 0.34 +
                greyDominance * 0.24 +
                topEdgeDensity * 0.18 +
                (topMean < 110 ? 0.14 : 0) +
                (greyDominance > 0.24 && darkTopBias > 0.18 ? 0.10 : 0) +
                (topEdgeDensity > 0.14 && horizontalBanding > 0.2 ? 0.08 : 0) +
                shingleFieldCue * 0.55)
            .clamp(0.0, 1.0);

    final wallSignal =
        (midToneDominance * 0.28 +
                verticalBanding * 0.28 +
                midEdgeDensity * 0.15 +
                (mean > 85 && mean < 190 ? 0.14 : 0.05) +
                (1 - darkTopBias) * 0.10 +
                (verticalBanding > 0.28 && midToneDominance > 0.3 ? 0.08 : 0) -
                // Full-frame shingle texture is not cladding.
                (shingleFieldCue > 0.35 ? 0.18 : 0.0))
            .clamp(0.0, 1.0);

    // Full-frame concrete crack close-ups: grey + lower dark + linear edges.
    // Require clearer line structure so soil shadow does not mint "presence".
    final foundationCloseupCue =
        ((greyDominance > 0.32 && crackLineScore > 0.42 ? 0.26 : 0.0) +
                (lowerThirdDark > 0.40 && crackLineScore > 0.40 ? 0.20 : 0.0) +
                (botEdgeDensity > 0.18 &&
                        greyDominance > 0.30 &&
                        crackLineScore > 0.34
                    ? 0.12
                    : 0.0) +
                (mean > 90 &&
                        mean < 170 &&
                        greyDominance > 0.34 &&
                        edgeDensity > 0.16 &&
                        crackLineScore > 0.36
                    ? 0.10
                    : 0.0))
            .clamp(0.0, 0.58);

    final foundationSignal =
        (lowerThirdDark * 0.28 +
                greyDominance * 0.16 +
                botEdgeDensity * 0.16 +
                (botMean < 100 ? 0.10 : 0.04) +
                darkPatchRatio * 0.08 +
                (botEdgeDensity > 0.16 && lowerThirdDark > 0.36 ? 0.06 : 0) +
                foundationCloseupCue * 0.55)
            .clamp(0.0, 1.0);

    // Composite distress: texture chaos + edges + moisture + peel + cracks.
    final overallDistress =
        (edgeDensity * 0.22 +
                chaosRatio * 0.24 +
                darkPatchRatio * 0.12 +
                highLuminanceVariance * 0.10 +
                crackLineScore * 0.16 +
                peelingScore * 0.10 +
                moistureStainScore * 0.06)
            .clamp(0.0, 1.0);

    return _ImageFeatures(
      brightness: mean,
      contrast: contrast,
      edgeDensity: edgeDensity,
      topEdgeDensity: topEdgeDensity,
      midEdgeDensity: midEdgeDensity,
      botEdgeDensity: botEdgeDensity,
      horizontalBanding: horizontalBanding,
      verticalBanding: verticalBanding,
      greenDominance: greenDominance,
      greyDominance: greyDominance,
      rustDominance: rustDominance,
      darkPatchRatio: darkPatchRatio,
      darkTopBias: darkTopBias,
      lowerThirdDark: lowerThirdDark,
      midToneDominance: midToneDominance,
      highLuminanceVariance: highLuminanceVariance,
      vegetationNear: vegetationNear,
      roofSignal: roofSignal,
      wallSignal: wallSignal,
      foundationSignal: foundationSignal,
      overallDistress: overallDistress,
      crackLineScore: crackLineScore,
      peelingScore: peelingScore,
      moistureStainScore: moistureStainScore,
      gutterLineScore: gutterLineScore,
      roofLikely: roofSignal > 0.34,
      wallLikely: wallSignal > 0.34,
      foundationLikely: foundationSignal > 0.40,
      highTextureChaos:
          chaosRatio > 0.26 || (edgeDensity > 0.22 && contrast > 55),
      hashSeed: seed,
    );
  }

  static _ImageFeatures aggregate(List<_ImageFeatures> list) {
    if (list.isEmpty) return _ImageFeatures.empty(0);
    if (list.length == 1) return list.first;

    double avg(double Function(_ImageFeatures f) sel) =>
        list.map(sel).reduce((a, b) => a + b) / list.length;
    double mx(double Function(_ImageFeatures f) sel) =>
        list.map(sel).reduce(max);

    final roofSignal = avg((f) => f.roofSignal);
    final wallSignal = avg((f) => f.wallSignal);
    final foundationSignal = avg((f) => f.foundationSignal);

    return _ImageFeatures(
      brightness: avg((f) => f.brightness),
      contrast: avg((f) => f.contrast),
      edgeDensity: avg((f) => f.edgeDensity),
      topEdgeDensity: mx((f) => f.topEdgeDensity),
      midEdgeDensity: avg((f) => f.midEdgeDensity),
      botEdgeDensity: mx((f) => f.botEdgeDensity),
      horizontalBanding: mx((f) => f.horizontalBanding),
      verticalBanding: avg((f) => f.verticalBanding),
      greenDominance: mx((f) => f.greenDominance),
      greyDominance: avg((f) => f.greyDominance),
      rustDominance: mx((f) => f.rustDominance),
      darkPatchRatio: avg((f) => f.darkPatchRatio),
      darkTopBias: mx((f) => f.darkTopBias),
      lowerThirdDark: mx((f) => f.lowerThirdDark),
      midToneDominance: avg((f) => f.midToneDominance),
      highLuminanceVariance: mx((f) => f.highLuminanceVariance),
      vegetationNear: mx((f) => f.vegetationNear),
      roofSignal: roofSignal,
      wallSignal: wallSignal,
      foundationSignal: foundationSignal,
      overallDistress: avg((f) => f.overallDistress),
      crackLineScore: mx((f) => f.crackLineScore),
      peelingScore: mx((f) => f.peelingScore),
      moistureStainScore: mx((f) => f.moistureStainScore),
      gutterLineScore: mx((f) => f.gutterLineScore),
      roofLikely: list.any((f) => f.roofLikely) || roofSignal > 0.34,
      wallLikely: list.any((f) => f.wallLikely) || wallSignal > 0.34,
      foundationLikely:
          list.any((f) => f.foundationLikely) || foundationSignal > 0.32,
      highTextureChaos: list.any((f) => f.highTextureChaos),
      hashSeed: list.fold<int>(0, (a, f) => a ^ f.hashSeed),
    );
  }
}
