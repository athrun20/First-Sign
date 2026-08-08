import 'package:flutter_test/flutter_test.dart';
import 'package:pillar_ai/models/analysis_models.dart';
import 'package:pillar_ai/models/contractor_models.dart';
import 'package:pillar_ai/services/contractor_matching.dart';

AnalysisIssue _issue({
  required String title,
  String location = 'Front elevation',
  String severity = 'Medium',
  int confidence = 85,
}) {
  return AnalysisIssue(
    title: title,
    location: location,
    severity: severity,
    cost: r'$500–$1,500',
    confidence: confidence,
    insight: 'Screening note for $title',
  );
}

AnalysisReport _report(List<AnalysisIssue> issues) {
  return AnalysisReport(
    overallScore: 80,
    conditionLabel: 'Mixed condition',
    issues: issues,
    estimatedRepairRange: r'$1,000–$4,000',
    analysisSource: 'test',
    photoCount: 3,
  );
}

Contractor _contractor({
  required String id,
  required String name,
  List<String> trades = const [],
  List<String> serviceAreas = const [],
  bool isActive = true,
  String? companyName,
}) {
  return Contractor(
    id: id,
    name: name,
    companyName: companyName,
    trades: trades,
    serviceAreas: serviceAreas,
    phone: '555-0100',
    email: '$id@example.com',
    isActive: isActive,
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

void main() {
  group('ContractorTrade.normalize', () {
    test('maps free text to canonical tags', () {
      expect(ContractorTrade.normalize('Roofer'), ContractorTrade.roofing);
      expect(ContractorTrade.normalize('GUTTERS'), ContractorTrade.gutters);
      expect(
        ContractorTrade.normalize('foundation repair'),
        ContractorTrade.foundation,
      );
      expect(ContractorTrade.normalize('general contractor'), ContractorTrade.general);
    });
  });

  group('tradeFromFinding', () {
    test('maps common exterior systems', () {
      expect(
        ContractorMatching.tradeFromFinding(
          _issue(title: 'Missing / Damaged Shingles'),
        ),
        ContractorTrade.roofing,
      );
      expect(
        ContractorMatching.tradeFromFinding(
          _issue(title: 'Possible Gutter Overflow'),
        ),
        ContractorTrade.gutters,
      );
      expect(
        ContractorMatching.tradeFromFinding(
          _issue(title: 'Foundation Crack / Settlement Signs'),
        ),
        ContractorTrade.foundation,
      );
      expect(
        ContractorMatching.tradeFromFinding(
          _issue(title: 'Peeling / Failing Exterior Paint'),
        ),
        ContractorTrade.paint,
      );
      expect(
        ContractorMatching.tradeFromFinding(
          _issue(title: 'Cracked / Damaged Siding'),
        ),
        ContractorTrade.siding,
      );
    });
  });

  group('matchContractors', () {
    final roofGutterReport = _report([
      _issue(title: 'Missing / Damaged Shingles', severity: 'High'),
      _issue(title: 'Possible Gutter Overflow', severity: 'Medium'),
    ]);

    test('returns empty when report has no findings', () {
      final matches = matchContractors(
        contractors: [
          _contractor(
            id: 'c1',
            name: 'Any',
            trades: [ContractorTrade.general],
          ),
        ],
        report: _report(const []),
        propertyAddress: 'Atlanta, GA 30301',
      );
      expect(matches, isEmpty);
    });

    test('skips inactive contractors', () {
      final matches = matchContractors(
        contractors: [
          _contractor(
            id: 'c1',
            name: 'Inactive Roofer',
            trades: [ContractorTrade.roofing],
            serviceAreas: const [],
            isActive: false,
          ),
        ],
        report: roofGutterReport,
        propertyAddress: 'Atlanta, GA 30301',
      );
      expect(matches, isEmpty);
    });

    test('requires trade overlap (no force-send)', () {
      final matches = matchContractors(
        contractors: [
          _contractor(
            id: 'c1',
            name: 'Windows Only',
            trades: [ContractorTrade.windows],
            serviceAreas: const [],
          ),
        ],
        report: roofGutterReport,
        propertyAddress: 'Atlanta, GA 30301',
      );
      expect(matches, isEmpty);
    });

    test('matches specialty trade + open service area (fallback)', () {
      final matches = matchContractors(
        contractors: [
          _contractor(
            id: 'c1',
            name: 'National Roof Co',
            trades: [ContractorTrade.roofing],
            serviceAreas: const [],
          ),
        ],
        report: roofGutterReport,
        propertyAddress: 'Atlanta, GA 30301',
      );
      expect(matches, hasLength(1));
      expect(matches.first.matchedTrades, contains(ContractorTrade.roofing));
      expect(matches.first.areaFallback, isTrue);
      expect(matches.first.areaSpecificMatch, isFalse);
    });

    test('general trade covers any finding set', () {
      final matches = matchContractors(
        contractors: [
          _contractor(
            id: 'c1',
            name: 'GC Pros',
            trades: [ContractorTrade.general],
            serviceAreas: const [],
          ),
        ],
        report: roofGutterReport,
        propertyAddress: 'Atlanta, GA 30301',
      );
      expect(matches, hasLength(1));
      expect(matches.first.matchedTrades, contains(ContractorTrade.general));
    });

    test('service area ZIP and city overlap', () {
      final pool = [
        _contractor(
          id: 'zip',
          name: 'ZIP Roofer',
          trades: [ContractorTrade.roofing],
          serviceAreas: const ['30301', '30308'],
        ),
        _contractor(
          id: 'city',
          name: 'City Gutter',
          trades: [ContractorTrade.gutters],
          serviceAreas: const ['Atlanta'],
        ),
        _contractor(
          id: 'far',
          name: 'Miami Only',
          trades: [ContractorTrade.roofing],
          serviceAreas: const ['Miami', '33101'],
        ),
      ];

      final matches = matchContractors(
        contractors: pool,
        report: roofGutterReport,
        propertyAddress: '123 Peachtree St, Atlanta, GA 30301',
      );

      final ids = matches.map((m) => m.contractor.id).toList();
      expect(ids, containsAll(['zip', 'city']));
      expect(ids, isNot(contains('far')));
    });

    test('specific area fails when property address is empty', () {
      final matches = matchContractors(
        contractors: [
          _contractor(
            id: 'c1',
            name: 'Local Only',
            trades: [ContractorTrade.roofing],
            serviceAreas: const ['Atlanta'],
          ),
        ],
        report: roofGutterReport,
        propertyAddress: '',
      );
      expect(matches, isEmpty);
    });

    test('ranks multi-trade local higher than national generalist', () {
      final matches = matchContractors(
        contractors: [
          _contractor(
            id: 'general_national',
            name: 'National GC',
            trades: [ContractorTrade.general],
            serviceAreas: const [],
          ),
          _contractor(
            id: 'local_specialist',
            name: 'Atlanta Exterior',
            companyName: 'Atlanta Exterior LLC',
            trades: [ContractorTrade.roofing, ContractorTrade.gutters],
            serviceAreas: const ['Atlanta', '30301'],
          ),
        ],
        report: roofGutterReport,
        propertyAddress: 'Atlanta, GA 30301',
      );

      expect(matches, hasLength(2));
      expect(matches.first.contractor.id, 'local_specialist');
      expect(matches.first.areaSpecificMatch, isTrue);
      expect(matches.first.score, greaterThan(matches.last.score));
    });

    test('JSON round-trip preserves contractor fields', () {
      final original = Contractor.create(
        name: 'Jordan Lee',
        companyName: 'Lee Roofing',
        trades: const ['roofing', 'gutters'],
        serviceAreas: const ['Decatur', '30030'],
        phone: '404-555-0101',
        email: 'jordan@leerofing.test',
        notes: 'Invite batch A',
      );
      final restored = Contractor.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.companyName, original.companyName);
      expect(restored.trades, containsAll([
        ContractorTrade.roofing,
        ContractorTrade.gutters,
      ]));
      expect(restored.serviceAreas, ['Decatur', '30030']);
      expect(restored.isActive, isTrue);
    });
  });

  group('serviceAreaOverlapsAddress', () {
    test('matches ZIP token', () {
      expect(
        ContractorMatching.serviceAreaOverlapsAddress(
          serviceAreas: const ['30309'],
          propertyAddress: '12 10th St NW, Atlanta GA 30309',
        ),
        isTrue,
      );
    });

    test('rejects unrelated metro', () {
      expect(
        ContractorMatching.serviceAreaOverlapsAddress(
          serviceAreas: const ['Savannah'],
          propertyAddress: 'Atlanta, GA 30301',
        ),
        isFalse,
      );
    });
  });
}
