import 'dart:async' show unawaited;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/twin_zone.dart';
import '../theme/app_lux.dart';

export '../models/twin_zone.dart';

/// Premium living AI digital twin — Vision Pro / Tesla-class aesthetic.
///
/// Clean materials, holographic analysis overlay, soft motion, and zone taps
/// that filter findings. Not a toy icon.
class DigitalTwinHouse extends StatefulWidget {
  const DigitalTwinHouse({
    super.key,
    this.size = 340,
    this.selectedZone = TwinZone.none,
    this.onZoneSelected,
    this.scrollProgress = 0,
    this.autoRotate = true,
    this.showMarkers = true,
    this.compact = false,
    this.markedZones = const {},
  });

  final double size;
  final TwinZone selectedZone;
  final ValueChanged<TwinZone>? onZoneSelected;
  final double scrollProgress;
  final bool autoRotate;
  final bool showMarkers;
  final bool compact;

  /// Zones that have findings — pulse amber/red when [showMarkers] is true.
  final Set<TwinZone> markedZones;

  @override
  State<DigitalTwinHouse> createState() => _DigitalTwinHouseState();
}

class _DigitalTwinHouseState extends State<DigitalTwinHouse>
    with TickerProviderStateMixin {
  /// Gentle yaw sway (±~7°) over several seconds.
  late final AnimationController _yaw;

  /// Soft vertical float.
  late final AnimationController _float;

  /// Full AI scan sweep cycle (~9s).
  late final AnimationController _scan;

  /// Finding / node pulse.
  late final AnimationController _pulse;

  /// Ground scan ring rotation.
  late final AnimationController _ring;

  @override
  void initState() {
    super.initState();
    _yaw = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    );
    if (widget.autoRotate) unawaited(_yaw.repeat(reverse: true));

    _float = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    );
    unawaited(_float.repeat(reverse: true));

    _scan = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 9000),
    );
    unawaited(_scan.repeat());

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    unawaited(_pulse.repeat(reverse: true));

    _ring = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );
    unawaited(_ring.repeat());
  }

  @override
  void didUpdateWidget(covariant DigitalTwinHouse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoRotate && !_yaw.isAnimating) {
      unawaited(_yaw.repeat(reverse: true));
    } else if (!widget.autoRotate && _yaw.isAnimating) {
      _yaw.stop();
    }
  }

  @override
  void dispose() {
    _yaw.dispose();
    _float.dispose();
    _scan.dispose();
    _pulse.dispose();
    _ring.dispose();
    super.dispose();
  }

  TwinZone _hitTest(Offset local, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 + 4;
    final dx = local.dx - cx;
    final dy = local.dy - cy;
    if (dy < -size.height * 0.18) return TwinZone.roof;
    if (dy > size.height * 0.24) return TwinZone.foundation;
    if (dx.abs() < size.width * 0.13 &&
        dy > -size.height * 0.08 &&
        dy < size.height * 0.14) {
      return TwinZone.windows;
    }
    if (dy > -size.height * 0.20 &&
        dy < -size.height * 0.02 &&
        dx.abs() > size.width * 0.08) {
      return TwinZone.gutters;
    }
    if (dy > size.height * 0.06 && dy < size.height * 0.24) {
      return TwinZone.gutters;
    }
    return TwinZone.siding;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return AnimatedBuilder(
      animation: Listenable.merge([_yaw, _float, _scan, _pulse, _ring]),
      builder: (context, _) {
        // Ease yaw through a soft curve so the 5–10° sway feels organic.
        final yawT = Curves.easeInOut.transform(_yaw.value);
        final yaw = (yawT * 2 - 1) * 0.14; // ≈ ±8°
        final floatY = math.sin(_float.value * math.pi) * -5.5;
        final camY = -2 + widget.scrollProgress * 10 + floatY;
        final scale = 1.0 - widget.scrollProgress * 0.025;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: widget.onZoneSelected == null
              ? null
              : (d) {
                  final zone = _hitTest(d.localPosition, Size(s, s));
                  widget.onZoneSelected!(zone);
                },
          child: SizedBox(
            width: s,
            height: s,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Stage: white → light gray + radial glow
                CustomPaint(
                  size: Size(s, s),
                  painter: _StagePainter(pulse: _pulse.value),
                ),
                // Soft floating model + subtle perspective
                Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.00085)
                    ..translateByDouble(0.0, camY, 0.0, 1.0)
                    ..scaleByDouble(scale, scale, scale, 1.0)
                    ..rotateY(yaw + widget.scrollProgress * 0.06)
                    ..rotateX(0.12 + widget.scrollProgress * 0.04),
                  child: CustomPaint(
                    size: Size(s * 0.94, s * 0.94),
                    painter: _LivingTwinPainter(
                      selected: widget.selectedZone,
                      pulse: _pulse.value,
                      scan: _scan.value,
                      ring: _ring.value,
                      scroll: widget.scrollProgress,
                      showMarkers: widget.showMarkers,
                      markedZones: widget.markedZones,
                    ),
                  ),
                ),
                if (!widget.compact) _buildZoneLabel(s),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildZoneLabel(double s) {
    const labels = <TwinZone, String>{
      TwinZone.roof: 'Roof',
      TwinZone.siding: 'Siding',
      TwinZone.windows: 'Windows',
      TwinZone.foundation: 'Foundation',
      TwinZone.gutters: 'Gutters',
    };
    if (widget.selectedZone == TwinZone.none ||
        !labels.containsKey(widget.selectedZone)) {
      return const SizedBox.shrink();
    }
    final isMarked = widget.markedZones.contains(widget.selectedZone);
    return Positioned(
      top: s * 0.035,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 240),
        opacity: 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(AppLux.radiusPill),
            border: Border.all(
              color: isMarked
                  ? AppLux.warning.withValues(alpha: 0.35)
                  : const Color(0xFFE2E8F0),
              width: 0.85,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6.5,
                height: 6.5,
                decoration: BoxDecoration(
                  color: isMarked ? AppLux.warning : const Color(0xFF14B8A6),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color:
                          (isMarked ? AppLux.warning : const Color(0xFF14B8A6))
                              .withValues(alpha: 0.45),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                labels[widget.selectedZone]!,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Stage background ──────────────────────────────────────────────────────────

class _StagePainter extends CustomPainter {
  _StagePainter({required this.pulse});
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Clean white → light gray
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(size.width * 0.5, 0),
          Offset(size.width * 0.5, size.height),
          const [Color(0xFFFFFFFF), Color(0xFFF4F6F8), Color(0xFFEEF1F4)],
          const [0.0, 0.55, 1.0],
        ),
    );
    // Soft radial teal glow behind the model
    final cx = size.width / 2;
    final cy = size.height * 0.48;
    canvas.drawCircle(
      Offset(cx, cy),
      size.width * 0.42,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, cy),
          size.width * 0.42,
          [
            const Color(0xFF14B8A6).withValues(alpha: 0.06 + pulse * 0.02),
            const Color(0xFF0EA5E9).withValues(alpha: 0.03),
            Colors.transparent,
          ],
          const [0.0, 0.45, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _StagePainter old) => old.pulse != pulse;
}

// ── Living twin painter ───────────────────────────────────────────────────────

class _LivingTwinPainter extends CustomPainter {
  _LivingTwinPainter({
    required this.selected,
    required this.pulse,
    required this.scan,
    required this.ring,
    required this.scroll,
    required this.showMarkers,
    this.markedZones = const {},
  });

  final TwinZone selected;
  final double pulse;
  final double scan;
  final double ring;
  final double scroll;
  final bool showMarkers;
  final Set<TwinZone> markedZones;

  // Cool premium materials (Vision Pro / Tesla calm tech)
  static const _bodyHi = Color(0xFFF8FAFC);
  static const _bodyMid = Color(0xFFE8EEF3);
  static const _bodyShade = Color(0xFFCBD5E1);
  static const _bodyDeep = Color(0xFF94A3B8);
  static const _roofHi = Color(0xFF334155);
  static const _roofMid = Color(0xFF1E293B);
  static const _roofDeep = Color(0xFF0F172A);
  static const _glassHi = Color(0xFFCCFBF1);
  static const _glassMid = Color(0xFF5EEAD4);
  static const _glassLo = Color(0xFF0F766E);
  static const _foundationHi = Color(0xFF64748B);
  static const _foundationLo = Color(0xFF334155);
  static const _metal = Color(0xFF94A3B8);
  static const _holo = Color(0xFF14B8A6);
  static const _holoSoft = Color(0xFF5EEAD4);
  static const _holoCyan = Color(0xFF22D3EE);
  static const _issueAmber = Color(0xFFF59E0B);
  static const _issueRed = Color(0xFFEF4444);

  bool _marked(TwinZone z) => showMarkers && markedZones.contains(z);

  Color _accentFor(TwinZone zone) {
    if (_marked(zone)) {
      // Roof / foundation tend higher severity → red; others amber.
      if (zone == TwinZone.roof || zone == TwinZone.foundation) {
        return _issueRed;
      }
      return _issueAmber;
    }
    return _holo;
  }

  double _zonePulse(TwinZone zone) {
    if (selected == zone) return 0.55 + pulse * 0.45;
    if (_marked(zone)) return 0.35 + pulse * 0.55;
    return 0.0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 + size.height * 0.02;
    final u = size.width * 0.195;

    // ── Ground scan ring + soft contact shadow ────────────────────────────
    _paintScanRing(canvas, Offset(cx, cy + u * 1.78), u);
    _paintContactShadow(canvas, Offset(cx, cy + u * 1.62), u);

    // Geometry anchors (shared by solid + wireframe)
    final geo = _HouseGeo(cx: cx, cy: cy, u: u);

    // ── Solid house (premium materials) ───────────────────────────────────
    _paintFoundation(canvas, geo);
    _paintBody(canvas, geo);
    _paintWindows(canvas, geo);
    _paintDoor(canvas, geo);
    _paintRoof(canvas, geo);
    _paintGutters(canvas, geo);

    // ── Holographic wireframe overlay ─────────────────────────────────────
    _paintHoloWireframe(canvas, geo);

    // ── Data nodes + connection paths ─────────────────────────────────────
    _paintDataNetwork(canvas, geo);

    // ── AI scan sweep ─────────────────────────────────────────────────────
    _paintScanSweep(canvas, geo);

    // ── Finding zone pulses (no heavy markers) ────────────────────────────
    _paintFindingPulses(canvas, geo);
  }

  void _paintContactShadow(Canvas canvas, Offset c, double u) {
    canvas.drawOval(
      Rect.fromCenter(center: c, width: u * 2.9, height: u * 0.38),
      Paint()
        ..shader = ui.Gradient.radial(
          c,
          u * 1.5,
          [
            const Color(0xFF0F172A).withValues(alpha: 0.10),
            const Color(0xFF0F172A).withValues(alpha: 0.03),
            Colors.transparent,
          ],
          const [0.0, 0.45, 1.0],
        ),
    );
  }

  void _paintScanRing(Canvas canvas, Offset c, double u) {
    final rot = ring * 2 * math.pi;
    // Faint outer ring
    canvas.drawOval(
      Rect.fromCenter(center: c, width: u * 3.55, height: u * 0.55),
      Paint()
        ..color = _holo.withValues(alpha: 0.10 + pulse * 0.04)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
    // Soft fill disc
    canvas.drawOval(
      Rect.fromCenter(center: c, width: u * 3.2, height: u * 0.48),
      Paint()
        ..shader = ui.Gradient.radial(
          c,
          u * 1.7,
          [
            _holoCyan.withValues(alpha: 0.05 + pulse * 0.02),
            _holo.withValues(alpha: 0.02),
            Colors.transparent,
          ],
          const [0.0, 0.5, 1.0],
        ),
    );
    // Rotating arc segments (subtle)
    final oval = Rect.fromCenter(center: c, width: u * 3.4, height: u * 0.52);
    final arcPaint = Paint()
      ..color = _holoSoft.withValues(alpha: 0.35 + pulse * 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6);
    canvas.drawArc(oval, rot, 0.9, false, arcPaint);
    canvas.drawArc(
      oval,
      rot + math.pi * 0.85,
      0.55,
      false,
      arcPaint..color = _holoCyan.withValues(alpha: 0.22),
    );
    // Tiny ring nodes
    for (var i = 0; i < 6; i++) {
      final a = rot + i * (math.pi * 2 / 6);
      final px = c.dx + math.cos(a) * u * 1.7;
      final py = c.dy + math.sin(a) * u * 0.26;
      canvas.drawCircle(
        Offset(px, py),
        1.4,
        Paint()..color = _holoSoft.withValues(alpha: 0.45 + pulse * 0.15),
      );
    }
  }

  // ── Solid geometry ──────────────────────────────────────────────────────

  void _paintFoundation(Canvas canvas, _HouseGeo g) {
    final r = g.foundation;
    final accent = _accentFor(TwinZone.foundation);
    final zp = _zonePulse(TwinZone.foundation);

    canvas.drawRRect(
      r,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(g.cx - g.u * 1.2, g.cy + g.u * 0.95),
          Offset(g.cx + g.u * 1.2, g.cy + g.u * 1.3),
          [
            Color.lerp(_foundationHi, accent, zp * 0.25)!,
            Color.lerp(_foundationLo, accent, zp * 0.2)!,
          ],
        ),
    );
    // Cap highlight
    canvas.drawLine(
      Offset(g.cx - g.u * 1.15, g.cy + g.u * 0.98),
      Offset(g.cx + g.u * 1.15, g.cy + g.u * 0.98),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.16)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );
    // Course lines
    final course = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..strokeWidth = 0.65;
    canvas.drawLine(
      Offset(g.cx - g.u * 1.08, g.cy + g.u * 1.12),
      Offset(g.cx + g.u * 1.08, g.cy + g.u * 1.12),
      course,
    );
    if (zp > 0) {
      canvas.drawRRect(
        r,
        Paint()
          ..color = accent.withValues(alpha: 0.18 + zp * 0.2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );
    }
  }

  void _paintBody(Canvas canvas, _HouseGeo g) {
    final accent = _accentFor(TwinZone.siding);
    final zp = _zonePulse(TwinZone.siding);

    canvas.drawRRect(
      g.body,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(g.cx - g.u * 1.15, g.cy - g.u * 0.8),
          Offset(g.cx + g.u * 1.0, g.cy + g.u * 1.0),
          [
            Color.lerp(_bodyHi, accent, zp * 0.12)!,
            Color.lerp(_bodyMid, accent, zp * 0.1)!,
            Color.lerp(_bodyShade, accent, zp * 0.14)!,
          ],
          const [0.0, 0.48, 1.0],
        ),
    );
    // Soft clapboard
    final course = Paint()
      ..color = const Color(0xFF0F172A).withValues(alpha: 0.035)
      ..strokeWidth = 0.8;
    for (var i = 0; i < 6; i++) {
      final y = g.cy - g.u * 0.52 + i * g.u * 0.255;
      canvas.drawLine(
        Offset(g.cx - g.u * 0.96, y),
        Offset(g.cx + g.u * 0.94, y),
        course,
      );
    }
    // Hairline edge
    canvas.drawRRect(
      g.body,
      Paint()
        ..color = const Color(0xFF0F172A).withValues(alpha: 0.05)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9,
    );

    // Depth face (right wall)
    canvas.drawPath(
      g.depthFace,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(g.cx + g.u * 1.05, g.cy - g.u * 0.4),
          Offset(g.cx + g.u * 1.48, g.cy + g.u * 0.9),
          [
            Color.lerp(_bodyShade, accent, zp * 0.12)!,
            Color.lerp(_bodyDeep, accent, zp * 0.1)!,
          ],
        ),
    );
    canvas.drawLine(
      Offset(g.cx + g.u * 1.02, g.cy - g.u * 0.68),
      Offset(g.cx + g.u * 1.02, g.cy + g.u * 0.90),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.14)
        ..strokeWidth = 1.0,
    );

    if (zp > 0) {
      canvas.drawRRect(
        g.body,
        Paint()
          ..color = accent.withValues(alpha: 0.12 + zp * 0.16)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2),
      );
    }
  }

  void _paintWindows(Canvas canvas, _HouseGeo g) {
    final accent = _accentFor(TwinZone.windows);
    final zp = _zonePulse(TwinZone.windows);
    final glow = selected == TwinZone.windows || _marked(TwinZone.windows);

    void window(Offset c, double w, double h) {
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: w, height: h),
        const Radius.circular(3.2),
      );
      canvas.drawRRect(
        r.inflate(1.5),
        Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.08),
      );
      canvas.drawRRect(
        r,
        Paint()
          ..shader = ui.Gradient.linear(
            c.translate(-w * 0.15, -h / 2),
            c.translate(w * 0.2, h / 2),
            [
              Color.lerp(
                _glassHi,
                accent,
                zp * 0.25,
              )!.withValues(alpha: glow ? 0.95 : 0.84),
              Color.lerp(_glassMid, accent, zp * 0.2)!.withValues(alpha: 0.80),
              Color.lerp(_glassLo, accent, zp * 0.15)!.withValues(alpha: 0.88),
            ],
            const [0.0, 0.45, 1.0],
          ),
      );
      // Specular
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(c.dx - w * 0.14, c.dy - h * 0.20),
            width: w * 0.36,
            height: h * 0.22,
          ),
          const Radius.circular(2),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.32),
      );
      final mullion = Paint()
        ..color = Colors.white.withValues(alpha: 0.48)
        ..strokeWidth = 1.05
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(c.dx, c.dy - h / 2 + 1),
        Offset(c.dx, c.dy + h / 2 - 1),
        mullion,
      );
      canvas.drawLine(
        Offset(c.dx - w / 2 + 1, c.dy),
        Offset(c.dx + w / 2 - 1, c.dy),
        mullion,
      );
      if (glow) {
        canvas.drawRRect(
          r,
          Paint()
            ..color = accent.withValues(alpha: 0.22 + pulse * 0.12)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0),
        );
      }
    }

    window(
      Offset(g.cx - g.u * 0.50, g.cy - g.u * 0.10),
      g.u * 0.40,
      g.u * 0.48,
    );
    window(
      Offset(g.cx + g.u * 0.36, g.cy - g.u * 0.10),
      g.u * 0.40,
      g.u * 0.48,
    );
  }

  void _paintDoor(Canvas canvas, _HouseGeo g) {
    final door = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(g.cx - g.u * 0.06, g.cy + g.u * 0.50),
        width: g.u * 0.36,
        height: g.u * 0.74,
      ),
      const Radius.circular(3.5),
    );
    canvas.drawRRect(
      door,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(g.cx - g.u * 0.22, g.cy + g.u * 0.14),
          Offset(g.cx + g.u * 0.10, g.cy + g.u * 0.88),
          const [Color(0xFF334155), Color(0xFF1E293B)],
        ),
    );
    canvas.drawCircle(
      Offset(g.cx + g.u * 0.07, g.cy + g.u * 0.50),
      2.1,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(g.cx + g.u * 0.065, g.cy + g.u * 0.49),
          2.1,
          [const Color(0xFFE2E8F0), const Color(0xFF94A3B8)],
        ),
    );
  }

  void _paintRoof(Canvas canvas, _HouseGeo g) {
    final accent = _accentFor(TwinZone.roof);
    final zp = _zonePulse(TwinZone.roof);

    // Soft eave shadow on body
    canvas.drawPath(
      Path()
        ..moveTo(g.cx - g.u * 1.12, g.cy - g.u * 0.50)
        ..lineTo(g.cx + g.u * 1.12, g.cy - g.u * 0.50)
        ..lineTo(g.cx + g.u * 1.02, g.cy - g.u * 0.36)
        ..lineTo(g.cx - g.u * 1.02, g.cy - g.u * 0.36)
        ..close(),
      Paint()
        ..color = const Color(0xFF0F172A).withValues(alpha: 0.06)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    canvas.drawPath(
      g.roofMass,
      Paint()..color = Color.lerp(_roofDeep, accent, zp * 0.18)!,
    );
    canvas.drawPath(
      g.roofFront,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(g.cx - g.u * 0.35, g.cy - g.u * 1.48),
          Offset(g.cx + g.u * 0.55, g.cy - g.u * 0.48),
          [
            Color.lerp(_roofHi, accent, zp * 0.22)!,
            Color.lerp(_roofDeep, accent, zp * 0.15)!,
            Color.lerp(_roofMid, accent, zp * 0.18)!,
          ],
          const [0.0, 0.42, 1.0],
        ),
    );
    // Ridge light
    canvas.drawLine(
      Offset(g.cx, g.cy - g.u * 1.44),
      Offset(g.cx + g.u * 0.02, g.cy - g.u * 0.56),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.10)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );
    // Chimney
    final chimney = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        g.cx + g.u * 0.40,
        g.cy - g.u * 1.40,
        g.u * 0.20,
        g.u * 0.42,
      ),
      const Radius.circular(2.2),
    );
    canvas.drawRRect(
      chimney,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(g.cx + g.u * 0.40, g.cy - g.u * 1.40),
          Offset(g.cx + g.u * 0.60, g.cy - g.u * 0.98),
          const [Color(0xFF475569), Color(0xFF1E293B)],
        ),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          g.cx + g.u * 0.37,
          g.cy - g.u * 1.44,
          g.u * 0.26,
          g.u * 0.06,
        ),
        const Radius.circular(1.2),
      ),
      Paint()..color = const Color(0xFF0F172A),
    );

    if (zp > 0) {
      canvas.drawPath(
        g.roofFront,
        Paint()
          ..color = accent.withValues(alpha: 0.22 + zp * 0.2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4),
      );
    }
  }

  void _paintGutters(Canvas canvas, _HouseGeo g) {
    final accent = _accentFor(TwinZone.gutters);
    final zp = _zonePulse(TwinZone.gutters);
    final gutterY = g.cy - g.u * 0.52;

    final gutterPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(g.cx - g.u * 1.25, gutterY),
        Offset(g.cx + g.u * 1.25, gutterY),
        [
          Color.lerp(const Color(0xFF64748B), accent, zp * 0.3)!,
          Color.lerp(_metal, accent, zp * 0.25)!,
          Color.lerp(const Color(0xFF64748B), accent, zp * 0.3)!,
        ],
        const [0.0, 0.5, 1.0],
      )
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(g.cx - g.u * 1.22, gutterY),
      Offset(g.cx + g.u * 1.22, gutterY),
      gutterPaint,
    );
    // Downspout
    canvas.drawLine(
      Offset(g.cx + g.u * 1.16, gutterY),
      Offset(g.cx + g.u * 1.20, g.cy + g.u * 1.05),
      Paint()
        ..color = Color.lerp(
          const Color(0xFF64748B),
          accent,
          zp * 0.25,
        )!.withValues(alpha: 0.88)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
    if (zp > 0) {
      canvas.drawLine(
        Offset(g.cx - g.u * 1.22, gutterY),
        Offset(g.cx + g.u * 1.22, gutterY),
        Paint()
          ..color = accent.withValues(alpha: 0.28 + zp * 0.18)
          ..strokeWidth = 3.6
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.8),
      );
    }
  }

  // ── Holographic wireframe ───────────────────────────────────────────────

  void _paintHoloWireframe(Canvas canvas, _HouseGeo g) {
    final baseAlpha = 0.22 + pulse * 0.06;
    final stroke = Paint()
      ..color = _holoSoft.withValues(alpha: baseAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.85
      ..strokeJoin = StrokeJoin.round;

    final glow = Paint()
      ..color = _holo.withValues(alpha: baseAlpha * 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);

    // Body wireframe
    canvas.drawRRect(g.body.inflate(2.5), glow);
    canvas.drawRRect(g.body.inflate(2.5), stroke);

    // Depth face edges
    canvas.drawPath(g.depthFace, stroke);

    // Roof wireframe
    canvas.drawPath(g.roofFront, glow);
    canvas.drawPath(g.roofFront, stroke);
    canvas.drawPath(
      g.roofMass,
      stroke..color = _holo.withValues(alpha: baseAlpha * 0.7),
    );

    // Foundation wireframe
    canvas.drawRRect(g.foundation.inflate(1.5), stroke);

    // Structural grid lines on body (subtle AI mesh)
    final mesh = Paint()
      ..color = _holoCyan.withValues(alpha: 0.08 + pulse * 0.04)
      ..strokeWidth = 0.6;
    for (var i = 0; i < 4; i++) {
      final y = g.cy - g.u * 0.45 + i * g.u * 0.32;
      canvas.drawLine(
        Offset(g.cx - g.u * 0.92, y),
        Offset(g.cx + g.u * 0.90, y),
        mesh,
      );
    }
    for (var i = 0; i < 3; i++) {
      final x = g.cx - g.u * 0.55 + i * g.u * 0.55;
      canvas.drawLine(
        Offset(x, g.cy - g.u * 0.65),
        Offset(x, g.cy + g.u * 0.85),
        mesh,
      );
    }

    // Window frames as holo outlines
    final winStroke = Paint()
      ..color = _holoSoft.withValues(alpha: 0.28 + pulse * 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    for (final c in [
      Offset(g.cx - g.u * 0.50, g.cy - g.u * 0.10),
      Offset(g.cx + g.u * 0.36, g.cy - g.u * 0.10),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: g.u * 0.44, height: g.u * 0.52),
          const Radius.circular(3.5),
        ),
        winStroke,
      );
    }

    // Gutter holo line
    canvas.drawLine(
      Offset(g.cx - g.u * 1.24, g.cy - g.u * 0.52),
      Offset(g.cx + g.u * 1.24, g.cy - g.u * 0.52),
      Paint()
        ..color = _holoCyan.withValues(alpha: 0.30 + pulse * 0.1)
        ..strokeWidth = 1.1
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8),
    );
  }

  // ── Data nodes + paths ──────────────────────────────────────────────────

  void _paintDataNetwork(Canvas canvas, _HouseGeo g) {
    final nodes = <(Offset, TwinZone)>[
      (Offset(g.cx, g.cy - g.u * 1.18), TwinZone.roof),
      (Offset(g.cx + g.u * 0.72, g.cy - g.u * 0.85), TwinZone.roof),
      (Offset(g.cx - g.u * 0.78, g.cy - g.u * 0.05), TwinZone.siding),
      (Offset(g.cx + g.u * 0.70, g.cy + g.u * 0.25), TwinZone.siding),
      (Offset(g.cx - g.u * 0.50, g.cy - g.u * 0.10), TwinZone.windows),
      (Offset(g.cx + g.u * 0.36, g.cy - g.u * 0.10), TwinZone.windows),
      (Offset(g.cx + g.u * 1.08, g.cy - g.u * 0.40), TwinZone.gutters),
      (Offset(g.cx - g.u * 1.05, g.cy - g.u * 0.48), TwinZone.gutters),
      (Offset(g.cx - g.u * 0.55, g.cy + g.u * 1.12), TwinZone.foundation),
      (Offset(g.cx + g.u * 0.70, g.cy + g.u * 1.10), TwinZone.foundation),
    ];

    // Connection paths (slow drift via phase from scan + pulse)
    final pathPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..strokeCap = StrokeCap.round;

    final pairs = <(int, int)>[
      (0, 1),
      (0, 2),
      (0, 4),
      (1, 6),
      (2, 4),
      (2, 8),
      (3, 5),
      (3, 9),
      (4, 5),
      (6, 9),
      (7, 8),
      (5, 6),
    ];

    for (final (a, b) in pairs) {
      final pa = nodes[a].$1;
      final pb = nodes[b].$1;
      final za = nodes[a].$2;
      final zb = nodes[b].$2;
      final issue = _marked(za) || _marked(zb);
      final color = issue ? _accentFor(_marked(za) ? za : zb) : _holoSoft;
      // Soft bezier mid control with gentle drift
      final mid = Offset(
        (pa.dx + pb.dx) / 2 + math.sin(scan * math.pi * 2 + a) * 3.5,
        (pa.dy + pb.dy) / 2 + math.cos(scan * math.pi * 2 + b) * 2.5,
      );
      final path = Path()
        ..moveTo(pa.dx, pa.dy)
        ..quadraticBezierTo(mid.dx, mid.dy, pb.dx, pb.dy);
      canvas.drawPath(
        path,
        pathPaint
          ..color = color.withValues(alpha: 0.14 + pulse * 0.08)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5),
      );
      canvas.drawPath(
        path,
        pathPaint
          ..color = color.withValues(alpha: 0.22 + pulse * 0.06)
          ..maskFilter = null,
      );
    }

    // Nodes
    for (var i = 0; i < nodes.length; i++) {
      final (pos, zone) = nodes[i];
      final issue = _marked(zone);
      final color = issue ? _accentFor(zone) : _holoSoft;
      final twinkle = 0.55 + 0.45 * math.sin((pulse + i * 0.17) * math.pi * 2);
      final r = issue ? 2.4 + pulse * 1.2 : 1.6 + twinkle * 0.6;

      canvas.drawCircle(
        pos,
        r * 2.4,
        Paint()..color = color.withValues(alpha: 0.10 + pulse * 0.06),
      );
      canvas.drawCircle(
        pos,
        r,
        Paint()..color = color.withValues(alpha: 0.55 + twinkle * 0.3),
      );
      canvas.drawCircle(
        pos,
        r * 0.35,
        Paint()..color = Colors.white.withValues(alpha: 0.85),
      );
    }
  }

  // ── Scan sweep ──────────────────────────────────────────────────────────

  void _paintScanSweep(Canvas canvas, _HouseGeo g) {
    // Active band for ~55% of the 9s cycle, then idle.
    final t = scan;
    if (t > 0.58) return;

    final progress = Curves.easeInOut.transform(t / 0.58);
    // Sweep top → bottom across the house
    final top = g.cy - g.u * 1.55;
    final bottom = g.cy + g.u * 1.25;
    final y = top + (bottom - top) * progress;

    final bandH = g.u * 0.55;
    final band = Rect.fromCenter(
      center: Offset(g.cx, y),
      width: g.u * 2.85,
      height: bandH,
    );

    canvas.save();
    // Clip loosely to house silhouette bounds
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(g.cx + g.u * 0.12, g.cy + g.u * 0.05),
          width: g.u * 3.1,
          height: g.u * 3.2,
        ),
        const Radius.circular(12),
      ),
    );

    canvas.drawRect(
      band,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(g.cx, y - bandH / 2),
          Offset(g.cx, y + bandH / 2),
          [
            Colors.transparent,
            _holoCyan.withValues(alpha: 0.08 + pulse * 0.03),
            _holoSoft.withValues(alpha: 0.18 + pulse * 0.05),
            _holoCyan.withValues(alpha: 0.06),
            Colors.transparent,
          ],
          const [0.0, 0.28, 0.5, 0.72, 1.0],
        ),
    );
    // Sharp leading edge
    canvas.drawLine(
      Offset(g.cx - g.u * 1.35, y),
      Offset(g.cx + g.u * 1.45, y),
      Paint()
        ..color = _holoSoft.withValues(alpha: 0.42)
        ..strokeWidth = 1.15
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );
    canvas.restore();
  }

  // ── Finding pulses ──────────────────────────────────────────────────────

  void _paintFindingPulses(Canvas canvas, _HouseGeo g) {
    if (!showMarkers || markedZones.isEmpty) return;

    void pulseAt(Offset c, Color color) {
      final r = 9.0 + pulse * 5.0;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = color.withValues(alpha: 0.10 + pulse * 0.08)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(
        c,
        3.2 + pulse * 0.8,
        Paint()..color = color.withValues(alpha: 0.55 + pulse * 0.25),
      );
      canvas.drawCircle(
        c,
        1.2,
        Paint()..color = Colors.white.withValues(alpha: 0.9),
      );
    }

    if (_marked(TwinZone.roof)) {
      pulseAt(Offset(g.cx + g.u * 0.35, g.cy - g.u * 1.05), _issueRed);
    }
    if (_marked(TwinZone.siding)) {
      pulseAt(Offset(g.cx - g.u * 0.72, g.cy + g.u * 0.12), _issueAmber);
    }
    if (_marked(TwinZone.windows)) {
      pulseAt(Offset(g.cx + g.u * 0.36, g.cy - g.u * 0.10), _issueAmber);
    }
    if (_marked(TwinZone.foundation)) {
      pulseAt(Offset(g.cx + g.u * 0.75, g.cy + g.u * 1.12), _issueRed);
    }
    if (_marked(TwinZone.gutters)) {
      pulseAt(Offset(g.cx - g.u * 0.95, g.cy - g.u * 0.48), _issueAmber);
    }
  }

  @override
  bool shouldRepaint(covariant _LivingTwinPainter old) {
    return old.selected != selected ||
        old.pulse != pulse ||
        old.scan != scan ||
        old.ring != ring ||
        old.scroll != scroll ||
        old.showMarkers != showMarkers ||
        old.markedZones != markedZones;
  }
}

