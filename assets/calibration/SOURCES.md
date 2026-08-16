# Calibration photo sources

Photos under `assets/calibration/` are free stock images from
[Unsplash](https://unsplash.com/license) (free to use, including commercial;
no attribution required by the license, but sources are listed for transparency).

They are **real photographs** used to exercise the local screening pipeline.
They are **not** labeled ground-truth inspections — scenario folders map loosely
to product bands (healthy, roof, gutters, etc.).

Replace any file with your own house photos and keep the same `manifest.json`
names when calibrating on a private golden set.

Local field replacements (not Unsplash):

- `drainage_grade/01_soil.jpg` and `02_closeup.jpg` — homeowner photos of PVC
  foundation discharge outlets (2026-08).
- `limited_dark/00_dark.jpg` — homeowner night street wide shot (2026-08).
  `01_porch.jpg` / `02_entry.jpg` are closer night frames, not in the manifest.
  `1000017200.jpg` is a daylight front elevation, held aside.
- `aging_roof_granules/02_field.jpg` — homeowner asphalt shingle slope (2026-08).
  Not in that manifest: local screening scored the frame as a strong roof
  (no defect finding). Held aside so the labeled aging fixture stays intact.
