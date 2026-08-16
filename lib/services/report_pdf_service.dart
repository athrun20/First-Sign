import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../legal/cost_copy.dart';
import '../legal/privacy_copy.dart';
import '../models/analysis_models.dart';
import 'branding_store.dart';

/// How the user wants to leave with the PDF.
enum PdfExportAction {
  /// System share sheet (mobile/desktop) or browser download (web).
  share,

  /// Print / system PDF preview dialog.
  print,
}

/// Calm luxury palette — mirrors the in-app Report screen
/// (warm paper + charcoal + soft teal / gold accents).
abstract final class _PdfLux {
  /// Page wash (Report screen background).
  static final paper = PdfColor.fromHex('#FAF7F2');

  /// Slightly warmer card fill on paper.
  static final cardFill = PdfColor.fromHex('#FFFCFA');
  static final surface = PdfColor.fromHex('#FFFFFF');
  static final border = PdfColor.fromHex('#EDE6DB');
  static final borderSoft = PdfColor.fromHex('#F3EEE6');
  static final charcoal = PdfColor.fromHex('#1C1917');
  static final charcoalMid = PdfColor.fromHex('#292524');
  static final body = PdfColor.fromHex('#57534E');
  static final muted = PdfColor.fromHex('#A8A29E');
  static final teal = PdfColor.fromHex('#0F766E');
  static final tealMist = PdfColor.fromHex('#F0FDFA');
  static final tealDeep = PdfColor.fromHex('#115E59');
  static final tealLine = PdfColor.fromHex('#99F6E4');
  static final gold = PdfColor.fromHex('#B45309');
  static final goldSoft = PdfColor.fromHex('#F8EEDC');
  static final goldLine = PdfColor.fromHex('#E8D5A8');
  static final stone = PdfColor.fromHex('#3A322B');
  static final stoneMid = PdfColor.fromHex('#342C26');
  static final stoneDeep = PdfColor.fromHex('#2E2722');
  static final high = PdfColor.fromHex('#B91C1C');
  static final highSoft = PdfColor.fromHex('#FEF2F2');
  static final med = gold;
  static final medSoft = goldSoft;
  static final low = teal;
  static final lowSoft = tealMist;
  static final disclaimerInk = PdfColor.fromHex('#78350F');

  static PdfColor scoreAccent(int score) {
    if (score >= 85) return teal;
    if (score >= 70) return gold;
    return high;
  }

  static PdfColor severityColor(String severity) {
    switch (severity) {
      case 'High':
        return high;
      case 'Medium':
        return med;
      default:
        return low;
    }
  }

  static PdfColor severitySoft(String severity) {
    switch (severity) {
      case 'High':
        return highSoft;
      case 'Medium':
        return medSoft;
      default:
        return lowSoft;
    }
  }
}

/// Builds and shares FirstSign exterior screening PDFs.
class ReportPdfService {
  ReportPdfService({BrandingStore? branding})
    : _branding = branding ?? BrandingStore.instance;

  final BrandingStore _branding;

  static const String _defaultCompany = 'Atlanta Construction Pros';

  /// Human-friendly default filename, e.g. FirstSign_Screening_2026-07-20.pdf
  String defaultFileName({AnalysisReport? report, DateTime? at}) {
    final when = at ?? DateTime.now();
    final y = when.year.toString().padLeft(4, '0');
    final m = when.month.toString().padLeft(2, '0');
    final d = when.day.toString().padLeft(2, '0');
    final score = report == null ? '' : '_${report.overallScore}';
    final demo =
        report != null && report.analysisSource.toLowerCase().contains('demo')
        ? '_Demo'
        : '';
    return 'FirstSign_Exterior_Screening$demo${score}_$y-$m-$d.pdf';
  }

