import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pillar_ai/config/app_config.dart';
import 'package:pillar_ai/models/analysis_models.dart';
import 'package:pillar_ai/models/contractor_models.dart';
import 'package:pillar_ai/models/lead_models.dart';
import 'package:pillar_ai/services/quote_submit_service.dart';

const _reportWithRoof = AnalysisReport(
  overallScore: 80,
  conditionLabel: 'Mixed',
  issues: [
    AnalysisIssue(
      title: 'Missing / Damaged Shingles',
      location: 'Front slope',
      severity: 'High',
      cost: r'$1,000 – $3,000',
      confidence: 90,
      insight: 'Replace damaged tabs.',
    ),
    AnalysisIssue(
      title: 'Possible Gutter Overflow',
      location: 'Eaves',
      severity: 'Medium',
      cost: r'$100',
      confidence: 88,
      insight: 'Clean gutters.',
    ),
  ],
  estimatedRepairRange: r'$1,500 – $4,000',
  analysisSource: 'test',
  photoCount: 3,
);

QuoteLead _lead({AnalysisReport report = _reportWithRoof}) {
  return QuoteLead(
    id: 'lead-test-1',
    name: 'Ada Lovelace',
    phone: '5551234567',
    email: 'ada@example.com',
    address: '123 Peachtree St, Atlanta, GA 30301',
    preferredContact: 'Anytime',
    homeownerNotes: 'Prefer morning calls',
    contractorNotes: '',
    status: LeadStatus.newLead,
    createdAt: DateTime(2026, 1, 1),
    reportSnapshot: report,
    photos: const [],
  );
}

