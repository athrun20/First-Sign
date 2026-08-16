import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../legal/cost_copy.dart';
import '../legal/privacy_copy.dart';
import '../models/analysis_models.dart';
import '../models/contractor_models.dart';
import '../models/lead_models.dart';
import 'contractor_matching.dart';
import 'contractor_store.dart';

/// Configuration for remote quote delivery (Formspree).
///
/// See [AppConfig] and `docs/QUOTE_EMAIL_SETUP.md`.
///
/// Quick start:
/// ```powershell
/// copy formspree.env.example.json formspree.env.json
/// # paste form URL into formspree.env.json
/// .\scripts\run_edge_with_quote.ps1
/// ```
abstract final class QuoteSubmitConfig {
  /// Inbox that should receive quote requests (configure this on Formspree).
  static String get destinationEmail => AppConfig.quoteTeamEmail;

  /// Normalized team Formspree endpoint (empty when not configured).
  static String get endpoint => AppConfig.formspreeEndpoint;

  /// Homeowner-confirm endpoint (falls back to [endpoint]).
  static String get confirmEndpoint => AppConfig.formspreeConfirmEndpoint;

  /// Invitee fan-out endpoint (falls back to [endpoint]).
  static String get contractorNotifyEndpoint =>
      AppConfig.formspreeContractorNotifyEndpoint;

  /// True when a real primary endpoint is configured at compile time.
  static bool get isConfigured => AppConfig.quoteEmailConfigured;

  /// True when confirmation uses a form URL different from the team form.
  static bool get hasDedicatedConfirmEndpoint =>
      AppConfig.hasDedicatedConfirmEndpoint;

  /// True when invitee notify uses a form URL different from the team form.
  static bool get hasDedicatedContractorNotifyEndpoint =>
      AppConfig.hasDedicatedContractorNotifyEndpoint;
}

/// Result of a remote quote submission attempt.
class QuoteSubmitResult {
  const QuoteSubmitResult({
    required this.ok,
    this.message,
    this.statusCode,
    this.homeownerConfirmAttempted = false,
    this.homeownerConfirmOk = false,
    this.contractorsMatched = 0,
    this.contractorsNotified = 0,
    this.contractorNotifySkipped = 0,
  });

  final bool ok;
  final String? message;
  final int? statusCode;

  /// Whether a homeowner confirmation POST was attempted after success.
  final bool homeownerConfirmAttempted;

  /// Whether that confirmation POST returned 2xx (best-effort only).
  final bool homeownerConfirmOk;

  /// Active invitees that matched trades + service area for this lead.
  final int contractorsMatched;

  /// Invitees for whom a Formspree notify POST returned 2xx.
  final int contractorsNotified;

  /// Matched invitees skipped (no email) or failed notify (best-effort).
  final int contractorNotifySkipped;

  factory QuoteSubmitResult.success({
    bool homeownerConfirmAttempted = false,
    bool homeownerConfirmOk = false,
    int contractorsMatched = 0,
    int contractorsNotified = 0,
    int contractorNotifySkipped = 0,
  }) => QuoteSubmitResult(
    ok: true,
    homeownerConfirmAttempted: homeownerConfirmAttempted,
    homeownerConfirmOk: homeownerConfirmOk,
    contractorsMatched: contractorsMatched,
    contractorsNotified: contractorsNotified,
    contractorNotifySkipped: contractorNotifySkipped,
  );

  factory QuoteSubmitResult.failure(String message, {int? statusCode}) =>
      QuoteSubmitResult(ok: false, message: message, statusCode: statusCode);
}

/// Thrown when Formspree (or the network) rejects the **primary** quote request.
class QuoteSubmitException implements Exception {
  QuoteSubmitException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Posts homeowner quote requests to Formspree (or any compatible form endpoint).
///
/// Flow after a successful **team** notification:
/// 1. Best-effort homeowner confirmation (unchanged UX).
/// 2. Best-effort invitee fan-out: [matchContractors] → one Formspree POST per
///    matching active contractor with a valid email (`_cc` + body).
///
/// Invitee failures never fail the quote. Local lead storage is handled
/// separately by [LeadStore].
class QuoteSubmitService {
  QuoteSubmitService({
    http.Client? client,
    String? endpoint,
    String? confirmEndpoint,
    String? contractorNotifyEndpoint,
    this._contractorsOverride,
  }) : _endpointOverride = endpoint,
       _confirmEndpointOverride = confirmEndpoint,
       _contractorNotifyEndpointOverride = contractorNotifyEndpoint,
       _httpClient = client;