  /// Helvetica cannot draw en/em dashes and some punctuation — normalize.
  ///
  /// Maps common Unicode punctuation to ASCII so default PDF fonts render
  /// cleanly (middle-dot, en/em dash, curly quotes, ellipsis, etc.).
  static String pdfSafe(String input) {
    final mapped = input
        .replaceAll('\u2014', '-') // em dash —
        .replaceAll('\u2013', '-') // en dash –
        .replaceAll('\u2212', '-') // minus −
        .replaceAll('\u00B7', ' | ') // middle-dot ·
        .replaceAll('\u2022', '*') // bullet •
        .replaceAll('\u2192', '->') // →
        .replaceAll('\u2190', '<-') // ←
        .replaceAll('\u2019', "'") // ’
        .replaceAll('\u2018', "'") // ‘
        .replaceAll('\u201C', '"') // “
        .replaceAll('\u201D', '"') // ”
        .replaceAll('\u2026', '...') // …
        .replaceAll('\u00A0', ' '); // nbsp
    // Drop any remaining non-Latin-1 code points Helvetica cannot draw.
    return mapped.replaceAll(RegExp(r'[^\x09\x0A\x0D\x20-\x7E\xA0-\xFF]'), '');
  }

  /// Build PDF bytes for [report] using current branding.
  Future<Uint8List> buildPdfBytes(AnalysisReport report) async {
    final pdf = pw.Document(
      title: 'First Sign Exterior Screening Report',
      author: 'First Sign',
      creator: 'First Sign',
    );
    final date = DateTime.now().toString().split('.').first;
    final companyName = pdfSafe(
      _branding.companyName.trim().isEmpty
          ? _defaultCompany
          : _branding.companyName.trim(),
    );
    final logoBytes = _branding.logoBytes;

    pw.MemoryImage? logoImage;
    if (logoBytes != null && logoBytes.isNotEmpty) {
      try {
        logoImage = pw.MemoryImage(logoBytes);
      } catch (_) {
        logoImage = null;
      }
    }

    final isDemo = report.analysisSource.toLowerCase().contains('demo');
    final scoreColor = _PdfLux.scoreAccent(report.overallScore);
    final ordered = report.issuesByPriority;

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(44, 40, 44, 40),
          theme: pw.ThemeData.withFont(
            base: pw.Font.helvetica(),
            bold: pw.Font.helveticaBold(),
            italic: pw.Font.helveticaOblique(),
            boldItalic: pw.Font.helveticaBoldOblique(),
          ),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Container(color: _PdfLux.paper),
          ),
        ),
        header: (context) {
          if (context.pageNumber > 1) {
            return _continuedHeader(companyName: companyName);
          }
          return pw.SizedBox();
        },
        footer: (context) => _pageFooter(context, companyName: companyName),
        build: (context) {
          final avgConf = _avgConfidence(report);
          final widgets = <pw.Widget>[
            _brandHeader(
              companyName: companyName,
              logoImage: logoImage,
              isDemo: isDemo,
            ),
            pw.SizedBox(height: 28),
            _documentTitle(
              date: date,
              source: report.analysisSource,
              report: report,
            ),
            pw.SizedBox(height: 26),
            _scoreHero(
              report: report,
              scoreColor: scoreColor,
              avgConfidence: avgConf,
            ),
            pw.SizedBox(height: 16),
            _metaStatsRow(report: report, findings: ordered.length),
            pw.SizedBox(height: 32),
            _sectionHeader('Screening story'),
            pw.SizedBox(height: 14),
          ];

          for (final chapter in report.storyChapters) {
            widgets.add(_storyChapter(chapter));
            widgets.add(pw.SizedBox(height: 12));
          }

          widgets.addAll([
            pw.SizedBox(height: 20),
            _sectionHeader(
              'Priority findings',
              trailing: ordered.isEmpty
                  ? null
                  : '${ordered.length} finding${ordered.length == 1 ? '' : 's'}',
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              ordered.isEmpty
                  ? 'No priority items in this screening pass.'
                  : 'Ordered by urgency - highest priority first.',
              style: pw.TextStyle(
                fontSize: 9.5,
                color: _PdfLux.muted,
                height: 1.5,
              ),
            ),
            pw.SizedBox(height: 16),
          ]);

          if (ordered.isEmpty) {
            widgets.add(_emptyFindingsCard());
          } else {
            for (var i = 0; i < ordered.length; i++) {
              widgets.add(_findingCard(issue: ordered[i], index: i + 1));
              widgets.add(pw.SizedBox(height: 14));
            }
          }

          widgets.addAll([
            pw.SizedBox(height: 16),
            _sectionHeader('Planning range'),
            pw.SizedBox(height: 14),
            _planningRangeCard(report),
            pw.SizedBox(height: 20),
            _disclaimerCard(),
            pw.SizedBox(height: 18),
            pw.Text(
              pdfSafe(PrivacyCopy.pdfShareNote),
              style: pw.TextStyle(
                fontSize: 9.5,
                color: _PdfLux.body,
                height: 1.55,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          ]);

          return widgets;
        },
      ),
    );

    return pdf.save();
  }

  // ── Layout building blocks ───────────────────────────────────────────────

  int _avgConfidence(AnalysisReport report) {
    if (report.issues.isEmpty) return 0;
    final sum = report.issues.fold<int>(0, (a, i) => a + i.confidence);
    return (sum / report.issues.length).round();
  }

  pw.Widget _brandHeader({
    required String companyName,
    required pw.MemoryImage? logoImage,
    required bool isDemo,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: pw.BoxDecoration(
        color: _PdfLux.surface,
        borderRadius: pw.BorderRadius.circular(14),
        border: pw.Border.all(color: _PdfLux.border, width: 0.7),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logoImage != null) ...[
                pw.Container(
                  width: 56,
                  height: 56,
                  decoration: pw.BoxDecoration(
                    color: _PdfLux.paper,
                    borderRadius: pw.BorderRadius.circular(14),
                    border: pw.Border.all(color: _PdfLux.border, width: 0.65),
                  ),
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Image(
                    logoImage,
                    width: 44,
                    height: 44,
                    fit: pw.BoxFit.contain,
                  ),
                ),
                pw.SizedBox(width: 16),
              ] else ...[
                // Monogram mark when no logo
                pw.Container(
                  width: 54,
                  height: 54,
                  alignment: pw.Alignment.center,
                  decoration: pw.BoxDecoration(
                    color: _PdfLux.stoneDeep,
                    borderRadius: pw.BorderRadius.circular(14),
                    border: pw.Border.all(
                      color: _PdfLux.goldLine.flattenAlpha(0.35),
                      width: 0.7,
                    ),
                  ),
                  child: pw.Text(
                    _monogram(companyName),
                    style: pw.TextStyle(
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                      color: _PdfLux.goldLine,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                pw.SizedBox(width: 16),
              ],
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      companyName,
                      style: pw.TextStyle(
                        fontSize: 21,
                        fontWeight: pw.FontWeight.bold,
                        color: _PdfLux.charcoal,
                        letterSpacing: -0.4,
                        height: 1.12,
                      ),
                    ),
                    pw.SizedBox(height: 7),
                    pw.Row(
                      children: [
                        pw.Container(
                          width: 16,
                          height: 2,
                          decoration: pw.BoxDecoration(
                            color: _PdfLux.teal,
                            borderRadius: pw.BorderRadius.circular(1),
                          ),
                        ),
                        pw.SizedBox(width: 8),
                        pw.Text(
                          'Powered by First Sign',
                          style: pw.TextStyle(
                            fontSize: 10.5,
                            fontWeight: pw.FontWeight.bold,
                            color: _PdfLux.teal,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isDemo)
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: pw.BoxDecoration(
                    color: _PdfLux.tealMist,
                    borderRadius: pw.BorderRadius.circular(20),
                    border: pw.Border.all(color: _PdfLux.tealLine, width: 0.6),
                  ),
                  child: pw.Text(
                    'DEMO',
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      fontWeight: pw.FontWeight.bold,
                      color: _PdfLux.tealDeep,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
            ],
          ),
          pw.SizedBox(height: 14),
          // Soft teal -> gold hairline under brand
          pw.Container(
            height: 2,
            decoration: pw.BoxDecoration(
              borderRadius: pw.BorderRadius.circular(2),
              gradient: pw.LinearGradient(
                colors: [_PdfLux.teal, _PdfLux.goldLine, _PdfLux.borderSoft],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _monogram(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'PA';
    if (parts.length == 1) {
      final s = parts.first;
      return s.length >= 2 ? s.substring(0, 2).toUpperCase() : s.toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  pw.Widget _continuedHeader({required String companyName}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 18),
      child: pw.Column(
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                companyName,
                style: pw.TextStyle(
                  fontSize: 9.5,
                  fontWeight: pw.FontWeight.bold,
                  color: _PdfLux.charcoalMid,
                ),
              ),
              pw.Text(
                'Exterior Screening Report  |  First Sign',
                style: pw.TextStyle(
                  fontSize: 8.5,
                  color: _PdfLux.muted,
                  letterSpacing: 0.15,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            height: 1,
            decoration: pw.BoxDecoration(
              gradient: pw.LinearGradient(
                colors: [_PdfLux.teal, _PdfLux.border, _PdfLux.borderSoft],
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _documentTitle({
    required String date,
    required String source,
    required AnalysisReport report,
  }) {
    final single = report.isSinglePhotoScan;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          single ? 'QUICK SCAN' : 'HOME EXTERIOR',
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: _PdfLux.teal,
            letterSpacing: 1.8,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          single ? 'Single-Photo Screening' : 'Screening Report',
          style: pw.TextStyle(
            fontSize: 24,
            fontWeight: pw.FontWeight.bold,
            color: _PdfLux.charcoal,
            letterSpacing: -0.5,
            height: 1.1,
          ),
        ),
        if (single) ...[
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: pw.BoxDecoration(
              color: _PdfLux.goldSoft,
              borderRadius: pw.BorderRadius.circular(12),
              border: pw.Border.all(color: _PdfLux.goldLine, width: 0.55),
            ),
            child: pw.Text(
              pdfSafe(AnalysisReport.singlePhotoBadge),
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: _PdfLux.gold,
                letterSpacing: 0.25,
              ),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Focused single-angle screening. Treat findings as a first look; '
            'a multi-shot set raises confidence across the home.',
            style: pw.TextStyle(fontSize: 9, height: 1.45, color: _PdfLux.body),
          ),
        ],
        pw.SizedBox(height: 10),
        pw.Container(height: 0.7, color: _PdfLux.border),
        pw.SizedBox(height: 10),
        pw.Row(
          children: [
            pw.Text(
              'Generated $date',
              style: pw.TextStyle(
                fontSize: 9,
                color: _PdfLux.muted,
                height: 1.3,
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8),
              child: pw.Text(
                '|',
                style: pw.TextStyle(fontSize: 9, color: _PdfLux.border),
              ),
            ),
            pw.Expanded(
              child: pw.Text(
                pdfSafe(
                  single ? 'Source: $source · 1 photo' : 'Source: $source',
                ),
                style: pw.TextStyle(
                  fontSize: 9,
                  color: _PdfLux.muted,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Large stone score panel — primary visual anchor of the report.
  /// Mirrors the in-app dual-ring condition score treatment.
  pw.Widget _scoreHero({
    required AnalysisReport report,
    required PdfColor scoreColor,
    required int avgConfidence,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(28, 30, 28, 28),
      decoration: pw.BoxDecoration(
        gradient: pw.LinearGradient(
          begin: pw.Alignment.topLeft,
          end: pw.Alignment.bottomRight,
          colors: [_PdfLux.stone, _PdfLux.stoneMid, _PdfLux.stoneDeep],
          stops: const [0.0, 0.45, 1.0],
        ),
        borderRadius: pw.BorderRadius.circular(18),
        border: pw.Border.all(
          color: _PdfLux.goldLine.flattenAlpha(0.18),
          width: 0.75,
        ),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            'SCREENING SCORE',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white.flattenAlpha(0.55),
              letterSpacing: 2.2,
            ),
          ),
          pw.SizedBox(height: 7),
          pw.Text(
            pdfSafe(AnalysisReport.screeningBadge),
            style: pw.TextStyle(
              fontSize: 9,
              color: PdfColors.white.flattenAlpha(0.40),
              letterSpacing: 0.2,
            ),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 22),
          // Dual-ring score mark (condition + confidence), app-aligned
          pw.Container(
            width: 138,
            height: 138,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              shape: pw.BoxShape.circle,
              border: pw.Border.all(
                color: _PdfLux.goldLine.flattenAlpha(0.55),
                width: 2.2,
              ),
            ),
            child: pw.Container(
              width: 118,
              height: 118,
              alignment: pw.Alignment.center,
              decoration: pw.BoxDecoration(
                shape: pw.BoxShape.circle,
                border: pw.Border.all(
                  color: scoreColor.flattenAlpha(0.7),
                  width: 4,
                ),
              ),
              child: pw.Container(
                width: 98,
                height: 98,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(
                  shape: pw.BoxShape.circle,
                  border: pw.Border.all(
                    color: PdfColors.white.flattenAlpha(0.08),
                    width: 1,
                  ),
                ),
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                      '${report.overallScore}',
                      style: const pw.TextStyle(
                        fontSize: 48,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                        letterSpacing: -1.6,
                        height: 0.95,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'out of 100',
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        color: PdfColors.white.flattenAlpha(0.44),
                        letterSpacing: 0.55,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          pw.SizedBox(height: 16),
          // Ring legend
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              _ringLegend(color: scoreColor, label: 'Condition'),
              pw.SizedBox(width: 18),
              _ringLegend(
                color: _PdfLux.goldLine,
                label: avgConfidence > 0
                    ? 'Avg. confidence $avgConfidence%'
                    : 'Avg. confidence',
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Container(
            height: 2.5,
            width: 52,
            decoration: pw.BoxDecoration(
              color: scoreColor,
              borderRadius: pw.BorderRadius.circular(2),
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            pdfSafe(report.conditionLabel),
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(
              fontSize: 17,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
              letterSpacing: -0.3,
              height: 1.25,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10),
            child: pw.Text(
              pdfSafe(report.scoreMeaning),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 10.5,
                height: 1.58,
                color: PdfColors.white.flattenAlpha(0.58),
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _ringLegend({required PdfColor color, required String label}) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(
          width: 8,
          height: 8,
          decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
        ),
        pw.SizedBox(width: 6),
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 8,
            color: PdfColors.white.flattenAlpha(0.5),
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  pw.Widget _metaStatsRow({
    required AnalysisReport report,
    required int findings,
  }) {
    return pw.Row(
      children: [
        pw.Expanded(
          child: _statChip(
            label: 'Photos',
            value: '${report.photoCount}',
            accent: _PdfLux.charcoalMid,
            soft: _PdfLux.borderSoft,
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: _statChip(
            label: 'Findings',
            value: '$findings',
            accent: _PdfLux.teal,
            soft: _PdfLux.tealMist,
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: _statChip(
            label: 'High',
            value: '${report.highCount}',
            accent: _PdfLux.high,
            soft: _PdfLux.highSoft,
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: _statChip(
            label: 'Medium',
            value: '${report.mediumCount}',
            accent: _PdfLux.med,
            soft: _PdfLux.medSoft,
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: _statChip(
            label: 'Low',
            value: '${report.lowCount}',
            accent: _PdfLux.low,
            soft: _PdfLux.lowSoft,
          ),
        ),
      ],
    );
  }

  pw.Widget _statChip({
    required String label,
    required String value,
    required PdfColor accent,
    required PdfColor soft,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 11, horizontal: 6),
      decoration: pw.BoxDecoration(
        color: soft,
        borderRadius: pw.BorderRadius.circular(9),
        border: pw.Border.all(color: _PdfLux.border, width: 0.55),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 15,
              fontWeight: pw.FontWeight.bold,
              color: accent,
              letterSpacing: -0.25,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            label.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
              color: _PdfLux.muted,
              letterSpacing: 0.75,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _sectionHeader(String title, {String? trailing}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Container(
              width: 3.5,
              height: 16,
              decoration: pw.BoxDecoration(
                color: _PdfLux.teal,
                borderRadius: pw.BorderRadius.circular(2),
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: _PdfLux.charcoal,
                  letterSpacing: -0.25,
                ),
              ),
            ),
            if (trailing != null)
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: pw.BoxDecoration(
                  color: _PdfLux.tealMist,
                  borderRadius: pw.BorderRadius.circular(12),
                  border: pw.Border.all(color: _PdfLux.tealLine, width: 0.5),
                ),
                child: pw.Text(
                  trailing,
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: _PdfLux.tealDeep,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          height: 0.7,
          decoration: pw.BoxDecoration(
            gradient: pw.LinearGradient(
              colors: [
                _PdfLux.teal.flattenAlpha(0.35),
                _PdfLux.border,
                _PdfLux.borderSoft,
              ],
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _storyChapter(({String title, String body}) chapter) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(15, 13, 15, 13),
      decoration: pw.BoxDecoration(
        color: _PdfLux.cardFill,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _PdfLux.border, width: 0.55),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            pdfSafe(chapter.title),
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: _PdfLux.charcoal,
              letterSpacing: -0.1,
              height: 1.25,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            pdfSafe(chapter.body),
            style: pw.TextStyle(
              fontSize: 9.5,
              height: 1.55,
              color: _PdfLux.body,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _emptyFindingsCard() {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(18),
      decoration: pw.BoxDecoration(
        color: _PdfLux.tealMist,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: _PdfLux.tealLine, width: 0.65),
      ),
      child: pw.Text(
        'No significant issues detected. Keep up routine exterior maintenance.',
        style: pw.TextStyle(
          fontSize: 10.5,
          height: 1.5,
          color: _PdfLux.tealDeep,
        ),
      ),
    );
  }

  pw.Widget _findingCard({required AnalysisIssue issue, required int index}) {
    final sevColor = _PdfLux.severityColor(issue.severity);
    final sevSoft = _PdfLux.severitySoft(issue.severity);

    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        color: _PdfLux.cardFill,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: _PdfLux.border, width: 0.65),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Soft severity rail
          pw.Container(
            width: 4,
            constraints: const pw.BoxConstraints(minHeight: 80),
            decoration: pw.BoxDecoration(
              color: sevColor,
              borderRadius: const pw.BorderRadius.only(
                topLeft: pw.Radius.circular(11),
                bottomLeft: pw.Radius.circular(11),
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(14, 14, 16, 16),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: 28,
                        height: 28,
                        alignment: pw.Alignment.center,
                        decoration: pw.BoxDecoration(
                          color: sevSoft,
                          borderRadius: pw.BorderRadius.circular(8),
                          border: pw.Border.all(
                            color: sevColor.flattenAlpha(0.18),
                            width: 0.55,
                          ),
                        ),
                        child: pw.Text(
                          '$index',
                          style: pw.TextStyle(
                            fontSize: 11.5,
                            fontWeight: pw.FontWeight.bold,
                            color: sevColor,
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 11),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              pdfSafe(issue.title),
                              style: pw.TextStyle(
                                fontSize: 12.5,
                                fontWeight: pw.FontWeight.bold,
                                color: _PdfLux.charcoal,
                                letterSpacing: -0.2,
                                height: 1.28,
                              ),
                            ),
                            pw.SizedBox(height: 5),
                            pw.Text(
                              pdfSafe(issue.location),
                              style: pw.TextStyle(
                                fontSize: 9.5,
                                color: _PdfLux.body,
                                height: 1.45,
                              ),
                            ),
                            if (issue.sourcePhotoLabel.isNotEmpty) ...[
                              pw.SizedBox(height: 3),
                              pw.Text(
                                pdfSafe(
                                  'From photo: ${issue.sourcePhotoDisplay}',
                                ),
                                style: pw.TextStyle(
                                  fontSize: 8.5,
                                  color: _PdfLux.charcoalMid,
                                  fontWeight: pw.FontWeight.bold,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      _severityChip(issue.severity, sevColor, sevSoft),
                    ],
                  ),
                  pw.SizedBox(height: 12),
                  pw.Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _metaPill(
                        label: 'Confidence',
                        value: '${issue.confidence}%',
                        accent: _PdfLux.teal,
                        soft: _PdfLux.tealMist,
                      ),
                      if (issue.needsCloserPhoto)
                        _metaPill(
                          label: 'Needs closer photos',
                          value: '',
                          accent: _PdfLux.gold,
                          soft: _PdfLux.goldSoft,
                        ),
                      _metaPill(
                        label: pdfSafe(issue.planningCostLabel),
                        value: '',
                        accent: _PdfLux.charcoalMid,
                        soft: _PdfLux.paper,
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    pdfSafe(CostCopy.inlineNote),
                    style: pw.TextStyle(
                      fontSize: 7.5,
                      color: _PdfLux.muted,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Container(height: 0.55, color: _PdfLux.borderSoft),
                  pw.SizedBox(height: 12),
                  _narrativeBlock(
                    label: 'What we found',
                    body: issue.storyWhat,
                  ),
                  pw.SizedBox(height: 10),
                  _narrativeBlock(
                    label: 'Impact if delayed',
                    body: issue.storyImpact,
                  ),
                  pw.SizedBox(height: 10),
                  _narrativeBlock(
                    label: 'Recommended',
                    body: issue.storyRecommendation,
                    accentLabel: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _severityChip(String severity, PdfColor color, PdfColor soft) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: pw.BoxDecoration(
        color: soft,
        borderRadius: pw.BorderRadius.circular(14),
        border: pw.Border.all(color: color.flattenAlpha(0.2), width: 0.55),
      ),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Container(
            width: 5.5,
            height: 5.5,
            decoration: pw.BoxDecoration(
              color: color,
              shape: pw.BoxShape.circle,
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Text(
            severity,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: color,
              letterSpacing: 0.35,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _metaPill({
    required String label,
    required String value,
    required PdfColor accent,
    required PdfColor soft,
  }) {
    final text = value.isEmpty ? label : '$label  $value';
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: pw.BoxDecoration(
        color: soft,
        borderRadius: pw.BorderRadius.circular(7),
        border: pw.Border.all(color: _PdfLux.border, width: 0.45),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: accent,
          letterSpacing: 0.1,
        ),
      ),
    );
  }

  pw.Widget _narrativeBlock({
    required String label,
    required String body,
    bool accentLabel = false,
  }) {
    var clean = body.trim();
    for (final prefix in [
      'Impact if delayed: ',
      'Recommended: ',
      'What we found: ',
    ]) {
      if (clean.toLowerCase().startsWith(prefix.toLowerCase())) {
        clean = clean.substring(prefix.length).trim();
      }
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 7.5,
            fontWeight: pw.FontWeight.bold,
            color: accentLabel ? _PdfLux.teal : _PdfLux.muted,
            letterSpacing: 1.0,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          pdfSafe(clean),
          style: pw.TextStyle(fontSize: 9.5, height: 1.55, color: _PdfLux.body),
        ),
      ],
    );
  }

  pw.Widget _planningRangeCard(AnalysisReport report) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: pw.BoxDecoration(
        color: _PdfLux.tealMist,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: PdfColor.fromHex('#5EEAD4'), width: 0.65),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            CostCopy.shortLabel.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: _PdfLux.tealDeep,
              letterSpacing: 1.2,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            pdfSafe(CostCopy.compact(report.estimatedRepairRange)),
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: _PdfLux.charcoal,
              letterSpacing: -0.25,
              height: 1.2,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            pdfSafe(CostCopy.inlineNote),
            style: pw.TextStyle(
              fontSize: 8,
              color: _PdfLux.muted,
              fontStyle: pw.FontStyle.italic,
              height: 1.4,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            pdfSafe(report.impactStory),
            style: pw.TextStyle(
              fontSize: 9.5,
              height: 1.55,
              color: _PdfLux.body,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            pdfSafe(CostCopy.footnote),
            style: pw.TextStyle(
              fontSize: 8,
              color: _PdfLux.muted,
              fontStyle: pw.FontStyle.italic,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _disclaimerCard() {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(15, 13, 15, 13),
      decoration: pw.BoxDecoration(
        color: _PdfLux.goldSoft,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _PdfLux.goldLine, width: 0.65),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'IMPORTANT',
            style: pw.TextStyle(
              fontSize: 7.5,
              fontWeight: pw.FontWeight.bold,
              color: _PdfLux.gold,
              letterSpacing: 1.1,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            pdfSafe(AnalysisReport.screeningDisclaimer),
            style: pw.TextStyle(
              fontSize: 8.5,
              height: 1.5,
              color: _PdfLux.disclaimerInk,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pageFooter(pw.Context context, {required String companyName}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14),
      child: pw.Column(
        children: [
          pw.Container(
            height: 0.7,
            decoration: pw.BoxDecoration(
              gradient: pw.LinearGradient(
                colors: [
                  _PdfLux.borderSoft,
                  _PdfLux.border,
                  _PdfLux.borderSoft,
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 9),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      companyName,
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: _PdfLux.charcoalMid,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      pdfSafe(AnalysisReport.screeningBadge),
                      style: pw.TextStyle(
                        fontSize: 7.5,
                        color: _PdfLux.muted,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: pw.TextStyle(
                  fontSize: 8,
                  color: _PdfLux.muted,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Share / download the PDF (primary path).
  ///
  /// - **Web:** triggers a browser download
  /// - **Mobile / desktop:** opens the system share sheet when available
  Future<bool> sharePdf(AnalysisReport report, {String? filename}) async {
    final bytes = await buildPdfBytes(report);
    final name = filename ?? defaultFileName(report: report);
    return Printing.sharePdf(bytes: bytes, filename: name);
  }

  /// Open the system print / PDF preview dialog.
  Future<void> printPdf(AnalysisReport report) async {
    final bytes = await buildPdfBytes(report);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: defaultFileName(report: report),
    );
  }

  /// Run share or print.
  Future<bool> export(
    AnalysisReport report, {
    PdfExportAction action = PdfExportAction.share,
    String? filename,
  }) async {
    switch (action) {
      case PdfExportAction.share:
        return sharePdf(report, filename: filename);
      case PdfExportAction.print:
        await printPdf(report);
        return true;
    }
  }

  /// Short success copy depending on platform + action.
  String successMessage(PdfExportAction action) {
    if (action == PdfExportAction.print) {
      return 'PDF opened in print preview.';
    }
    if (kIsWeb) {
      return 'PDF download started — check your Downloads folder.';
    }
    return 'PDF ready to share.';
  }
}

/// Soft alpha helper for PdfColor (package has no built-in withOpacity).
extension on PdfColor {
  PdfColor flattenAlpha(double alpha) {
    final a = alpha.clamp(0.0, 1.0);
    return PdfColor(red * a + (1 - a), green * a + (1 - a), blue * a + (1 - a));
  }
}
