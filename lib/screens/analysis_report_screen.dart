import 'dart:async' show unawaited;
import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../legal/cost_copy.dart';
import '../legal/privacy_copy.dart';
import '../models/analysis_models.dart';
import '../models/capture_models.dart';
import '../models/saved_report.dart';
import '../models/score_comparison.dart';
import '../services/evidence_timeline.dart';
import '../services/exterior_analysis_service.dart';
import '../services/finding_feedback_store.dart';
import '../services/finding_retake_service.dart';
import '../services/quote_submit_service.dart';
import '../services/report_pdf_service.dart';
import '../services/report_store.dart';
import '../services/storage_exception.dart';
import '../widgets/closer_photo_tip.dart';
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

/// Excellent · Good · Stable · Needs Attention from overall score.
///
/// 80+ is Good so an 81 with no emergency does not read as "Fair".
String reportHealthLabel(int score) {
  if (score >= 92) return 'Excellent';
  if (score >= 80) return 'Good';
  if (score >= 68) return 'Stable';
  return 'Needs Attention';
}

Color reportHealthColor(int score) {
  if (score >= 92) return _Lux.emerald;
  if (score >= 80) return const Color(0xFF0D9488);
  if (score >= 68) return _Lux.emeraldDeep;
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
      return 'Look closely or take a closer photo';
    case _TimelineBucket.days30:
      return 'Schedule a look this month';
    case _TimelineBucket.months6:
      return 'Plan with seasonal exterior work';
    case _TimelineBucket.months12:
      return 'Monitor and bundle with maintenance';
  }
}