  http.Client? _httpClient;
  final String? _endpointOverride;
  final String? _confirmEndpointOverride;
  final String? _contractorNotifyEndpointOverride;

  /// When non-null, used instead of [ContractorStore] (tests / injection).
  final List<Contractor>? _contractorsOverride;

  http.Client get _http => _httpClient ??= http.Client();

  String get endpoint {
    final o = _endpointOverride?.trim();
    if (o != null && o.isNotEmpty) return o;
    return QuoteSubmitConfig.endpoint;
  }

  String get confirmEndpoint {
    final o = _confirmEndpointOverride?.trim();
    if (o != null && o.isNotEmpty) return o;
    return QuoteSubmitConfig.confirmEndpoint;
  }

  String get contractorNotifyEndpoint {
    final o = _contractorNotifyEndpointOverride?.trim();
    if (o != null && o.isNotEmpty) return o;
    return QuoteSubmitConfig.contractorNotifyEndpoint;
  }

  bool get isConfigured {
    final override = _endpointOverride?.trim() ?? '';
    if (override.isNotEmpty) {
      return AppConfig.isValidFormspreeEndpoint(override);
    }
    return QuoteSubmitConfig.isConfigured;
  }

  String get _resolvedEndpoint {
    final override = _endpointOverride?.trim() ?? '';
    if (override.isNotEmpty) {
      return AppConfig.normalizeFormspreeEndpoint(override);
    }
    return endpoint;
  }

  String get _resolvedConfirmEndpoint {
    final override = _confirmEndpointOverride?.trim() ?? '';
    if (override.isNotEmpty) {
      return AppConfig.normalizeFormspreeEndpoint(override);
    }
    return confirmEndpoint;
  }

  String get _resolvedContractorNotifyEndpoint {
    final override = _contractorNotifyEndpointOverride?.trim() ?? '';
    if (override.isNotEmpty) {
      return AppConfig.normalizeFormspreeEndpoint(override);
    }
    return contractorNotifyEndpoint;
  }

  /// Build a short multi-line summary of highest-priority findings.
  static String topFindingsSummary(AnalysisReport report, {int maxItems = 5}) {
    final ranked = report.issuesByPriority;
    if (ranked.isEmpty) return 'No findings flagged in this screening.';
    final buf = StringBuffer();
    final take = ranked.take(maxItems).toList();
    for (var i = 0; i < take.length; i++) {
      final issue = take[i];
      final loc = issue.location.trim().isEmpty
          ? ''
          : ' @ ${issue.location.trim()}';
      buf.writeln('${i + 1}. [${issue.severity}] ${issue.storyTitle}$loc');
    }
    if (ranked.length > maxItems) {
      buf.writeln('…and ${ranked.length - maxItems} more');
    }
    return buf.toString().trim();
  }

