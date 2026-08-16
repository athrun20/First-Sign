import 'dart:async' show unawaited;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../legal/product_copy.dart';
import '../models/saved_report.dart';
import '../services/capture_draft_store.dart';
import '../services/home_insight.dart';
import '../services/lead_store.dart';
import '../services/onboarding_store.dart';
import '../services/report_store.dart';
import '../widgets/brand_mark.dart';
import '../widgets/onboarding_sheet.dart';

/// Premium Home tokens — living AI dashboard (Apple Health for homes).
/// Score dial / digital twin stay on other screens.
abstract final class _HomeLux {
  static const bg = Color(0xFFF5F7F9);
  static const surface = Color(0xFFFFFFFF);
  static const glass = Color(0xF2FFFFFF);
  static const border = Color(0xFFE4E9EE);
  static const charcoal = Color(0xFF0F172A);
  static const charcoalMid = Color(0xFF1E293B);
  static const body = Color(0xFF475569);
  static const muted = Color(0xFF94A3B8);

  static const emerald = Color(0xFF059669);
  static const emeraldDeep = Color(0xFF047857);
  static const emeraldBright = Color(0xFF10B981);
  static const emeraldMist = Color(0xFFECFDF5);

  static const navy = Color(0xFF0F2744);
  static const navySoft = Color(0xFF1E3A5F);
  static const navyMist = Color(0xFFEEF2F7);

  static const cardRadius = 24.0;

  static List<BoxShadow> softShadow({double intensity = 1}) => [
        BoxShadow(
          color: navy.withValues(alpha: 0.06 * intensity),
          blurRadius: 34,
          offset: const Offset(0, 14),
        ),
        BoxShadow(
          color: emerald.withValues(alpha: 0.04 * intensity),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> cardShadow({double intensity = 1}) => [
        BoxShadow(
          color: navy.withValues(alpha: 0.05 * intensity),
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: navy.withValues(alpha: 0.018 * intensity),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> ctaGlow({double t = 0}) => [
        BoxShadow(
          color: emerald.withValues(alpha: 0.32 + t * 0.14),
          blurRadius: 24 + t * 12,
          offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: emeraldBright.withValues(alpha: 0.14 + t * 0.08),
          blurRadius: 40 + t * 10,
          offset: const Offset(0, 14),
        ),
      ];

  static BoxDecoration glassCard({double radius = cardRadius}) => BoxDecoration(
        color: glass,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.88),
          width: 1,
        ),
        boxShadow: softShadow(intensity: 0.9),
        // Soft, native — not multi-stop template glass.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            surface.withValues(alpha: 0.98),
            emeraldMist.withValues(alpha: 0.42),
          ],
        ),
      );
}

