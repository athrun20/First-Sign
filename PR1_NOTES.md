# FirstSign PR1 — Property Memory foundation

**Scope:** Additive Property Memory brain (models, mapper, reconciler, Hive store, dual-write hook). Feature flag **off** by default. No analyzer/UI/Twin/nav changes. No PR2.

**Package:** files live in the existing `pillar_ai` Flutter app (imports use `package:pillar_ai/...`).

## Files

| Path | Role |
|---|---|
| `lib/config/property_memory_flags.dart` | `pm_enabled_v1` prefs flag (default **false**) |
| `lib/models/property_memory_enums.dart` | Schema enums + `toStorage`/`fromStorage` (`fresh`↔`"new"`, `checkIn`↔`"check_in"`) |
| `lib/models/property_memory_models.dart` | Pm* models + `PmPropertyMemoryBundle` + `PmDetection` |
| `lib/services/property_memory_mapper.dart` | `AnalysisIssue` / `SavedReport` → detections + coverage |
| `lib/services/property_memory_reconciler.dart` | Baseline + check-in reconcile (no auto-resolve) |
| `lib/services/property_memory_store.dart` | Dedicated Hive box `pillar_pm_v1`, dual-write API |
| `lib/services/report_store.dart` | Existing store + dual-write hook only (+9 lines) |
| `test/property_memory/*` | Unit tests for mapper / reconciler / store |

## Persistence

- Dedicated Hive box: `pillar_pm_v1` (separate from report photo blobs)
- Bundle JSON key: `bundle`
- Evidence bytes: `pm/ev/{evidenceId}` (same PM box; copied from `SavedReport.photos` when observations are created)
- Flag: SharedPreferences `pm_enabled_v1` (default **false** / unset → OFF)
- Historical `SavedReport`s are **not** migrated into Property Memory

## Baseline rules (final / approved)

Completed baseline is **slot-based Guided Capture only**. Bare photo count is **not** sufficient (obsolete: ~~`photoCount >= 4`~~).

`meetsBaselineMinimum` is true only when:

- **front + left + right + rear** slots are all present, **or**
- **≥3 distinct elevations** (from front/left/right/rear) **plus roof**

Otherwise the capture stays incomplete:

- Quick Scan, single-photo, single-slot, untagged, close-up-only, or any set that fails the slot rules → `baselineIncomplete`
- **No** `baselineScanId`
- Incomplete baseline scans create **no** Property Memory observations (and no provisional observation stack)
- Obsolete: ~~provisional observations OK on incomplete baseline~~

When `lifecycleState == active` (completed baseline) → subsequent saves are **check-in**.

Defensive cleanup: if an older incomplete bundle somehow still held provisional rows, completing baseline clears observations/evidence and deletes orphaned `pm/ev/*` bytes before writing the completed baseline.

## Reconciliation invariants

- Matcher: same `SurfaceType` + `ObservationCategory`; IoU≥0.3 → strong; same capture slot/zone → medium; else weak
- Completed baseline → observations `fresh` (`"new"`)
- Check-in match → `monitoring` (+ evidence); absence + good recapture → `unverified`; missing/poor → `unableToDetermine`
- Severity rematch only when detection confidence ≥ medium
- Poor image quality caps high/medium confidence → low (insufficient stays insufficient)
- Resolved + matching detection → **reopen same id** → `fresh`
- **NEVER** auto-resolve; **no** auto `worsened` / `improved`

## Dual-write hook

Inserted at end of `ReportStore.saveFromCapture` before `return saved;`, gated by `PropertyMemoryFlags.isEnabled`.

- Dual-write failures are logged and **ignored** — they must never break report saving
- `PropertyMemoryStore.applyFromSavedReport` also no-ops when the flag is OFF and swallows errors

## AT coverage (PR1 unit tests)

| AT | Covered? | Where |
|---|---|---|
| AT-1 baseline success | ✅ Pass | reconciler + store |
| AT-2 baseline incomplete / Quick Scan (no observations) | ✅ Pass | reconciler + store |
| AT-3 second scan check-in | ✅ Pass | reconciler + store |
| AT-4 same observation rematch → monitoring | ✅ Pass | reconciler |
| AT-5 absent + good recapture → unverified | ✅ Pass | reconciler |
| AT-6 absent + poor → unable_to_determine | ⏸ Deferred (partial via AT-30 poor branch) |
| AT-7 zone missing → unable_to_determine | ✅ Pass | reconciler |
| AT-8 new observation | ✅ Pass | reconciler |
| AT-17 user mark repaired → resolved | ✅ Pass | store |
| AT-18 repaired reappears → reopen same id | ✅ Pass | reconciler + store |
| AT-22 mixed check-in batch | ✅ Pass | reconciler |
| AT-30 no auto-resolve paths | ✅ Pass | reconciler |
| AT-9…16,19–21,23–29 | ⏸ Deferred (out of PR1 unit gate or UI-bound) |

Additional PR1 unit coverage (not numbered ATs): untagged 4-photo ≠ baseline; 3 elevations + roof = baseline; concurrent `ensureLoaded`; poor-quality confidence cap; severity rematch confidence gate.

## How to run

From the FirstSign app root:

```bash
flutter test test/property_memory/
```

Enable the flag **only** in tests / debug (never default-on in PR1):

```dart
await PropertyMemoryFlags.setEnabled(true);
```

## Explicit non-goals (PR1)

- No UI / Twin / Home Health / navigation changes
- No `exterior_analysis_service` changes
- No historical SavedReport migration
- No Supabase / embeddings / new state framework
- No auto worsened / improved / resolved
- No PR2 (read models / surfaces wiring beyond dual-write foundation)