  /// POST the quote payload to Formspree (team), then best-effort homeowner
  /// confirm + invitee network notify.
  ///
  /// Throws [QuoteSubmitException] only when the **primary** team send fails.
  ///
  /// [contractors] overrides the local invite directory (useful in tests).
  /// When null, loads [ContractorStore.activeContractors].
  Future<QuoteSubmitResult> submit({
    required QuoteLead lead,
    AnalysisReport? report,
    List<Contractor>? contractors,
  }) async {
    if (!isConfigured) {
      throw QuoteSubmitException(
        'Quote email is not configured yet. Copy formspree.env.example.json to '
        'formspree.env.json, paste your Formspree form URL, then run with '
        '--dart-define-from-file=formspree.env.json (see docs/QUOTE_EMAIL_SETUP.md).',
      );
    }

    final r = report ?? lead.reportSnapshot;
    final findings = topFindingsSummary(r);
    final primary = _resolvedEndpoint;
    if (primary.isEmpty) {
      throw QuoteSubmitException(
        'Quote email endpoint is invalid. Use https://formspree.io/f/YOUR_FORM_ID.',
      );
    }

    await _postJson(
      uri: Uri.parse(primary),
      payload: _teamPayload(lead: lead, report: r, findings: findings),
      failureLabel: 'quote request',
    );

    // Primary path succeeded — confirmation is best-effort only.
    final confirm = await _tryHomeownerConfirmation(
      lead: lead,
      report: r,
      findings: findings,
    );

    // Invitee fan-out is also best-effort and never fails the quote.
    final invitee = await _tryNotifyMatchedContractors(
      lead: lead,
      report: r,
      findings: findings,
      contractors: contractors ?? _contractorsOverride,
    );

    return QuoteSubmitResult.success(
      homeownerConfirmAttempted: confirm.attempted,
      homeownerConfirmOk: confirm.ok,
      contractorsMatched: invitee.matched,
      contractorsNotified: invitee.notified,
      contractorNotifySkipped: invitee.skipped,
    );
  }

  /// Best-effort homeowner confirmation. Never throws.
  Future<({bool attempted, bool ok})> _tryHomeownerConfirmation({
    required QuoteLead lead,
    required AnalysisReport report,
    required String findings,
  }) async {
    final homeEmail = lead.email.trim();
    if (homeEmail.isEmpty || !homeEmail.contains('@')) {
      debugPrint('QuoteSubmit: skip homeowner confirm — no valid email');
      return (attempted: false, ok: false);
    }

    final confirmUrl = _resolvedConfirmEndpoint;
    if (!AppConfig.isValidFormspreeEndpoint(confirmUrl)) {
      debugPrint('QuoteSubmit: skip homeowner confirm — endpoint not set');
      return (attempted: false, ok: false);
    }

    try {
      await _postJson(
        uri: Uri.parse(confirmUrl),
        payload: _homeownerConfirmPayload(
          lead: lead,
          report: report,
          findings: findings,
        ),
        failureLabel: 'homeowner confirmation',
      );
      debugPrint('QuoteSubmit: homeowner confirmation posted to $confirmUrl');
      return (attempted: true, ok: true);
    } catch (e) {
      debugPrint('QuoteSubmit: homeowner confirmation failed (ignored): $e');
      return (attempted: true, ok: false);
    }
  }

  /// Match invitees and POST one Formspree notification each. Never throws.
  ///
  /// Rules: [matchContractors] (active + trade + service area). No match → no
  /// extra work. Missing contractor email → skip with log. HTTP failures →
  /// log and continue.
  Future<({int matched, int notified, int skipped})>
  _tryNotifyMatchedContractors({
    required QuoteLead lead,
    required AnalysisReport report,
    required String findings,
    List<Contractor>? contractors,
  }) async {
    try {
      final directory = await _resolveDirectory(contractors);
      final matches = matchContractors(
        contractors: directory,
        report: report,
        propertyAddress: lead.address,
      );

      if (matches.isEmpty) {
        debugPrint(
          'QuoteSubmit: invitee match — 0 contractors for lead ${lead.id} '
          '(address="${lead.address}", findings=${report.issues.length})',
        );
        return (matched: 0, notified: 0, skipped: 0);
      }

      debugPrint(
        'QuoteSubmit: invitee match — ${matches.length} contractor(s) for '
        'lead ${lead.id}: '
        '${matches.map((m) => m.contractor.displayName).join(", ")}',
      );

      final notifyUrl = _resolvedContractorNotifyEndpoint;
      if (!AppConfig.isValidFormspreeEndpoint(notifyUrl)) {
        debugPrint(
          'QuoteSubmit: invitee notify skipped — no Formspree endpoint '
          '(matched ${matches.length})',
        );
        return (matched: matches.length, notified: 0, skipped: matches.length);
      }

      var notified = 0;
      var skipped = 0;

      for (final match in matches) {
        final c = match.contractor;
        final email = c.email.trim();
        if (email.isEmpty || !email.contains('@')) {
          skipped++;
          debugPrint(
            'QuoteSubmit: invitee notify skip ${c.displayName} (${c.id}) '
            '— no email',
          );
          continue;
        }

        try {
          await _postJson(
            uri: Uri.parse(notifyUrl),
            payload: _inviteeLeadPayload(
              lead: lead,
              report: report,
              findings: findings,
              match: match,
            ),
            failureLabel: 'invitee lead notify',
          );
          notified++;
          debugPrint(
            'QuoteSubmit: invitee notified ${c.displayName} <$email> '
            'trades=${match.matchedTrades.join(",")} score=${match.score}',
          );
        } catch (e) {
          skipped++;
          debugPrint(
            'QuoteSubmit: invitee notify failed for ${c.displayName} '
            '(ignored): $e',
          );
        }
      }

      debugPrint(
        'QuoteSubmit: invitee fan-out done — matched=${matches.length} '
        'notified=$notified skipped=$skipped lead=${lead.id}',
      );
      return (matched: matches.length, notified: notified, skipped: skipped);
    } catch (e) {
      debugPrint('QuoteSubmit: invitee matching/notify crashed (ignored): $e');
      return (matched: 0, notified: 0, skipped: 0);
    }
  }

