# FirstSign PR1 — Property Memory foundation

**Scope:** Additive Property Memory brain (models, mapper, reconciler, Hive store, dual-write hook). Feature flag **off** by default. No analyzer/UI/Twin/nav changes.

**Package:** drop these files into the existing `pillar_ai` Flutter app (imports use `package:pillar_ai/...`).

## Files

| Path | Role |
|---|---|
| `lib/config/property_memory_flags.dart` | `pm_enabled_v1` prefs flag (default false) |
| `lib/models/property_memory_enums.dart` | Schema enums + `toStorage`/`fromStorage` (`fresh`↔`"new"`, `checkIn`↔`"check_in"`) |
| `lib/models/property_memory_models.dart` | Pm* models + `PmPropertyMemoryBundle` + `PmDetection` |
| `lib/services/property_memory_mapper.dart` | `AnalysisIssue` / `SavedReport` → detections + coverage |
| `lib/services/property_memory_reconciler.dart` | Baseline + check-in reconcile (no auto-resolve) |
| `lib/services/property_memory_store.dart` | Hive box `pillar_pm_v1`, dual-write API |
| `lib/services/report_store.dart` | GitHub HEAD + dual-write hook only |
| `lib/services/report_store_patch_snippet.dart.txt` | Exact insertion snippet |
| `test/property_memory/*` | Unit tests for mapper / reconciler / store |

## Persistence

- Hive box: `pillar_pm_v1`
- Bundle JSON key: `bundle`
- Evidence bytes: `pm/ev/{evidenceId}` (same box; copied from `SavedReport.photos`)
- Flag: SharedPreferences `pm_enabled_v1` (default **false**)

## Baseline rules (approved overrides)

- `meetsBaselineMinimum` = `photoCount >= 4` OR front+left+right+rear slots present
- Quick Scan / `photoCount==1` / single-slot → **cannot** complete baseline (`baselineIncomplete`, provisional observations OK, **no** `baselineScanId`)
- When `lifecycleState == active` → subsequent saves are **check-in**
- Completing baseline after incomplete drops provisional observations

## Reconciliation invariants

- Matcher: same `SurfaceType` + `ObservationCategory`; IoU≥0.3 → strong; same capture slot/zone → medium; else weak
- Baseline → observations `fresh` (`"new"`)
- Check-in match → `monitoring` (+ evidence); absence + good recapture → `unverified`; missing/poor → `unableToDetermine`
- Resolved + matching detection → **reopen same id** → `fresh`
- **NEVER** auto-resolve; **no** auto `worsened`/`improved`

## Dual-write hook

Inserted at end of `ReportStore.saveFromCapture` before `return saved;`. Failures are logged and ignored.

## AT coverage (PR1 unit tests)

| AT | Covered? | Where |
|---|---|---|
| AT-1 baseline success | ✅ Pass (intended) | reconciler + store |
| AT-2 baseline incomplete / Quick Scan | ✅ Pass | reconciler + store |
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

## How to run

From the real FirstSign app root (after copying these files in):

```bash
flutter test test/property_memory/
```

Enable the flag only in tests / debug:

```dart
await PropertyMemoryFlags.setEnabled(true);
```

## Explicit non-goals (PR1)

- No UI / Twin / Home Health / navigation changes
- No `exterior_analysis_service` changes
- No historical SavedReport migration
- No Supabase / embeddings / new state framework
- No auto worsened/improved/resolved
