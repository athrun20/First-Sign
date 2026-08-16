import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/capture_models.dart';
import '../services/capture_draft_store.dart';
import '../services/exterior_analysis_service.dart';
import '../services/report_store.dart';
import '../services/storage_exception.dart';
import '../theme/app_lux.dart';
import '../widgets/closer_photo_tip.dart';
import '../widgets/photo_thumb.dart';
import 'analysis_report_screen.dart';

class PhotoReviewScreen extends StatefulWidget {
  final List<CapturePhoto> photos;

  /// Soft pre-analysis hint when a dark / low-detail frame was accepted.
  final bool lowDetailHint;

  const PhotoReviewScreen({
    super.key,
    required this.photos,
    this.lowDetailHint = false,
  });

  @override
  State<PhotoReviewScreen> createState() => _PhotoReviewScreenState();
}

class _PhotoReviewScreenState extends State<PhotoReviewScreen> {
  bool _analyzing = false;

  bool get _isQuickScan => widget.photos.length == 1;

  Future<void> _runAnalysis() async {
    if (_analyzing) return;
    setState(() => _analyzing = true);

    try {
      final report = await ExteriorAnalysisService().analyzeCapture(
        widget.photos,
      );
      // Persist for homeowner history (photos compressed).
      final saved = await ReportStore.instance.saveFromCapture(
        report: report,
        photos: widget.photos,
      );
      // Analysis finished — drop in-progress capture draft.
      await CaptureDraftStore.instance.clear();
      if (!mounted) return;

      final route = PageRouteBuilder<void>(
        transitionDuration: Duration(milliseconds: _isQuickScan ? 480 : 320),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (context, animation, secondaryAnimation) {
          return AnalysisReportScreen(
            photos: widget.photos,
            report: report,
            savedReportId: saved.id,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: Offset(0, _isQuickScan ? 0.04 : 0.02),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      );
      unawaited(Navigator.push(context, route));
    } on StorageFullException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.userMessage),
          backgroundColor: Colors.orange.shade800,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Analysis failed: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.photos.length;
    final quick = _isQuickScan;
    final shot = quick ? widget.photos.first : null;

    return Scaffold(
      backgroundColor: AppLux.bg,
      appBar: AppBar(
        backgroundColor: quick ? AppLux.bg : null,
        surfaceTintColor: Colors.transparent,
        elevation: quick ? 0 : null,
        title: Text(
          quick ? 'Review Quick Scan' : 'Review photos',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: quick ? 17 : null,
            letterSpacing: quick ? -0.2 : null,
            color: quick ? AppLux.charcoal : null,
          ),
        ),
        iconTheme: quick ? const IconThemeData(color: AppLux.charcoal) : null,
      ),
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (quick && shot != null)
                Expanded(child: _buildQuickScanReview(shot))
              else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Text(
                    '$count photo${count == 1 ? '' : 's'} ready with checklist labels. '
                    'Go back to retake any shot.',
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      color: AppLux.body,
                      height: 1.35,
                    ),
                  ),
                ),
                if (widget.lowDetailHint)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 10, 20, 4),
                    child: CloserPhotoCaptureHint(),
                  ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemCount: count,
                    itemBuilder: (context, index) {
                      final photo = widget.photos[index];
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            PhotoThumb(photo: photo.file),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                color: Colors.black.withValues(alpha: 0.55),
                                child: Text(
                                  photo.shortLabel,
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
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _analyzing ? null : _runAnalysis,
                      style: AppLux.primaryButton(minHeight: 52),
                      child: Text(
                        _analyzing ? 'Analyzing…' : 'Analyze with AI',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (_analyzing)
            _AnalysisLoadingOverlay(
              photoCount: count,
              usingVision: ExteriorAnalysisService().hasVisionKey,
              quickScan: quick,
              areaLabel: shot?.label,
            ),
        ],
      ),
    );
  }

  Widget _buildQuickScanReview(CapturePhoto shot) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
            children: [
              Text(
                'Confirm this photo, then run a focused screening.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  height: 1.5,
                  color: AppLux.body,
                  letterSpacing: 0.05,
                ),
              ),
              const SizedBox(height: 18),
              // Hero photo card
              Container(
                decoration: BoxDecoration(
                  color: AppLux.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppLux.border, width: 0.75),
                  boxShadow: [
                    BoxShadow(
                      color: AppLux.charcoal.withValues(alpha: 0.04),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AspectRatio(
                      aspectRatio: 4 / 3,
                      child: PhotoThumb(photo: shot.file),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AREA',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppLux.teal,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            shot.label,
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppLux.charcoal,
                              letterSpacing: -0.3,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppLux.tealMist,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppLux.teal.withValues(alpha: 0.18),
                                width: 0.6,
                              ),
                            ),
                            child: Text(
                              'Quick Scan · single photo',
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppLux.teal,
                                letterSpacing: 0.15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: AppLux.goldSoft.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFE8D5A8),
                    width: 0.65,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: AppLux.gold,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Single-angle screening is faster and still useful for a first look. '
                        'A full 6-shot set usually raises confidence across the home.',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          height: 1.5,
                          color: const Color(0xFF78350F),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.lowDetailHint) ...[
                const SizedBox(height: 12),
                const CloserPhotoCaptureHint(),
              ],
              const SizedBox(height: 12),
              TextButton(
                onPressed: _analyzing
                    ? null
                    : () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(foregroundColor: AppLux.body),
                child: Text(
                  'Retake or change area tag',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(22, 12, 22, 12 + bottom),
          decoration: const BoxDecoration(
            color: AppLux.surface,
            border: Border(top: BorderSide(color: AppLux.border, width: 0.75)),
          ),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _analyzing ? null : _runAnalysis,
              style: FilledButton.styleFrom(
                backgroundColor: AppLux.teal,
                disabledBackgroundColor: AppLux.teal.withValues(alpha: 0.45),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: Text(
                _analyzing ? 'Screening…' : 'Run Quick Scan analysis',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 15.5,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Polished multi-step loading overlay shown while AI analysis runs.
class _AnalysisLoadingOverlay extends StatefulWidget {
  final int photoCount;
  final bool usingVision;
  final bool quickScan;
  final String? areaLabel;

  const _AnalysisLoadingOverlay({
    required this.photoCount,
    required this.usingVision,
    this.quickScan = false,
    this.areaLabel,
  });

  @override
  State<_AnalysisLoadingOverlay> createState() =>
      _AnalysisLoadingOverlayState();
}

class _AnalysisLoadingOverlayState extends State<_AnalysisLoadingOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _stepController;
  int _activeStep = 0;

  late final List<String> _steps;

  @override
  void initState() {
    super.initState();
    if (widget.quickScan) {
      final area = (widget.areaLabel ?? '').trim();
      _steps = [
        area.isEmpty
            ? 'Preparing your photo'
            : 'Preparing ${area.toLowerCase()} photo',
        widget.usingVision
            ? 'Reading visual cues'
            : 'Running on-device image analysis',
        'Mapping findings with single-angle care',
        'Scoring confidence & planning range',
      ];
    } else {
      _steps = [
        'Preparing ${widget.photoCount} photo${widget.photoCount == 1 ? '' : 's'}',
        widget.usingVision
            ? 'Sending to Google Cloud Vision'
            : 'Running on-device image analysis',
        'Mapping defects & severity',
        'Scoring confidence & planning range',
      ];
    }

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    unawaited(_pulseController.repeat(reverse: true));

    _stepController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1100),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            if (!mounted) return;
            setState(() {
              _activeStep = (_activeStep + 1).clamp(0, _steps.length - 1);
            });
            if (_activeStep < _steps.length - 1) {
              _stepController.reset();
              unawaited(_stepController.forward());
            }
          }
        });

    unawaited(_stepController.forward());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _stepController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_activeStep + 1) / _steps.length;
    final quick = widget.quickScan;
    const accent = AppLux.teal;
    const ink = AppLux.charcoal;
    const muted = AppLux.muted;

    return AnimatedOpacity(
      opacity: 1,
      duration: const Duration(milliseconds: 280),
      child: Container(
        color: AppLux.stoneDeep.withValues(alpha: 0.52),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 28),
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            decoration: BoxDecoration(
              color: AppLux.surface,
              borderRadius: BorderRadius.circular(AppLux.radiusHero),
              border: Border.all(
                color: AppLux.border,
                width: AppLux.borderWidth,
              ),
              boxShadow: AppLux.softShadow(intensity: 1.2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: Tween<double>(begin: 0.94, end: 1.0).animate(
                    CurvedAnimation(
                      parent: _pulseController,
                      curve: Curves.easeInOut,
                    ),
                  ),
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          accent.withValues(alpha: 0.14),
                          ink.withValues(alpha: 0.06),
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: accent,
                            backgroundColor: accent.withValues(alpha: 0.12),
                          ),
                        ),
                        Icon(
                          quick ? Icons.bolt_rounded : Icons.auto_awesome,
                          color: accent,
                          size: 24,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  quick
                      ? 'Screening your Quick Scan'
                      : 'AI is analyzing your exterior',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17.5,
                    fontWeight: FontWeight.w700,
                    color: ink,
                    letterSpacing: -0.25,
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  child: Text(
                    _steps[_activeStep],
                    key: ValueKey(_activeStep),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: muted,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppLux.radiusPill),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: progress),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) {
                      return LinearProgressIndicator(
                        value: value,
                        minHeight: 6,
                        backgroundColor: AppLux.border,
                        valueColor: const AlwaysStoppedAnimation<Color>(accent),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
                ...List.generate(_steps.length, (i) {
                  final done = i < _activeStep;
                  final active = i == _activeStep;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 280),
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: done
                                ? accent
                                : active
                                ? accent.withValues(alpha: 0.12)
                                : AppLux.bg,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: done || active ? accent : AppLux.border,
                            ),
                          ),
                          child: done
                              ? const Icon(
                                  Icons.check_rounded,
                                  size: 12,
                                  color: Colors.white,
                                )
                              : active
                              ? Center(
                                  child: Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: accent,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _steps[i],
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: active
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: done || active ? ink : muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
