import 'dart:convert';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'analysis_models.dart';
import 'capture_models.dart';

/// A persisted exterior photo (compressed bytes + checklist label).
class SavedPhoto {
  final int index;
  final String label;
  final CaptureShotId? slotId;
  final Uint8List bytes;

  const SavedPhoto({
    required this.index,
    required this.label,
    required this.bytes,
    this.slotId,
  });

  CapturePhoto toCapturePhoto() {
    return CapturePhoto(
      file: XFile.fromData(
        bytes,
        name: 'photo_$index.jpg',
        mimeType: 'image/jpeg',
      ),
      label: label,
      index: index,
      slotId: slotId,
    );
  }

  factory SavedPhoto.fromJson(Map<String, dynamic> json) {
    final b64 = json['bytesB64'] as String? ?? '';
    return SavedPhoto(
      index: (json['index'] as num?)?.round() ?? 0,
      label: json['label'] as String? ?? 'Photo',
      slotId: _slotFromName(json['slotId'] as String?),
      bytes: b64.isEmpty ? Uint8List(0) : base64Decode(b64),
    );
  }

  /// Metadata only — photo bytes live in [LocalBlobStore].
  Map<String, dynamic> toMetaJson() => {
    'index': index,
    'label': label,
    'slotId': slotId?.name,
  };

  /// Legacy full JSON (inline base64). Prefer [toMetaJson] + blob store.
  Map<String, dynamic> toJson() => {
    ...toMetaJson(),
    if (bytes.isNotEmpty) 'bytesB64': base64Encode(bytes),
  };

  SavedPhoto copyWithBytes(Uint8List next) =>
      SavedPhoto(index: index, label: label, slotId: slotId, bytes: next);

  static CaptureShotId? _slotFromName(String? name) {
    if (name == null || name.isEmpty) return null;
    for (final v in CaptureShotId.values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

/// A saved homeowner assessment with report + photos.
class SavedReport {
  final String id;
  final DateTime createdAt;
  final AnalysisReport report;
  final List<SavedPhoto> photos;

  const SavedReport({
    required this.id,
    required this.createdAt,
    required this.report,
    required this.photos,
  });

  int get score => report.overallScore;
  int get findingsCount => report.issues.length;
  int get photoCount => photos.isNotEmpty ? photos.length : report.photoCount;

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

  List<CapturePhoto> toCapturePhotos() =>
      photos.map((p) => p.toCapturePhoto()).toList();

  factory SavedReport.fromJson(Map<String, dynamic> json) {
    final rawPhotos = json['photos'] as List<dynamic>? ?? const [];
    return SavedReport(
      id: json['id'] as String? ?? 'report_unknown',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      report: AnalysisReport.fromJson(
        (json['report'] as Map<String, dynamic>?) ?? const {},
      ),
      photos: rawPhotos
          .map((e) => SavedPhoto.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((p) => p.bytes.isNotEmpty)
          .toList(),
    );
  }

  /// Persistable metadata (no inline photo bytes).
  Map<String, dynamic> toMetaJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'report': report.toJson(),
    'photos': photos.map((p) => p.toMetaJson()).toList(),
    'storage': 'blob_v2',
  };

  /// Full JSON including optional inline bytes (migration / legacy).
  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'report': report.toJson(),
    'photos': photos.map((p) => p.toJson()).toList(),
  };
}
