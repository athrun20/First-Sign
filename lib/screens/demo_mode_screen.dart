import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/demo_mode_service.dart';
import '../services/storage_exception.dart';
import '../theme/app_lux.dart';
import 'analysis_report_screen.dart';

/// One-tap demo: paints a sample home, runs calibrated screening, opens report.
class DemoModeScreen extends StatefulWidget {
  const DemoModeScreen({super.key});

  @override
  State<DemoModeScreen> createState() => _DemoModeScreenState();
}

class _DemoModeScreenState extends State<DemoModeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  String _status = 'Building sample elevations…';
  String? _error;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    unawaited(_pulse.repeat(reverse: true));
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _error = null;
      _status = 'Building sample elevations…';
    });

    try {
      await Future<void>.delayed(const Duration(milliseconds: 280));
      if (!mounted) return;
      setState(() => _status = 'Running AI exterior screening…');

      final session = await DemoModeService().run();
      if (!mounted) return;

      setState(() => _status = 'Opening your sample report…');
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (!mounted) return;

      unawaited(
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => AnalysisReportScreen(
              photos: session.photos,
              report: session.report,
              savedReportId: session.savedReportId,
            ),
          ),
        ),
      );
    } on StorageFullException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.userMessage;
        _status = 'Storage full';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _status = 'Demo failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Demo mode',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
          child: Column(
            children: [
              const Spacer(flex: 2),
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  final t = 0.85 + _pulse.value * 0.15;
                  return Transform.scale(
                    scale: _error == null ? t : 1,
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppLux.teal.withValues(alpha: 0.9),
                            const Color(0xFF0E3A30),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppLux.teal.withValues(alpha: 0.35),
                            blurRadius: 28,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        _error == null
                            ? Icons.home_work_rounded
                            : Icons.error_outline_rounded,
                        size: 42,
                        color: Colors.white,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 28),
              Text(
                'Sample home walkthrough',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _error == null
                    ? 'No camera needed. We load a realistic sample exterior, '
                          'run the same screening engine, and open a full report '
                          'with twin, surface evidence detail, and PDF.'
                    : 'Something went wrong preparing the demo.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  height: 1.45,
                  color: Colors.white.withValues(alpha: 0.62),
                ),
              ),
              const SizedBox(height: 28),
              if (_error == null) ...[
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Color(0xFF6EE7B7),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _status,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFA7F3D0),
                  ),
                ),
              ] else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0x33EF4444),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x66EF4444)),
                  ),
                  child: Text(
                    _error!,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: const Color(0xFFFECACA),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _run,
                    child: const Text('Try again'),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Back to home',
                    style: GoogleFonts.inter(color: Colors.white70),
                  ),
                ),
              ],
              const Spacer(flex: 3),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Demo photos are illustrated samples — not a real property. '
                        'Findings use the same screening engine as a live capture.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          height: 1.35,
                          color: Colors.white.withValues(alpha: 0.55),
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
