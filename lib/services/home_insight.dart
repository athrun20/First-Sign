import 'package:flutter/material.dart';

import '../models/analysis_models.dart';
import '../widgets/condition_score_dial.dart';

/// Score-band label shared with history / dial UI.
String homeStatusFromScore(int score) => conditionStatusFromScore(score);

/// Score-band accent color shared with history / dial UI.
Color homeStatusColor(int score) => conditionStatusColor(score);

/// One honest conversational line from the latest report only.
String latestInsightLine(AnalysisReport report) {
  final lower = report.conditionLabel.toLowerCase();
  if (lower.contains('insufficient exterior')) {
    return 'Latest scan needs clearer exterior photos.';
  }

  final top = report.topPriorityIssue;
  if (top == null) {
    return 'No high-priority issues in the latest scan.';
  }

  var watch = top.homeownerTitle.trim();
  if (watch.isEmpty) {
    return report.calmConditionLine;
  }
  if (watch.endsWith('.')) {
    watch = watch.substring(0, watch.length - 1);
  }

  if (report.highCount > 0) {
    return '$watch is the main item to watch.';
  }
  if (report.mediumCount > 0) {
    return '$watch is the main item to plan.';
  }
  return 'Minor notes only — $watch is worth a look.';
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