/// Premium FirstSign Home (Intro) — emotional first impression, no score dial.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late final AnimationController _entrance;
  late final AnimationController _ctaPulse;
  late final AnimationController _ambient;
  late final Animation<double> _topBar;
  late final Animation<double> _hero;
  late final Animation<double> _cta;
  late final Animation<double> _insight;
  late final Animation<double> _trust;

  bool _onboardingChecked = false;

  @override
  void initState() {
    super.initState();
    ReportStore.instance.addListener(_onStoresChanged);
    LeadStore.instance.addListener(_onStoresChanged);
    CaptureDraftStore.instance.addListener(_onStoresChanged);
    unawaited(ReportStore.instance.ensureLoaded());
    unawaited(LeadStore.instance.ensureLoaded());
    unawaited(CaptureDraftStore.instance.ensureLoaded());
    unawaited(OnboardingStore.instance.ensureLoaded());

    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _ctaPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    unawaited(_ctaPulse.repeat(reverse: true));
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 9000),
    );
    unawaited(_ambient.repeat(reverse: true));

    Animation<double> slot(double begin, double end) {
      return CurvedAnimation(
        parent: _entrance,
        curve: Interval(begin, end, curve: Curves.easeOutCubic),
      );
    }

    _topBar = slot(0.0, 0.22);
    _hero = slot(0.04, 0.42);
    _cta = slot(0.18, 0.55);
    _insight = slot(0.32, 0.72);
    _trust = slot(0.48, 0.92);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_entrance.forward());
      unawaited(_maybeShowFirstRunOnboarding());
    });
  }

  Future<void> _maybeShowFirstRunOnboarding() async {
    if (_onboardingChecked) return;
    _onboardingChecked = true;
    await OnboardingStore.instance.ensureLoaded();
    await ReportStore.instance.ensureLoaded();
    if (!mounted) return;
    if (!OnboardingStore.instance.shouldAutoShow(
      reportCount: ReportStore.instance.reports.length,
    )) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (!mounted) return;
    await showFirstSignOnboarding(context);
  }

  Future<void> _openHowItWorksTips() async {
    await showFirstSignOnboarding(context, markComplete: true);
  }

  void _onStoresChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ReportStore.instance.removeListener(_onStoresChanged);
    LeadStore.instance.removeListener(_onStoresChanged);
    CaptureDraftStore.instance.removeListener(_onStoresChanged);
    _entrance.dispose();
    _ctaPulse.dispose();
    _ambient.dispose();
    super.dispose();
  }

  Widget _reveal(Animation<double> animation, Widget child, {double dy = 14}) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, dy * (1 - t)),
            child: child,
          ),
        );
      },
    );
  }

  void _startCapture() {
    unawaited(Navigator.of(context).pushNamed('/guided-capture'));
  }

  void _startQuickScan() {
    unawaited(
      Navigator.of(context).pushNamed(
        '/guided-capture',
        arguments: const {'singlePhotoMode': true},
      ),
    );
  }

  void _startDemo() {
    unawaited(Navigator.of(context).pushNamed('/demo'));
  }

  void _resumeDraft() {
    final draft = CaptureDraftStore.instance;
    unawaited(
      Navigator.of(context).pushNamed(
        '/guided-capture',
        arguments: {'seed': draft.photos, 'focus': draft.focusSlot},
      ),
    );
  }

  void _openLatestReport(SavedReport report) {
    unawaited(
      Navigator.of(context).pushNamed('/saved-report', arguments: report),
    );
  }

  void _openReports() {
    unawaited(Navigator.of(context).pushNamed('/report-history'));
  }

  void _openContractors() {
    unawaited(Navigator.of(context).pushNamed('/contractors'));
  }

  void _openProfile() {
    unawaited(Navigator.of(context).pushNamed('/profile'));
  }

  SavedReport? get _latestReport {
    final list = ReportStore.instance.reports;
    return list.isEmpty ? null : list.first;
  }

  int get _reportCount => ReportStore.instance.reports.length;

  int get _newLeadCount => LeadStore.instance.countForStatus('New');

  bool get _hasDraft => CaptureDraftStore.instance.hasDraft;

  @override
  Widget build(BuildContext context) {
    final latest = _latestReport;
    final draft = CaptureDraftStore.instance;
    final isReturning = latest != null || _reportCount > 0;

    return Scaffold(
      backgroundColor: _HomeLux.bg,
      body: Stack(
        children: [
          // Living ambient: emerald glow + faint blueprint.
          const Positioned.fill(child: _BlueprintTexture()),
          AnimatedBuilder(
            animation: _ambient,
            builder: (context, _) {
              final t = Curves.easeInOut.transform(_ambient.value);
              return Stack(
                children: [
                  Positioned(
                    top: -140 + t * 12,
                    right: -90,
                    child: _GlowOrb(
                      size: 320,
                      colors: [
                        _HomeLux.emerald.withValues(alpha: 0.13 + t * 0.04),
                        _HomeLux.emerald.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 160 - t * 8,
                    left: -120,
                    child: _GlowOrb(
                      size: 300,
                      colors: [
                        _HomeLux.navy.withValues(alpha: 0.08 + t * 0.02),
                        _HomeLux.navy.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: 60 + t * 10,
                    right: -50,
                    child: _GlowOrb(
                      size: 240,
                      colors: [
                        _HomeLux.emeraldBright.withValues(alpha: 0.07),
                        _HomeLux.emeraldBright.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 300,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            _HomeLux.emeraldMist.withValues(alpha: 0.45),
                            _HomeLux.navyMist.withValues(alpha: 0.35),
                            _HomeLux.bg.withValues(alpha: 0.0),
                          ],
                          stops: const [0.0, 0.4, 1.0],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          SafeArea(
            child: Column(
              children: [
                _reveal(
                  _topBar,
                  _TopBar(
                    reportCount: _reportCount,
                    newLeadCount: _newLeadCount,
                    onContractors: _openContractors,
                    onReports: _openReports,
                    onProfile: _openProfile,
                    onTips: _openHowItWorksTips,
                  ),
                  dy: 8,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    // Phone-first column; cap width on web/desktop so the hero
                    // does not stretch into empty template space.
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (kIsWeb) ...[
                              _reveal(
                                _hero,
                                const _WebBestOnPhoneNote(),
                                dy: 6,
                              ),
                              const SizedBox(height: 12),
                            ],
                            // Living hero: status → what matters → primary action.
                            _reveal(
                              _hero,
                              _LivingDashboardHero(
                                latestReport: latest,
                                pulse: _ctaPulse,
                                onScan: _startCapture,
                                onQuickScan: _startQuickScan,
                                onOpenReport: latest == null
                                    ? null
                                    : () => _openLatestReport(latest),
                              ),
                              dy: 16,
                            ),
                            if (_hasDraft) ...[
                              const SizedBox(height: 14),
                              _reveal(
                                _cta,
                                _ResumeDraftCard(
                                  filledCount: draft.filledCount,
                                  relativeLabel: draft.relativeLabel,
                                  onResume: _resumeDraft,
                                  onDiscard: () async {
                                    await CaptureDraftStore.instance.clear();
                                  },
                                ),
                                dy: 10,
                              ),
                            ],
                            if (latest != null) ...[
                              const SizedBox(height: 14),
                              _reveal(
                                _insight,
                                _AiInsightCard(
                                  report: latest,
                                  onOpen: () => _openLatestReport(latest),
                                ),
                                dy: 12,
                              ),
                            ] else ...[
                              const SizedBox(height: 12),
                              _reveal(
                                _insight,
                                _AiEmptyInsightCard(onDemo: _startDemo),
                                dy: 12,
                              ),
                            ],
                            if (isReturning) ...[
                              const SizedBox(height: 20),
                              _reveal(
                                _trust,
                                _QuietSecondaryLinks(
                                  reportCount: _reportCount,
                                  onReports: _openReports,
                                  onTips: _openHowItWorksTips,
                                ),
                                dy: 8,
                              ),
                            ] else ...[
                              const SizedBox(height: 18),
                              _reveal(
                                _trust,
                                const _QuietTrustFooter(),
                                dy: 6,
                              ),
                              const SizedBox(height: 4),
                              _reveal(
                                _trust,
                                Center(
                                  child: TextButton(
                                    onPressed: _startDemo,
                                    child: Text(
                                      'Try a sample home first',
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: _HomeLux.emeraldDeep,
                                      ),
                                    ),
                                  ),
                                ),
                                dy: 6,
                              ),
                            ],
                          ],
                        ),
                      ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Top bar — minimal, consumer-clean
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onContractors,
    required this.onReports,
    required this.onProfile,
    required this.onTips,
    this.reportCount = 0,
    this.newLeadCount = 0,
  });

  final VoidCallback onContractors;
  final VoidCallback onReports;
  final VoidCallback onProfile;
  final VoidCallback onTips;
  final int reportCount;
  final int newLeadCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 4),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: _HomeLux.cardShadow(intensity: 0.4),
            ),
            child: const BrandMark(size: 40, radius: 12),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ProductCopy.displayName,
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _HomeLux.charcoal,
                  letterSpacing: -0.4,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'AI property companion',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: _HomeLux.muted,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
          const Spacer(),
          _NavIconButton(
            tooltip: 'How it works',
            icon: Icons.lightbulb_outline_rounded,
            onPressed: onTips,
          ),
          const SizedBox(width: 4),
          _NavIconButton(
            tooltip: 'Your reports',
            icon: Icons.folder_outlined,
            badge: reportCount > 0 ? reportCount : null,
            onPressed: onReports,
          ),
          const SizedBox(width: 4),
          _NavIconButton(
            tooltip: 'Pro tools',
            icon: Icons.handyman_outlined,
            badge: newLeadCount > 0 ? newLeadCount : null,
            onPressed: onContractors,
          ),
          const SizedBox(width: 4),
          _NavIconButton(
            tooltip: 'Profile',
            icon: Icons.person_outline_rounded,
            onPressed: onProfile,
          ),
        ],
      ),
    );
  }
}

class _NavIconButton extends StatelessWidget {
  const _NavIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.badge,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _HomeLux.surface.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _HomeLux.border, width: 0.75),
                ),
                child: Icon(icon, size: 19, color: _HomeLux.charcoalMid),
              ),
              if (badge != null && badge! > 0)
                Positioned(
                  top: -3,
                  right: -3,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: _HomeLux.emerald,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: _HomeLux.bg, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      badge! > 9 ? '9+' : '$badge',
                      style: GoogleFonts.inter(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Living dashboard hero — How is my home? → What matters? → What next?
// No mini twin here (interactive Digital Twin lives on Home Health).
// ─────────────────────────────────────────────────────────────────────────────

class _LivingDashboardHero extends StatelessWidget {
  const _LivingDashboardHero({
    required this.pulse,
    required this.onScan,
    required this.onQuickScan,
    this.latestReport,
    this.onOpenReport,
  });

  final SavedReport? latestReport;
  final AnimationController pulse;
  final VoidCallback onScan;
  final VoidCallback onQuickScan;
  final VoidCallback? onOpenReport;

  @override
  Widget build(BuildContext context) {
    final report = latestReport;
    final hasReport = report != null;
    final greeting = homeGreeting(returning: hasReport);
    final statusColor =
        hasReport ? homeStatusColor(report.score) : _HomeLux.emerald;
    final reassurance =
        hasReport ? homeReassuranceLine(report.report) : 'Not scanned yet';
    final band =
        hasReport ? homeStatusFromScore(report.score) : '';
    // Single place for “what matters” — FirstSign AI does not repeat this.
    final whatMatters = hasReport
        ? latestInsightLine(report.report)
        : 'Capture clear exterior photos to unlock your first calm condition report.';

    // Empty state is tighter so the card feels intentional, not sparse.
    final gapAfterTitle = hasReport ? 24.0 : 18.0;
    final gapBeforeRule = hasReport ? 22.0 : 16.0;
    final gapAfterRule = hasReport ? 18.0 : 14.0;
    final gapBeforeCta = hasReport ? 24.0 : 18.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(_HomeLux.cardRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          decoration: _HomeLux.glassCard(),
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _BlueprintPainter(
                      color: _HomeLux.navy.withValues(alpha: 0.022),
                      dense: true,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  22,
                  hasReport ? 24 : 22,
                  22,
                  hasReport ? 20 : 18,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greeting,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _HomeLux.emeraldDeep,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hasReport ? 'Your home' : 'Know before problems grow.',
                      style: GoogleFonts.inter(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: _HomeLux.charcoal,
                        letterSpacing: -1.0,
                        height: 1.1,
                      ),
                    ),

                    SizedBox(height: gapAfterTitle),

                    // ── How is my home? + compact Home Health indicator ──
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 9,
                                height: 9,
                                margin: const EdgeInsets.only(top: 6),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: statusColor,
                                  boxShadow: [
                                    BoxShadow(
                                      color: statusColor.withValues(alpha: 0.35),
                                      blurRadius: 7,
                                      spreadRadius: 0.4,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      reassurance,
                                      style: GoogleFonts.inter(
                                        fontSize: 17.5,
                                        fontWeight: FontWeight.w700,
                                        color: _HomeLux.charcoal,
                                        letterSpacing: -0.35,
                                        height: 1.22,
                                      ),
                                    ),
                                    if (hasReport) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Scanned ${report.relativeDateLabel}',
                                        style: GoogleFonts.inter(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                          color: _HomeLux.muted,
                                          letterSpacing: -0.05,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (hasReport) ...[
                          const SizedBox(width: 12),
                          _CompactHealthScore(
                            score: report.score,
                            band: band,
                            accent: statusColor,
                          ),
                        ],
                      ],
                    ),

                    // Soft section break — intentional rhythm, not empty air.
                    SizedBox(height: gapBeforeRule),
                    Container(
                      height: 1,
                      width: double.infinity,
                      color: _HomeLux.border.withValues(alpha: 0.85),
                    ),
                    SizedBox(height: gapAfterRule),

                    // ── What matters (once only) ──────────────────────────
                    Text(
                      hasReport ? 'WHAT MATTERS' : 'GET STARTED',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: _HomeLux.muted,
                        letterSpacing: 1.05,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      whatMatters,
                      style: GoogleFonts.inter(
                        fontSize: hasReport ? 16 : 15,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                        color: _HomeLux.charcoalMid,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (hasReport && onOpenReport != null) ...[
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: onOpenReport,
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'View latest report',
                              style: GoogleFonts.inter(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: _HomeLux.emeraldDeep,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 15,
                              color: _HomeLux.emeraldDeep.withValues(alpha: 0.9),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // ── Primary action ────────────────────────────────────
                    SizedBox(height: gapBeforeCta),
                    AnimatedBuilder(
                      animation: pulse,
                      builder: (context, child) {
                        final t = Curves.easeInOut.transform(pulse.value);
                        return Transform.scale(
                          scale: 1.0 + t * 0.008,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: _HomeLux.ctaGlow(t: t * 0.7),
                            ),
                            child: child,
                          ),
                        );
                      },
                      child: SizedBox(
                        height: 54,
                        width: double.infinity,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                _HomeLux.emeraldBright,
                                _HomeLux.emerald,
                                _HomeLux.emeraldDeep,
                              ],
                              stops: [0.0, 0.5, 1.0],
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: onScan,
                              borderRadius: BorderRadius.circular(16),
                              child: Center(
                                child: Text(
                                  'Scan My Home',
                                  style: GoogleFonts.inter(
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: -0.25,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'Guided multi-angle exterior scan',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _HomeLux.muted,
                          letterSpacing: -0.05,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: TextButton(
                        onPressed: onQuickScan,
                        style: TextButton.styleFrom(
                          foregroundColor: _HomeLux.body,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: 'Quick Scan',
                                style: GoogleFonts.inter(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: _HomeLux.charcoalMid,
                                ),
                              ),
                              TextSpan(
                                text: '  ·  one photo  ·  first look',
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: _HomeLux.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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
}

/// Compact Home Health score — comprehension only, not a dashboard dial.
class _CompactHealthScore extends StatelessWidget {
  const _CompactHealthScore({
    required this.score,
    required this.band,
    required this.accent,
  });

  final int score;
  final String band;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 64),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _HomeLux.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.2), width: 1),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$score',
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: _HomeLux.charcoal,
              letterSpacing: -0.8,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            band,
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: accent,
              letterSpacing: 0.1,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FirstSign AI companion — extra context, never the same “what matters” line
// ─────────────────────────────────────────────────────────────────────────────

class _AiInsightCard extends StatelessWidget {
  const _AiInsightCard({required this.report, required this.onOpen});

  final SavedReport report;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    // Additional framing only — finding title lives once in the hero.
    final note = firstSignAiCompanionNote(report.report);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(_HomeLux.cardRadius),
        splashColor: _HomeLux.emerald.withValues(alpha: 0.04),
        child: Ink(
          decoration: BoxDecoration(
            color: _HomeLux.surface,
            borderRadius: BorderRadius.circular(_HomeLux.cardRadius),
            border: Border.all(
              color: _HomeLux.border,
              width: 1,
            ),
            boxShadow: _HomeLux.cardShadow(intensity: 0.7),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 17, 16, 17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        color: _HomeLux.navyMist,
                        border: Border.all(
                          color: _HomeLux.navy.withValues(alpha: 0.07),
                        ),
                      ),
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        size: 15,
                        color: _HomeLux.navySoft.withValues(alpha: 0.88),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ProductCopy.companionLabel,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _HomeLux.charcoal,
                              letterSpacing: -0.2,
                            ),
                          ),
                          Text(
                            'What to do next',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: _HomeLux.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: _HomeLux.muted.withValues(alpha: 0.8),
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  note,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    height: 1.48,
                    fontWeight: FontWeight.w400,
                    color: _HomeLux.body,
                    letterSpacing: -0.08,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty-state AI card — intentional, not blank.
class _AiEmptyInsightCard extends StatelessWidget {
  const _AiEmptyInsightCard({required this.onDemo});

  final VoidCallback onDemo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: _HomeLux.surface,
        borderRadius: BorderRadius.circular(_HomeLux.cardRadius),
        border: Border.all(color: _HomeLux.border, width: 1),
        boxShadow: _HomeLux.cardShadow(intensity: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: _HomeLux.navyMist,
                  border: Border.all(
                    color: _HomeLux.navy.withValues(alpha: 0.08),
                  ),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: _HomeLux.navySoft.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ProductCopy.companionLabel,
                      style: GoogleFonts.inter(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: _HomeLux.charcoal,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      'After your first scan',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _HomeLux.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'You’ll get calm next-step context for your exterior — '
            'separate from the main finding, ready when you are.',
            style: GoogleFonts.inter(
              fontSize: 14.5,
              height: 1.45,
              fontWeight: FontWeight.w400,
              color: _HomeLux.body,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onDemo,
            style: TextButton.styleFrom(
              foregroundColor: _HomeLux.emeraldDeep,
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'See a sample insight',
              style: GoogleFonts.inter(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: _HomeLux.emeraldDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quiet first-run trust line — not a product brochure strip
// ─────────────────────────────────────────────────────────────────────────────

class _QuietTrustFooter extends StatelessWidget {
  const _QuietTrustFooter();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Photo screening  ·  PDF reports  ·  No account needed',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: _HomeLux.muted,
          letterSpacing: 0.05,
          height: 1.35,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quiet secondary links (returning users only)
// ─────────────────────────────────────────────────────────────────────────────

class _QuietSecondaryLinks extends StatelessWidget {
  const _QuietSecondaryLinks({
    required this.reportCount,
    required this.onReports,
    required this.onTips,
  });

  final int reportCount;
  final VoidCallback onReports;
  final VoidCallback onTips;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SoftLinkChip(
            icon: Icons.folder_outlined,
            label: reportCount == 1 ? '1 report' : '$reportCount reports',
            onTap: onReports,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SoftLinkChip(
            icon: Icons.help_outline_rounded,
            label: 'How it works',
            onTap: onTips,
          ),
        ),
      ],
    );
  }
}

class _SoftLinkChip extends StatelessWidget {
  const _SoftLinkChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: _HomeLux.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _HomeLux.border, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: _HomeLux.navySoft),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: _HomeLux.charcoalMid,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Resume draft
// ─────────────────────────────────────────────────────────────────────────────

class _ResumeDraftCard extends StatelessWidget {
  const _ResumeDraftCard({
    required this.filledCount,
    required this.relativeLabel,
    required this.onResume,
    required this.onDiscard,
  });

  final int filledCount;
  final String relativeLabel;
  final VoidCallback onResume;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: _HomeLux.emeraldMist.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _HomeLux.emerald.withValues(alpha: 0.16),
          width: 0.85,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _HomeLux.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.photo_camera_back_outlined,
              color: _HomeLux.emerald,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Resume capture',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _HomeLux.charcoal,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$filledCount photo${filledCount == 1 ? '' : 's'} saved'
                  '${relativeLabel.isEmpty ? '' : ' · $relativeLabel'}',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: _HomeLux.body,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onDiscard,
            child: Text(
              'Discard',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: _HomeLux.muted,
                fontSize: 12.5,
              ),
            ),
          ),
          FilledButton(
            onPressed: onResume,
            style: FilledButton.styleFrom(
              backgroundColor: _HomeLux.emerald,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Web note + ambient orb
// ─────────────────────────────────────────────────────────────────────────────

class _WebBestOnPhoneNote extends StatelessWidget {
  const _WebBestOnPhoneNote();

  @override
  Widget build(BuildContext context) {
    // Quiet utility line — not a marketing banner.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.phone_iphone_rounded,
            size: 15,
            color: _HomeLux.muted.withValues(alpha: 0.95),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Best on a phone with the camera · on web, try Demo or upload clear exterior photos',
              style: GoogleFonts.inter(
                fontSize: 12,
                height: 1.4,
                color: _HomeLux.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.colors});

  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }
}

/// Full-screen faint blueprint grid — luxury depth without clutter.
class _BlueprintTexture extends StatelessWidget {
  const _BlueprintTexture();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _BlueprintPainter(
          color: _HomeLux.navy.withValues(alpha: 0.028),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _BlueprintPainter extends CustomPainter {
  _BlueprintPainter({required this.color, this.dense = false});

  final Color color;
  final bool dense;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;

    final step = dense ? 18.0 : 28.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Soft diagonal construction lines
    final diag = Paint()
      ..color = color.withValues(alpha: color.a * 0.55)
      ..strokeWidth = 0.55;
    canvas.drawLine(Offset(0, size.height * 0.2), Offset(size.width * 0.55, 0), diag);
    canvas.drawLine(
      Offset(size.width * 0.4, size.height),
      Offset(size.width, size.height * 0.35),
      diag,
    );
  }

  @override
  bool shouldRepaint(covariant _BlueprintPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.dense != dense;
}
