import 'dart:async' show unawaited;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../legal/privacy_copy.dart';
import '../models/analysis_models.dart';
import '../models/saved_report.dart';
import '../models/score_comparison.dart';
import '../services/report_store.dart';
import '../theme/app_lux.dart';
import '../widgets/condition_score_dial.dart';
import '../widgets/digital_twin_house.dart';

/// Sort / filter chips for the report list.
enum _ReportFilter { all, thisWeek, strong, needsAttention }

/// Homeowner list of past exterior assessments — calm luxury + practical reopen.
class ReportHistoryScreen extends StatefulWidget {
  const ReportHistoryScreen({super.key});

  @override
  State<ReportHistoryScreen> createState() => _ReportHistoryScreenState();
}

class _ReportHistoryScreenState extends State<ReportHistoryScreen> {
  final _searchCtrl = TextEditingController();
  _ReportFilter _filter = _ReportFilter.all;

  @override
  void initState() {
    super.initState();
    ReportStore.instance.addListener(_onChange);
    unawaited(ReportStore.instance.ensureLoaded());
    _searchCtrl.addListener(_onChange);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onChange);
    _searchCtrl.dispose();
    ReportStore.instance.removeListener(_onChange);
    super.dispose();
  }

  Future<void> _open(SavedReport report) async {
    await Navigator.of(context).pushNamed('/saved-report', arguments: report);
  }

  Future<void> _delete(SavedReport report) async {
    final label = report.report.conditionLabel.trim().isEmpty
        ? 'this assessment'
        : '"${report.report.conditionLabel.trim()}"';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppLux.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppLux.radius2xl),
        ),
        title: Text(
          'Delete report?',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 17,
            letterSpacing: -0.25,
            color: AppLux.charcoal,
          ),
        ),
        content: Text(
          'Remove $label from this device? Photos and findings for this '
          'assessment will be permanently deleted.',
          style: GoogleFonts.inter(
            color: AppLux.body,
            height: 1.5,
            fontSize: 14,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: AppLux.ghostButton(),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: AppLux.body,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppLux.danger,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppLux.radiusMd),
              ),
            ),
            child: Text(
              'Delete',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ReportStore.instance.delete(report.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppLux.charcoal,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppLux.radiusMd),
          ),
          content: Text(
            'Report deleted',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      );
    }
  }

  void _startCapture() {
    unawaited(Navigator.of(context).pushNamed('/guided-capture'));
  }

  Color _scoreColor(int score) {
    if (score >= 85) return AppLux.teal;
    if (score >= 70) return AppLux.warning;
    return AppLux.danger;
  }

  bool _isRecent(SavedReport r) {
    return DateTime.now().difference(r.createdAt).inDays < 7;
  }

  String _absoluteDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final now = DateTime.now();
    final month = months[d.month - 1];
    if (d.year == now.year) return '$month ${d.day}';
    return '$month ${d.day}, ${d.year}';
  }

  List<SavedReport> _applyFilters(List<SavedReport> source) {
    final q = _searchCtrl.text.trim().toLowerCase();
    return source.where((r) {
      if (_filter == _ReportFilter.thisWeek && !_isRecent(r)) return false;
      if (_filter == _ReportFilter.strong && r.score < 85) return false;
      if (_filter == _ReportFilter.needsAttention && r.score >= 70) {
        return false;
      }

      if (q.isEmpty) return true;
      final top = r.report.topPriorityIssue;
      final hay = [
        r.report.conditionLabel,
        r.relativeDateLabel,
        _absoluteDate(r.createdAt),
        '${r.score}',
        if (top != null) top.storyTitle,
        if (top != null) top.location,
        for (final issue in r.report.issues) issue.title,
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  /// Latest vs previous; past reports vs most recent scan.
  ScoreComparison? _comparisonFor(SavedReport report, List<SavedReport> all) {
    if (all.length < 2) return null;
    return ScoreComparison.forSavedReport(reportId: report.id, reports: all);
  }

  @override
  Widget build(BuildContext context) {
    final store = ReportStore.instance;
    final all = store.reports;
    final filtered = _applyFilters(all);
    final recent = filtered.where(_isRecent).toList();
    final older = filtered.where((r) => !_isRecent(r)).toList();
    // When filtering "This week", older is empty by design — skip dual sections.
    final useSections =
        _filter == _ReportFilter.all && recent.isNotEmpty && older.isNotEmpty;

    final latest = all.isEmpty ? null : all.first;
    final previous = all.length >= 2 ? all[1] : null;
    final comparison = latest != null && previous != null
        ? ScoreComparison.latestVsPrevious(
            latest: latest,
            previous: previous,
          )
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F7F9),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Home Health',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: AppLux.titleMd,
            letterSpacing: -0.2,
            color: AppLux.charcoal,
          ),
        ),
        actions: [
          if (all.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppLux.tealMist,
                    borderRadius: BorderRadius.circular(AppLux.radiusPill),
                    border: Border.all(
                      color: AppLux.teal.withValues(alpha: 0.16),
                      width: AppLux.borderWidth,
                    ),
                  ),
                  child: Text(
                    '${all.length} saved',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppLux.tealDeep,
                      letterSpacing: 0.15,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: !store.isLoaded
          ? Center(child: AppLux.loadingCard(label: 'Loading reports…'))
          : all.isEmpty
          ? _EmptyState(onStart: _startCapture)
          : Stack(
              children: [
                const Positioned.fill(child: _ReportsBlueprint()),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: filtered.isEmpty
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    AppLux.pagePaddingH,
                                    4,
                                    AppLux.pagePaddingH,
                                    0,
                                  ),
                                  child: Column(
                                    children: [
                                      _HomeHealthDashboardHero(
                                        latest: latest!,
                                        allReports: all,
                                        comparison: comparison,
                                        absoluteDate: _absoluteDate,
                                      ),
                                      const SizedBox(height: 14),
                                      _SearchField(controller: _searchCtrl),
                                      const SizedBox(height: 12),
                                      _FilterChips(
                                        value: _filter,
                                        onChanged: (f) =>
                                            setState(() => _filter = f),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: _NoMatchState(
                                    onClear: () {
                                      _searchCtrl.clear();
                                      setState(
                                        () => _filter = _ReportFilter.all,
                                      );
                                    },
                                  ),
                                ),
                              ],
                            )
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(
                                AppLux.pagePaddingH,
                                8,
                                AppLux.pagePaddingH,
                                32,
                              ),
                              children: [
                                _HomeHealthDashboardHero(
                                  latest: latest!,
                                  allReports: all,
                                  comparison: comparison,
                                  absoluteDate: _absoluteDate,
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'Your living scan history — reopen any assessment.',
                                  style: GoogleFonts.inter(
                                    fontSize: 13.5,
                                    height: 1.4,
                                    color: AppLux.muted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _SearchField(controller: _searchCtrl),
                                const SizedBox(height: 12),
                                _FilterChips(
                                  value: _filter,
                                  onChanged: (f) =>
                                      setState(() => _filter = f),
                                ),
                                const SizedBox(height: 16),
                            if (useSections) ...[
                              AppLux.sectionHeader(
                                'Recent',
                                trailing: '${recent.length}',
                              ),
                              const SizedBox(height: 12),
                              for (var i = 0; i < recent.length; i++) ...[
                                _ReportCard(
                                  report: recent[i],
                                  absoluteDate: _absoluteDate(
                                    recent[i].createdAt,
                                  ),
                                  scoreColor: _scoreColor(recent[i].score),
                                  emphasize: i == 0,
                                  comparison: _comparisonFor(recent[i], all),
                                  onOpen: () => _open(recent[i]),
                                  onDelete: () => _delete(recent[i]),
                                ),
                                const SizedBox(height: 12),
                              ],
                              const SizedBox(height: 8),
                              AppLux.sectionHeader(
                                'Earlier',
                                trailing: '${older.length}',
                              ),
                              const SizedBox(height: 12),
                              for (final r in older) ...[
                                _ReportCard(
                                  report: r,
                                  absoluteDate: _absoluteDate(r.createdAt),
                                  scoreColor: _scoreColor(r.score),
                                  emphasize: false,
                                  comparison: _comparisonFor(r, all),
                                  onOpen: () => _open(r),
                                  onDelete: () => _delete(r),
                                ),
                                const SizedBox(height: 12),
                              ],
                            ] else ...[
                              if (_filter != _ReportFilter.all ||
                                  _searchCtrl.text.trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(
                                    '${filtered.length} match'
                                    '${filtered.length == 1 ? '' : 'es'}',
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppLux.muted,
                                      letterSpacing: 0.1,
                                    ),
                                  ),
                                ),
                              for (var i = 0; i < filtered.length; i++) ...[
                                _ReportCard(
                                  report: filtered[i],
                                  absoluteDate: _absoluteDate(
                                    filtered[i].createdAt,
                                  ),
                                  scoreColor: _scoreColor(filtered[i].score),
                                  emphasize:
                                      i == 0 &&
                                      _filter == _ReportFilter.all &&
                                      _searchCtrl.text.trim().isEmpty,
                                  comparison: _comparisonFor(filtered[i], all),
                                  onOpen: () => _open(filtered[i]),
                                  onDelete: () => _delete(filtered[i]),
                                ),
                                const SizedBox(height: 12),
                              ],
                            ],
                              ],
                            ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

// ── System status helpers (from real findings) ───────────────────────────────

enum _SysHealth { good, watch, attention }

_SysHealth _systemHealth(AnalysisReport report, TwinZone zone) {
  final issues = report.issues.where((i) => i.twinZone == zone);
  if (issues.any((i) => i.severity == 'High')) return _SysHealth.attention;
  if (issues.any((i) => i.severity == 'Medium')) return _SysHealth.watch;
  if (issues.any((i) => i.severity == 'Low')) return _SysHealth.watch;
  return _SysHealth.good;
}

String _sysLabel(_SysHealth h) {
  switch (h) {
    case _SysHealth.good:
      return 'Good';
    case _SysHealth.watch:
      return 'Watch';
    case _SysHealth.attention:
      return 'Attention';
  }
}

Color _sysColor(_SysHealth h) {
  switch (h) {
    case _SysHealth.good:
      return AppLux.teal;
    case _SysHealth.watch:
      return AppLux.warning;
    case _SysHealth.attention:
      return AppLux.danger;
  }
}

// ── Home Health dashboard hero ───────────────────────────────────────────────

/// Living dashboard: score dial + systems + trend + timeline (real data only).
class _HomeHealthDashboardHero extends StatelessWidget {
  const _HomeHealthDashboardHero({
    required this.latest,
    required this.allReports,
    required this.absoluteDate,
    this.comparison,
  });

  final SavedReport latest;
  final List<SavedReport> allReports;
  final ScoreComparison? comparison;
  final String Function(DateTime) absoluteDate;

  @override
  Widget build(BuildContext context) {
    final score = latest.score;
    final status = conditionStatusFromScore(score);
    final accent = conditionStatusColor(score);
    final systems = <(String, TwinZone)>[
      ('Roof', TwinZone.roof),
      ('Siding', TwinZone.siding),
      ('Foundation', TwinZone.foundation),
      ('Gutters', TwinZone.gutters),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.9),
              width: 1.1,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppLux.surface.withValues(alpha: 0.97),
                AppLux.tealMist.withValues(alpha: 0.65),
                const Color(0xFFEEF2F7).withValues(alpha: 0.55),
              ],
            ),
            boxShadow: AppLux.softShadow(intensity: 1.1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Home Health Score',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppLux.muted,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 14),
              // Score + systems side by side
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ConditionScoreDial(
                    key: ValueKey(latest.id),
                    score: score,
                    accent: accent,
                    size: 148,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status,
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: accent,
                            letterSpacing: -0.25,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Last scanned ${latest.relativeDateLabel}',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: AppLux.body,
                          ),
                        ),
                        if (comparison != null) ...[
                          const SizedBox(height: 10),
                          _TrendChip(comparison: comparison!),
                        ],
                        const SizedBox(height: 14),
                        for (final s in systems) ...[
                          _SystemStatusRow(
                            label: s.$1,
                            health: _systemHealth(latest.report, s.$2),
                          ),
                          if (s != systems.last) const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Home Health Timeline
              _HomeHealthTimeline(
                reports: allReports,
                absoluteDate: absoluteDate,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendChip extends StatelessWidget {
  const _TrendChip({required this.comparison});

  final ScoreComparison comparison;

  @override
  Widget build(BuildContext context) {
    final c = comparison.accentColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: comparison.softFill,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: c.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(comparison.trendIcon, size: 15, color: c),
          const SizedBox(width: 5),
          Text(
            comparison.unchanged
                ? 'Unchanged vs last scan'
                : '${comparison.pointsLabel} vs last scan',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: c,
            ),
          ),
        ],
      ),
    );
  }
}

class _SystemStatusRow extends StatelessWidget {
  const _SystemStatusRow({required this.label, required this.health});

  final String label;
  final _SysHealth health;

  @override
  Widget build(BuildContext context) {
    final color = _sysColor(health);
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.35),
                blurRadius: 4,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppLux.charcoal,
            ),
          ),
        ),
        Text(
          _sysLabel(health),
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _TimelineEvent {
  const _TimelineEvent({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
}

List<_TimelineEvent> _buildTimelineEvents(
  List<SavedReport> reports,
  String Function(DateTime) absoluteDate,
) {
  final events = <_TimelineEvent>[];
  // Newest first, cap at 5 for calm density.
  final slice = reports.take(5).toList();
  for (var i = 0; i < slice.length; i++) {
    final r = slice[i];
    final date = absoluteDate(r.createdAt);
    events.add(
      _TimelineEvent(
        title: i == 0 ? 'Latest scan' : 'Scan completed',
        subtitle: '$date · score ${r.score}',
        icon: Icons.radar_rounded,
        color: AppLux.teal,
      ),
    );
    if (i + 1 < reports.length) {
      final older = reports[i + 1];
      final delta = r.score - older.score;
      if (delta > 0) {
        events.add(
          _TimelineEvent(
            title: 'Health improved',
            subtitle: '$date · +$delta pts since prior scan',
            icon: Icons.trending_up_rounded,
            color: AppLux.teal,
          ),
        );
      } else if (delta < 0) {
        events.add(
          _TimelineEvent(
            title: 'Attention noted',
            subtitle: '$date · ${delta.abs()} pts lower than prior',
            icon: Icons.trending_down_rounded,
            color: AppLux.warning,
          ),
        );
      }
    }
    if (r.report.highCount > 0 && i == 0) {
      events.add(
        _TimelineEvent(
          title: 'Priority item flagged',
          subtitle:
              '${r.report.topPriorityIssue?.storyTitle ?? 'High severity'} · watch soon',
          icon: Icons.flag_outlined,
          color: AppLux.danger,
        ),
      );
    } else if (r.report.issues.isEmpty && i == 0) {
      events.add(
        _TimelineEvent(
          title: 'No priority repairs',
          subtitle: '$date · exterior screening looked solid',
          icon: Icons.verified_outlined,
          color: AppLux.teal,
        ),
      );
    }
  }
  return events.take(6).toList();
}

class _HomeHealthTimeline extends StatelessWidget {
  const _HomeHealthTimeline({
    required this.reports,
    required this.absoluteDate,
  });

  final List<SavedReport> reports;
  final String Function(DateTime) absoluteDate;

  @override
  Widget build(BuildContext context) {
    final events = _buildTimelineEvents(reports, absoluteDate);
    if (events.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppLux.surface.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppLux.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Home Health Timeline',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppLux.charcoal,
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < events.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: events[i].color.withValues(alpha: 0.12),
                        border: Border.all(
                          color: events[i].color.withValues(alpha: 0.28),
                        ),
                      ),
                      child: Icon(
                        events[i].icon,
                        size: 13,
                        color: events[i].color,
                      ),
                    ),
                    if (i < events.length - 1)
                      Container(
                        width: 1.5,
                        height: 18,
                        color: AppLux.border,
                      ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: i < events.length - 1 ? 8 : 0,
                      top: 3,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          events[i].title,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppLux.charcoal,
                          ),
                        ),
                        Text(
                          events[i].subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppLux.muted,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ReportsBlueprint extends StatelessWidget {
  const _ReportsBlueprint();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _FaintGridPainter(
          color: const Color(0xFF0F2744).withValues(alpha: 0.025),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _FaintGridPainter extends CustomPainter {
  _FaintGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.7;
    const step = 28.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FaintGridPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ── Search ───────────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: GoogleFonts.inter(
        fontSize: 14.5,
        fontWeight: FontWeight.w500,
        color: AppLux.charcoal,
      ),
      cursorColor: AppLux.teal,
      decoration: InputDecoration(
        hintText: 'Search by condition, finding, or score…',
        hintStyle: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppLux.muted,
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppLux.icon,
          size: 22,
        ),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, value, _) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return IconButton(
              tooltip: 'Clear',
              onPressed: controller.clear,
              icon: const Icon(
                Icons.close_rounded,
                size: 18,
                color: AppLux.muted,
              ),
            );
          },
        ),
        filled: true,
        fillColor: AppLux.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppLux.radiusXl),
          borderSide: const BorderSide(
            color: AppLux.border,
            width: AppLux.borderWidth,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppLux.radiusXl),
          borderSide: const BorderSide(
            color: AppLux.border,
            width: AppLux.borderWidth,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppLux.radiusXl),
          borderSide: BorderSide(
            color: AppLux.teal.withValues(alpha: 0.55),
            width: 1.2,
          ),
        ),
      ),
    );
  }
}

