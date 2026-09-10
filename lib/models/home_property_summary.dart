import 'property_memory_enums.dart';
import 'saved_report.dart';

/// Home hero / companion summary - SavedReport for score and navigation;
/// Property Memory may own What Matters when authoritative.
class HomePropertySummary {
  final bool fromPropertyMemory;
  final bool hasScanContent;
  final int? score;
  final String reassuranceLine;
  final String whatMattersLine;
  final String companionNote;
  final String? scannedRelativeLabel;
  final SavedReport? latestReport;
  final PropertyLifecycleState? lifecycle;
  final int openObservationCount;

  const HomePropertySummary({
    required this.fromPropertyMemory,
    required this.hasScanContent,
    required this.score,
    required this.reassuranceLine,
    required this.whatMattersLine,
    required this.companionNote,
    required this.scannedRelativeLabel,
    required this.latestReport,
    required this.lifecycle,
    required this.openObservationCount,
  });
}
