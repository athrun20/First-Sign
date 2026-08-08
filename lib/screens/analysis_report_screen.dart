import 'dart:async' show unawaited;
import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../models/analysis_models.dart';
import '../models/capture_models.dart';
import '../models/saved_report.dart';
import '../models/score_comparison.dart';
import '../services/exterior_analysis_service.dart';
import '../services/finding_feedback_store.dart';
import '../services/finding_retake_service.dart';
import '../services/quote_submit_service.dart';
import '../services/report_pdf_service.dart';
import '../services/report_store.dart';
import '../services/storage_exception.dart';
import '../widgets/condition_score_dial.dart';
import '../widgets/digital_twin_house.dart';
import '../widgets/photo_thumb.dart';
import '../widgets/score_compare.dart';
import '../widgets/surface_evidence_sheet.dart';
import 'request_quote_screen.dart';

/// Premium report tokens — Apple Health / Tesla calm luxury.
abstract final class _Lux {
  static const bg = Color(0xFFF6F7F9);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE4E8EE);
  static const charcoal = Color(0xFF0F172A);
  static const charcoalMid = Color(0xFF1E293B);
  static const body = Color(0xFF475569);
  static const muted = Color(0xFF94A3B8);
  static const emerald = Color(0xFF059669);
  static const emeraldDeep = Color(0xFF047857);
  static const emeraldMist = Color(0xFFECFDF5);
  static const navy = Color(0xFF0F2744);
  static const navyMist = Color(0xFFEEF2F7);
  static const gold = Color(0xFFD97706);
  static const danger = Color(0xFFB91C1C);

  static List<BoxShadow> softShadow({double intensity = 1}) => [
        BoxShadow(
          color: navy.withValues(alpha: 0.06 * intensity),
          blurRadius: 28,
          offset: const Offset(0, 12),
        ),
        BoxShadow(
          color: navy.withValues(alpha: 0.02 * intensity),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];

  static BoxDecoration card({double radius = 22}) => BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border, width: 1),
        boxShadow: softShadow(intensity: 0.85),
      );
}

/// Excellent · Good · Fair · Needs Attention from overall score.
String reportHealthLabel(int score) {
  if (score >= 92) return 'Excellent';
  if (score >= 85) return 'Good';
  if (score >= 70) return 'Fair';
  return 'Needs Attention';
}

Color reportHealthColor(int score) {
  if (score >= 92) return _Lux.emerald;
  if (score >= 85) return const Color(0xFF0D9488);
  if (score >= 70) return _Lux.gold;
  return _Lux.danger;
}

/// Timeline bucket for a finding (homeowner-friendly).
enum _TimelineBucket { today, days30, months6, months12 }

_TimelineBucket _bucketForIssue(AnalysisIssue issue) {
  switch (issue.severity) {
    case 'High':
      return issue.needsCloserPhoto || issue.confidence >= 85
          ? _TimelineBucket.today
          : _TimelineBucket.days30;
    case 'Medium':
      return _TimelineBucket.months6;
    default:
      return _TimelineBucket.months12;
  }
}

String _bucketTitle(_TimelineBucket b) {
  switch (b) {
    case _TimelineBucket.today:
      return 'Today';
    case _TimelineBucket.days30:
      return 'Within 30 Days';
    case _TimelineBucket.months6:
      return '6 Months';
    case _TimelineBucket.months12:
      return '12 Months';
  }
}

String _bucketHint(_TimelineBucket b) {
  switch (b) {
    case _TimelineBucket.today:
      return 'Look closely or get a closer photo';
    case _TimelineBucket.days30:
      return 'Schedule soon to limit weather risk';
    case _TimelineBucket.months6:
      return 'Plan with seasonal exterior work';
    case _TimelineBucket.months12:
      return 'Monitor and bundle with maintenance';
  }
}

class AnalysisReportScreen extends StatefulWidget {
  final List<CapturePhoto> photos;
  final AnalysisReport report;
  final String? savedReportId;

  const AnalysisReportScreen({
    super.key,
    required this.photos,
    required this.report,
    this.savedReportId,
  });

  @override
  State<AnalysisReportScreen> createState() => _AnalysisReportScreenState();
}

