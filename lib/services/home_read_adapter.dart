import 'package:flutter/foundation.dart';
import 'package:pillar_ai/config/property_memory_flags.dart';
import 'package:pillar_ai/models/home_property_summary.dart';
import 'package:pillar_ai/models/property_memory_enums.dart';
import 'package:pillar_ai/models/property_memory_models.dart';
import 'package:pillar_ai/models/saved_report.dart';
import 'package:pillar_ai/services/home_insight.dart';
import 'package:pillar_ai/services/property_memory_store.dart';
import 'package:pillar_ai/services/report_store.dart';

/// Reads Home hero / companion copy from SavedReport and (when authoritative)
/// Property Memory. Flag OFF keeps the SavedReport + home_insight path.
class HomeReadAdapter {
  HomeReadAdapter._();

  static bool? _cachedFlagEnabled;

  /// Last known [PropertyMemoryFlags.isEnabled] after [load] / [refreshFlag].
  static bool get cachedFlagEnabled => _cachedFlagEnabled ?? false;

  @visibleForTesting
  static void debugSetFlagCache(bool? value) => _cachedFlagEnabled = value;

  /// Ensure stores are loaded, refresh flag cache, then [peek].
  ///
  /// Never throws to callers — any failure falls back to SavedReport path.
  static Future<HomePropertySummary> load() async {
    try {
      await ReportStore.instance.ensureLoaded();
      final enabled = await PropertyMemoryFlags.isEnabled;
      _cachedFlagEnabled = enabled;
      if (enabled) {
        await PropertyMemoryStore.instance.ensureLoaded();
      }
      return peek();
    } catch (e, st) {
      debugPrint('HomeReadAdapter.load failed (fallback): $e\n$st');
      try {
        return _fromSavedReport(
          _latestReport(),
          lifecycle: null,
          openObservationCount: 0,
        );
      } catch (_) {
        return _emptyFallback();
      }
    }
  }

  /// Refresh flag cache without rebuilding (e.g. Home bootstrap).
  static Future<bool> refreshFlag() async {
    final enabled = await PropertyMemoryFlags.isEnabled;
    _cachedFlagEnabled = enabled;
    return enabled;
  }

  /// Sync snapshot from in-memory stores. If PM is not loaded yet, treats as
  /// non-authoritative fallback. Uses cached flag (defaults OFF).
  static HomePropertySummary peek() {
    try {
      return buildFromCurrentStores();
    } catch (e, st) {
      debugPrint('HomeReadAdapter.peek failed (fallback): $e\n$st');
      return _fromSavedReport(
        _latestReport(),
        lifecycle: null,
        openObservationCount: 0,
      );
    }
  }

  /// Sync build from current ReportStore + PropertyMemoryStore memory.
  static HomePropertySummary buildFromCurrentStores() {
    final pm = PropertyMemoryStore.instance;
    return compose(
      flagEnabled: cachedFlagEnabled,
      latestReport: _latestReport(),
      pmLoaded: pm.isLoaded,
      pmLoadFailed: pm.hasLoadFailed,
      bundle: pm.bundle,
    );
  }

  /// Pure composer for tests and [peek].
  @visibleForTesting
  static HomePropertySummary compose({
    required bool flagEnabled,
    required SavedReport? latestReport,
    required bool pmLoaded,
    required bool pmLoadFailed,
    required PmPropertyMemoryBundle? bundle,
  }) {
    final open = _openObservations(bundle);
    final lifecycle = bundle?.property.lifecycleState;

    if (!_isAuthoritative(
      flagEnabled: flagEnabled,
      pmLoaded: pmLoaded,
      pmLoadFailed: pmLoadFailed,
      bundle: bundle,
    )) {
      return _fromSavedReport(
        latestReport,
        lifecycle: lifecycle,
        openObservationCount: open.length,
      );
    }

    return _fromPropertyMemory(
      latestReport: latestReport,
      bundle: bundle!,
      open: open,
    );
  }