  Future<List<Contractor>> _resolveDirectory(
    List<Contractor>? contractors,
  ) async {
    if (contractors != null) return contractors;
    final override = _contractorsOverride;
    if (override != null) return override;
    await ContractorStore.instance.ensureLoaded();
    return ContractorStore.instance.activeContractors;
  }

  /// Team inbox payload (primary Formspree form).
  Map<String, dynamic> _teamPayload({
    required QuoteLead lead,
    required AnalysisReport report,
    required String findings,
  }) {
    return <String, dynamic>{
      // Contact
      'name': lead.name,
      'full_name': lead.name,
      'phone': lead.phone,
      'email': lead.email,
      'property_address': lead.address,
      'address': lead.address,
      // Report snapshot
      'report_score': report.overallScore,
      'top_findings': findings,
      'planning_range': CostCopy.labeled(report.estimatedRepairRange),
      'planning_range_note': CostCopy.inlineNote,
      // Extra context
      'preferred_contact': lead.preferredContact,
      'homeowner_notes': lead.homeownerNotes,
      'condition_label': report.conditionLabel,
      'findings_count': report.issues.length,
      'photo_count': lead.photoCount,
      'lead_id': lead.id,
      'submission_type': 'contractor_quote',
      'app': 'First Sign',
      'team_inbox': QuoteSubmitConfig.destinationEmail,
      // Formspree helpers
      '_replyto': lead.email,
      '_subject':
          'First Sign quote request · score ${report.overallScore} · ${lead.address}',
      // Honeypot — leave empty (spam bots often fill it).
      '_gotcha': '',
      'message': _composeTeamMessage(
        lead: lead,
        report: report,
        findings: findings,
      ),
    };
  }

  /// Payload shaped for homeowner confirmation + Formspree Autoresponse / `_cc`.
  Map<String, dynamic> _homeownerConfirmPayload({
    required QuoteLead lead,
    required AnalysisReport report,
    required String findings,
  }) {
    final body = composeHomeownerConfirmation(
      lead: lead,
      report: report,
      findings: findings,
    );
    final first = lead.name.trim().split(RegExp(r'\s+')).first;
    return <String, dynamic>{
      // Required for Formspree Autoresponse target
      'email': lead.email,
      'name': lead.name,
      'full_name': lead.name,
      // Structured fields (useful if custom templates allow them)
      'property_address': lead.address,
      'report_score': report.overallScore,
      'top_findings': findings,
      'planning_range': CostCopy.labeled(report.estimatedRepairRange),
      'planning_range_note': CostCopy.inlineNote,
      'condition_label': report.conditionLabel,
      'lead_id': lead.id,
      'submission_type': 'homeowner_confirmation',
      // Formspree helpers
      '_replyto': QuoteSubmitConfig.destinationEmail,
      '_subject': 'We received your First Sign quote request',
      // CC homeowner so they get a copy even without Autoresponse plugin
      '_cc': lead.email,
      '_gotcha': '',
      'message': body,
      'confirmation_body': body,
      'greeting': first.isEmpty ? 'Hello' : 'Hi $first',
      'app': 'First Sign',
    };
  }

