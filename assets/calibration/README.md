# Real-photo calibration fixtures

This tree already includes **real stock exterior photos** (Unsplash) under each
scenario folder, with `manifest.json` files. See `SOURCES.md` for licensing notes.

You can replace any image with your own house photos (keep filenames or update
the manifest). Drop **real exterior photos** here to override painted fallbacks.

## Layout

```
assets/calibration/
  README.md
  healthy_multi_angle/
    manifest.json
    00_front.jpg
    01_left.jpg
    …
  severe_roof_damage/
    manifest.json
    00_front.jpg
    01_roof.jpg
    …
```

## manifest.json example

```json
{
  "id": "severe_roof_damage",
  "description": "Real storm-damaged asphalt roof",
  "photos": [
    { "file": "00_front.jpg", "slot": "front", "label": "Front of home" },
    { "file": "01_roof.jpg", "slot": "roof", "label": "Roof field" },
    { "file": "02_closeup.jpg", "slot": "problemCloseup", "label": "Close-up" }
  ]
}
```

### Slot values

`front` · `left` · `right` · `rear` · `roof` · `problemCloseup`

## Scenario IDs (must match harness)

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

## Register assets

After adding folders, ensure `pubspec.yaml` includes:

```yaml
flutter:
  assets:
    - assets/calibration/
```

(Already configured for the `assets/calibration/` tree.)

## Run calibration

```bash
flutter test test/photo_calibration_test.dart
```

Painted fixtures run when a scenario has no real photos. When real photos are present, the same score/severity bands apply — tune detection if a real set fails.