  static SavedReport? _latestReport() {
    final list = ReportStore.instance.reports;
    return list.isEmpty ? null : list.first;
  }

  static bool _isAuthoritative({
    required bool flagEnabled,
    required bool pmLoaded,
    required bool pmLoadFailed,
    required PmPropertyMemoryBundle? bundle,
  }) {
    if (!flagEnabled) return false;
    if (!pmLoaded || pmLoadFailed) return false;
    if (bundle == null) return false;
    final property = bundle.property;
    if (property.lifecycleState != PropertyLifecycleState.active) return false;
    if (property.baselineScanId == null) return false;

    // Prefer latest completed baseline/check-in coverage adequacy when readable.
    if (bundle.scans.isNotEmpty) {
      final scans = [...bundle.scans]
        ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
      if (!scans.first.coverageReport.meetsBaselineMinimum) {
        return false;
      }
    }
    return true;
  }

  static List<PmObservation> _openObservations(PmPropertyMemoryBundle? bundle) {
    if (bundle == null) return const [];
    return [
      for (final o in bundle.observations)
        if (!o.userDismissed && o.status != ObservationStatus.resolved) o,
    ];
  }

  static PmObservation? _topOpenObservation(List<PmObservation> open) {
    if (open.isEmpty) return null;
    final sorted = [...open]..sort((a, b) {
        final bySev = _severityRank(b.severityBand).compareTo(
          _severityRank(a.severityBand),
        );
        if (bySev != 0) return bySev;
        final aAt = a.lastSeenAt ?? a.firstSeenAt;
        final bAt = b.lastSeenAt ?? b.firstSeenAt;
        return bAt.compareTo(aAt);
      });
    return sorted.first;
  }

  static int _severityRank(SeverityBand band) => switch (band) {
        SeverityBand.urgent => 3,
        SeverityBand.attention => 2,
        SeverityBand.watch => 1,
        SeverityBand.info => 0,
      };

  static HomePropertySummary _fromPropertyMemory({
    required SavedReport? latestReport,
    required PmPropertyMemoryBundle bundle,
    required List<PmObservation> open,
  }) {
    final property = bundle.property;
    final top = _topOpenObservation(open);
    final signal = property.overallConditionSignal;

    final whatMatters = _pmWhatMatters(top: top, signal: signal);
    final reassurance = _pmReassurance(top: top, signal: signal);
    final companion = _pmCompanionNote(
      top: top,
      signal: signal,
      latestReport: latestReport,
      openCount: open.length,
    );

    return HomePropertySummary(
      fromPropertyMemory: true,
      hasScanContent: latestReport != null || bundle.scans.isNotEmpty,
      score: latestReport?.score,
      reassuranceLine: reassurance,
      whatMattersLine: whatMatters,
      companionNote: companion,
      scannedRelativeLabel: latestReport?.relativeDateLabel,
      latestReport: latestReport,
      lifecycle: property.lifecycleState,
      openObservationCount: open.length,
    );
  }

  static String _pmWhatMatters({
    required PmObservation? top,
    required OverallConditionSignal signal,
  }) {
    if (top != null) {
      return _whatMattersFromObservation(top);
    }
    // Authoritative + no open observations.
    switch (signal) {
      case OverallConditionSignal.urgentAttention:
        return 'Property Memory still flags urgent attention — open the latest report to review.';
      case OverallConditionSignal.needsAttention:
        return 'A few exterior items may still need planning even with none open right now.';
      case OverallConditionSignal.incompleteCoverage:
        // Should not be authoritative, but never claim healthy from empty list.
        return 'Coverage is incomplete — capture a fuller exterior scan when you can.';
      case OverallConditionSignal.stable:
        return 'No open exterior items to track right now.';
    }
  }

  static String _whatMattersFromObservation(PmObservation obs) {
    final subject = naturalFindingSubject(obs.title);
    if (subject.isEmpty) {
      return 'An open exterior item needs your attention.';
    }
    switch (obs.severityBand) {
      case SeverityBand.urgent:
        return '$subject needs a closer look soon.';
      case SeverityBand.attention:
        final verb = looksPluralSubject(subject) ? 'appear' : 'appears';
        return '$subject $verb to need attention.';
      case SeverityBand.watch:
      case SeverityBand.info:
        return 'Minor note — $subject is worth a look.';
    }
  }