  /// One POST per matched invitee. Uses `_cc` + `email` so Formspree can
  /// deliver to the contractor (plan features: CC and/or Autoresponse).
  Map<String, dynamic> _inviteeLeadPayload({
    required QuoteLead lead,
    required AnalysisReport report,
    required String findings,
    required ContractorMatch match,
  }) {
    final c = match.contractor;
    final body = composeInviteeLeadMessage(
      lead: lead,
      report: report,
      findings: findings,
      match: match,
    );
    final trades = match.matchedTrades.isEmpty
        ? c.trades.join(', ')
        : match.matchedTrades.join(', ');

    return <String, dynamic>{
      // Homeowner contact (the lead)
      'name': lead.name,
      'full_name': lead.name,
      'phone': lead.phone,
      'homeowner_email': lead.email,
      'homeowner_phone': lead.phone,
      'property_address': lead.address,
      'address': lead.address,
      // Report
      'report_score': report.overallScore,
      'condition_label': report.conditionLabel,
      'top_findings': findings,
      'planning_range': CostCopy.labeled(report.estimatedRepairRange),
      'planning_range_note': CostCopy.inlineNote,
      'findings_count': report.issues.length,
      'photo_count': lead.photoCount,
      'preferred_contact': lead.preferredContact,
      'homeowner_notes': lead.homeownerNotes,
      'lead_id': lead.id,
      // Invitee metadata
      'contractor_id': c.id,
      'contractor_name': c.name,
      'contractor_company': c.companyName ?? '',
      'contractor_email': c.email,
      'contractor_phone': c.phone,
      'matched_trades': trades,
      'match_score': match.score,
      'area_specific_match': match.areaSpecificMatch,
      'area_fallback': match.areaFallback,
      'submission_type': 'invitee_lead_notify',
      'app': 'First Sign',
      'screening_note':
          'Screening lead from First Sign — not a licensed inspection.',
      // Formspree delivery helpers — contractor is the recipient target
      'email': c.email.trim(),
      '_cc': c.email.trim(),
      '_replyto': lead.email,
      '_subject':
          'First Sign screening lead · score ${report.overallScore} · ${lead.address}',
      '_gotcha': '',
      'message': body,
    };
  }

  /// Calm homeowner-facing confirmation text (also used for Formspree `message`).
  static String composeHomeownerConfirmation({
    required QuoteLead lead,
    required AnalysisReport report,
    required String findings,
  }) {
    final first = lead.name.trim().split(RegExp(r'\s+')).first;
    final greet = first.isEmpty ? 'Hello' : 'Hi $first';
    final address = lead.address.trim().isEmpty
        ? 'your property'
        : lead.address.trim();
    final range = CostCopy.compact(report.estimatedRepairRange);

    return '''
$greet,

We received your quote request for $address.

Your screening summary
• Score: ${report.overallScore}/100
• Condition: ${report.conditionLabel.trim().isEmpty ? 'See report' : report.conditionLabel.trim()}
• ${CostCopy.shortLabel}: $range
  ${CostCopy.inlineNote}

Top findings
$findings

A local contractor may follow up using the contact details you shared. Your photos and full report stay on your device unless you export or share them.

${CostCopy.footnote}
${PrivacyCopy.screeningReminder}

— First Sign
'''
        .trim();
  }

