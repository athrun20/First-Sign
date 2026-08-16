# Scenario: `mixed_ambiguous`

Mixed / ambiguous exterior signals (glare, partial angles, unclear defects).

## Drop real photos

1. Add 1–4 real photos that are intentionally hard to classify.
2. Keep score/severity bands wide in `expected`.
3. Empty `photos[]` → harness skips gracefully.

## Run

```bash
flutter test test/calibration_harness_test.dart
```