String _bucketEmptyState(_TimelineBucket b) {
  switch (b) {
    case _TimelineBucket.today:
    case _TimelineBucket.days30:
      return 'No urgent action';
    case _TimelineBucket.months6:
    case _TimelineBucket.months12:
      return 'No planned work';
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

  late final Animation<double> _scoreFade;
  late final Animation<double> _statsFade;
  late final Animation<double> _severityFade;
  late final Animation<double> _headerFade;
  late final List<Animation<double>> _issueFades;
  late final Animation<double> _footerFade;

  TwinZone _selectedZone = TwinZone.none;
  bool _overviewExpanded = false;

  final _scrollController = ScrollController();
  final _findingsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _photos = List<CapturePhoto>.from(widget.photos);
    _report = widget.report.copyWith(
      issues: FindingRetakeService.rebindIssues(
        issues: widget.report.issues,
        photos: _photos,
      ),
    );
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
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  CapturePhoto? _photoForIssue(AnalysisIssue issue, {int? fallbackIndex}) {
    return FindingRetakeService.primaryEvidencePhoto(
      issue: issue,
      photos: _photos,
      fallbackIndex: fallbackIndex,
    );
  }

  void _openSurfaceEvidence(
    AnalysisIssue issue, {
    int? issueIndex,
    int? photoIndex,
    int? focusPhotoIndex,
  }) {
    final shot = _photoForIssue(issue, fallbackIndex: photoIndex);
    final findingIndex = issueIndex != null ? issueIndex + 1 : null;
    final rematchedAway =
        shot != null &&
        issue.photoIndex != null &&
        issue.photoIndex != shot.index;
    final evidenceIssue = rematchedAway
        ? issue.copyWith(clearHighlight: true)
        : issue;

    // Multi-angle: other exterior capture photos in the same session.
    // Primary is always a photo that supports the finding; others may be
    // related context only.
    final relatedPhotos = [
      for (final p in _photos)
        if ((shot == null || p.index != shot.index) &&
            !FindingRetakeService.looksNonExteriorPhoto(p))
          p,
    ].take(4).toList();
    final related = [
      for (final p in relatedPhotos)
        SurfaceEvidenceAngle(
          label: p.label,
          photo: p.file,
          supportsFinding: FindingRetakeService.photoSupportsIssue(issue, p),
        ),
    ];

    var initialAngleIndex = 0;
    if (focusPhotoIndex != null) {
      if (shot != null && shot.index == focusPhotoIndex) {
        initialAngleIndex = 0;
      } else {
        final ri = relatedPhotos.indexWhere((p) => p.index == focusPhotoIndex);
        if (ri >= 0) {
          initialAngleIndex = ri + (shot != null ? 1 : 0);
        }
      }
    }

    unawaited(
      showSurfaceEvidenceSheet(
        context: context,
        issue: evidenceIssue,
        photo: shot?.file,
        findingIndex: findingIndex,
        sourcePhotoLabel: shot?.label ?? issue.sourcePhotoDisplay,
        relatedAngles: related,
        initialAngleIndex: initialAngleIndex,
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

  /// Build a prior-scan timeline only when a comparable photo exists.
  SurfaceEvidenceTimeline? _evidenceTimelineFor(AnalysisIssue issue) {
    final prior = _priorSavedReport();
    if (prior == null) return null;

    final match = EvidenceTimelinePairing.matchPriorIssue(
      issue,
      prior.report.issues,
    );
    if (match == null) return null;

    final priorSaved = EvidenceTimelinePairing.priorEvidencePhoto(
      match: match,
      prior: prior,
    );
    if (priorSaved == null || priorSaved.bytes.isEmpty) return null;

    final currentPhoto = _photoForIssue(issue);
    if (!EvidenceTimelinePairing.isComparablePair(
      current: issue,
      currentPhoto: currentPhoto,
      prior: match,
      priorPhoto: priorSaved,
    )) {
      return null;
    }

    final areaDelta = _highlightAreaDelta(
      issue.surfaceHighlight,
      match.surfaceHighlight,
    );

    final d = prior.createdAt;
    final priorDate = '${d.month}/${d.day}/${d.year.toString().substring(2)}';
    final priorHighlight = match.surfaceHighlight == Rect.zero
        ? null
        : match.surfaceHighlight;

    return SurfaceEvidenceTimeline(
      priorLabel: 'Prior scan',
      currentLabel: 'This scan',
      priorPhoto: XFile.fromData(
        priorSaved.bytes,
        name: 'prior_${priorSaved.index}.jpg',
        mimeType: 'image/jpeg',
      ),
      priorHighlight: priorHighlight,
      priorDateLabel: priorDate,
      currentDateLabel: 'Now',
      areaChangePercent: areaDelta,
    );
  }

  /// Report just older than the current saved id, else the second-newest.
  SavedReport? _priorSavedReport() {
    final reports = ReportStore.instance.reports;
    if (reports.length < 2) return null;

    final id = _savedReportId;
    if (id != null) {
      final idx = reports.indexWhere((r) => r.id == id);
      if (idx >= 0 && idx + 1 < reports.length) return reports[idx + 1];
    }
    return reports[1];
  }



  double? _highlightAreaDelta(Rect a, Rect b) {
    if (a == Rect.zero || b == Rect.zero) return null;
    final old = b.width * b.height;
    if (old <= 0.0001) return null;
    final cur = a.width * a.height;
    return ((cur - old) / old) * 100;
  }

  void _openSurfaceEvidenceForPhoto(int photoIndex) {
    if (photoIndex >= 0 &&
        photoIndex < _photos.length &&
        FindingRetakeService.looksNonExteriorPhoto(_photos[photoIndex])) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This photo is not an exterior surface, so it is not used as evidence.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

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

    final photo = _photos[photoIndex];
    final matched = FindingRetakeService.bestIssueForPhoto(
      photo: photo,
      issues: issues,
    );
    if (matched != null) {
      final issueIndex = issues.indexOf(matched);
      _openSurfaceEvidence(
        matched,
        issueIndex: issueIndex >= 0 ? issueIndex : 0,
        photoIndex: photoIndex,
      );
      return;
    }

    // This frame does not support any listed finding (e.g. a roof photo
    // next to a grade-only drainage note). Open the first finding with
    // this photo as related context — not as proof.
    _openSurfaceEvidence(
      issues.first,
      issueIndex: 0,
      focusPhotoIndex: photoIndex,
    );
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

  Future<void> _retakePhotos() async {
    if (_reanalyzing) return;
    final args = <String, dynamic>{
      'seed': _photos,
    };
    if (_report.isSinglePhotoScan) {
      args['singlePhotoMode'] = true;
      if (_photos.isNotEmpty && _photos.first.slotId != null) {
        args['focus'] = _photos.first.slotId;
      }
    }
    await Navigator.of(context).pushNamed('/guided-capture', arguments: args);
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
        _report = report.copyWith(
          issues: FindingRetakeService.rebindIssues(
            issues: report.issues,
            photos: photos,
          ),
        );
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
    final next = _selectedZone == zone ? TwinZone.none : zone;
    setState(() => _selectedZone = next);
    if (next == TwinZone.none) return;
    final hasFinding = _orderedIssues.any((i) => i.twinZone == next);
    if (hasFinding) _scrollToFindings();
  }

  void _highlightZoneForIssue(AnalysisIssue issue) {
    if (issue.twinZone == TwinZone.none) return;
    if (_selectedZone == issue.twinZone) return;
    setState(() => _selectedZone = issue.twinZone);
  }

  void _scrollToFindings() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _findingsKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      unawaited(
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          alignment: 0.08,
        ),
      );
    });
  }

  void _selectFindingFromPlan(AnalysisIssue issue, int issueIndex) {
    setState(() {
      if (issue.twinZone != TwinZone.none) {
        _selectedZone = issue.twinZone;
      }
    });
    _openSurfaceEvidence(issue, issueIndex: issueIndex);
  }

  String _zoneLabel(TwinZone zone) => zone.surfaceLabel;

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
    final shotLabel = shot.label.toLowerCase();
    for (final i in _report.issues) {
      if (i.photoIndex == shot.index) return true;
      final label = i.sourcePhotoLabel.trim().toLowerCase();
      if (label.isNotEmpty && label == shotLabel) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final allIssues = _orderedIssues;
    final issues = _visibleIssues;
    final scoreColor = reportHealthColor(report.overallScore);
    final scoreCompare = _scoreComparison();
    final compareOther = scoreCompare == null
        ? null
        : _otherCompareReport(scoreCompare);
    // Index once so finding cards stay O(n) instead of indexOf each row.
    final globalIndexByIssue = <AnalysisIssue, int>{
      for (var i = 0; i < allIssues.length; i++) allIssues[i]: i,
    };

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
            controller: _scrollController,
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
                // House → Health
                _reveal(
                  _scoreFade,
                  _buildPropertyHero(report, scoreColor),
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
                if (report.hasLimitedVisibility) ...[
                  const SizedBox(height: 14),
                  _reveal(
                    _statsFade,
                    CloserPhotoTipCard(onRetake: _retakePhotos),
                  ),
                ],
                // What Matters
                const SizedBox(height: 28),
                KeyedSubtree(
                  key: _findingsKey,
                  child: _reveal(
                    _headerFade,
                    _sectionLabel(
                      _selectedZone == TwinZone.none
                          ? 'What matters'
                          : _zoneLabel(_selectedZone),
                      allIssues.isEmpty ? 'None' : '${issues.length}',
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                _reveal(
                  _headerFade,
                  Text(
                    allIssues.isEmpty
                        ? 'Nothing elevated from this screening pass.'
                        : _selectedZone == TwinZone.none
                        ? 'Each observation, with the photo evidence behind it.'
                        : 'Findings on the ${_zoneLabel(_selectedZone).toLowerCase()}.',
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
                    final globalIndex = globalIndexByIssue[issue] ?? index;
                    final fadeIndex = globalIndex.clamp(
                      0,
                      _issueFades.length - 1,
                    );
                    return _reveal(
                      _issueFades[fadeIndex],
                      _buildFindingCard(issue, globalIndex + 1),
                    );
                  }),
                // Timeline
                if (allIssues.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _reveal(
                    _severityFade,
                    _buildTimelineSection(allIssues, globalIndexByIssue),
                  ),
                ],
                // Evidence photos
                if (_photos.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _reveal(_severityFade, _buildPhotoGallery()),
                ],
                // Planning range — subordinate
                const SizedBox(height: 22),
                _reveal(_footerFade, _buildCostSummary(report)),
                const SizedBox(height: 22),
                _reveal(_footerFade, _buildCollapsibleOverview(report)),
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

  /// House first, then a restrained health readout.
  Widget _buildPropertyHero(AnalysisReport report, Color scoreColor) {
    final label = reportHealthLabel(report.overallScore);
    final isDemo = report.analysisSource.toLowerCase().contains('demo');
    final marked = report.markedTwinZones;
    final width = MediaQuery.sizeOf(context).width;
    final twinSize = (width - 56).clamp(248.0, 318.0);
    final cueZones = <TwinZone>[
      TwinZone.roof,
      TwinZone.siding,
      TwinZone.gutters,
      TwinZone.foundation,
      if (marked.contains(TwinZone.windows)) TwinZone.windows,
    ];
    final zoneFindings = _selectedZone == TwinZone.none
        ? const <AnalysisIssue>[]
        : _visibleIssues;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: _Lux.emerald.withValues(alpha: 0.12),
          width: 1,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _Lux.surface,
            _Lux.emeraldMist.withValues(alpha: 0.42),
            _Lux.navyMist.withValues(alpha: 0.32),
          ],
          stops: const [0.0, 0.58, 1.0],
        ),
        boxShadow: _Lux.softShadow(intensity: 1.05),
      ),
      child: Column(
        children: [
          Text(
            isDemo ? 'Demo · Your home' : 'Your home',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _Lux.muted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          DigitalTwinHouse(
            size: twinSize,
            selectedZone: _selectedZone,
            onZoneSelected: _onTwinZoneSelected,
            autoRotate: _selectedZone == TwinZone.none,
            showMarkers: marked.isNotEmpty,
            markedZones: marked,
          ),
          if (_selectedZone == TwinZone.none) ...[
            const SizedBox(height: 8),
            Text(
              TwinZoneCopy.tapHelper,
              key: const Key('twin-tap-helper'),
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: _Lux.body,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final z in cueZones) _zoneCueChip(z, marked.contains(z)),
            ],
          ),
          if (_selectedZone != TwinZone.none) ...[
            const SizedBox(height: 12),
            _twinFindingBridge(zoneFindings),
          ],
          const SizedBox(height: 18),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${report.overallScore}',
                  style: GoogleFonts.inter(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: _Lux.charcoal,
                    letterSpacing: -0.8,
                    height: 1.05,
                  ),
                ),
                TextSpan(
                  text: '  ·  ',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: _Lux.muted,
                  ),
                ),
                TextSpan(
                  text: label,
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: scoreColor,
                    letterSpacing: -0.35,
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            report.monitorContextLine,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              color: _Lux.charcoalMid,
              letterSpacing: -0.15,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            report.photoTrustLine,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: _Lux.body,
            ),
          ),
          const SizedBox(height: 8),
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

  Widget _zoneCueChip(TwinZone zone, bool hasFinding) {
    final selected = _selectedZone == zone;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onTwinZoneSelected(zone),
        borderRadius: BorderRadius.circular(99),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? _Lux.emerald : Colors.transparent,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected
                  ? _Lux.emerald
                  : hasFinding
                  ? _Lux.gold.withValues(alpha: 0.28)
                  : _Lux.border.withValues(alpha: 0.85),
              width: selected ? 1.25 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _Lux.emerald.withValues(alpha: 0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasFinding) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? Colors.white : _Lux.gold,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                _zoneLabel(zone),
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? Colors.white
                      : hasFinding
                      ? _Lux.charcoalMid
                      : _Lux.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Compact zone summary under the twin — title + severity, or a calm empty.
  Widget _twinFindingBridge(List<AnalysisIssue> zoneFindings) {
    if (zoneFindings.isEmpty) {
      return Text(
        TwinZoneCopy.noIssuesLine(_selectedZone),
        key: const Key('twin-zone-empty'),
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 13,
          height: 1.4,
          fontWeight: FontWeight.w500,
          color: _Lux.muted,
        ),
      );
    }

    final first = zoneFindings.first;
    final extra = zoneFindings.length - 1;
    final sevColor = _severityColor(first.severity);

    return Material(
      key: const Key('twin-zone-summary'),
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          final idx = _orderedIssues.indexOf(first);
          _openSurfaceEvidence(first, issueIndex: idx >= 0 ? idx : 0);
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: _Lux.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _Lux.border.withValues(alpha: 0.9)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: sevColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      first.severity,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: sevColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      first.homeownerTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: _Lux.charcoal,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
              if (extra > 0) ...[
                const SizedBox(height: 6),
                Text(
                  extra == 1
                      ? '+1 more on ${_zoneLabel(_selectedZone)}'
                      : '+$extra more on ${_zoneLabel(_selectedZone)}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _Lux.muted,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                first.planningCostLabel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _Lux.muted,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'View evidence →',
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: _Lux.emeraldDeep,
                ),
              ),
            ],
          ),
        ),
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
    final slotLabel = FindingRetakeService.slotCoachLabel(
      _slotForIssue(issue),
    ).toLowerCase();
    final markedWrong = FindingFeedbackStore.instance.isMarkedWrong(
      reportId: _savedReportId,
      title: issue.homeownerTitle,
      location: issue.location,
    );
    final selectedHere =
        _selectedZone != TwinZone.none && issue.twinZone == _selectedZone;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          _highlightZoneForIssue(issue);
          _openSurfaceEvidence(issue, issueIndex: index - 1);
        },
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: _Lux.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selectedHere
                  ? _Lux.emerald.withValues(alpha: 0.35)
                  : _Lux.border,
              width: selectedHere ? 1.25 : 1,
            ),
            boxShadow: _Lux.softShadow(intensity: selectedHere ? 1.05 : 0.85),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 3,
                color: sevColor.withValues(alpha: 0.85),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      issue.homeownerTitle,
                      softWrap: true,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 16.5,
                        color: _Lux.charcoal,
                        height: 1.28,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      issue.shortLocation,
                      softWrap: true,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: _Lux.muted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      [
                        '${issue.confidence}% confidence',
                        issue.planningCostLabel,
                        if (issue.needsCloserPhoto) 'Closer photo helps',
                      ].join('  ·  '),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _Lux.muted,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      issue.companionNextStep,
                      softWrap: true,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        height: 1.45,
                        color: _Lux.body,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'View evidence →',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: _Lux.emeraldDeep,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        Tooltip(
                          message: 'Retake $slotLabel',
                          child: TextButton(
                            onPressed: _reanalyzing
                                ? null
                                : () => _retakeForIssue(issue),
                            style: _findingActionButtonStyle(_Lux.muted),
                            child: Text(
                              'Retake',
                              maxLines: 1,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: markedWrong
                              ? null
                              : () => _markFindingWrong(issue),
                          style: _findingActionButtonStyle(_Lux.muted),
                          child: Text(
                            markedWrong ? 'Flagged' : 'Looks wrong',
                            maxLines: 1,
                            style: GoogleFonts.inter(
                              fontSize: 12,
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

  ButtonStyle _findingActionButtonStyle(Color foreground) {
    return TextButton.styleFrom(
      foregroundColor: foreground,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildTimelineSection(
    List<AnalysisIssue> issues,
    Map<AnalysisIssue, int> globalIndexByIssue,
  ) {
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
          'A maintenance plan for this property — tap an item to see the area and evidence.',
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
            globalIndexByIssue: globalIndexByIssue,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _timelineRow({
    required _TimelineBucket bucket,
    required List<AnalysisIssue> items,
    required Map<AnalysisIssue, int> globalIndexByIssue,
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
                  color: items.isEmpty ? _Lux.muted.withValues(alpha: 0.55) : accent,
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
              if (items.isNotEmpty)
                Text(
                  '${items.length}',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _Lux.muted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            items.isEmpty ? _bucketEmptyState(bucket) : _bucketHint(bucket),
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: _Lux.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final issue in items.take(3))
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _selectFindingFromPlan(
                    issue,
                    globalIndexByIssue[issue] ?? 0,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
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
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: _Lux.muted.withValues(alpha: 0.8),
                        ),
                      ],
                    ),
                  ),
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
        _sectionLabel('Photos', '${photos.length}'),
        const SizedBox(height: 6),
        Text(
          'Photos with linked evidence open Surface Evidence.',
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
                  ? _Lux.emerald.withValues(alpha: 0.55)
                  : _Lux.border;

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
                          if (problem)
                            Positioned(
                              top: 7,
                              right: 7,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: _Lux.emeraldDeep.withValues(alpha: 0.92),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  'Evidence',
                                  style: GoogleFonts.inter(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: 0.15,
                                  ),
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
    final withheld = CostCopy.isWithheldRange(report.estimatedRepairRange);
    final range = withheld
        ? CostCopy.withheld
        : CostCopy.compact(report.estimatedRepairRange);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: _Lux.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Lux.border, width: 0.75),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            CostCopy.shortLabel,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _Lux.muted,
              letterSpacing: 0.15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            range,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _Lux.charcoalMid,
              letterSpacing: -0.35,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            withheld ? CostCopy.footnote : CostCopy.inlineNote,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: _Lux.muted,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          if (!withheld) ...[
            const SizedBox(height: 6),
            Text(
              CostCopy.footnote,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: _Lux.muted,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            PrivacyCopy.screeningReminder,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: _Lux.muted,
              fontWeight: FontWeight.w500,
              height: 1.4,
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
              border: Border.all(color: _Lux.emerald.withValues(alpha: 0.16)),
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
            'First Sign did not flag high-priority exterior defects. Keep seasonal maintenance, and re-scan after storms.',
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
            TwinZoneCopy.noIssuesLine(_selectedZone),
            textAlign: TextAlign.center,
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
              border: Border.all(color: _Lux.gold.withValues(alpha: 0.18)),
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
                colors: [Color(0xFF10B981), _Lux.emerald, _Lux.emeraldDeep],
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
