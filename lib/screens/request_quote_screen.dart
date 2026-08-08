import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../legal/privacy_copy.dart';
import '../models/analysis_models.dart';
import '../models/capture_models.dart';
import '../models/lead_models.dart';
import '../models/saved_report.dart';
import '../services/image_codec_util.dart';
import '../services/lead_store.dart';
import '../services/profile_store.dart';
import '../services/quote_submit_service.dart';
import '../services/storage_exception.dart';
import '../theme/app_lux.dart';
import 'quote_confirmation_screen.dart';

/// Homeowner form to request a contractor quote from an analysis report.
class RequestQuoteScreen extends StatefulWidget {
  const RequestQuoteScreen({
    super.key,
    required this.report,
    this.photos = const [],
    this.savedReportId,
  });

  final AnalysisReport report;
  final List<CapturePhoto> photos;
  final String? savedReportId;

  @override
  State<RequestQuoteScreen> createState() => _RequestQuoteScreenState();
}

class _RequestQuoteScreenState extends State<RequestQuoteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  final _quoteSubmit = QuoteSubmitService();

  String _window = ContactWindows.all.first;
  bool _submitting = false;
  String? _submitError;

  /// Built on first submit attempt so retries reuse the same lead id.
  QuoteLead? _pendingLead;

  @override
  void initState() {
    super.initState();
    unawaited(_prefillProfile());
  }

  Future<void> _prefillProfile() async {
    await ProfileStore.instance.ensureLoaded();
    final p = ProfileStore.instance;
    if (!mounted) return;
    setState(() {
      if (p.name.isNotEmpty) _name.text = p.name;
      if (p.phone.isNotEmpty) _phone.text = p.phone;
      if (p.email.isNotEmpty) _email.text = p.email;
      if (p.address.isNotEmpty) _address.text = p.address;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _notes.dispose();
    _quoteSubmit.dispose();
    super.dispose();
  }

  AnalysisReport get report => widget.report;

  void _clearError() {
    if (_submitError != null) setState(() => _submitError = null);
  }

  Future<List<SavedPhoto>> _compressPhotos() async {
    final out = <SavedPhoto>[];
    for (final p in widget.photos) {
      try {
        final raw = await p.file.readAsBytes();
        final bytes = await ImageCodecUtil.compressForStorage(raw);
        if (bytes.isEmpty) continue;
        out.add(
          SavedPhoto(
            index: p.index,
            label: p.label,
            slotId: p.slotId,
            bytes: bytes,
          ),
        );
      } catch (_) {}
    }
    return out;
  }

  Future<QuoteLead> _buildOrReuseLead() async {
    final existing = _pendingLead;
    if (existing != null) {
      final updated = existing.copyWith(
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        address: _address.text.trim(),
        preferredContact: _window,
        homeownerNotes: _notes.text.trim(),
      );
      _pendingLead = updated;
      return updated;
    }
    final photos = await _compressPhotos();
    final lead = QuoteLead.fromReport(
      name: _name.text,
      phone: _phone.text,
      email: _email.text,
      address: _address.text,
      preferredContact: _window,
      homeownerNotes: _notes.text,
      report: report,
      savedReportId: widget.savedReportId,
      photos: photos,
    );
    _pendingLead = lead;
    return lead;
  }

  Future<void> _persistLeadLocally(QuoteLead lead) async {
    // Avoid duplicate entries if the user retries after a network error.
    final store = LeadStore.instance;
    await store.ensureLoaded();
    final already = store.leads.any((l) => l.id == lead.id);
    if (already) {
      await store.update(lead);
    } else {
      await store.add(lead);
    }
  }

  Future<void> _goToConfirmation(
    QuoteLead lead, {
    required bool deliveredRemotely,
  }) async {
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => QuoteConfirmationScreen(
          lead: lead,
          deliveredRemotely: deliveredRemotely,
        ),
      ),
    );
  }

  Future<void> _submit({bool localOnly = false}) async {
    if (_submitting) return;
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    // Unconfigured builds always save locally — never throw "not configured".
    final forceLocal = localOnly || !QuoteSubmitConfig.isConfigured;

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      // Remember contact details for quote autofill (offline-safe).
      await ProfileStore.instance.save(
        name: _name.text,
        phone: _phone.text,
        email: _email.text,
        address: _address.text,
      );

      final lead = await _buildOrReuseLead();

      if (forceLocal) {
        await _persistLeadLocally(lead);
        await _goToConfirmation(lead, deliveredRemotely: false);
        return;
      }

      // Send via Formspree (or configured endpoint).
      try {
        await _quoteSubmit.submit(lead: lead, report: report);
        await _persistLeadLocally(lead);
        await _goToConfirmation(lead, deliveredRemotely: true);
      } on QuoteSubmitException catch (e) {
        // Network/config failure: keep the lead on-device so the user is not stuck.
        await _persistLeadLocally(lead);
        if (!mounted) return;
        setState(() {
          _submitError =
              '${e.message} Your details were still saved as a local lead.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Email failed — lead saved on this device. You can share a PDF from the report.',
            ),
            backgroundColor: Colors.orange.shade800,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Done',
              textColor: Colors.white,
              onPressed: () {
                unawaited(
                  _goToConfirmation(lead, deliveredRemotely: false),
                );
              },
            ),
          ),
        );
        // Land on confirmation so the flow completes.
        await _goToConfirmation(lead, deliveredRemotely: false);
      }
    } on StorageFullException catch (e) {
      if (!mounted) return;
      setState(() => _submitError = e.userMessage);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.userMessage),
          backgroundColor: Colors.orange.shade800,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      const msg = 'Could not complete request. Please try again.';
      setState(() => _submitError = msg);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(msg),
          backgroundColor: AppLux.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final r = report;

    return Scaffold(
      backgroundColor: AppLux.bg,
      appBar: AppBar(
        backgroundColor: AppLux.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppLux.charcoal,
        title: Text(
          'Request a quote',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: AppLux.titleMd,
            letterSpacing: -0.2,
            color: AppLux.charcoal,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppLux.pagePaddingH,
                  10,
                  AppLux.pagePaddingH,
                  40,
                ),
                children: [
                  Text(
                    PrivacyCopy.quoteIntro,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      height: 1.55,
                      color: AppLux.body,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.05,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: AppLux.goldNote(radius: AppLux.radiusXl),
                    child: Text(
                      PrivacyCopy.screeningReminder,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        height: 1.45,
                        color: AppLux.disclaimerInk,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (!QuoteSubmitConfig.isConfigured) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      decoration: BoxDecoration(
                        color: AppLux.tealMist,
                        borderRadius: BorderRadius.circular(AppLux.radiusXl),
                        border: Border.all(
                          color: AppLux.teal.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Text(
                        'Email delivery is not configured in this build. '
                        'Submitting saves a contractor lead on this device only — '
                        'use Share PDF from your report to send the screening yourself.\n\n'
                        'To enable email: copy formspree.env.example.json → formspree.env.json, '
                        'paste your Formspree form URL, then run:\n'
                        r'.\scripts\run_edge_with_quote.ps1',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          height: 1.45,
                          color: AppLux.tealDeep,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      decoration: BoxDecoration(
                        color: AppLux.tealMist.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(AppLux.radiusXl),
                        border: Border.all(
                          color: AppLux.teal.withValues(alpha: 0.16),
                        ),
                      ),
                      child: Text(
                        'Email is on. Your request will notify the FirstSign team '
                        '(${QuoteSubmitConfig.destinationEmail}) and save a local lead.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          height: 1.45,
                          color: AppLux.tealDeep,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _ReportSummaryCard(report: r),
                  const SizedBox(height: 28),
                  AppLux.sectionHeader('Your details'),
                  const SizedBox(height: 8),
                  Text(
                    'Prefills from your profile when available. FirstSign keeps a '
                    'copy on this device after you submit.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.45,
                      color: AppLux.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _field(
                    controller: _name,
                    label: 'Full name',
                    hint: 'e.g. Maria Gonzalez',
                    icon: Icons.person_outline_rounded,
                    textCapitalization: TextCapitalization.words,
                    validator: (v) {
                      if (v == null || v.trim().length < 2) {
                        return 'Please enter your name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 22),
                  _field(
                    controller: _phone,
                    label: 'Phone',
                    hint: '(555) 123-4567',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[\d\s\-\+\(\)]'),
                      ),
                    ],
                    validator: (v) {
                      final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                      if (digits.length < 10) {
                        return 'Enter a valid phone number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 22),
                  _field(
                    controller: _email,
                    label: 'Email',
                    hint: 'you@email.com',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty || !t.contains('@') || !t.contains('.')) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 22),
                  _field(
                    controller: _address,
                    label: 'Property address',
                    hint: '123 Maple Grove Lane, City, ST',
                    icon: Icons.home_outlined,
                    textCapitalization: TextCapitalization.words,
                    maxLines: 2,
                    validator: (v) {
                      if (v == null || v.trim().length < 5) {
                        return 'Enter the property address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Best time to contact',
                    style: GoogleFonts.inter(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppLux.charcoal,
                      letterSpacing: -0.15,
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _window,
                    dropdownColor: AppLux.surface,
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppLux.icon,
                      size: 22,
                    ),
                    decoration: _decoration(icon: Icons.schedule_rounded),
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppLux.charcoal,
                    ),
                    items: ContactWindows.all
                        .map(
                          (w) => DropdownMenuItem(
                            value: w,
                            child: Text(w, style: GoogleFonts.inter()),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _window = v);
                    },
                  ),
                  const SizedBox(height: 22),
                  _field(
                    controller: _notes,
                    label: 'Notes for contractors (optional)',
                    hint: 'Access notes, urgency, preferred materials…',
                    icon: Icons.notes_rounded,
                    maxLines: 3,
                    validator: (_) => null,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    PrivacyCopy.quoteFootnote,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.5,
                      color: AppLux.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Sticky premium CTA + error strip
          Container(
            padding: EdgeInsets.fromLTRB(26, 14, 26, 18 + bottom),
            decoration: BoxDecoration(
              color: AppLux.surface.withValues(alpha: 0.97),
              border: Border(
                top: BorderSide(
                  color: AppLux.border.withValues(alpha: 0.75),
                  width: 0.55,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppLux.charcoal.withValues(alpha: 0.035),
                  blurRadius: 24,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_submitError != null) ...[
                  _SubmitErrorBanner(
                    message: _submitError!,
                    onDismiss: _clearError,
                    onSaveLocally: _submitting
                        ? null
                        : () => _submit(localOnly: true),
                  ),
                  const SizedBox(height: 12),
                ],
                _PremiumSubmitButton(
                  submitting: _submitting,
                  label: QuoteSubmitConfig.isConfigured
                      ? null
                      : 'Save lead on this device',
                  onPressed: _submitting
                      ? null
                      : () => _submit(
                          localOnly: !QuoteSubmitConfig.isConfigured,
                        ),
                ),
                if (QuoteSubmitConfig.isConfigured) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => _submit(localOnly: true),
                    child: Text(
                      'Save on this device only (no email)',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: AppLux.body,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Tall fields, hairline borders, soft teal focus.
  InputDecoration _decoration({required IconData icon, String? hint}) {
    final radius = BorderRadius.circular(AppLux.radius2xl);
    return InputDecoration(
      isDense: false,
      hintText: hint,
      hintStyle: GoogleFonts.inter(
        color: AppLux.muted.withValues(alpha: 0.85),
        fontSize: 15,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.05,
      ),
      prefixIcon: Icon(icon, size: 20, color: AppLux.icon),
      prefixIconConstraints: const BoxConstraints(minWidth: 52, minHeight: 56),
      filled: true,
      fillColor: AppLux.surface,
      contentPadding: const EdgeInsets.fromLTRB(4, 20, 18, 20),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: AppLux.borderSoft, width: 0.7),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: AppLux.border, width: 0.7),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(
          color: AppLux.teal.withValues(alpha: 0.72),
          width: 1.35,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(
          color: const Color(0xFFB91C1C).withValues(alpha: 0.55),
          width: 0.9,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(
          color: const Color(0xFFB91C1C).withValues(alpha: 0.8),
          width: 1.25,
        ),
      ),
      errorStyle: GoogleFonts.inter(
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        height: 1.35,
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
    int maxLines = 1,
    required String? Function(String?) validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: AppLux.charcoal,
            letterSpacing: -0.15,
          ),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textCapitalization: textCapitalization,
          maxLines: maxLines,
          cursorColor: AppLux.teal,
          cursorWidth: 1.4,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: AppLux.charcoal,
            height: 1.4,
            letterSpacing: -0.1,
          ),
          decoration: _decoration(icon: icon, hint: hint),
          validator: validator,
        ),
      ],
    );
  }
}

/// Inline error after a failed Formspree send, with optional local-only save.
class _SubmitErrorBanner extends StatelessWidget {
  const _SubmitErrorBanner({
    required this.message,
    required this.onDismiss,
    this.onSaveLocally,
  });

  final String message;
  final VoidCallback onDismiss;
  final VoidCallback? onSaveLocally;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: AppLux.dangerSoft,
        borderRadius: BorderRadius.circular(AppLux.radiusLg),
        border: Border.all(
          color: AppLux.danger.withValues(alpha: 0.22),
          width: 0.75,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 20,
                color: AppLux.danger,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                    color: AppLux.charcoal,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                onPressed: onDismiss,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: AppLux.muted,
                ),
              ),
            ],
          ),
          if (onSaveLocally != null) ...[
            const SizedBox(height: 8),
            Text(
              'Your report is still saved on this device. You can retry sending, '
              'or keep a local contractor lead only.',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                height: 1.4,
                color: AppLux.body,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onSaveLocally,
                style: TextButton.styleFrom(
                  foregroundColor: AppLux.teal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(
                  'Save on this device only',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Premium teal CTA — taller, soft layered shadow, gentle press.
class _PremiumSubmitButton extends StatefulWidget {
  const _PremiumSubmitButton({
    required this.submitting,
    required this.onPressed,
    this.label,
  });

  final bool submitting;
  final VoidCallback? onPressed;
  final String? label;

  @override
  State<_PremiumSubmitButton> createState() => _PremiumSubmitButtonState();
}

class _PremiumSubmitButtonState extends State<_PremiumSubmitButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.submitting;

    return AnimatedScale(
      scale: _pressed && enabled ? 0.982 : 1.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: enabled
                ? [
                    Color.lerp(AppLux.teal, AppLux.tealBright, 0.28)!,
                    AppLux.teal,
                    Color.lerp(AppLux.teal, const Color(0xFF0A5C56), 0.25)!,
                  ]
                : [
                    AppLux.teal.withValues(alpha: 0.42),
                    AppLux.teal.withValues(alpha: 0.38),
                    AppLux.teal.withValues(alpha: 0.35),
                  ],
            stops: const [0.0, 0.55, 1.0],
          ),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AppLux.teal.withValues(
                      alpha: _pressed ? 0.14 : 0.22,
                    ),
                    blurRadius: _pressed ? 16 : 28,
                    offset: Offset(0, _pressed ? 6 : 12),
                    spreadRadius: _pressed ? 0 : 0.5,
                  ),
                  BoxShadow(
                    color: AppLux.charcoal.withValues(alpha: 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? widget.onPressed : null,
            onHighlightChanged: (v) => setState(() => _pressed = v),
            borderRadius: BorderRadius.circular(18),
            splashColor: Colors.white.withValues(alpha: 0.10),
            highlightColor: Colors.white.withValues(alpha: 0.05),
            child: SizedBox(
              height: 60,
              width: double.infinity,
              child: Center(
                child: widget.submitting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.label ?? 'Send quote request',
                            style: GoogleFonts.inter(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              letterSpacing: 0.2,
                              height: 1,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                            color: Colors.white.withValues(alpha: 0.88),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportSummaryCard extends StatelessWidget {
  const _ReportSummaryCard({required this.report});
  final AnalysisReport report;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppLux.border.withValues(alpha: 0.85),
          width: 0.65,
        ),
        boxShadow: AppLux.softShadow(),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppLux.surface,
            Color.lerp(AppLux.surface, AppLux.tealMist, 0.35)!,
            Color.lerp(AppLux.surface, AppLux.goldSoft, 0.28)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Subtle teal accent rail
            Container(
              width: 3.5,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppLux.teal,
                    AppLux.tealBright.withValues(alpha: 0.55),
                    AppLux.gold.withValues(alpha: 0.45),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 20, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppLux.charcoal,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: AppLux.charcoal.withValues(
                                  alpha: 0.14,
                                ),
                                blurRadius: 14,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${report.overallScore}',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  fontSize: 20,
                                  height: 1,
                                  letterSpacing: -0.8,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'SCORE',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withValues(alpha: 0.48),
                                  fontSize: 9,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppLux.teal.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: AppLux.teal.withValues(
                                      alpha: 0.12,
                                    ),
                                    width: 0.6,
                                  ),
                                ),
                                child: Text(
                                  'REPORT ATTACHED',
                                  style: GoogleFonts.inter(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppLux.teal,
                                    letterSpacing: 0.85,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                report.conditionLabel,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppLux.charcoal,
                                  height: 1.28,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppLux.teal.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            size: 17,
                            color: AppLux.teal.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      height: 0.55,
                      color: AppLux.border.withValues(alpha: 0.75),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip(
                          '${report.photoCount} photos',
                          Icons.photo_library_outlined,
                        ),
                        _chip(
                          '${report.issues.length} findings',
                          Icons.analytics_outlined,
                        ),
                        if (report.highCount > 0)
                          _chip(
                            '${report.highCount} high',
                            Icons.priority_high_rounded,
                            accent: const Color(0xFFB91C1C),
                          ),
                        _chip(
                          report.estimatedRepairRange,
                          Icons.attach_money_rounded,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, IconData icon, {Color? accent}) {
    final color = accent ?? AppLux.charcoal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppLux.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: (accent ?? AppLux.border).withValues(
            alpha: accent != null ? 0.18 : 0.9,
          ),
          width: 0.6,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color.withValues(alpha: 0.7)),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.05,
            ),
          ),
        ],
      ),
    );
  }
}