Contractor _roofer({
  String id = 'c-roof',
  bool active = true,
  String email = 'roofer@example.com',
  List<String> areas = const ['Atlanta', '30301'],
}) {
  return Contractor(
    id: id,
    name: 'Riley Roofer',
    companyName: 'Riley Roofing',
    trades: const [ContractorTrade.roofing],
    serviceAreas: areas,
    phone: '404-555-0100',
    email: email,
    isActive: active,
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

void main() {
  group('AppConfig Formspree normalize', () {
    test('expands bare form id', () {
      expect(
        AppConfig.normalizeFormspreeEndpoint('xpwzgkqr'),
        'https://formspree.io/f/xpwzgkqr',
      );
    });

    test('keeps full https URL', () {
      expect(
        AppConfig.normalizeFormspreeEndpoint(
          'https://formspree.io/f/xpwzgkqr',
        ),
        'https://formspree.io/f/xpwzgkqr',
      );
    });

    test('rejects placeholders', () {
      expect(AppConfig.normalizeFormspreeEndpoint('YOUR_FORM_ID'), isEmpty);
      expect(
        AppConfig.normalizeFormspreeEndpoint(
          'https://formspree.io/f/YOUR_FORM_ID',
        ),
        isEmpty,
      );
      expect(AppConfig.normalizeFormspreeEndpoint(''), isEmpty);
    });

    test('isValidFormspreeEndpoint', () {
      expect(
        AppConfig.isValidFormspreeEndpoint('https://formspree.io/f/xpwzgkqr'),
        isTrue,
      );
      expect(AppConfig.isValidFormspreeEndpoint('xpwzgkqr'), isTrue);
      expect(AppConfig.isValidFormspreeEndpoint('YOUR_FORM_ID'), isFalse);
    });
  });

  group('QuoteSubmitService helpers', () {
    test('topFindingsSummary lists issues', () {
      final summary = QuoteSubmitService.topFindingsSummary(_reportWithRoof);
      expect(summary.toLowerCase(), contains('shingle'));
      expect(summary, contains('High'));
    });

    test('composeHomeownerConfirmation includes score and screening note', () {
      final lead = _lead();
      final body = QuoteSubmitService.composeHomeownerConfirmation(
        lead: lead,
        report: _reportWithRoof,
        findings: QuoteSubmitService.topFindingsSummary(_reportWithRoof),
      );
      expect(body, contains('80'));
      expect(body.toLowerCase(), contains('screening'));
      expect(body, contains('Ada'));
    });

    test('composeInviteeLeadMessage includes lead fields and screening note', () {
      final lead = _lead();
      final match = ContractorMatch(
        contractor: _roofer(),
        score: 32,
        matchedTrades: {ContractorTrade.roofing},
        areaSpecificMatch: true,
        areaFallback: false,
      );
      final body = QuoteSubmitService.composeInviteeLeadMessage(
        lead: lead,
        report: _reportWithRoof,
        findings: QuoteSubmitService.topFindingsSummary(_reportWithRoof),
        match: match,
      );
      expect(body, contains('Ada Lovelace'));
      expect(body, contains('5551234567'));
      expect(body, contains('ada@example.com'));
      expect(body, contains('Peachtree'));
      expect(body, contains('80'));
      expect(body, contains('lead-test-1'));
      expect(body.toLowerCase(), contains('firstsign'));
      expect(body.toLowerCase(), contains('screening'));
      expect(body, contains(ContractorTrade.roofing));
    });
  });

  group('QuoteSubmitService invitee fan-out', () {
    test('notifies matching contractors after team post (best-effort)', () async {
      final posts = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        posts.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('{"ok":true}', 200);
      });

      final service = QuoteSubmitService(
        client: client,
        endpoint: 'https://formspree.io/f/teamform1',
        confirmEndpoint: 'https://formspree.io/f/confirm1',
        contractorNotifyEndpoint: 'https://formspree.io/f/invitee1',
        contractorsOverride: [
          _roofer(),
          _roofer(
            id: 'c-miami',
            email: 'miami@example.com',
            areas: const ['Miami', '33101'],
          ),
          _roofer(id: 'c-inactive', active: false, email: 'off@example.com'),
          _roofer(id: 'c-no-email', email: ''),
        ],
      );

      final result = await service.submit(lead: _lead());
      expect(result.ok, isTrue);
      // team + homeowner confirm + 1 invitee (Atlanta roofer only)
      expect(posts.length, 3);
      expect(result.contractorsMatched, 2); // atlanta + no-email still matches
      expect(result.contractorsNotified, 1);
      expect(result.contractorNotifySkipped, 1);

      final inviteePosts = posts
          .where((p) => p['submission_type'] == 'invitee_lead_notify')
          .toList();
      expect(inviteePosts, hasLength(1));
      expect(inviteePosts.single['contractor_email'], 'roofer@example.com');
      expect(inviteePosts.single['_cc'], 'roofer@example.com');
      expect(inviteePosts.single['lead_id'], 'lead-test-1');
      expect(inviteePosts.single['email'], 'roofer@example.com');
      expect(
        (inviteePosts.single['message'] as String).toLowerCase(),
        contains('screening lead'),
      );

      service.dispose();
    });

    test('no invitee posts when no contractors match', () async {
      final posts = <String>[];
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        posts.add(body['submission_type'] as String? ?? '');
        return http.Response('{"ok":true}', 200);
      });

      final service = QuoteSubmitService(
        client: client,
        endpoint: 'https://formspree.io/f/teamform1',
        confirmEndpoint: 'https://formspree.io/f/confirm1',
        contractorNotifyEndpoint: 'https://formspree.io/f/invitee1',
        contractorsOverride: [
          _roofer(areas: const ['Miami']), // wrong metro
        ],
      );

      final result = await service.submit(lead: _lead());
      expect(result.ok, isTrue);
      expect(result.contractorsMatched, 0);
      expect(result.contractorsNotified, 0);
      expect(posts, isNot(contains('invitee_lead_notify')));
      // team + homeowner only
      expect(posts, containsAll(['contractor_quote', 'homeowner_confirmation']));

      service.dispose();
    });

    test('invitee HTTP failure does not fail quote', () async {
      var n = 0;
      final client = MockClient((request) async {
        n++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['submission_type'] == 'invitee_lead_notify') {
          return http.Response('{"error":"rate limit"}', 429);
        }
        return http.Response('{"ok":true}', 200);
      });

      final service = QuoteSubmitService(
        client: client,
        endpoint: 'https://formspree.io/f/teamform1',
        confirmEndpoint: 'https://formspree.io/f/confirm1',
        contractorNotifyEndpoint: 'https://formspree.io/f/invitee1',
        contractorsOverride: [_roofer()],
      );

      final result = await service.submit(lead: _lead());
      expect(result.ok, isTrue);
      expect(result.contractorsMatched, 1);
      expect(result.contractorsNotified, 0);
      expect(result.contractorNotifySkipped, 1);
      expect(n, greaterThanOrEqualTo(3));

      service.dispose();
    });
  });
}
