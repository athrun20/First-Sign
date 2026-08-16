# Calibration fixtures (First Sign)

Two harnesses share this tree:

| Harness | Test | Purpose |
|---------|------|---------|
| **Field pack (A1)** | `flutter test test/calibration_harness_test.dart` | Manifest `expected` bands for field photos |
| **Pixel pipeline** | `flutter test test/photo_calibration_test.dart` | Legacy golden bands + painted fallbacks |

Stock Unsplash photos seed many folders. See `SOURCES.md` for licensing.
Replace with **local house photos** when available (keep filenames or update the manifest).

> **Do not change analysis thresholds** to make fixtures pass. Widen `expected` bands or fix photos first; threshold work is a separate ticket.

---

## Field pack layout (A1)

```
assets/calibration/
  healthy_multi/          # control multi-angle
  paint_clear/            # clear paint peel
  drainage_grade/         # grade / foundation / drainage
  limited_dark/           # weak / dark single frame
  mixed_ambiguous/        # mixed hard cases
  …
```

Each field scenario folder:

```
<scenario_id>/
  manifest.json     # required
  README.md         # how to drop real photos
  00_….jpg          # optional until you add field photos
```

### Field `manifest.json` schema

```json
{
  "id": "healthy_multi",
  "title": "Healthy multi-angle control home",
  "photos": [
    { "file": "00_front.jpg", "slot": "front", "label": "Front of home" },
    { "file": "01_left.jpg", "slot": "left", "label": "Left side" }
  ],
  "expected": {
    "maxFindings": 12,
    "allowedCategories": ["paint", "siding", "roof", "gutter", "drainage", "foundation", "window", "vegetation", "general"],
    "forbiddenCategories": [],
    "scoreMin": 55,
    "scoreMax": 98,
    "maxSeverity": "Medium",
    "needsCloserPhotoOk": true
  },
  "notes": "Optional free-text notes for the lab book."
}
```

| Field | Meaning |
|-------|---------|
| `maxFindings` | `report.issues.length` must be ≤ this |
| `minFindings` | `report.issues.length` must be ≥ this (default 0) |
| `allowedCategories` | If non-empty, every inferred category (except `general`) must be listed |
| `requiredCategories` | If non-empty, each listed category must appear at least once |
| `forbiddenCategories` | Inferred category must not appear |
| `scoreMin` / `scoreMax` | Inclusive overall score band |
| `maxSeverity` | No finding may exceed this (`Low` \| `Medium` \| `High`) |
| `needsCloserPhotoOk` | If `false`, any `needsCloserPhoto` finding fails |
| `requireNeedsCloserPhoto` | If `true`, at least one finding must have `needsCloserPhoto` |

Categories are **inferred from finding text** (title/location/insight) in the harness only — analysis models are unchanged.

### Slot values

`front` · `left` · `right` · `rear` · `roof` · `problemCloseup`

### Field scenario IDs

| ID | Intent |
|----|--------|
| `healthy_multi` | Clean multi-angle control |
| `paint_clear` | Clear paint film failure |
| `drainage_grade` | Grade / foundation / drainage |
| `limited_dark` | Dark / limited visibility |
| `mixed_ambiguous` | Mixed ambiguous signals |

### Add a new field scenario

1. Create `assets/calibration/<id>/` with `manifest.json` (schema above).
2. Drop JPEG/PNG photos; list them under `photos[]`.
3. Add a short `README.md` (copy from `healthy_multi/README.md`).
4. Register the folder in `pubspec.yaml` under `flutter.assets`.
5. Append `<id>` to `FieldCalibrationHarness.scenarioIds` in  
   `lib/services/field_calibration_harness.dart`.
6. Run:

```bash
flutter test test/calibration_harness_test.dart
```

**Empty photos:** leave `photos: []` or omit image files — the harness **skips** that scenario (not a failure).

---

## Legacy pixel-pipeline scenarios

| ID | Intent |
|----|--------|
| `healthy_multi_angle` | Clean home, high score, no Highs |
| `severe_roof_damage` | Missing/damaged shingles |
| `gutter_overflow` | Debris / overflow at eaves |
| `foundation_concern` | Grade/base cracks or moisture |
| `peeling_paint` | Failing paint film |
| `cracked_siding` | Cracked cladding |
| `weak_single_photo` | Bad/ambiguous single shot |
| `aging_roof_granules` | Aging asphalt, not catastrophic |

Legacy manifests may use `description` + optional `groundTruth` (no `expected` block).

```bash
flutter test test/photo_calibration_test.dart
```

---

## Register assets

```yaml
flutter:
  assets:
    - assets/calibration/
    - assets/calibration/<scenario_id>/
```

See root `pubspec.yaml` for the full list.
