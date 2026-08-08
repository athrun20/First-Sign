import 'analysis_models.dart';
import 'saved_report.dart';

/// Pipeline statuses for contractor leads.
abstract final class LeadStatus {
  static const newLead = 'New';
  static const contacted = 'Contacted';
  static const quoted = 'Quoted';
  static const won = 'Won';

  static const all = [newLead, contacted, quoted, won];
}

/// Preferred contact windows offered on the quote form.
abstract final class ContactWindows {
  static const all = [
    'Anytime',
    'Morning (8am–12pm)',
    'Afternoon (12pm–5pm)',
    'Evening (5pm–8pm)',
  ];
}

/// A homeowner quote request with an attached report snapshot + photos.
class QuoteLead {
  final String id;
  String name;
  String phone;
  String email;
  String address;
  String preferredContact;

  /// Notes the homeowner left on the form.
  String homeownerNotes;

  /// Private contractor notes.
  String contractorNotes;
  String status;
  final DateTime createdAt;
  final AnalysisReport reportSnapshot;

  /// Optional link back to homeowner saved report.
  final String? savedReportId;

  /// Compressed photos for contractor follow-up.
  final List<SavedPhoto> photos;

  QuoteLead({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.address,
    required this.preferredContact,
    required this.homeownerNotes,
    required this.contractorNotes,
    required this.status,
    required this.createdAt,
    required this.reportSnapshot,
    this.savedReportId,
    this.photos = const [],
  });

  factory QuoteLead.fromReport({
    required String name,
    required String phone,
    required String email,
    required String address,
    required String preferredContact,
    required String homeownerNotes,
    required AnalysisReport report,
    String? savedReportId,
    List<SavedPhoto> photos = const [],
  }) {
    final now = DateTime.now();
    return QuoteLead(
      id: 'lead_${now.millisecondsSinceEpoch}',
      name: name.trim(),
      phone: phone.trim(),
      email: email.trim(),
      address: address.trim(),
      preferredContact: preferredContact,
      homeownerNotes: homeownerNotes.trim(),
      contractorNotes: '',
      status: LeadStatus.newLead,
      createdAt: now,
      reportSnapshot: report,
      savedReportId: savedReportId,
      photos: photos,
    );
  }

  int get photoCount =>
      photos.isNotEmpty ? photos.length : reportSnapshot.photoCount;
  int get overallScore => reportSnapshot.overallScore;
  String get estimatedRepairRange => reportSnapshot.estimatedRepairRange;
  int get findingsCount => reportSnapshot.issues.length;
  int get highCount => reportSnapshot.highCount;
  bool get hasPhotos => photos.isNotEmpty;

  String get relativeDateLabel {
    final now = DateTime.now();
    final diff = now.difference(createdAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) {
      return diff.inHours == 1 ? '1 hour ago' : '${diff.inHours} hours ago';
    }
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    final m = createdAt.month.toString().padLeft(2, '0');
    final d = createdAt.day.toString().padLeft(2, '0');
    return '${createdAt.year}-$m-$d';
  }

  String get severitySummary {
    final h = reportSnapshot.highCount;
    final m = reportSnapshot.mediumCount;
    final l = reportSnapshot.lowCount;
    final parts = <String>[];
    if (h > 0) parts.add('$h high');
    if (m > 0) parts.add('$m medium');
    if (l > 0) parts.add('$l low');
    if (parts.isEmpty) return 'No findings';
    return parts.join(' · ');
  }

  factory QuoteLead.fromJson(Map<String, dynamic> json) {
    final rawPhotos = json['photos'] as List<dynamic>? ?? const [];
    return QuoteLead(
      id: json['id'] as String? ?? 'lead_unknown',
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      address: json['address'] as String? ?? '',
      preferredContact: json['preferredContact'] as String? ?? 'Anytime',
      homeownerNotes: json['homeownerNotes'] as String? ?? '',
      contractorNotes: json['contractorNotes'] as String? ?? '',
      status: json['status'] as String? ?? LeadStatus.newLead,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      reportSnapshot: AnalysisReport.fromJson(
        (json['reportSnapshot'] as Map<String, dynamic>?) ?? const {},
      ),
      savedReportId: json['savedReportId'] as String?,
      photos: rawPhotos
          .map((e) => SavedPhoto.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((p) => p.bytes.isNotEmpty)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'email': email,
    'address': address,
    'preferredContact': preferredContact,
    'homeownerNotes': homeownerNotes,
    'contractorNotes': contractorNotes,
    'status': status,
    'createdAt': createdAt.toIso8601String(),
    'reportSnapshot': reportSnapshot.toJson(),
    'savedReportId': savedReportId,
    'photos': photos.map((p) => p.toJson()).toList(),
  };

  QuoteLead copyWith({
    String? name,
    String? phone,
    String? email,
    String? address,
    String? preferredContact,
    String? homeownerNotes,
    String? contractorNotes,
    String? status,
    List<SavedPhoto>? photos,
  }) {
    return QuoteLead(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      preferredContact: preferredContact ?? this.preferredContact,
      homeownerNotes: homeownerNotes ?? this.homeownerNotes,
      contractorNotes: contractorNotes ?? this.contractorNotes,
      status: status ?? this.status,
      createdAt: createdAt,
      reportSnapshot: reportSnapshot,
      savedReportId: savedReportId,
      photos: photos ?? this.photos,
    );
  }
}