  static String _pmReassurance({
    required PmObservation? top,
    required OverallConditionSignal signal,
  }) {
    // Never say healthy if coverage incomplete (defensive).
    if (signal == OverallConditionSignal.incompleteCoverage) {
      return 'Need clearer exterior coverage';
    }

    final topUrgent = top?.severityBand == SeverityBand.urgent;
    final topAttention = top?.severityBand == SeverityBand.attention;

    if (signal == OverallConditionSignal.urgentAttention || topUrgent) {
      return 'Worth a closer look soon';
    }
    if (signal == OverallConditionSignal.needsAttention || topAttention) {
      return 'A few items to plan';
    }

    // stable + no open / only watch (or info)
    if (top == null ||
        top.severityBand == SeverityBand.watch ||
        top.severityBand == SeverityBand.info) {
      return 'Your home looks healthy';
    }

    return 'Generally sound overall';
  }

  static String _pmCompanionNote({
    required PmObservation? top,
    required OverallConditionSignal signal,
    required SavedReport? latestReport,
    required int openCount,
  }) {
    final hasReport = latestReport != null;
    final elevated = top != null &&
        (top.severityBand == SeverityBand.urgent ||
            top.severityBand == SeverityBand.attention);

    if (elevated) {
      if (hasReport) {
        return 'Open the report for photo evidence and a clear next step.';
      }
      return 'A full-home re-scan will raise confidence before you schedule work.';
    }

    if (top != null) {
      return 'Optional when convenient — keep an eye on it during routine upkeep.';
    }

    switch (signal) {
      case OverallConditionSignal.urgentAttention:
      case OverallConditionSignal.needsAttention:
        return hasReport
            ? 'Review the latest report to confirm nothing was missed.'
            : 'Re-scan when you can so Property Memory stays current.';
      case OverallConditionSignal.incompleteCoverage:
        return 'Capture clearer wall, roof, and foundation angles in good light.';
      case OverallConditionSignal.stable:
        return openCount == 0
            ? 'Exterior looks calm in Property Memory. Re-scan after weather or if you notice a new change.'
            : 'Keep routine upkeep going — nothing elevated to act on first.';
    }
  }

  static HomePropertySummary _fromSavedReport(
    SavedReport? latest, {
    required PropertyLifecycleState? lifecycle,
    required int openObservationCount,
  }) {
    if (latest == null) {
      return HomePropertySummary(
        fromPropertyMemory: false,
        hasScanContent: false,
        score: null,
        reassuranceLine: 'Not scanned yet',
        whatMattersLine:
            'Capture clear exterior photos to unlock your first calm condition report.',
        companionNote: '',
        scannedRelativeLabel: null,
        latestReport: null,
        lifecycle: lifecycle,
        openObservationCount: openObservationCount,
      );
    }

    return HomePropertySummary(
      fromPropertyMemory: false,
      hasScanContent: true,
      score: latest.score,
      reassuranceLine: homeReassuranceLine(latest.report),
      whatMattersLine: latestInsightLine(latest.report),
      companionNote: firstSignAiCompanionNote(latest.report),
      scannedRelativeLabel: latest.relativeDateLabel,
      latestReport: latest,
      lifecycle: lifecycle,
      openObservationCount: openObservationCount,
    );
  }

  static HomePropertySummary _emptyFallback() {
    return const HomePropertySummary(
      fromPropertyMemory: false,
      hasScanContent: false,
      score: null,
      reassuranceLine: 'Not scanned yet',
      whatMattersLine:
          'Capture clear exterior photos to unlock your first calm condition report.',
      companionNote: '',
      scannedRelativeLabel: null,
      latestReport: null,
      lifecycle: null,
      openObservationCount: 0,
    );
  }
}