// ── Filter chips ─────────────────────────────────────────────────────────────

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.value, required this.onChanged});

  final _ReportFilter value;
  final ValueChanged<_ReportFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = <(_ReportFilter, String)>[
      (_ReportFilter.all, 'All'),
      (_ReportFilter.thisWeek, 'This week'),
      (_ReportFilter.strong, 'Strong 85+'),
      (_ReportFilter.needsAttention, 'Needs attention'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _Chip(
              label: items[i].$2,
              selected: value == items[i].$1,
              onTap: () => onChanged(items[i].$1),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppLux.radiusLg),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: AppLux.chip(selected: selected),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.05,
              color: selected ? AppLux.tealDeep : AppLux.body,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Report card ──────────────────────────────────────────────────────────────

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    required this.absoluteDate,
    required this.scoreColor,
    required this.emphasize,
    required this.onOpen,
    required this.onDelete,
    this.comparison,
  });

  final SavedReport report;
  final String absoluteDate;
  final Color scoreColor;
  final bool emphasize;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final ScoreComparison? comparison;

  @override
  Widget build(BuildContext context) {
    final top = report.report.topPriorityIssue;
    final condition = report.report.conditionLabel.trim().isEmpty
        ? 'Exterior assessment'
        : report.report.conditionLabel.trim();
    final range = report.report.estimatedRepairRange.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AppLux.radiusCard),
        splashColor: AppLux.teal.withValues(alpha: 0.04),
        highlightColor: AppLux.teal.withValues(alpha: 0.02),
        child: Ink(
          decoration: BoxDecoration(
            color: AppLux.surface,
            borderRadius: BorderRadius.circular(AppLux.radiusCard),
            border: Border.all(
              color: emphasize
                  ? AppLux.teal.withValues(alpha: 0.22)
                  : AppLux.border,
              width: emphasize ? 1.0 : AppLux.borderWidth,
            ),
            boxShadow: AppLux.cardShadow(intensity: emphasize ? 1.0 : 0.7),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Score badge
                    Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scoreColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppLux.radiusLg),
                        border: Border.all(
                          color: scoreColor.withValues(alpha: 0.2),
                          width: 0.75,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${report.score}',
                            style: GoogleFonts.inter(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: scoreColor,
                              letterSpacing: -0.4,
                              height: 1.05,
                            ),
                          ),
                          Text(
                            'score',
                            style: GoogleFonts.inter(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: scoreColor.withValues(alpha: 0.85),
                              letterSpacing: 0.2,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (emphasize) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppLux.tealMist,
                                    borderRadius: BorderRadius.circular(
                                      AppLux.radiusPill,
                                    ),
                                    border: Border.all(
                                      color: AppLux.teal.withValues(alpha: 0.2),
                                      width: 0.5,
                                    ),
                                  ),
                                  child: Text(
                                    'LATEST',
                                    style: GoogleFonts.inter(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppLux.tealDeep,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                child: Text(
                                  '$absoluteDate · ${report.relativeDateLabel}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppLux.muted,
                                    letterSpacing: 0.05,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            condition,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppLux.charcoal,
                              letterSpacing: -0.25,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Delete report',
                      onPressed: onDelete,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: AppLux.muted,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                if (comparison != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        comparison!.trendIcon,
                        size: 15,
                        color: comparison!.accentColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          emphasize
                              ? comparison!.unchanged
                                    ? 'Unchanged vs last scan'
                                    : '${comparison!.pointsLabel} vs last scan'
                              : comparison!.unchanged
                              ? 'Same as latest (${comparison!.toScore})'
                              : '${comparison!.fromScore} → latest ${comparison!.toScore} · ${comparison!.pointsLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: comparison!.accentColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                // Top priority finding
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppLux.cardFill,
                    borderRadius: BorderRadius.circular(AppLux.radiusMd),
                    border: Border.all(
                      color: AppLux.borderSoft,
                      width: AppLux.borderWidth,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        top == null
                            ? Icons.check_circle_outline_rounded
                            : Icons.flag_outlined,
                        size: 16,
                        color: top == null
                            ? AppLux.teal
                            : top.severity == 'High'
                            ? AppLux.danger
                            : top.severity == 'Medium'
                            ? AppLux.warning
                            : AppLux.muted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          top == null
                              ? 'No priority findings flagged'
                              : 'Priority: ${top.storyTitle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppLux.charcoalMid,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                      if (top != null) ...[
                        const SizedBox(width: 6),
                        _SeverityPill(severity: top.severity),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Meta row
                Row(
                  children: [
                    _MetaChip(
                      icon: Icons.photo_library_outlined,
                      label:
                          '${report.photoCount} photo${report.photoCount == 1 ? '' : 's'}',
                    ),
                    const SizedBox(width: 8),
                    _MetaChip(
                      icon: Icons.list_alt_rounded,
                      label:
                          '${report.findingsCount} finding${report.findingsCount == 1 ? '' : 's'}',
                    ),
                    if (range.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: _MetaChip(
                          icon: Icons.payments_outlined,
                          label: range,
                          teal: true,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Open',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppLux.teal,
                            letterSpacing: 0.05,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: AppLux.teal,
                          size: 20,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SeverityPill extends StatelessWidget {
  const _SeverityPill({required this.severity});

  final String severity;

  @override
  Widget build(BuildContext context) {
    final Color fg;
    final Color bg;
    switch (severity) {
      case 'High':
        fg = AppLux.danger;
        bg = AppLux.dangerSoft;
      case 'Medium':
        fg = AppLux.warning;
        bg = AppLux.goldSoft;
      default:
        fg = AppLux.body;
        bg = AppLux.borderSoft;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppLux.radiusPill),
      ),
      child: Text(
        severity,
        style: GoogleFonts.inter(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.15,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label, this.teal = false});

  final IconData icon;
  final String label;
  final bool teal;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: teal ? AppLux.teal : AppLux.muted),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: teal ? AppLux.teal : AppLux.body,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Empty / no-match states ──────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppLux.pagePaddingH,
        24,
        AppLux.pagePaddingH,
        32,
      ),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      child: Column(
        children: [
          AppLux.emptyState(
            icon: Icons.folder_open_outlined,
            title: 'No reports yet',
            body:
                'Run a Full Assessment (6 guided photos) or a Quick Scan (1 photo). '
                'FirstSign saves each screening here so you can reopen it anytime.',
            action: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onStart,
                style: AppLux.primaryButton(minHeight: 50),
                child: Text(
                  'Start Full Assessment',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 15.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            decoration: AppLux.card(radius: AppLux.radius2xl),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppLux.tealMist,
                    borderRadius: BorderRadius.circular(AppLux.radiusMd),
                    border: Border.all(
                      color: AppLux.teal.withValues(alpha: 0.14),
                      width: AppLux.borderWidth,
                    ),
                  ),
                  child: const Icon(
                    Icons.bolt_rounded,
                    size: 20,
                    color: AppLux.teal,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'In a hurry?',
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppLux.charcoal,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Quick Scan uses one photo — faster, with lower confidence.',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          height: 1.4,
                          color: AppLux.body,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: AppLux.goldNote(radius: AppLux.radiusXl),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 18,
                  color: AppLux.gold,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    PrivacyCopy.reportsStayLocal,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                      color: AppLux.disclaimerInk,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoMatchState extends StatelessWidget {
  const _NoMatchState({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppLux.pagePaddingH,
        24,
        AppLux.pagePaddingH,
        32,
      ),
      child: AppLux.emptyState(
        icon: Icons.search_off_rounded,
        title: 'No matching reports',
        body:
            'Nothing matches this search or filter. Clear filters to see your full FirstSign history.',
        action: OutlinedButton(
          onPressed: onClear,
          style: AppLux.secondaryButton(minHeight: 46),
          child: Text(
            'Clear search & filters',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
