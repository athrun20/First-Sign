import 'package:flutter/material.dart';

import '../models/analysis_models.dart';
import '../widgets/condition_score_dial.dart';

/// Score-band label shared with history / dial UI.
String homeStatusFromScore(int score) => conditionStatusFromScore(score);

/// Score-band accent color shared with history / dial UI.
Color homeStatusColor(int score) => conditionStatusColor(score);

/// One honest conversational line from the latest report only.
///
/// Used as the single “what matters right now” line on Home — do not also
/// surface this string in the FirstSign AI companion card.
///
/// Grammar is homeowner-friendly: never “X is the main item to plan” when X is
/// plural or already hedged (e.g. “Possible siding cracks”).
String latestInsightLine(AnalysisReport report) {
  final lower = report.conditionLabel.toLowerCase();
  if (lower.contains('insufficient exterior')) {
    return 'Latest scan needs clearer exterior photos.';
  }

  final top = report.topPriorityIssue;
  if (top == null) {
    return 'No high-priority issues from the latest scan.';
  }

  final subject = naturalFindingSubject(top.homeownerTitle);
  if (subject.isEmpty) {
    return report.calmConditionLine;
  }

  if (report.highCount > 0) {
    return '$subject needs a closer look soon.';
  }
  if (report.mediumCount > 0) {
    final verb = looksPluralSubject(subject) ? 'appear' : 'appears';
    return '$subject $verb to need attention.';
  }
  return 'Minor note — $subject is worth a look.';
}

/// Additional FirstSign AI context for Home — never repeats [latestInsightLine].
///
/// Complements the hero’s “what matters” finding with calm next-step framing.
String firstSignAiCompanionNote(AnalysisReport report) {
  final lower = report.conditionLabel.toLowerCase();
  if (lower.contains('insufficient exterior')) {
    return 'Capture clearer wall, roof, and foundation angles in good light, '
        'then re-scan for a real condition picture.';
  }

  if (report.issues.isEmpty) {
    if (report.photoCount <= 1) {
      return 'Nothing elevated from this angle. A full-home scan can provide a '
          'more complete assessment when you are ready.';
    }
    return 'Exterior looks calm from the latest screening. Re-scan after weather '
        'or if you notice a new change.';
  }

  if (report.highCount > 0) {
    return report.photoCount <= 1
        ? 'Worth a closer look this season. A full-home scan will raise '
            'confidence before you schedule work.'
        : 'Worth a closer look this season. Open the report for photo evidence '
            'and a clear next step.';
  }
  if (report.mediumCount > 0) {
    return report.photoCount <= 1
        ? 'This appears manageable through routine maintenance. A full-home '
            'scan can provide a more complete assessment.'
        : 'This appears manageable through routine maintenance. Open the report '
            'when you want evidence and next steps.';
  }
  return 'Optional when convenient — overall condition still looks generally '
      'sound from this screening.';
}

/// Time-aware greeting for the home welcome line.
String homeGreeting({DateTime? now, bool returning = false}) {
  if (returning) return 'Welcome back';
  final h = (now ?? DateTime.now()).hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

/// Short reassuring status under the home score (no dial on Home).
String homeReassuranceLine(AnalysisReport report) {
  final lower = report.conditionLabel.toLowerCase();
  if (lower.contains('insufficient exterior')) {
    return 'Need clearer exterior photos';
  }
  if (report.highCount > 0) return 'Worth a closer look soon';
  if (report.mediumCount > 0) return 'A few items to plan';
  final s = report.overallScore;
  if (s >= 85 || report.issues.isEmpty) return 'Your home looks healthy';
  if (s >= 70) return 'Generally sound overall';
  return 'Worth a closer look soon';
}

/// Strip hedging prefixes so copy can use natural verb agreement.
String naturalFindingSubject(String raw) {
  var t = raw.trim();
  if (t.isEmpty) return '';
  if (t.endsWith('.')) t = t.substring(0, t.length - 1).trim();

  final lower = t.toLowerCase();
  const hedges = [
    'possible ',
    'possible: ',
    'signs of ',
    'likely ',
  ];
  for (final h in hedges) {
    if (lower.startsWith(h)) {
      t = t.substring(h.length).trim();
      break;
    }
  }
  if (t.isEmpty) return raw.trim();
  return t[0].toUpperCase() + t.substring(1);
}

/// Rough plural check for homeowner-facing subjects (not full NLP).
bool looksPluralSubject(String subject) {
  final w = subject.toLowerCase().trim();
  if (w.isEmpty) return false;
  if (w.contains(' and ')) return true;
  // Common finding plurals.
  if (w.contains('cracks') ||
      w.contains('shingles') ||
      w.contains('stains') ||
      w.contains('gutters') ||
      w.contains('cables') ||
      w.contains('issues') ||
      w.contains('signs')) {
    return true;
  }
  // Trailing "s" but not mass nouns / -ness / -ss.
  if (w.endsWith('ss') ||
      w.endsWith('ness') ||
      w.endsWith('us') ||
      w.endsWith('is') ||
      w.endsWith('paint') ||
      w.endsWith('wear') ||
      w.endsWith('loss') ||
      w.endsWith('clutter') ||
      w.endsWith('overflow')) {
    return false;
  }
  return w.endsWith('s');
}
