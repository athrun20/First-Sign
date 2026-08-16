# Scenario: `limited_dark`

Dark, underexposed, or low-detail single frame (limited visibility).

## Drop real photos

1. Replace `00_dark.jpg` with a real poor-light porch / side shot.
2. Expect `needsCloserPhoto` flags; keep `needsCloserPhotoOk: true`.
3. If the folder has no photos, the harness **skips** this scenario (not a fail).

Current field set: `00_dark.jpg` is the night street wide shot (in the manifest).
`01_porch.jpg` and `02_entry.jpg` are closer night frames kept for reference.

## Run

```bash
flutter test test/calibration_harness_test.dart
```
