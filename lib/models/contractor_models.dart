// Invite-only contractor network models (local-first).
//
// Not wired into quote email yet — foundation for matching homeowners to
// local pros by trade + service area.

/// Canonical trade tags used on [Contractor.trades] and matching.
///
/// Prefer these string constants when seeding invitees so matching stays stable.
abstract final class ContractorTrade {
  static const roofing = 'roofing';
  static const siding = 'siding';
  static const gutters = 'gutters';
  static const foundation = 'foundation';
  static const paint = 'paint';
  static const windows = 'windows';
  static const fascia = 'fascia';
  static const general = 'general';

  /// Known invite tags (order is display-friendly, not ranking).
  static const all = <String>[
    roofing,
    siding,
    gutters,
    foundation,
    paint,
    windows,
    fascia,
    general,
  ];

  /// Normalize free-text trade labels to a canonical tag when possible.
  static String normalize(String raw) {
    final t = raw.trim().toLowerCase();
    if (t.isEmpty) return t;
    if (t == roofing ||
        t.contains('roof') ||
        t.contains('shingle') ||
        t == 'roofer') {
      return roofing;
    }
    if (t == siding || t.contains('siding') || t.contains('cladding')) {
      return siding;
    }
    if (t == gutters ||
        t.contains('gutter') ||
        t.contains('downspout') ||
        t.contains('eave')) {
      return gutters;
    }
    if (t == foundation ||
        t.contains('foundation') ||
        t.contains('masonry') ||
        t.contains('structural')) {
      return foundation;
    }
    if (t == paint ||
        t.contains('paint') ||
        t.contains('coating') ||
        t.contains('painter')) {
      return paint;
    }
    if (t == windows ||
        t.contains('window') ||
        t.contains('glazing') ||
        t.contains('seal')) {
      return windows;
    }
    if (t == fascia ||
        t.contains('fascia') ||
        t.contains('soffit') ||
        t.contains('trim')) {
      return fascia;
    }
    if (t == general ||
        t.contains('general') ||
        t.contains('handyman') ||
        t.contains('exterior')) {
      return general;
    }
    return t;
  }
}

/// An invite-only network contractor (stored on-device for now).
class Contractor {
  final String id;
  final String name;

  /// Optional DBA / company line for PDF or future routing emails.
  final String? companyName;

  /// Canonical trade tags (see [ContractorTrade]).
  final List<String> trades;

  /// Cities, ZIPs, metro labels, or free-form areas.
  /// Empty list = national / unrestricted fallback (matches any property).
  final List<String> serviceAreas;

  final String phone;
  final String email;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;

  const Contractor({
    required this.id,
    required this.name,
    this.companyName,
    this.trades = const [],
    this.serviceAreas = const [],
    this.phone = '',
    this.email = '',
    this.notes,
    this.isActive = true,
    required this.createdAt,
  });

  /// Display name: company if set, else person name.
  String get displayName {
    final company = companyName?.trim() ?? '';
    if (company.isNotEmpty) return company;
    return name.trim().isEmpty ? 'Contractor' : name.trim();
  }

  /// Normalized trade set for matching.
  Set<String> get tradeSet =>
      trades.map(ContractorTrade.normalize).where((t) => t.isNotEmpty).toSet();

  /// True when no service area is configured (open / national fallback).
  bool get isOpenServiceArea =>
      serviceAreas.every((a) => a.trim().isEmpty) || serviceAreas.isEmpty;

  factory Contractor.create({
    required String name,
    String? companyName,
    List<String> trades = const [],
    List<String> serviceAreas = const [],
    String phone = '',
    String email = '',
    String? notes,
    bool isActive = true,
    String? id,
    DateTime? createdAt,
  }) {
    final now = createdAt ?? DateTime.now();
    return Contractor(
      id: id ?? 'contractor_${now.millisecondsSinceEpoch}',
      name: name.trim(),
      companyName: _emptyToNull(companyName),
      trades: trades
          .map(ContractorTrade.normalize)
          .where((t) => t.isNotEmpty)
          .toList(),
      serviceAreas: serviceAreas
          .map((a) => a.trim())
          .where((a) => a.isNotEmpty)
          .toList(),
      phone: phone.trim(),
      email: email.trim(),
      notes: _emptyToNull(notes),
      isActive: isActive,
      createdAt: now,
    );
  }

  factory Contractor.fromJson(Map<String, dynamic> json) {
    final rawTrades = json['trades'] as List<dynamic>? ?? const [];
    final rawAreas = json['serviceAreas'] as List<dynamic>? ?? const [];
    return Contractor(
      id: json['id'] as String? ?? 'contractor_unknown',
      name: json['name'] as String? ?? '',
      companyName: _emptyToNull(json['companyName'] as String?),
      trades: rawTrades
          .map((e) => ContractorTrade.normalize('$e'))
          .where((t) => t.isNotEmpty)
          .toList(),
      serviceAreas: rawAreas
          .map((e) => '$e'.trim())
          .where((a) => a.isNotEmpty)
          .toList(),
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      notes: _emptyToNull(json['notes'] as String?),
      isActive: json['isActive'] as bool? ?? true,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'companyName': companyName,
    'trades': trades,
    'serviceAreas': serviceAreas,
    'phone': phone,
    'email': email,
    'notes': notes,
    'isActive': isActive,
    'createdAt': createdAt.toIso8601String(),
  };

  Contractor copyWith({
    String? name,
    String? companyName,
    List<String>? trades,
    List<String>? serviceAreas,
    String? phone,
    String? email,
    String? notes,
    bool? isActive,
    bool clearCompanyName = false,
    bool clearNotes = false,
  }) {
    return Contractor(
      id: id,
      name: name ?? this.name,
      companyName: clearCompanyName ? null : (companyName ?? this.companyName),
      trades: trades ?? this.trades,
      serviceAreas: serviceAreas ?? this.serviceAreas,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      notes: clearNotes ? null : (notes ?? this.notes),
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
    );
  }

  static String? _emptyToNull(String? value) {
    final t = value?.trim() ?? '';
    return t.isEmpty ? null : t;
  }
}

/// One ranked match from [matchContractors] (pure matching layer).
class ContractorMatch {
  final Contractor contractor;

  /// Higher = better fit for this report + property.
  final int score;

  /// Trades that overlapped report findings (or `general` when used).
  final Set<String> matchedTrades;

  /// True when a non-empty service area token hit the property address.
  final bool areaSpecificMatch;

  /// True when contractor has empty service areas (national/fallback).
  final bool areaFallback;

  const ContractorMatch({
    required this.contractor,
    required this.score,
    required this.matchedTrades,
    required this.areaSpecificMatch,
    required this.areaFallback,
  });
}