  /// Clean lead email body for a matched invite-only contractor.
  static String composeInviteeLeadMessage({
    required QuoteLead lead,
    required AnalysisReport report,
    required String findings,
    required ContractorMatch match,
  }) {
    final c = match.contractor;
    final company = (c.companyName ?? '').trim();
    final greetName = c.name.trim().isEmpty
        ? (company.isEmpty ? 'there' : company)
        : c.name.trim().split(RegExp(r'\s+')).first;
    final range = CostCopy.compact(report.estimatedRepairRange);
    final condition = report.conditionLabel.trim().isEmpty
        ? 'See report'
        : report.conditionLabel.trim();
    final trades = match.matchedTrades.isEmpty
        ? '(see report)'
        : match.matchedTrades.join(', ');
    final areaNote = match.areaSpecificMatch
        ? 'Service area matched property address'
        : (match.areaFallback
              ? 'Open / national service area'
              : 'Service area check passed');

    return '''
Hi $greetName,

You have a new screening lead from First Sign (invite-only network).

This is a photo-based exterior screening lead — not a licensed inspection. Confirm scope on-site before bidding. Dollar amounts below are a planning range from photos, not a bid or inspection price.

HOMEOWNER
Name: ${lead.name}
Phone: ${lead.phone}
Email: ${lead.email}
Property: ${lead.address}
Best time: ${lead.preferredContact}

REPORT
Score: ${report.overallScore}/100
Condition: $condition
${CostCopy.shortLabel}: $range
${CostCopy.inlineNote}
Photos on homeowner device: ${lead.photoCount}
Findings flagged: ${report.issues.length}

TOP FINDINGS
$findings

HOMEOWNER NOTES
${lead.homeownerNotes.trim().isEmpty ? '(none)' : lead.homeownerNotes.trim()}

MATCH
Trades: $trades
Area: $areaNote
Lead id: ${lead.id}

${CostCopy.footnote}

Reply to the homeowner using the contact details above.

— First Sign
'''
        .trim();
  }

  static String _composeTeamMessage({
    required QuoteLead lead,
    required AnalysisReport report,
    required String findings,
  }) {
    return '''
New First Sign quote request
Destination: ${QuoteSubmitConfig.destinationEmail}

CONTACT
Name: ${lead.name}
Phone: ${lead.phone}
Email: ${lead.email}
Property: ${lead.address}
Best time: ${lead.preferredContact}

REPORT
Score: ${report.overallScore}/100
Condition: ${report.conditionLabel}
${CostCopy.shortLabel}: ${CostCopy.compact(report.estimatedRepairRange)}
${CostCopy.inlineNote}
Photos: ${lead.photoCount}
Findings: ${report.issues.length}

TOP FINDINGS
$findings

HOMEOWNER NOTES
${lead.homeownerNotes.trim().isEmpty ? '(none)' : lead.homeownerNotes.trim()}

Lead id: ${lead.id}

${CostCopy.footnote}
'''
        .trim();
  }

  Future<void> _postJson({
    required Uri uri,
    required Map<String, dynamic> payload,
    required String failureLabel,
  }) async {
    try {
      final response = await _http
          .post(
            uri,
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return;
      }

      final detail = _parseError(response.body);
      throw QuoteSubmitException(
        detail.isNotEmpty
            ? detail
            : 'Could not send $failureLabel (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    } on QuoteSubmitException {
      rethrow;
    } on http.ClientException catch (e) {
      throw QuoteSubmitException(
        'Network error — check your connection and try again. (${e.message})',
      );
    } catch (e) {
      if (e is QuoteSubmitException) rethrow;
      final msg = e.toString();
      if (msg.toLowerCase().contains('timeout') ||
          msg.toLowerCase().contains('timed out')) {
        throw QuoteSubmitException(
          'The request timed out. Check your connection and try again.',
        );
      }
      throw QuoteSubmitException(
        'Could not send $failureLabel. Please try again.',
      );
    }
  }

  static String _parseError(String body) {
    if (body.trim().isEmpty) return '';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final err = decoded['error'];
        if (err is String && err.trim().isNotEmpty) return err.trim();
        final errors = decoded['errors'];
        if (errors is List && errors.isNotEmpty) {
          return errors.map((e) => e.toString()).join(' ');
        }
        final msg = decoded['message'];
        if (msg is String && msg.trim().isNotEmpty) return msg.trim();
      }
    } catch (_) {
      // plain text body
    }
    final trimmed = body.trim();
    if (trimmed.length > 160) return '${trimmed.substring(0, 160)}…';
    return trimmed;
  }

  void dispose() {
    _httpClient?.close();
    _httpClient = null;
  }
}
