import '../models/analysis_models.dart';
import '../models/contractor_models.dart';

/// Pure, local-first contractor ↔ report matching.
///
/// ## Matching rules (invite-only network)
///
/// 1. **Active only** — inactive contractors never match.
/// 2. **Trade overlap** — contractor trades must intersect the trades inferred
///    from the report's top findings (title + location). Mapping examples:
///    roof/shingle → `roofing`, siding → `siding`, gutter → `gutters`,
///    foundation → `foundation`, paint/peel → `paint`, window/seal → `windows`.
///    A contractor tagged `general` matches any non-empty finding set.
/// 3. **Service area** — empty `serviceAreas` = national/fallback (passes any
///    property). Otherwise at least one area token must overlap the property
///    address / city / zip string (case-insensitive substring either way).
/// 4. **No force-send** — if nothing qualifies, return an empty list.
/// 5. **Ranking** — more / higher-severity trade hits score higher; specific
///    area beats national fallback; name is a stable tie-breaker.
///
/// Not wired into quote email or UI yet — call from a future router only.
abstract final class ContractorMatching {
  /// Default number of priority findings used for trade inference.
  static const int defaultTopFindingLimit = 5;

  /// Match [contractors] to a report + optional property address.
  ///
  /// [propertyAddress] should include city and/or ZIP when available
  /// (e.g. quote form address). Empty address still allows national/fallback
  /// contractors and anyone whose area list is empty; specific areas require
  /// a non-empty address to match.
  static List<ContractorMatch> matchContractors({
    required List<Contractor> contractors,
    required AnalysisReport report,
    String propertyAddress = '',
    int topFindingLimit = defaultTopFindingLimit,
  }) {
    final needed = tradesFromReport(report, topFindingLimit: topFindingLimit);
    // No findings → nothing to route (do not blast the network).
    if (needed.isEmpty) return const [];

    final address = propertyAddress.trim();
    final matches = <ContractorMatch>[];

    for (final c in contractors) {
      if (!c.isActive) continue;

      final tradeHit = _tradeOverlap(c.tradeSet, needed);
      if (tradeHit.isEmpty) continue;

      final area = _areaFit(c, address);
      if (!area.ok) continue;

      matches.add(
        ContractorMatch(
          contractor: c,
          score: _score(
            matchedTrades: tradeHit,
            needed: needed,
            areaSpecific: area.specific,
            areaFallback: area.fallback,
          ),
          matchedTrades: tradeHit,
          areaSpecificMatch: area.specific,
          areaFallback: area.fallback,
        ),
      );
    }

    matches.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      // Prefer specific-area over national when scores tie.
      if (a.areaSpecificMatch != b.areaSpecificMatch) {
        return a.areaSpecificMatch ? -1 : 1;
      }
      return a.contractor.displayName.toLowerCase().compareTo(
        b.contractor.displayName.toLowerCase(),
      );
    });

    return matches;
  }

  /// Infer trade tags from a report's highest-priority findings.
  static Set<String> tradesFromReport(
    AnalysisReport report, {
    int topFindingLimit = defaultTopFindingLimit,
  }) {
    final issues = report.issuesByPriority;
    if (issues.isEmpty) return {};

    final limit = topFindingLimit <= 0
        ? issues.length
        : topFindingLimit.clamp(1, issues.length);
    final out = <String>{};
    for (final issue in issues.take(limit)) {
      final trade = tradeFromFinding(issue);
      if (trade != null) out.add(trade);
    }
    return out;
  }

  /// Map one finding to a primary trade tag, or null if unknown.
  static String? tradeFromFinding(AnalysisIssue issue) {
    final key = '${issue.title} ${issue.location} ${issue.insight}'
        .toLowerCase();
    if (key.contains('roof') ||
        key.contains('shingle') ||
        key.contains('ridge') ||
        key.contains('underlayment') ||
        key.contains('flashing') ||
        key.contains('chimney')) {
      return ContractorTrade.roofing;
    }
    if (key.contains('gutter') ||
        key.contains('downspout') ||
        key.contains('eave') ||
        key.contains('drainage')) {
      return ContractorTrade.gutters;
    }
    if (key.contains('foundation') ||
        key.contains('settlement') ||
        key.contains('grade line') ||
        (key.contains('crack') &&
            (key.contains('base') ||
                key.contains('masonry') ||
                key.contains('concrete')))) {
      return ContractorTrade.foundation;
    }
    if (key.contains('window') ||
        key.contains('caulk') ||
        key.contains('glazing')) {
      return ContractorTrade.windows;
    }
    if (key.contains('fascia') ||
        key.contains('soffit') ||
        key.contains('trim rot')) {
      return ContractorTrade.fascia;
    }
    if (key.contains('paint') ||
        key.contains('peel') ||
        key.contains('coating') ||
        key.contains('blister')) {
      return ContractorTrade.paint;
    }
    if (key.contains('siding') ||
        key.contains('cladding') ||
        key.contains('vinyl') ||
        key.contains('fiber cement') ||
        key.contains('mismatched') ||
        key.contains('patched siding') ||
        key.contains('wiring') ||
        key.contains('cable clutter')) {
      return ContractorTrade.siding;
    }
    // Soft wall/exterior without a clearer system → siding bucket.
    if (key.contains('wall') && key.contains('exterior')) {
      return ContractorTrade.siding;
    }
    return null;
  }

  /// Severity weight used when scoring trade hits (High > Medium > Low).
  static int severityWeight(String severity) {
    switch (severity) {
      case 'High':
        return 3;
      case 'Medium':
        return 2;
      default:
        return 1;
    }
  }

  // ── internals ────────────────────────────────────────────────────────────

  static Set<String> _tradeOverlap(Set<String> contractor, Set<String> needed) {
    if (contractor.isEmpty || needed.isEmpty) return {};
    final hit = contractor.intersection(needed);
    if (hit.isNotEmpty) return hit;
    // Generalists cover any finding set when no specialty tag matched.
    if (contractor.contains(ContractorTrade.general)) {
      return {ContractorTrade.general};
    }
    return {};
  }

  static ({bool ok, bool specific, bool fallback}) _areaFit(
    Contractor c,
    String propertyAddress,
  ) {
    if (c.isOpenServiceArea) {
      return (ok: true, specific: false, fallback: true);
    }
    // Specific areas need something to match against.
    if (propertyAddress.trim().isEmpty) {
      return (ok: false, specific: false, fallback: false);
    }
    final specific = serviceAreaOverlapsAddress(
      serviceAreas: c.serviceAreas,
      propertyAddress: propertyAddress,
    );
    return (ok: specific, specific: specific, fallback: false);
  }

  /// Token / substring overlap between service areas and a property address.
  ///
  /// ZIP: 5-digit codes match as whole tokens. City / metro strings match if
  /// either side contains the other (after lowercasing). Short tokens (< 3
  /// chars) are ignored except pure digits of length ≥ 5 (ZIP).
  static bool serviceAreaOverlapsAddress({
    required List<String> serviceAreas,
    required String propertyAddress,
  }) {
    final addressNorm = _normalizeAreaText(propertyAddress);
    if (addressNorm.isEmpty) return false;

    final addressTokens = _tokens(addressNorm);
    final addressZips = addressTokens.where(_isZip).toSet();

    for (final raw in serviceAreas) {
      final area = _normalizeAreaText(raw);
      if (area.isEmpty) continue;

      // Full-string containment either direction (city inside full address).
      if (addressNorm.contains(area) || area.contains(addressNorm)) {
        return true;
      }

      final areaTokens = _tokens(area);
      for (final t in areaTokens) {
        if (_isZip(t) && addressZips.contains(t)) return true;
        if (t.length < 3) continue;
        if (addressNorm.contains(t)) return true;
        // Multi-word area pieces already covered by full-string check.
      }
    }
    return false;
  }

  static int _score({
    required Set<String> matchedTrades,
    required Set<String> needed,
    required bool areaSpecific,
    required bool areaFallback,
  }) {
    // Specialty overlap counts more than a lone "general" match.
    var score = 0;
    for (final t in matchedTrades) {
      if (t == ContractorTrade.general) {
        score += 1;
      } else {
        score += 10;
        // Slight boost when the trade was actually needed.
        if (needed.contains(t)) score += 2;
      }
    }
    if (areaSpecific) {
      score += 20;
    } else if (areaFallback) {
      score += 5;
    }
    return score;
  }

  static String _normalizeAreaText(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static List<String> _tokens(String normalized) {
    if (normalized.isEmpty) return const [];
    return normalized.split(' ').where((t) => t.isNotEmpty).toList();
  }

  static bool _isZip(String token) =>
      RegExp(r'^\d{5}$').hasMatch(token) ||
      RegExp(r'^\d{5}\d{4}$').hasMatch(token);
}

/// Convenience top-level API (same as [ContractorMatching.matchContractors]).
List<ContractorMatch> matchContractors({
  required List<Contractor> contractors,
  required AnalysisReport report,
  String propertyAddress = '',
  int topFindingLimit = ContractorMatching.defaultTopFindingLimit,
}) {
  return ContractorMatching.matchContractors(
    contractors: contractors,
    report: report,
    propertyAddress: propertyAddress,
    topFindingLimit: topFindingLimit,
  );
}
