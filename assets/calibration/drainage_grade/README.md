# Scenario: `drainage_grade`

Foundation line, grade slope, or ground drainage concerns.

## Drop real photos

1. Capture grade-to-wall, downspout outlet, and any pooling / soil line.
2. Update `manifest.json` slots (`front`, `left`, `problemCloseup`, etc.).
3. Keep `expected` bands wide until local homes are validated.

Current field set: `01_soil.jpg` (two PVC outlets at grade) and `02_closeup.jpg` (pipe dripping onto soil).

## Run

```bash
flutter test test/calibration_harness_test.dart
```
