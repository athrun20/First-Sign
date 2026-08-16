import 'dart:async' show unawaited;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../legal/cost_copy.dart';
import '../legal/privacy_copy.dart';
import '../models/analysis_models.dart';
import '../services/finding_retake_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public types
// ─────────────────────────────────────────────────────────────────────────────

/// Three viewing modes for Surface Evidence.
enum EvidenceViewMode { original, overlay, confidence }

/// Optional multi-angle / related capture for comparison.
class SurfaceEvidenceAngle {
  const SurfaceEvidenceAngle({
    required this.label,
    required this.photo,
    this.highlight,
    this.isPrimary = false,
    this.supportsFinding = true,
  });

  final String label;
  final XFile photo;
  final Rect? highlight;
  final bool isPrimary;

  /// False when this frame is related context, not proof of the finding.
  final bool supportsFinding;
}

/// Prior-scan evidence for the Evidence Timeline.
class SurfaceEvidenceTimeline {
  const SurfaceEvidenceTimeline({
    required this.priorLabel,
    required this.currentLabel,
    this.priorPhoto,
    this.priorHighlight,
    this.priorDateLabel,
    this.currentDateLabel,
    this.areaChangePercent,
  });

  final String priorLabel;
  final String currentLabel;
  final XFile? priorPhoto;
  final Rect? priorHighlight;
  final String? priorDateLabel;
  final String? currentDateLabel;

  /// Positive = grew, negative = improved/shrunk, null = unknown.
  final double? areaChangePercent;

  String get changeNarrative {
    final p = areaChangePercent;
    if (p == null) {
      return 'Same exterior area across scans — compare with the slider. '
          'Alignment is approximate; photos were not 3D-registered.';
    }
    if (p.abs() < 3) {
      return 'No measurable change detected since your last scan.';
    }
    if (p > 0) {
      return 'Estimated affected region increased '
          '~${p.abs().toStringAsFixed(0)}% since your last scan.';
    }
    return 'Estimated affected region decreased '
        '~${p.abs().toStringAsFixed(0)}% since your last scan.';
  }

  bool get improved => (areaChangePercent ?? 0) < -3;
  bool get worsened => (areaChangePercent ?? 0) > 3;
}

