# Scenario: `healthy_multi`

Control multi-angle exterior (expect healthy-ish score, no High severity).

## Drop real photos

1. Replace `00_front.jpg` … with your house photos (JPEG/PNG).
2. Keep filenames or update `photos[]` in `manifest.json`.
3. Tune `expected` bands only after a field pass — **do not** change analysis thresholds for fixture work.

## Run

```bash
flutter test test/calibration_harness_test.dart
```