/// Shared house geometry in painter space.
class _HouseGeo {
  _HouseGeo({required this.cx, required this.cy, required this.u})
    : foundation = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, cy + u * 1.12),
          width: u * 2.45,
          height: u * 0.32,
        ),
        const Radius.circular(5),
      ),
      body = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx - u * 0.02, cy + u * 0.10),
          width: u * 2.08,
          height: u * 1.65,
        ),
        const Radius.circular(11),
      ) {
    depthFace = Path()
      ..moveTo(cx + u * 1.02, cy - u * 0.70)
      ..lineTo(cx + u * 1.45, cy - u * 0.40)
      ..lineTo(cx + u * 1.45, cy + u * 0.98)
      ..lineTo(cx + u * 1.02, cy + u * 0.92)
      ..close();

    roofMass = Path()
      ..moveTo(cx - u * 1.40, cy - u * 0.56)
      ..lineTo(cx, cy - u * 1.52)
      ..lineTo(cx + u * 1.40, cy - u * 0.56)
      ..lineTo(cx + u * 1.58, cy - u * 0.32)
      ..lineTo(cx, cy - u * 1.32)
      ..lineTo(cx - u * 1.20, cy - u * 0.38)
      ..close();

    roofFront = Path()
      ..moveTo(cx - u * 1.28, cy - u * 0.54)
      ..lineTo(cx, cy - u * 1.46)
      ..lineTo(cx + u * 1.28, cy - u * 0.54)
      ..close();
  }

  final double cx;
  final double cy;
  final double u;
  final RRect foundation;
  final RRect body;
  late final Path depthFace;
  late final Path roofMass;
  late final Path roofFront;
}