class _AnalysisReportScreenState extends State<AnalysisReportScreen>
    with TickerProviderStateMixin {
  final ReportPdfService _pdfService = ReportPdfService();
  bool _pdfBusy = false;
  bool _reanalyzing = false;

  late List<CapturePhoto> _photos;
  late AnalysisReport _report;
  String? _savedReportId;
  String? _retakeBanner;

  late final AnimationController _entranceController;
  late final AnimationController _scoreController;

  late final Animation<double> _scoreFade;
  late final Animation<double> _statsFade;
  late final Animation<double> _severityFade;
  late final Animation<double> _headerFade;
  late final List<Animation<double>> _issueFades;
  late final Animation<double> _footerFade;

  TwinZone _selectedZone = TwinZone.none;
  bool _overviewExpanded = false;
  bool _twinExpanded = false;

  @override
  void initState() {
    super.initState();
    _photos = List<CapturePhoto>.from(widget.photos);
    _report = widget.report;
    _savedReportId = widget.savedReportId;
    unawaited(
      FindingFeedbackStore.instance.ensureLoaded().then((_) {
        if (mounted) setState(() {});
      }),
    );
    final issueCount = max(1, _report.issues.length);
    final totalSlots = 4 + issueCount + 1;

    _entranceController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 520 + totalSlots * 140),
    );

    _scoreController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    Animation<double> slot(int index) {
      final start = (index / totalSlots) * 0.85;
      final end = ((index + 1.15) / totalSlots).clamp(0.0, 1.0);
      return CurvedAnimation(
        parent: _entranceController,
        curve: Interval(start, end, curve: Curves.easeOutCubic),
      );
    }

    _scoreFade = slot(0);
    _statsFade = slot(1);
    _severityFade = slot(2);
    _headerFade = slot(3);
    _issueFades = List.generate(issueCount, (i) => slot(4 + i));
    _footerFade = slot(4 + issueCount);

    unawaited(_entranceController.forward());
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 180), () {
        if (mounted) unawaited(_scoreController.forward());
      }),
    );
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _scoreController.dispose();
    super.dispose();
  }

  CapturePhoto? _photoForIssue(AnalysisIssue issue, {int? fallbackIndex}) {
    final photos = _photos;
    if (photos.isEmpty) return null;

    if (issue.photoIndex != null) {
      final byIndex = issue.photoIndex!;
      if (byIndex >= 0 && byIndex < photos.length) return photos[byIndex];
    }

    final label = issue.sourcePhotoLabel.trim().toLowerCase();
    if (label.isNotEmpty) {
      for (final p in photos) {
        if (p.label.toLowerCase() == label) return p;
      }
    }

    if (fallbackIndex != null &&
        fallbackIndex >= 0 &&
        fallbackIndex < photos.length) {
      return photos[fallbackIndex];
    }
    return photos.first;
  }

  void _openSurfaceEvidence(
    AnalysisIssue issue, {
    int? issueIndex,
    int? photoIndex,
  }) {
    final shot = _photoForIssue(issue, fallbackIndex: photoIndex);
    final findingIndex = issueIndex != null ? issueIndex + 1 : null;

    // Multi-angle: other capture photos in the same session.
    final related = <SurfaceEvidenceAngle>[
      for (final p in _photos)
        if (shot == null || p.index != shot.index)
          SurfaceEvidenceAngle(
            label: p.label,
            photo: p.file,
          ),
    ];

    unawaited(
      showSurfaceEvidenceSheet(
        context: context,
        issue: issue,
        photo: shot?.file,
        findingIndex: findingIndex,
        sourcePhotoLabel: issue.sourcePhotoDisplay.isNotEmpty
            ? issue.sourcePhotoDisplay
            : shot?.label,
        relatedAngles: related.take(4).toList(),
        timeline: _evidenceTimelineFor(issue),
        onRetake: _reanalyzing
            ? null
            : () {
                Navigator.of(context).pop();
                unawaited(_retakeForIssue(issue));
              },
      ),
    );
  }

  /// Build a prior-scan timeline when history has a matching finding.
  SurfaceEvidenceTimeline? _evidenceTimelineFor(AnalysisIssue issue) {
    final reports = ReportStore.instance.reports;
    if (reports.length < 2) return null;

    // Prefer the report just older than the current saved id, else second newest.
    SavedReport? prior;
    final id = _savedReportId;
    if (id != null) {
      final idx = reports.indexWhere((r) => r.id == id);
      if (idx >= 0 && idx + 1 < reports.length) {
        prior = reports[idx + 1];
      }
    }
    prior ??= reports.length > 1 ? reports[1] : null;
    if (prior == null) return null;

    // Match by twin zone first, then soft title overlap.
    AnalysisIssue? match;
    for (final p in prior.report.issues) {
      if (p.twinZone == issue.twinZone && p.twinZone != TwinZone.none) {
        match = p;
        break;
      }
    }
    match ??= prior.report.issues.cast<AnalysisIssue?>().firstWhere(
          (p) =>
              p != null &&
              (p.title.toLowerCase().contains(
                    issue.title.toLowerCase().split(' ').first,
                  ) ||
                  issue.title.toLowerCase().contains(
                    p.title.toLowerCase().split(' ').first,
                  )),
          orElse: () => null,
        );
    if (match == null) return null;

    XFile? priorPhoto;
    final pi = match.photoIndex;
    if (pi != null && pi >= 0 && pi < prior.photos.length) {
      final bytes = prior.photos[pi].bytes;
      if (bytes.isNotEmpty) {
        priorPhoto = XFile.fromData(
          bytes,
          name: 'prior_$pi.jpg',
          mimeType: 'image/jpeg',
        );
      }
    } else if (prior.photos.isNotEmpty && prior.photos.first.bytes.isNotEmpty) {
      final bytes = prior.photos.first.bytes;
      priorPhoto = XFile.fromData(
        bytes,
        name: 'prior_0.jpg',
        mimeType: 'image/jpeg',
      );
    }

    double? areaDelta;
    final a = issue.surfaceHighlight;
    final b = match.surfaceHighlight;
    if (a != Rect.zero && b != Rect.zero) {
      final cur = a.width * a.height;
      final old = b.width * b.height;
      if (old > 0.0001) {
        areaDelta = ((cur - old) / old) * 100;
      }
    }

    String fmt(DateTime d) =>
        '${d.month}/${d.day}/${d.year.toString().substring(2)}';

    return SurfaceEvidenceTimeline(
      priorLabel: 'Prior scan',
      currentLabel: 'This scan',
      priorPhoto: priorPhoto,
      priorHighlight: match.surfaceHighlight == Rect.zero
          ? null
          : match.surfaceHighlight,
      priorDateLabel: fmt(prior.createdAt),
      currentDateLabel: 'Now',
      areaChangePercent: areaDelta,
    );
  }

  void _openSurfaceEvidenceForPhoto(int photoIndex) {
    final issues = _report.issues;
    if (issues.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No surface findings linked to this photo yet.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final bound = issues.indexWhere((i) => i.photoIndex == photoIndex);
    final issueIndex = bound >= 0 ? bound : 0;
    final issue = bound >= 0
        ? issues[bound]
        : issues[issueIndex].copyWith(
            photoIndex: photoIndex,
            sourcePhotoLabel: _photos[photoIndex].label,
          );

    _openSurfaceEvidence(issue, issueIndex: issueIndex, photoIndex: photoIndex);
  }

  Widget _reveal(Animation<double> animation, Widget child) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - t)),
            child: Transform.scale(
              scale: 0.97 + (0.03 * t),
              alignment: Alignment.topCenter,
              child: child,
            ),
          ),
        );
      },
    );
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'High':
        return _Lux.danger;
      case 'Medium':
        return _Lux.gold;
      default:
        return _Lux.emerald;
    }
  }

  Color _scoreColor(int score) => reportHealthColor(score);

  void _requestQuote() {
    if (!QuoteSubmitConfig.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Quote email is not configured in this build. '
            'You can still share a PDF, or save a local pro lead from the form’s offline option.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 5),
        ),
      );
    }
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RequestQuoteScreen(
            report: _report,
            photos: _photos,
            savedReportId: _savedReportId,
          ),
        ),
      ),
    );
  }

  Future<void> _markFindingWrong(AnalysisIssue issue) async {
    await FindingFeedbackStore.instance.markWrong(
      reportId: _savedReportId,
      title: issue.homeownerTitle,
      location: issue.location,
    );
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Thanks — marked as looks wrong. Stored only on this device for calibration.',
        ),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ),
    );
  }

  CaptureShotId _slotForIssue(AnalysisIssue issue) {
    return FindingRetakeService.preferredSlot(
      issue,
      boundPhoto: _photoForIssue(issue),
    );
  }

  Future<void> _retakeForIssue(AnalysisIssue issue) async {
    if (_reanalyzing) return;
    final focus = _slotForIssue(issue);
    final result = await Navigator.of(context).pushNamed(
      '/guided-capture',
      arguments: {
        'seed': _photos,
        'focus': focus,
        'retakeMode': true,
        'findingTitle': issue.title,
      },
    );
    if (!mounted) return;
    if (result is! List<CapturePhoto> || result.isEmpty) return;
    await _reanalyzeAfterRetake(result, previousIssue: issue);
  }

  Future<void> _reanalyzeAfterRetake(
    List<CapturePhoto> photos, {
    required AnalysisIssue previousIssue,
  }) async {
    if (_reanalyzing) return;
    setState(() {
      _reanalyzing = true;
      _retakeBanner = null;
    });

    final before = _report;
    try {
      final report = await ExteriorAnalysisService().analyzeCapture(photos);
      final saved = await ReportStore.instance.saveFromCapture(
        report: report,
        photos: photos,
        id: _savedReportId,
      );
      if (!mounted) return;
      final summary = FindingRetakeService.changeSummary(
        before: before,
        after: report,
        previousIssue: previousIssue,
      );
      setState(() {
        _photos = photos;
        _report = report;
        _savedReportId = saved.id;
        _retakeBanner = summary;
        _reanalyzing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(summary),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    } on StorageFullException catch (e) {
      if (!mounted) return;
      setState(() => _reanalyzing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.userMessage),
          backgroundColor: Colors.orange.shade800,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _reanalyzing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Re-analysis failed: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _sharePdf({
    PdfExportAction action = PdfExportAction.share,
  }) async {
    if (_pdfBusy) return;
    setState(() => _pdfBusy = true);
    try {
      await _pdfService.export(_report, action: action);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_pdfService.successMessage(action)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not share PDF: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  Future<void> _showPdfActions() async {
    if (_pdfBusy) return;
    final choice = await showModalBottomSheet<PdfExportAction>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    'Share screening PDF',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.ios_share_rounded),
                  title: const Text('Share / download PDF'),
                  subtitle: const Text('Send the file or save it to Downloads'),
                  onTap: () => Navigator.pop(ctx, PdfExportAction.share),
                ),
                ListTile(
                  leading: const Icon(Icons.print_outlined),
                  title: const Text('Print / preview'),
                  subtitle: const Text('Open the system print dialog'),
                  onTap: () => Navigator.pop(ctx, PdfExportAction.print),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        );
      },
    );
    if (choice == null || !mounted) return;
    await _sharePdf(action: choice);
  }

  List<AnalysisIssue> get _orderedIssues => _report.issuesByPriority;

  List<AnalysisIssue> get _visibleIssues {
    final all = _orderedIssues;
    if (_selectedZone == TwinZone.none) return all;
    return all.where((i) => i.twinZone == _selectedZone).toList();
  }

  void _onTwinZoneSelected(TwinZone zone) {
    setState(() {
      _selectedZone = _selectedZone == zone ? TwinZone.none : zone;
    });
  }

  String _zoneLabel(TwinZone zone) {
    switch (zone) {
      case TwinZone.roof:
        return 'Roof';
      case TwinZone.siding:
        return 'Siding';
      case TwinZone.windows:
        return 'Windows';
      case TwinZone.foundation:
        return 'Foundation';
      case TwinZone.gutters:
        return 'Gutters';
      case TwinZone.none:
        return 'All zones';
    }
  }

  ScoreComparison? _scoreComparison() {
    final id = _savedReportId;
    if (id == null) return null;
    return ScoreComparison.forSavedReport(
      reportId: id,
      reports: ReportStore.instance.reports,
      liveScore: _report.overallScore,
    );
  }

  SavedReport? _otherCompareReport(ScoreComparison comparison) {
    final id = _savedReportId;
    if (id == null) return null;
    final reports = ReportStore.instance.reports;
    if (reports.length < 2) return null;
    final idx = reports.indexWhere((r) => r.id == id);
    if (idx < 0) return null;
    if (idx == 0) return reports[1];
    return reports.first;
  }

  Future<void> _openComparedReport(SavedReport other) async {
    if (!mounted) return;
    await Navigator.of(context).pushNamed('/saved-report', arguments: other);
  }

  bool _photoHasFindings(CapturePhoto shot) {
    for (final i in _report.issues) {
      if (i.photoIndex == shot.index) return true;
      final label = i.sourcePhotoLabel.trim().toLowerCase();
      if (label.isNotEmpty && shot.label.toLowerCase() == label) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final allIssues = _orderedIssues;
    final issues = _visibleIssues;
    final scoreColor = _scoreColor(report.overallScore);
    final scoreCompare = _scoreComparison();
    final compareOther =
        scoreCompare == null ? null : _otherCompareReport(scoreCompare);

    return Scaffold(
      backgroundColor: _Lux.bg,
      appBar: AppBar(
        backgroundColor: _Lux.bg.withValues(alpha: 0.92),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        title: Text(
          'Home Health',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 17,
            letterSpacing: -0.25,
            color: _Lux.charcoal,
          ),
        ),
        iconTheme: const IconThemeData(color: _Lux.charcoal),
        actionsIconTheme: const IconThemeData(color: _Lux.charcoalMid),
        actions: [
          if (_pdfBusy || _reanalyzing)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.ios_share_rounded),
              tooltip: 'Share PDF',
              onPressed: () => _sharePdf(action: PdfExportAction.share),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: 'PDF options',
              onPressed: _showPdfActions,
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          // Ambient depth
          Positioned(
            top: -80,
            right: -60,
            child: IgnorePointer(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _Lux.emerald.withValues(alpha: 0.08),
                      _Lux.emerald.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 220,
            left: -100,
            child: IgnorePointer(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _Lux.navy.withValues(alpha: 0.05),
                      _Lux.navy.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 56),
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_retakeBanner != null) ...[
                  _buildRetakeBanner(),
                  const SizedBox(height: 16),
                ],
                // ── How healthy is my home? ─────────────────────────────
                _reveal(
                  _scoreFade,
                  _buildHealthHero(report, scoreColor),
                ),
                if (scoreCompare != null) ...[
                  const SizedBox(height: 14),
                  _reveal(
                    _scoreFade,
                    ScoreCompareStrip(
                      comparison: scoreCompare,
                      onOpenOther: compareOther == null
                          ? null
                          : () => _openComparedReport(compareOther),
                      otherActionLabel: compareOther == null
                          ? null
                          : scoreCompare.toLabel == 'Latest scan'
                              ? 'Open latest scan'
                              : 'Open last scan',
                    ),
                  ),
                ],
                if (report.isSinglePhotoScan) ...[
                  const SizedBox(height: 12),
                  _reveal(_statsFade, _buildQuickScanNote()),
                ],
                // ── Findings as modern cards ────────────────────────────
                const SizedBox(height: 28),
                _reveal(
                  _headerFade,
                  _sectionLabel(
                    _selectedZone == TwinZone.none
                        ? 'Findings'
                        : '${_zoneLabel(_selectedZone)} findings',
                    allIssues.isEmpty ? 'None' : '${issues.length}',
                  ),
                ),
                const SizedBox(height: 6),
                _reveal(
                  _headerFade,
                  Text(
                    allIssues.isEmpty
                        ? 'Nothing elevated from this screening pass.'
                        : 'Each card is one observation — severity, confidence, and planning cost.',
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      height: 1.4,
                      color: _Lux.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (allIssues.isEmpty)
                  _reveal(_issueFades.first, _buildEmptyIssuesCard())
                else if (issues.isEmpty)
                  _reveal(_issueFades.first, _buildNoZoneMatchCard())
                else
                  ...List.generate(issues.length, (index) {
                    final issue = issues[index];
                    final globalIndex = allIssues.indexOf(issue);
                    final displayIndex =
                        (globalIndex >= 0 ? globalIndex : index) + 1;
                    return _reveal(
                      _issueFades[(globalIndex >= 0 ? globalIndex : index)
                          .clamp(0, _issueFades.length - 1)],
                      _buildFindingCard(issue, displayIndex),
                    );
                  }),
                // ── Recommended timeline ────────────────────────────────
                if (allIssues.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _reveal(
                    _severityFade,
                    _buildTimelineSection(allIssues),
                  ),
                ],
                // ── Photo gallery ───────────────────────────────────────
                if (_photos.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _reveal(_severityFade, _buildPhotoGallery()),
                ],
                // ── Cost + savings ──────────────────────────────────────
                const SizedBox(height: 28),
                _reveal(
                  _footerFade,
                  _buildCostSummary(report),
                ),
                if (allIssues.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _reveal(
                    _footerFade,
                    _buildPotentialSavings(report),
                  ),
                ],
                // ── Secondary: overview, twin, disclaimer, CTAs ─────────
                const SizedBox(height: 28),
                _reveal(_footerFade, _buildCollapsibleOverview(report)),
                const SizedBox(height: 12),
                _reveal(_footerFade, _buildTwinViewCard(report)),
                const SizedBox(height: 16),
                _reveal(_footerFade, _buildDisclaimerCard()),
                const SizedBox(height: 24),
                _reveal(_footerFade, _buildActionBar()),
              ],
            ),
          ),
          if (_reanalyzing)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.28),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Re-running screening…',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String title, String badge) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _Lux.charcoal,
              letterSpacing: -0.45,
              height: 1.2,
            ),
          ),
        ),
        Text(
          badge,
          style: GoogleFonts.inter(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: _Lux.muted,
          ),
        ),
      ],
    );
  }

  Widget _buildRetakeBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: _Lux.emeraldMist.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _Lux.emerald.withValues(alpha: 0.14),
          width: 0.75,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.check_circle_outline_rounded,
              color: _Lux.emerald,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _retakeBanner!,
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w500,
                color: _Lux.emeraldDeep,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _retakeBanner = null),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }

  /// Hero: answers “How healthy is my home?”
  Widget _buildHealthHero(AnalysisReport report, Color scoreColor) {
    final label = reportHealthLabel(report.overallScore);
    final isDemo = report.analysisSource.toLowerCase().contains('demo');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: _Lux.emerald.withValues(alpha: 0.12),
          width: 1,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _Lux.surface,
            _Lux.emeraldMist.withValues(alpha: 0.55),
            _Lux.navyMist.withValues(alpha: 0.4),
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        boxShadow: _Lux.softShadow(intensity: 1.1),
      ),
      child: Column(
        children: [
          Text(
            isDemo ? 'Demo · Home Health Score' : 'How healthy is my home?',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _Lux.muted,
              letterSpacing: 0.15,
            ),
          ),
          const SizedBox(height: 18),
          ConditionScoreDial(
            key: ValueKey(report.overallScore),
            score: report.overallScore,
            accent: scoreColor,
            size: 200,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: scoreColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: scoreColor.withValues(alpha: 0.22),
              ),
            ),
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: scoreColor,
                letterSpacing: -0.1,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            report.calmHeadline,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 16.5,
              fontWeight: FontWeight.w500,
              color: _Lux.charcoal,
              height: 1.4,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            AnalysisReport.screeningBadge,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: _Lux.muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickScanNote() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _Lux.gold.withValues(alpha: 0.2),
          width: 0.75,
        ),
      ),
      child: Text(
        'Quick Scan · one photo only. Other elevations are not covered — '
        'treat findings as a first look. Run a Full Assessment for multi-angle confidence.',
        style: GoogleFonts.inter(
          fontSize: 13,
          height: 1.45,
          color: _Lux.body,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildFindingCard(AnalysisIssue issue, int index) {
    final sevColor = _severityColor(issue.severity);
    final slotLabel =
        FindingRetakeService.slotCoachLabel(_slotForIssue(issue)).toLowerCase();
    final markedWrong = FindingFeedbackStore.instance.isMarkedWrong(
      reportId: _savedReportId,
      title: issue.homeownerTitle,
      location: issue.location,
    );
    final costShort = issue.cost.trim().isEmpty ||
            issue.cost.toUpperCase() == 'TBD'
        ? 'TBD'
        : issue.cost.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openSurfaceEvidence(issue, issueIndex: index - 1),
        borderRadius: BorderRadius.circular(22),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: _Lux.card(radius: 22),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 3.5,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      sevColor,
                      sevColor.withValues(alpha: 0.35),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            issue.homeownerTitle,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              fontSize: 16.5,
                              color: _Lux.charcoal,
                              height: 1.28,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _pill(issue.severity, sevColor),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      issue.location,
                      style: GoogleFonts.inter(
                        color: _Lux.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Meta chips: confidence · cost
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _metaChip(
                          Icons.shield_outlined,
                          '${issue.confidence}% confidence',
                          _Lux.navy,
                        ),
                        _metaChip(
                          Icons.payments_outlined,
                          costShort,
                          _Lux.charcoalMid,
                        ),
                        if (issue.needsCloserPhoto)
                          _metaChip(
                            Icons.photo_camera_outlined,
                            'Closer photo helps',
                            _Lux.gold,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      issue.displayInsight,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        height: 1.45,
                        color: _Lux.body,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          'View evidence',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _Lux.emeraldDeep,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: _Lux.emerald.withValues(alpha: 0.85),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: _reanalyzing
                              ? null
                              : () => _retakeForIssue(issue),
                          style: TextButton.styleFrom(
                            foregroundColor: issue.needsCloserPhoto
                                ? _Lux.gold
                                : _Lux.emeraldDeep,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            visualDensity: VisualDensity.compact,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            issue.needsCloserPhoto
                                ? 'Retake'
                                : 'Retake $slotLabel',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: markedWrong
                              ? null
                              : () => _markFindingWrong(issue),
                          style: TextButton.styleFrom(
                            foregroundColor: _Lux.muted,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            visualDensity: VisualDensity.compact,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            markedWrong ? 'Flagged' : 'Looks wrong',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _Lux.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _Lux.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color.withValues(alpha: 0.85)),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: _Lux.charcoalMid,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineSection(List<AnalysisIssue> issues) {
    final buckets = <_TimelineBucket, List<AnalysisIssue>>{
      for (final b in _TimelineBucket.values) b: [],
    };
    for (final i in issues) {
      buckets[_bucketForIssue(i)]!.add(i);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Recommended Timeline', ''),
        const SizedBox(height: 6),
        Text(
          'A calm plan for what to do now versus later.',
          style: GoogleFonts.inter(
            fontSize: 13.5,
            color: _Lux.muted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 14),
        for (final b in _TimelineBucket.values) ...[
          _timelineRow(
            bucket: b,
            items: buckets[b]!,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _timelineRow({
    required _TimelineBucket bucket,
    required List<AnalysisIssue> items,
  }) {
    final accent = switch (bucket) {
      _TimelineBucket.today => _Lux.danger,
      _TimelineBucket.days30 => _Lux.gold,
      _TimelineBucket.months6 => const Color(0xFF0D9488),
      _TimelineBucket.months12 => _Lux.emerald,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: _Lux.card(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent,
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _bucketTitle(bucket),
                style: GoogleFonts.inter(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: _Lux.charcoal,
                  letterSpacing: -0.15,
                ),
              ),
              const Spacer(),
              Text(
                items.isEmpty ? 'Clear' : '${items.length}',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: items.isEmpty ? _Lux.emerald : _Lux.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            items.isEmpty ? _bucketHint(bucket) : _bucketHint(bucket),
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: _Lux.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final issue in items.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Icon(
                        Icons.circle,
                        size: 5,
                        color: accent.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        issue.homeownerTitle,
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: _Lux.charcoalMid,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (items.length > 3)
              Text(
                '+ ${items.length - 3} more',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _Lux.muted,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildPhotoGallery() {
    final photos = _photos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Photo gallery', '${photos.length}'),
        const SizedBox(height: 6),
        Text(
          'Green = no linked findings · Amber/red = problem area in this scan.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: _Lux.muted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final shot = photos[index];
              final problem = _photoHasFindings(shot);
              final borderColor = problem
                  ? (shot.index % 2 == 0
                      ? _Lux.gold.withValues(alpha: 0.55)
                      : _Lux.danger.withValues(alpha: 0.45))
                  : _Lux.emerald.withValues(alpha: 0.45);

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _openSurfaceEvidenceForPhoto(shot.index),
                  borderRadius: BorderRadius.circular(16),
                  child: Ink(
                    width: 100,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor, width: 1.5),
                      boxShadow: _Lux.softShadow(intensity: 0.5),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14.5),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          PhotoThumb(photo: shot.file),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: problem ? _Lux.gold : _Lux.emerald,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 5,
                              ),
                              color: Colors.black.withValues(alpha: 0.5),
                              child: Text(
                                shot.shortLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCostSummary(AnalysisReport report) {
    final range = report.estimatedRepairRange.trim().isEmpty
        ? 'TBD'
        : report.estimatedRepairRange.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _Lux.surface,
            _Lux.navyMist.withValues(alpha: 0.65),
          ],
        ),
        border: Border.all(color: _Lux.border),
        boxShadow: _Lux.softShadow(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Repair cost summary',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _Lux.muted,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            range,
            style: GoogleFonts.inter(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: _Lux.charcoal,
              letterSpacing: -0.7,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Planning range only — not a contractor bid. Confirm on-site.',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: _Lux.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (report.highCount + report.mediumCount + report.lowCount > 0) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                _costStat('High', report.highCount, _Lux.danger),
                const SizedBox(width: 10),
                _costStat('Medium', report.mediumCount, _Lux.gold),
                const SizedBox(width: 10),
                _costStat('Low', report.lowCount, _Lux.emerald),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _costStat(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: _Lux.surface.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _Lux.border),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: _Lux.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPotentialSavings(AnalysisReport report) {
    final high = report.highCount;
    final medium = report.mediumCount;
    // Heuristic narrative — not a calculated bid.
    final factor = high > 0
        ? '2–3×'
        : medium > 0
            ? '1.5–2×'
            : '1.2–1.5×';
    final headline = high > 0
        ? 'Fixing high-priority items early can prevent damage that often costs $factor more later.'
        : medium > 0
            ? 'Planning medium items this season can avoid the $factor jump that weather and delay often bring.'
            : 'Staying ahead of minor notes keeps costs near routine maintenance — not emergency repairs.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _Lux.emeraldMist,
            _Lux.surface,
          ],
        ),
        border: Border.all(
          color: _Lux.emerald.withValues(alpha: 0.18),
        ),
        boxShadow: _Lux.softShadow(intensity: 0.7),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              color: _Lux.emerald.withValues(alpha: 0.12),
            ),
            child: const Icon(
              Icons.savings_outlined,
              color: _Lux.emeraldDeep,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Potential savings',
                  style: GoogleFonts.inter(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: _Lux.charcoal,
                    letterSpacing: -0.15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  headline,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    height: 1.45,
                    fontWeight: FontWeight.w400,
                    color: _Lux.body,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Illustrative only — not a guarantee or bid.',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: _Lux.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyIssuesCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(26, 32, 26, 30),
      decoration: _Lux.card(),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _Lux.emerald.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: _Lux.emerald.withValues(alpha: 0.16),
              ),
            ),
            child: const Icon(
              Icons.verified_rounded,
              color: _Lux.emerald,
              size: 26,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Looking solid from these photos',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              fontSize: 17,
              color: _Lux.charcoal,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'FirstSign did not flag high-priority exterior defects. Keep seasonal maintenance, and re-scan after storms.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14.5,
              height: 1.45,
              color: _Lux.body,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoZoneMatchCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: _Lux.card(radius: 20),
      child: Column(
        children: [
          const Icon(
            Icons.filter_alt_off_outlined,
            color: _Lux.muted,
            size: 28,
          ),
          const SizedBox(height: 12),
          Text(
            'No findings in ${_zoneLabel(_selectedZone)}',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: _Lux.charcoal,
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _selectedZone = TwinZone.none),
            style: TextButton.styleFrom(foregroundColor: _Lux.emeraldDeep),
            child: const Text('Show all findings'),
          ),
        ],
      ),
    );
  }

  Widget _buildDisclaimerCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: _Lux.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Lux.border, width: 0.75),
      ),
      child: Text(
        AnalysisReport.screeningDisclaimer,
        style: GoogleFonts.inter(
          fontSize: 12.5,
          height: 1.5,
          color: _Lux.muted,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildCollapsibleOverview(AnalysisReport report) {
    final chapters = report.storyChapters;
    const plainTitles = <String>[
      'Condition',
      'Priority',
      'What to do',
      'Why it matters',
    ];

    return Container(
      width: double.infinity,
      decoration: _Lux.card(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _overviewExpanded = !_overviewExpanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Full story',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _Lux.charcoal,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Optional deeper read',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: _Lux.muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _overviewExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: _Lux.muted,
                  ),
                ],
              ),
            ),
          ),
          if (_overviewExpanded) ...[
            const Divider(height: 1, thickness: 0.75, color: _Lux.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < chapters.length; i++) ...[
                    if (i > 0) const SizedBox(height: 16),
                    Text(
                      i < plainTitles.length
                          ? plainTitles[i]
                          : chapters[i].title,
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: _Lux.charcoal,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      chapters[i].body,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        height: 1.5,
                        color: _Lux.body,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTwinViewCard(AnalysisReport report) {
    final marked = report.markedTwinZones;
    final width = MediaQuery.sizeOf(context).width;
    final twinSize = (width - 72).clamp(220.0, 280.0);

    return Container(
      width: double.infinity,
      decoration: _Lux.card(radius: 20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _twinExpanded = !_twinExpanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _Lux.emeraldMist,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.view_in_ar_rounded,
                      size: 18,
                      color: _Lux.emerald,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI Digital Twin',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _Lux.charcoal,
                          ),
                        ),
                        Text(
                          _selectedZone == TwinZone.none
                              ? 'Living model · tap a zone to filter findings'
                              : 'Focused: ${_zoneLabel(_selectedZone)}',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: _Lux.muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_selectedZone != TwinZone.none)
                    TextButton(
                      onPressed: () =>
                          setState(() => _selectedZone = TwinZone.none),
                      style: TextButton.styleFrom(
                        foregroundColor: _Lux.emeraldDeep,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Clear'),
                    ),
                  Icon(
                    _twinExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: _Lux.muted,
                  ),
                ],
              ),
            ),
          ),
          if (_twinExpanded) ...[
            const Divider(height: 1, thickness: 0.75, color: _Lux.border),
            Container(
              width: double.infinity,
              color: _Lux.bg,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                children: [
                  Center(
                    child: DigitalTwinHouse(
                      size: twinSize,
                      selectedZone: _selectedZone,
                      onZoneSelected: _onTwinZoneSelected,
                      autoRotate: _selectedZone == TwinZone.none,
                      showMarkers: marked.isNotEmpty,
                      markedZones: marked,
                      compact: false,
                    ),
                  ),
                  if (marked.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final z in TwinZone.values)
                          if (z != TwinZone.none && marked.contains(z))
                            ActionChip(
                              label: Text(
                                _zoneLabel(z),
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _selectedZone == z
                                      ? Colors.white
                                      : _Lux.charcoal,
                                ),
                              ),
                              backgroundColor: _selectedZone == z
                                  ? _Lux.emerald
                                  : _Lux.surface,
                              side: BorderSide(
                                color: _selectedZone == z
                                    ? _Lux.emerald
                                    : _Lux.border,
                              ),
                              onPressed: () => _onTwinZoneSelected(z),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    final quoteReady = QuoteSubmitConfig.isConfigured;
    return Column(
      children: [
        if (!quoteReady) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _Lux.gold.withValues(alpha: 0.18),
              ),
            ),
            child: Text(
              'Email delivery is not configured in this build. You can still '
              'share a PDF, or save a local contractor lead offline.',
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.4,
                color: _Lux.body,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
        SizedBox(
          width: double.infinity,
          height: 54,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF10B981),
                  _Lux.emerald,
                  _Lux.emeraldDeep,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: _Lux.emerald.withValues(alpha: 0.28),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _requestQuote,
                borderRadius: BorderRadius.circular(16),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        quoteReady
                            ? Icons.request_quote_rounded
                            : Icons.save_alt_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        quoteReady
                            ? 'Request a quote'
                            : 'Save lead / request quote',
                        style: GoogleFonts.inter(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonal(
            onPressed: _pdfBusy
                ? null
                : () => _sharePdf(action: PdfExportAction.share),
            style: FilledButton.styleFrom(
              foregroundColor: _Lux.charcoal,
              backgroundColor: _Lux.border.withValues(alpha: 0.55),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_pdfBusy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  const Icon(Icons.ios_share_rounded, size: 18),
                const SizedBox(width: 8),
                Text(
                  _pdfBusy ? 'Preparing PDF…' : 'Share PDF',
                  style: GoogleFonts.inter(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: TextButton(
            onPressed: _pdfBusy ? null : _showPdfActions,
            style: TextButton.styleFrom(foregroundColor: _Lux.body),
            child: const Text('More PDF options (print)'),
          ),
        ),
      ],
    );
  }
}