/// Opens the Surface Evidence experience (exterior photo screening only).
Future<void> showSurfaceEvidenceSheet({
  required BuildContext context,
  required AnalysisIssue issue,
  XFile? photo,
  int? findingIndex,
  String? sourcePhotoLabel,
  VoidCallback? onRetake,
  List<SurfaceEvidenceAngle> relatedAngles = const [],
  SurfaceEvidenceTimeline? timeline,
  int initialAngleIndex = 0,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) {
      return _SurfaceEvidenceSheet(
        issue: issue,
        photo: photo,
        findingIndex: findingIndex,
        sourcePhotoLabel: sourcePhotoLabel ?? issue.sourcePhotoDisplay,
        onRetake: onRetake,
        relatedAngles: relatedAngles,
        timeline: timeline,
        initialAngleIndex: initialAngleIndex,
      );
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────

abstract final class _Fx {
  static const bg = Color(0xFFF7F8FA);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE8ECF0);
  static const ink = Color(0xFF0F172A);
  static const body = Color(0xFF475569);
  static const muted = Color(0xFF94A3B8);
  static const orange = Color(0xFFEA580C);
  static const orangeSoft = Color(0xFFFB923C);
  static const amber = Color(0xFFD97706);
  static const teal = Color(0xFF0F766E);
  static const cyan = Color(0xFF0891B2);
  static const success = Color(0xFF059669);
  static const danger = Color(0xFFB91C1C);
  static const orangeMist = Color(0xFFFFF7ED);
  static const amberMist = Color(0xFFFFFBEB);
  static const amberBorder = Color(0xFFFDE68A);
  static const amberInk = Color(0xFF92400E);
  static const amberBody = Color(0xFF78350F);
  static const chipInk = Color(0xFF9A3412);
  static const stageBg = Color(0xFF0B1220);
  static const stagePlaceholder = Color(0xFF1E293B);

  static List<BoxShadow> soft({double i = 1}) => [
    BoxShadow(
      color: const Color(0xFF0F172A).withValues(alpha: 0.045 * i),
      blurRadius: 28,
      offset: const Offset(0, 12),
    ),
    BoxShadow(
      color: const Color(0xFF0F172A).withValues(alpha: 0.018 * i),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];

  static BoxDecoration card({
    double radius = 18,
    double shadow = 0.5,
    Color? color,
    Color? borderColor,
  }) {
    return BoxDecoration(
      color: color ?? surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor ?? border),
      boxShadow: shadow <= 0 ? null : soft(i: shadow),
    );
  }

  static TextStyle sectionLabelStyle() => GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.0,
    color: muted,
  );

  static TextStyle titleStyle({double size = 15.5}) => GoogleFonts.inter(
    fontSize: size,
    fontWeight: FontWeight.w700,
    color: ink,
    letterSpacing: -0.2,
  );

  static TextStyle bodyStyle({double size = 13.5, double height = 1.4}) =>
      GoogleFonts.inter(fontSize: size, height: height, color: body);

  static TextStyle mutedStyle({double size = 12.5}) => GoogleFonts.inter(
    fontSize: size,
    color: muted,
    fontWeight: FontWeight.w500,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Root sheet
// ─────────────────────────────────────────────────────────────────────────────

class _SurfaceEvidenceSheet extends StatefulWidget {
  const _SurfaceEvidenceSheet({
    required this.issue,
    this.photo,
    this.findingIndex,
    this.sourcePhotoLabel = '',
    this.onRetake,
    this.relatedAngles = const [],
    this.timeline,
    this.initialAngleIndex = 0,
  });

  final AnalysisIssue issue;
  final XFile? photo;
  final int? findingIndex;
  final String sourcePhotoLabel;
  final VoidCallback? onRetake;
  final List<SurfaceEvidenceAngle> relatedAngles;
  final SurfaceEvidenceTimeline? timeline;
  final int initialAngleIndex;

  @override
  State<_SurfaceEvidenceSheet> createState() => _SurfaceEvidenceSheetState();
}

class _SurfaceEvidenceSheetState extends State<_SurfaceEvidenceSheet>
    with TickerProviderStateMixin {
  late final AnimationController _scan;
  late final AnimationController _pulse;
  late final AnimationController _overlayFade;
  late final TransformationController _transform;
  AnimationController? _zoomAnim;

  EvidenceViewMode _mode = EvidenceViewMode.original;
  bool _scanComplete = false;
  bool _whyOpen = true;
  late int _angleIndex;
  double _timelineSplit = 0.5;
  Size? _stageSize;

  AnalysisIssue get issue => widget.issue;

  Rect get _highlight {
    if (!_selectedSupportsFinding) return Rect.zero;
    if (!issue.shouldShowSurfaceHighlight) return Rect.zero;
    return issue.surfaceHighlight;
  }

  List<SurfaceEvidenceAngle> get _angles {
    final list = <SurfaceEvidenceAngle>[];
    final primary = widget.photo;
    if (primary != null) {
      list.add(
        SurfaceEvidenceAngle(
          label: widget.sourcePhotoLabel.isNotEmpty
              ? widget.sourcePhotoLabel
              : 'Primary',
          photo: primary,
          isPrimary: true,
          supportsFinding: true,
        ),
      );
    }
    for (final a in widget.relatedAngles) {
      if (primary != null && a.photo.path == primary.path) continue;
      list.add(a);
    }
    return list;
  }

  SurfaceEvidenceAngle? get _selectedAngle {
    final angles = _angles;
    if (angles.isEmpty) return null;
    final i = _angleIndex.clamp(0, angles.length - 1);
    return angles[i];
  }

  bool get _selectedSupportsFinding =>
      _selectedAngle?.supportsFinding ?? true;

  @override
  void initState() {
    super.initState();
    _angleIndex = widget.initialAngleIndex < 0 ? 0 : widget.initialAngleIndex;
    _transform = TransformationController();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    unawaited(_pulse.repeat(reverse: true));
    _overlayFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scan = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        _scan.forward().whenComplete(() {
          if (!mounted) return;
          setState(() {
            _scanComplete = true;
            _mode = EvidenceViewMode.overlay;
          });
          unawaited(_overlayFade.forward(from: 0));
        }),
      );
    });
  }

  @override
  void dispose() {
    _zoomAnim?.dispose();
    _scan.dispose();
    _pulse.dispose();
    _overlayFade.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _setMode(EvidenceViewMode m) {
    if (_mode == m) return;
    setState(() => _mode = m);
    if (m == EvidenceViewMode.overlay || m == EvidenceViewMode.confidence) {
      unawaited(_overlayFade.forward(from: 0));
    }
  }

  void _resetZoom() {
    _zoomAnim?.stop();
    _transform.value = Matrix4.identity();
  }

  void _noteStageSize(Size size) {
    if (_stageSize == size) return;
    _stageSize = size;
  }

  void _zoomToEvidence() {
    final hl = _highlight;
    final size = _stageSize;
    if (hl == Rect.zero || size == null) return;

    final center = Offset(
      (hl.left + hl.width / 2) * size.width,
      (hl.top + hl.height / 2) * size.height,
    );
    const targetScale = 2.15;
    final endDx = size.width / 2 - center.dx * targetScale;
    final endDy = size.height / 2 - center.dy * targetScale;

    final beginM = _transform.value;
    final beginScale = beginM.getMaxScaleOnAxis().clamp(1.0, 4.5);
    final beginDx = beginM.storage[12];
    final beginDy = beginM.storage[13];

    _zoomAnim?.dispose();
    final anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _zoomAnim = anim;
    final curved = CurvedAnimation(parent: anim, curve: Curves.easeInOutCubic);
    void tick() {
      final t = curved.value;
      final s = beginScale + (targetScale - beginScale) * t;
      final dx = beginDx + (endDx - beginDx) * t;
      final dy = beginDy + (endDy - beginDy) * t;
      _transform.value = Matrix4.identity()
        ..translateByDouble(dx, dy, 0, 1)
        ..scaleByDouble(s, s, 1, 1);
    }

    curved.addListener(tick);
    unawaited(
      anim.forward().whenComplete(() {
        curved.removeListener(tick);
        if (identical(_zoomAnim, anim)) {
          anim.dispose();
          _zoomAnim = null;
        }
      }),
    );

    if (_mode == EvidenceViewMode.original) {
      _setMode(EvidenceViewMode.overlay);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final maxH = MediaQuery.sizeOf(context).height * 0.96;
    final angles = _angles;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: const BoxDecoration(
        color: _Fx.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(18, 4, 18, 24 + bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title block
                  Text(
                    issue.homeownerTitle,
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: _Fx.ink,
                      letterSpacing: -0.5,
                      height: 1.22,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    FindingRetakeService.evidenceCaption(
                      issue: issue,
                      photoLabel: _selectedAngle?.label ??
                          widget.sourcePhotoLabel,
                      photoSupportsFinding: _selectedSupportsFinding,
                    ),
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      color: _Fx.body,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                  if (!_selectedSupportsFinding) ...[
                    const SizedBox(height: 10),
                    _RelatedContextBanner(issue: issue),
                  ],
                  const SizedBox(height: 14),

                  // Primary confidence label (not %)
                  _ConfidenceHero(issue: issue),
                  const SizedBox(height: 16),

                  // Mode switcher — three modes only
                  _ModeBar(
                    mode: _mode,
                    enabled: _scanComplete,
                    onChanged: _setMode,
                  ),
                  const SizedBox(height: 14),

                  // Large photo stage
                  _PhotoStage(
                    angles: angles,
                    angleIndex: _angleIndex,
                    mode: _mode,
                    pulse: _pulse,
                    scan: _scan,
                    overlayFade: _overlayFade,
                    scanComplete: _scanComplete,
                    transform: _transform,
                    highlight: _highlight,
                    maskSeed: issue.forensicMaskSeed,
                    confidence: issue.confidence,
                    hasLocalized: issue.hasLocalizedHighlight,
                    onStageSized: _noteStageSize,
                    onEvidenceTap: _zoomToEvidence,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _modeCaption(_mode),
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: _Fx.muted,
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _resetZoom,
                        icon: const Icon(Icons.fit_screen_rounded, size: 16),
                        label: const Text('Fit'),
                        style: TextButton.styleFrom(
                          foregroundColor: _Fx.body,
                          visualDensity: VisualDensity.compact,
                          textStyle: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _highlight == Rect.zero
                            ? null
                            : _zoomToEvidence,
                        icon: const Icon(
                          Icons.center_focus_strong_rounded,
                          size: 16,
                        ),
                        label: const Text('Focus'),
                        style: TextButton.styleFrom(
                          foregroundColor: _Fx.orange,
                          visualDensity: VisualDensity.compact,
                          textStyle: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Low visibility CTA
                  if (issue.confidence < 80 || issue.needsCloserPhoto) ...[
                    const SizedBox(height: 8),
                    _LimitedVisibilityCard(
                      issue: issue,
                      onRetake: widget.onRetake,
                    ),
                  ],

                  if (angles.length > 1) ...[
                    const SizedBox(height: 16),
                    _AngleStrip(
                      angles: angles,
                      selected: _angleIndex,
                      onSelect: (i) {
                        setState(() => _angleIndex = i);
                        _resetZoom();
                      },
                    ),
                  ],

                  const SizedBox(height: 20),
                  _ExplainableAiCard(
                    issue: issue,
                    expanded: _whyOpen,
                    onToggle: () => setState(() => _whyOpen = !_whyOpen),
                  ),

                  const SizedBox(height: 14),
                  _AnalysisGrid(issue: issue),

                  const SizedBox(height: 14),
                  if (widget.timeline != null)
                    _TimelineCard(
                      timeline: widget.timeline!,
                      currentPhoto: widget.photo,
                      currentHighlight: _highlight,
                      split: _timelineSplit,
                      onSplit: (v) => setState(() => _timelineSplit = v),
                    )
                  else
                    const _TimelinePlaceholder(),

                  const SizedBox(height: 14),
                  _NextStepsCard(issue: issue, onRetake: widget.onRetake),

                  const SizedBox(height: 16),
                  Text(
                    'Visualizations show estimated regions from exterior photo screening. '
                    'First Sign does not see through walls, measure depth, or replace an on-site inspection.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      height: 1.45,
                      color: _Fx.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _modeCaption(EvidenceViewMode m) => switch (m) {
    EvidenceViewMode.original => 'Your capture — no AI markup.',
    EvidenceViewMode.overlay =>
      'Estimated damage region from photo cues (not a surveyed outline).',
    EvidenceViewMode.confidence =>
      'Where the model focused attention — softer = lower certainty.',
  };

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 8, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _Fx.ink,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.biotech_rounded,
                  size: 15,
                  color: _Fx.orangeSoft.withValues(alpha: 0.95),
                ),
                const SizedBox(width: 6),
                Text(
                  'Surface evidence',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          if (widget.findingIndex != null) ...[
            const SizedBox(width: 10),
            Text(
              'Finding ${widget.findingIndex}',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _Fx.muted,
              ),
            ),
          ],
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: _Fx.body),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Confidence hero
// ─────────────────────────────────────────────────────────────────────────────

class _ConfidenceHero extends StatelessWidget {
  const _ConfidenceHero({required this.issue});
  final AnalysisIssue issue;

  Color get _color {
    switch (issue.forensicConfidenceTitle) {
      case 'High Confidence':
        return _Fx.success;
      case 'Moderate Confidence':
        return _Fx.amber;
      default:
        return _Fx.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _color;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: _Fx.card(radius: 16),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: c.withValues(alpha: 0.35), blurRadius: 8),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  issue.forensicConfidenceTitle,
                  style: _Fx.titleStyle(size: 16),
                ),
                const SizedBox(height: 3),
                Text(
                  issue.forensicConfidenceSubtitle,
                  style: _Fx.bodyStyle(size: 13, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${issue.confidence}',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: c,
                  height: 1,
                ),
              ),
              Text('score', style: _Fx.mutedStyle(size: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mode bar — Original · AI Overlay · Confidence
// ─────────────────────────────────────────────────────────────────────────────

class _ModeBar extends StatelessWidget {
  const _ModeBar({
    required this.mode,
    required this.enabled,
    required this.onChanged,
  });

  final EvidenceViewMode mode;
  final bool enabled;
  final ValueChanged<EvidenceViewMode> onChanged;

  static const _items = <(EvidenceViewMode, String)>[
    (EvidenceViewMode.original, 'Original'),
    (EvidenceViewMode.overlay, 'AI Overlay'),
    (EvidenceViewMode.confidence, 'Confidence'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF1F4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final (m, label) in _items)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  if (enabled || m == EvidenceViewMode.original) {
                    onChanged(m);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: mode == m ? _Fx.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: mode == m ? _Fx.soft(i: 0.7) : null,
                  ),
                  child: Opacity(
                    opacity: (enabled || m == EvidenceViewMode.original)
                        ? 1
                        : 0.4,
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: mode == m
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: mode == m ? _Fx.ink : _Fx.body,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Large photo stage
// ─────────────────────────────────────────────────────────────────────────────

class _PhotoStage extends StatelessWidget {
  const _PhotoStage({
    required this.angles,
    required this.angleIndex,
    required this.mode,
    required this.pulse,
    required this.scan,
    required this.overlayFade,
    required this.scanComplete,
    required this.transform,
    required this.highlight,
    required this.maskSeed,
    required this.confidence,
    required this.hasLocalized,
    required this.onStageSized,
    required this.onEvidenceTap,
  });

  final List<SurfaceEvidenceAngle> angles;
  final int angleIndex;
  final EvidenceViewMode mode;
  final Animation<double> pulse;
  final Animation<double> scan;
  final Animation<double> overlayFade;
  final bool scanComplete;
  final TransformationController transform;
  final Rect highlight;
  final int maskSeed;
  final int confidence;
  final bool hasLocalized;
  final ValueChanged<Size> onStageSized;
  final VoidCallback onEvidenceTap;

  @override
  Widget build(BuildContext context) {
    final angle = angles.isEmpty
        ? null
        : angles[angleIndex.clamp(0, angles.length - 1)];
    final hl = (angle?.supportsFinding ?? true)
        ? (angle?.highlight ?? highlight)
        : Rect.zero;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: _Fx.soft(i: 1.1),
        border: Border.all(color: _Fx.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 4 / 3.35,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            onStageSized(size);
            return Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: _Fx.stageBg),
                if (angle != null)
                  InteractiveViewer(
                    transformationController: transform,
                    minScale: 1,
                    maxScale: 4.5,
                    boundaryMargin: const EdgeInsets.all(64),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _PhotoFill(photo: angle.photo),
                        if (mode == EvidenceViewMode.overlay && hl != Rect.zero)
                          FadeTransition(
                            opacity: overlayFade,
                            child: AnimatedBuilder(
                              animation: pulse,
                              builder: (_, _) => CustomPaint(
                                painter: _OrangeMaskPainter(
                                  highlight: hl,
                                  pulse: pulse.value,
                                  seed: maskSeed,
                                  confidence: confidence,
                                ),
                              ),
                            ),
                          ),
                        if (mode == EvidenceViewMode.confidence &&
                            hl != Rect.zero)
                          FadeTransition(
                            opacity: overlayFade,
                            child: CustomPaint(
                              painter: _ConfidenceMapPainter(
                                highlight: hl,
                                confidence: confidence,
                                seed: maskSeed,
                              ),
                            ),
                          ),
                        if (hl != Rect.zero &&
                            mode != EvidenceViewMode.original)
                          AnimatedBuilder(
                            animation: pulse,
                            builder: (_, _) => CustomPaint(
                              painter: _PulseFocusPainter(
                                highlight: hl,
                                pulse: pulse.value,
                                color: mode == EvidenceViewMode.confidence
                                    ? _Fx.cyan
                                    : _Fx.orange,
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                else
                  Center(
                    child: Text(
                      'No source photo',
                      style: GoogleFonts.inter(
                        color: Colors.white54,
                        fontSize: 14,
                      ),
                    ),
                  ),
                if (!scanComplete || scan.value < 1)
                  AnimatedBuilder(
                    animation: scan,
                    builder: (_, _) => CustomPaint(
                      painter: _ScanPainter(progress: scan.value),
                    ),
                  ),
                if (hl != Rect.zero && angle != null)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTapUp: (d) {
                        final local = d.localPosition;
                        final r = Rect.fromLTWH(
                          hl.left * size.width,
                          hl.top * size.height,
                          hl.width * size.width,
                          hl.height * size.height,
                        ).inflate(28);
                        if (r.contains(local)) onEvidenceTap();
                      },
                    ),
                  ),
                Positioned(
                  left: 12,
                  top: 12,
                  child: _Tag(
                    label: switch (mode) {
                      EvidenceViewMode.original => 'Original',
                      EvidenceViewMode.overlay =>
                        hasLocalized ? 'Estimated region' : 'Zone estimate',
                      EvidenceViewMode.confidence => 'Attention map',
                    },
                  ),
                ),
                if (mode == EvidenceViewMode.confidence)
                  const Positioned(
                    right: 12,
                    bottom: 12,
                    child: _ConfidenceLegend(),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _ConfidenceLegend extends StatelessWidget {
  const _ConfidenceLegend();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Model attention',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 88,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: const LinearGradient(
                colors: [
                  Color(0x0022D3EE),
                  Color(0xAAFBBF24),
                  Color(0xEEF97316),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Lower',
                style: GoogleFonts.inter(fontSize: 9, color: Colors.white60),
              ),
              const SizedBox(width: 28),
              Text(
                'Higher',
                style: GoogleFonts.inter(fontSize: 9, color: Colors.white60),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrangeMaskPainter extends CustomPainter {
  _OrangeMaskPainter({
    required this.highlight,
    required this.pulse,
    required this.seed,
    required this.confidence,
  });

  final Rect highlight;
  final double pulse;
  final int seed;
  final int confidence;

  @override
  void paint(Canvas canvas, Size size) {
    if (highlight == Rect.zero) return;
    final path = _organicMask(size, highlight, seed);
    final bounds = path.getBounds();
    if (bounds.width < 6) return;

    final conf = (confidence / 100).clamp(0.45, 1.0);

    canvas.drawPath(
      path,
      Paint()
        ..color = _Fx.orange.withValues(alpha: 0.10 + pulse * 0.04)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = _Fx.orangeSoft.withValues(alpha: 0.12 * conf)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.radial(
          bounds.center,
          bounds.longestSide * 0.7,
          [
            _Fx.orange.withValues(alpha: 0.34 * conf),
            _Fx.orangeSoft.withValues(alpha: 0.22 * conf),
            _Fx.orange.withValues(alpha: 0.10 * conf),
          ],
          const [0.0, 0.55, 1.0],
        ),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = _Fx.orange.withValues(alpha: 0.35 + pulse * 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5 + pulse * 1.2
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = _Fx.orange.withValues(alpha: 0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _OrangeMaskPainter old) =>
      old.highlight != highlight ||
      old.pulse != pulse ||
      old.seed != seed ||
      old.confidence != confidence;
}

class _ConfidenceMapPainter extends CustomPainter {
  _ConfidenceMapPainter({
    required this.highlight,
    required this.confidence,
    required this.seed,
  });

  final Rect highlight;
  final int confidence;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    if (highlight == Rect.zero) return;

    final cx = (highlight.left + highlight.width / 2) * size.width;
    final cy = (highlight.top + highlight.height / 2) * size.height;
    final rx = highlight.width * size.width * 0.85;
    final ry = highlight.height * size.height * 0.85;
    final conf = (confidence / 100).clamp(0.4, 1.0);

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = _Fx.ink.withValues(alpha: 0.12),
    );

    final rng = math.Random(seed);
    final lobes = 3 + (seed % 2);
    for (var i = 0; i < lobes; i++) {
      final ox = (rng.nextDouble() - 0.5) * rx * 0.55;
      final oy = (rng.nextDouble() - 0.5) * ry * 0.55;
      final strength = (1.0 - i * 0.18) * conf;
      final r = math.max(rx, ry) * (0.55 + i * 0.12);
      canvas.drawCircle(
        Offset(cx + ox, cy + oy),
        r,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(cx + ox, cy + oy),
            r,
            [
              Color.lerp(
                const Color(0xFFF97316),
                const Color(0xFFEF4444),
                strength,
              )!.withValues(alpha: 0.42 * strength),
              const Color(0xFFFBBF24).withValues(alpha: 0.22 * strength),
              const Color(0xFF22D3EE).withValues(alpha: 0.10 * strength),
              Colors.transparent,
            ],
            const [0.0, 0.35, 0.65, 1.0],
          ),
      );
    }

    final coreR = math.min(rx, ry) * 0.42;
    canvas.drawCircle(
      Offset(cx, cy),
      coreR,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, cy),
          coreR,
          [
            _Fx.orange.withValues(alpha: 0.50 * conf),
            const Color(0xFFFBBF24).withValues(alpha: 0.18 * conf),
            Colors.transparent,
          ],
          const [0.0, 0.5, 1.0],
        ),
    );

    final path = _organicMask(size, highlight, seed);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(covariant _ConfidenceMapPainter old) =>
      old.highlight != highlight ||
      old.confidence != confidence ||
      old.seed != seed;
}

class _PulseFocusPainter extends CustomPainter {
  _PulseFocusPainter({
    required this.highlight,
    required this.pulse,
    required this.color,
  });

  final Rect highlight;
  final double pulse;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (highlight == Rect.zero) return;
    final c = Offset(
      (highlight.left + highlight.width / 2) * size.width,
      (highlight.top + highlight.height / 2) * size.height,
    );
    final r = 7.0 + pulse * 3.5;

    canvas.drawCircle(
      c,
      r + 10,
      Paint()..color = color.withValues(alpha: 0.10 + pulse * 0.08),
    );
    canvas.drawCircle(
      c,
      r + 4,
      Paint()
        ..color = color.withValues(alpha: 0.18 + pulse * 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.drawCircle(
      c,
      4.2,
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );
    canvas.drawCircle(c, 3.0, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PulseFocusPainter old) =>
      old.highlight != highlight || old.pulse != pulse || old.color != color;
}

Path _organicMask(Size size, Rect highlight, int seed) {
  final rng = math.Random(seed);
  final cx = (highlight.left + highlight.width / 2) * size.width;
  final cy = (highlight.top + highlight.height / 2) * size.height;
  final rx = (highlight.width * size.width) * 0.52;
  final ry = (highlight.height * size.height) * 0.52;
  const n = 20;
  final pts = <Offset>[];
  for (var i = 0; i < n; i++) {
    final a = (i / n) * math.pi * 2;
    final jitter = 0.80 + rng.nextDouble() * 0.36;
    final lobe = 1.0 + 0.07 * math.sin(a * 3 + seed * 0.01);
    pts.add(
      Offset(
        cx + math.cos(a) * rx * jitter * lobe,
        cy + math.sin(a) * ry * jitter * lobe,
      ),
    );
  }
  final path = Path();
  if (pts.isEmpty) return path;
  path.moveTo(
    (pts.last.dx + pts.first.dx) / 2,
    (pts.last.dy + pts.first.dy) / 2,
  );
  for (var i = 0; i < pts.length; i++) {
    final p = pts[i];
    final next = pts[(i + 1) % pts.length];
    final mid = Offset((p.dx + next.dx) / 2, (p.dy + next.dy) / 2);
    path.quadraticBezierTo(p.dx, p.dy, mid.dx, mid.dy);
  }
  path.close();
  return path;
}

class _ScanPainter extends CustomPainter {
  _ScanPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress >= 1) return;
    final y = size.height * Curves.easeInOut.transform(progress);
    final band = size.height * 0.12;
    canvas.drawRect(
      Rect.fromLTWH(0, y - band / 2, size.width, band),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, y - band / 2),
          Offset(0, y + band / 2),
          [
            Colors.transparent,
            _Fx.orangeSoft.withValues(alpha: 0.08),
            _Fx.orangeSoft.withValues(alpha: 0.22),
            _Fx.orangeSoft.withValues(alpha: 0.08),
            Colors.transparent,
          ],
          const [0.0, 0.25, 0.5, 0.75, 1.0],
        ),
    );
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = _Fx.orangeSoft.withValues(alpha: 0.5)
        ..strokeWidth = 1.2
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );
  }

  @override
  bool shouldRepaint(covariant _ScanPainter old) => old.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
// Explainable AI
// ─────────────────────────────────────────────────────────────────────────────

class _ExplainableAiCard extends StatelessWidget {
  const _ExplainableAiCard({
    required this.issue,
    required this.expanded,
    required this.onToggle,
  });

  final AnalysisIssue issue;
  final bool expanded;
  final VoidCallback onToggle;

  TextStyle get _subhead => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: _Fx.muted,
    letterSpacing: 0.4,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _Fx.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _Fx.orangeMist,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.visibility_outlined,
                      size: 18,
                      color: _Fx.orange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('What the AI noticed', style: _Fx.titleStyle()),
                        Text(
                          'Explainable photo cues — not a structural diagnosis',
                          style: _Fx.mutedStyle(),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: _Fx.muted,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 240),
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Visual evidence', style: _subhead),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final cue in issue.forensicVisualCues.take(4))
                        _EvidenceChip(label: cue),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Why this conclusion', style: _subhead),
                  const SizedBox(height: 8),
                  Text(
                    issue.forensicAiReasoning,
                    style: _Fx.bodyStyle(size: 14, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  Text('What can reduce confidence', style: _subhead),
                  const SizedBox(height: 8),
                  for (final f in issue.forensicConfidenceLimiters)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 5),
                            child: Icon(
                              Icons.remove_circle_outline_rounded,
                              size: 14,
                              color: _Fx.amber,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(f, style: _Fx.bodyStyle())),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceChip extends StatelessWidget {
  const _EvidenceChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _Fx.orangeMist,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _Fx.orange.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: _Fx.chipInk,
          height: 1.25,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Analysis metrics grid
// ─────────────────────────────────────────────────────────────────────────────

class _AnalysisGrid extends StatelessWidget {
  const _AnalysisGrid({required this.issue});
  final AnalysisIssue issue;

  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[
      ('Damage type', issue.forensicDamageType),
      ('Material', issue.forensicAffectedMaterial),
      ('Est. size', issue.forensicEstimatedSize),
      ('Detection', issue.forensicDetectionQuality),
      (CostCopy.shortLabel, issue.planningCostLabel),
      ('Priority', '${issue.severity} · ${issue.surfaceTimeline}'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ANALYSIS DETAILS', style: _Fx.sectionLabelStyle()),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, c) {
            final w = (c.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (label, value) in items)
                  SizedBox(
                    width: w,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      decoration: _Fx.card(radius: 14, shadow: 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: _Fx.muted,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            value,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: _Fx.ink,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Text(
          CostCopy.inlineNote,
          style: GoogleFonts.inter(
            fontSize: 12,
            height: 1.4,
            fontWeight: FontWeight.w500,
            color: _Fx.muted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          CostCopy.footnote,
          style: GoogleFonts.inter(
            fontSize: 12,
            height: 1.4,
            fontWeight: FontWeight.w500,
            color: _Fx.muted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          PrivacyCopy.screeningReminder,
          style: GoogleFonts.inter(
            fontSize: 12,
            height: 1.4,
            fontWeight: FontWeight.w500,
            color: _Fx.muted,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Limited visibility / retake
// ─────────────────────────────────────────────────────────────────────────────

class _LimitedVisibilityCard extends StatelessWidget {
  const _LimitedVisibilityCard({required this.issue, this.onRetake});
  final AnalysisIssue issue;
  final VoidCallback? onRetake;

  @override
  Widget build(BuildContext context) {
    final limited = issue.forensicConfidenceTitle == 'Limited Visibility';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: _Fx.card(
        radius: 16,
        shadow: 0,
        color: _Fx.amberMist,
        borderColor: _Fx.amberBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            limited
                ? 'Limited visibility in this photo'
                : 'More photos would improve accuracy',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _Fx.amberInk,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            issue.forensicRetakeAngleHint,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.4,
              color: _Fx.amberBody,
            ),
          ),
          if (onRetake != null) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: onRetake,
              icon: const Icon(Icons.camera_alt_rounded, size: 18),
              label: const Text('Capture a clearer angle'),
              style: FilledButton.styleFrom(
                backgroundColor: _Fx.amber,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RelatedContextBanner extends StatelessWidget {
  const _RelatedContextBanner({required this.issue});
  final AnalysisIssue issue;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _Fx.amberMist,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _Fx.amberBorder),
      ),
      child: Text(
        FindingRetakeService.relatedContextNote(issue),
        style: GoogleFonts.inter(
          fontSize: 13,
          height: 1.4,
          color: _Fx.amberBody,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _AngleStrip extends StatelessWidget {
  const _AngleStrip({
    required this.angles,
    required this.selected,
    required this.onSelect,
  });

  final List<SurfaceEvidenceAngle> angles;
  final int selected;
  final ValueChanged<int> onSelect;

  String _chipLabel(SurfaceEvidenceAngle a) {
    if (a.isPrimary) return 'Primary · ${a.label}';
    if (!a.supportsFinding) return 'Related · ${a.label}';
    return a.label;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('OTHER ANGLES', style: _Fx.sectionLabelStyle()),
        const SizedBox(height: 8),
        SizedBox(
          height: 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: angles.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final a = angles[i];
              final sel = i == selected;
              return GestureDetector(
                onTap: () => onSelect(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 108,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: sel ? _Fx.orange : _Fx.border,
                      width: sel ? 1.6 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _PhotoFill(photo: a.photo),
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
                            _chipLabel(a),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Timeline + next steps
// ─────────────────────────────────────────────────────────────────────────────

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({
    required this.timeline,
    required this.currentPhoto,
    required this.currentHighlight,
    required this.split,
    required this.onSplit,
  });

  final SurfaceEvidenceTimeline timeline;
  final XFile? currentPhoto;
  final Rect currentHighlight;
  final double split;
  final ValueChanged<double> onSplit;

  @override
  Widget build(BuildContext context) {
    final changeColor = timeline.worsened
        ? _Fx.danger
        : timeline.improved
        ? _Fx.success
        : _Fx.body;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _Fx.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Evidence Timeline', style: _Fx.titleStyle()),
          const SizedBox(height: 4),
          Text(
            'Approximate alignment of the same exterior surface across scans',
            style: _Fx.mutedStyle(),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth;
                  final splitX = w * split;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      if (timeline.priorPhoto != null)
                        _PhotoFill(photo: timeline.priorPhoto!)
                      else
                        const ColoredBox(color: _Fx.stagePlaceholder),
                      if (currentPhoto != null)
                        ClipRect(
                          clipper: _SplitClipper(split),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _PhotoFill(photo: currentPhoto!),
                              if (currentHighlight != Rect.zero)
                                CustomPaint(
                                  painter: _OrangeMaskPainter(
                                    highlight: currentHighlight,
                                    pulse: 0.4,
                                    seed: 7,
                                    confidence: 80,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      Positioned(
                        left: splitX - 1,
                        top: 0,
                        bottom: 0,
                        child: Container(width: 2, color: Colors.white),
                      ),
                      Positioned(
                        left: splitX - 14,
                        top: c.maxHeight / 2 - 14,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.drag_handle_rounded,
                            size: 16,
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onHorizontalDragUpdate: (d) {
                            onSplit((split + d.delta.dx / w).clamp(0.08, 0.92));
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            timeline.changeNarrative,
            style: GoogleFonts.inter(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: changeColor,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _SplitClipper extends CustomClipper<Rect> {
  _SplitClipper(this.split);
  final double split;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(
    size.width * split,
    0,
    size.width * (1 - split),
    size.height,
  );

  @override
  bool shouldReclip(covariant _SplitClipper old) => old.split != split;
}

class _TimelinePlaceholder extends StatelessWidget {
  const _TimelinePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _Fx.card(shadow: 0),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _Fx.orangeMist,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.timeline_rounded,
              color: _Fx.orange,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No prior photo of this area yet. Scan this same surface again '
              'later to compare — First Sign only pairs photos of the same '
              'exterior area.',
              style: _Fx.bodyStyle(size: 13, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _NextStepsCard extends StatelessWidget {
  const _NextStepsCard({required this.issue, this.onRetake});
  final AnalysisIssue issue;
  final VoidCallback? onRetake;

  @override
  Widget build(BuildContext context) {
    final steps = issue.surfaceRepairSteps.take(4).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _Fx.card(shadow: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Suggested next steps', style: _Fx.titleStyle()),
          const SizedBox(height: 12),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _Fx.teal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _Fx.teal,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      steps[i],
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        height: 1.4,
                        color: _Fx.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (onRetake != null) ...[
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: onRetake,
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              label: const Text('Retake supporting photo'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _Fx.ink,
                side: const BorderSide(color: _Fx.border),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Loads photo bytes once per path (avoids re-reading on every rebuild).
class _PhotoFill extends StatefulWidget {
  const _PhotoFill({required this.photo});
  final XFile photo;

  @override
  State<_PhotoFill> createState() => _PhotoFillState();
}

class _PhotoFillState extends State<_PhotoFill> {
  Future<Uint8List>? _bytes;
  String? _path;

  Future<Uint8List> _load() {
    final path = widget.photo.path;
    if (_path == path && _bytes != null) return _bytes!;
    _path = path;
    _bytes = widget.photo.readAsBytes();
    return _bytes!;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _load(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const ColoredBox(
            color: _Fx.stagePlaceholder,
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _Fx.orangeSoft,
                ),
              ),
            ),
          );
        }
        return Image.memory(
          snapshot.data!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
        );
      },
    );
  }
}
