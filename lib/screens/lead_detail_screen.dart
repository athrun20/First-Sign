import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/analysis_models.dart';
import '../models/lead_models.dart';
import '../services/branding_store.dart';
import '../services/lead_store.dart';
import '../services/report_pdf_service.dart';
import '../theme/app_lux.dart';

/// Contractor view of a single quote lead + attached report snapshot.
class LeadDetailScreen extends StatefulWidget {
  const LeadDetailScreen({super.key, required this.leadId});

  final String leadId;

  @override
  State<LeadDetailScreen> createState() => _LeadDetailScreenState();
}

class _LeadDetailScreenState extends State<LeadDetailScreen> {
  late final TextEditingController _notesController;
  QuoteLead? _lead;

  @override
  void initState() {
    super.initState();
    _lead = LeadStore.instance.byId(widget.leadId);
    _notesController = TextEditingController(
      text: _lead?.contractorNotes ?? '',
    );
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  QuoteLead? get lead => LeadStore.instance.byId(widget.leadId) ?? _lead;

  Future<void> _setStatus(String status) async {
    final l = lead;
    if (l == null) return;
    await LeadStore.instance.updateStatus(l.id, status);
    if (mounted) setState(() {});
  }

  Future<void> _saveNotes() async {
    final l = lead;
    if (l == null) return;
    await LeadStore.instance.updateContractorNotes(l.id, _notesController.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Notes saved', style: GoogleFonts.inter()),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _exportReportPdf() async {
    final l = lead;
    if (l == null) return;
    final report = l.reportSnapshot;
    final branding = BrandingStore.instance;
    String safe(String s) => ReportPdfService.pdfSafe(s);

    try {
      final pdf = pw.Document();
      pw.MemoryImage? logoImage;
      final logoBytes = branding.logoBytes;
      if (logoBytes != null && logoBytes.isNotEmpty) {
        try {
          logoImage = pw.MemoryImage(logoBytes);
        } catch (_) {}
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (context) {
            final widgets = <pw.Widget>[
              pw.Row(
                children: [
                  if (logoImage != null) ...[
                    pw.Image(logoImage, width: 48, height: 48),
                    pw.SizedBox(width: 12),
                  ],
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          safe(
                            branding.companyName.trim().isEmpty
                                ? 'FirstSign'
                                : branding.companyName.trim(),
                          ),
                          style: const pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          safe('Lead report · Powered by FirstSign'),
                          style: const pw.TextStyle(
                            fontSize: 10,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Text(
                safe(l.name),
                style: const pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(safe(l.address)),
              pw.Text(safe('${l.phone} · ${l.email}')),
              pw.SizedBox(height: 12),
              pw.Text(
                'Condition score: ${report.overallScore}/100',
                style: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(safe(report.conditionLabel)),
              pw.Text(safe(report.scoreMeaning)),
              pw.SizedBox(height: 6),
              pw.Text(safe(report.priorityStory)),
              pw.Text(safe(report.recommendationStory)),
              pw.Text(safe(report.impactStory)),
              pw.Text(
                safe('Est. repair range: ${report.estimatedRepairRange}'),
              ),
              pw.Text('Photos analyzed: ${report.photoCount}'),
              pw.SizedBox(height: 16),
              pw.Text(
                'Priority findings',
                style: const pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
            ];

            final ordered = report.issuesByPriority;
            if (ordered.isEmpty) {
              widgets.add(pw.Text('No findings recorded.'));
            } else {
              for (final issue in ordered) {
                widgets.add(
                  pw.Container(
                    margin: const pw.EdgeInsets.only(bottom: 10),
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          safe(issue.title),
                          style: const pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          safe(
                            '${issue.severity} · ${issue.location} · ${issue.cost}',
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(safe(issue.storyWhat)),
                        pw.Text(safe(issue.storyImpact)),
                        pw.Text(safe(issue.storyRecommendation)),
                      ],
                    ),
                  ),
                );
              }
            }

            if (l.homeownerNotes.isNotEmpty) {
              widgets.addAll([
                pw.SizedBox(height: 12),
                pw.Text(
                  'Homeowner notes',
                  style: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(safe(l.homeownerNotes)),
              ]);
            }

            return widgets;
          },
        ),
      );

      await Printing.layoutPdf(onLayout: (_) async => pdf.save());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF error: $e'),
          backgroundColor: AppLux.danger,
        ),
      );
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case LeadStatus.newLead:
        return const Color(0xFF2563EB);
      case LeadStatus.contacted:
        return const Color(0xFFD97706);
      case LeadStatus.quoted:
        return const Color(0xFF7C3AED);
      case LeadStatus.won:
        return const Color(0xFF059669);
      default:
        return const Color(0xFF64748B);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = lead;
    if (l == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Lead')),
        body: const Center(child: Text('Lead not found')),
      );
    }

    final report = l.reportSnapshot;
    final color = _statusColor(l.status);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppLux.bg,
      appBar: AppBar(
        title: Text(
          l.name,
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Export report PDF',
            onPressed: _exportReportPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + bottom),
        children: [
          // Contact card
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Contact',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppLux.charcoal,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        l.status,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _info(Icons.place_outlined, l.address),
                const SizedBox(height: 8),
                _info(Icons.phone_outlined, l.phone),
                const SizedBox(height: 8),
                _info(Icons.email_outlined, l.email),
                const SizedBox(height: 8),
                _info(Icons.schedule_rounded, l.preferredContact),
                const SizedBox(height: 8),
                _info(Icons.history_rounded, l.relativeDateLabel),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          unawaited(
                            Clipboard.setData(ClipboardData(text: l.phone)),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Phone copied',
                                style: GoogleFonts.inter(),
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Copy phone'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          unawaited(
                            Clipboard.setData(ClipboardData(text: l.email)),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Email copied',
                                style: GoogleFonts.inter(),
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Copy email'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Status
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pipeline status',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppLux.charcoal,
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: l.status,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppLux.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppLux.border),
                    ),
                  ),
                  items: LeadStatus.all
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(s, style: GoogleFonts.inter()),
                        ),
                      )
                      .toList(),
                  onChanged: (s) {
                    if (s != null) unawaited(_setStatus(s));
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Report snapshot
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Attached report',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppLux.charcoal,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _exportReportPdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: const Text('PDF'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Score ${report.overallScore}/100 · ${report.conditionLabel}',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppLux.charcoal,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${report.photoCount} photos · ${report.issues.length} findings · '
                  '${l.severitySummary}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppLux.body,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Planning range ${report.estimatedRepairRange}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppLux.teal,
                  ),
                ),
                if (l.hasPhotos) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Job photos (${l.photos.length})',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppLux.body,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 88,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: l.photos.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final p = l.photos[i];
                        return Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(
                                p.bytes,
                                width: 72,
                                height: 64,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(height: 2),
                            SizedBox(
                              width: 72,
                              child: Text(
                                p.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 9.5,
                                  color: AppLux.muted,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
                if (report.issues.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Findings',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppLux.body,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final issue in report.issues) _IssueRow(issue: issue),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          if (l.homeownerNotes.isNotEmpty) ...[
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Homeowner notes',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppLux.charcoal,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l.homeownerNotes,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      height: 1.4,
                      color: AppLux.charcoal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Contractor notes
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Internal notes',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppLux.charcoal,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _notesController,
                  minLines: 3,
                  maxLines: 6,
                  style: GoogleFonts.inter(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Private notes about this lead…',
                    hintStyle: GoogleFonts.inter(color: AppLux.muted),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppLux.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppLux.border),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _saveNotes,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppLux.charcoal,
                    ),
                    child: const Text('Save notes'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppLux.border),
      ),
      child: child,
    );
  }

  Widget _info(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppLux.charcoal,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.issue});
  final AnalysisIssue issue;

  Color get _color {
    switch (issue.severity) {
      case 'High':
        return const Color(0xFFDC2626);
      case 'Medium':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFF2563EB);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  issue.title,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppLux.charcoal,
                  ),
                ),
                Text(
                  '${issue.severity} · ${issue.location}'
                  '${issue.sourcePhotoLabel.isNotEmpty ? ' · From: ${issue.sourcePhotoLabel}' : ''}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppLux.body,
                  ),
                ),
                Text(
                  issue.planningCostLabel,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: AppLux.muted,
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
