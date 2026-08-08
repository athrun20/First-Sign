import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/analysis_models.dart';
import '../models/capture_models.dart';
import '../models/saved_report.dart';
import 'image_codec_util.dart';
import 'local_blob_store.dart';
import 'storage_exception.dart';

/// Local-first homeowner report history.
///
/// Analysis JSON stays in SharedPreferences (small). Photo bytes live in
/// [LocalBlobStore] so web localStorage is not flooded with base64.
class ReportStore extends ChangeNotifier {
  ReportStore._();
  static final ReportStore instance = ReportStore._();

  static const _idsKey = 'pillar_report_ids_v2';
  static const _metaPrefix = 'pillar_report_meta_v2_';
  // Legacy keys (v1 stored full report + base64 photos in prefs).
  static const _legacyIdsKey = 'pillar_report_ids_v1';
  static const _legacyPrefix = 'pillar_report_v1_';

  final List<SavedReport> _reports = [];
  bool _loaded = false;
  bool _loading = false;

  List<SavedReport> get reports => List.unmodifiable(_reports);
  bool get isLoaded => _loaded;
  bool get isEmpty => _reports.isEmpty;

  int get maxReports => StorageLimits.maxReports(isWeb: kIsWeb);

  SavedReport? byId(String id) {
    for (final r in _reports) {
      if (r.id == id) return r;
    }
    return null;
  }

  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      await LocalBlobStore.instance.init();
      final prefs = await SharedPreferences.getInstance();
      await _migrateLegacyIfNeeded(prefs);

      final ids = prefs.getStringList(_idsKey) ?? const <String>[];
      _reports.clear();
      for (final id in ids) {
        final raw = prefs.getString('$_metaPrefix$id');
        if (raw == null || raw.isEmpty) continue;
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          final hydrated = await _hydrateFromMeta(map);
          if (hydrated != null) _reports.add(hydrated);
        } catch (e) {
          debugPrint('ReportStore skip $id: $e');
        }
      }
      _reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _loaded = true;
    } catch (e) {
      debugPrint('ReportStore load failed: $e');
      _loaded = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Save a new assessment from live capture + analysis.
  Future<SavedReport> saveFromCapture({
    required AnalysisReport report,
    required List<CapturePhoto> photos,
    String? id,
  }) async {
    await ensureLoaded();
    final now = DateTime.now();
    final reportId = id ?? 'report_${now.millisecondsSinceEpoch}';
    final blobs = LocalBlobStore.instance;

    final limited = photos.take(StorageLimits.maxPhotosPerReport).toList();
    final savedPhotos = <SavedPhoto>[];
    var incoming = 0;

    for (final p in limited) {
      try {
        final raw = await p.file.readAsBytes();
        final compressed = await ImageCodecUtil.compressForStorage(raw);
        if (compressed.isEmpty) continue;
        savedPhotos.add(
          SavedPhoto(
            index: p.index,
            label: p.label,
            slotId: p.slotId,
            bytes: compressed,
          ),
        );
        incoming += compressed.lengthInBytes;
      } catch (e) {
        debugPrint('ReportStore photo skip: $e');
      }
    }

    // Evict oldest reports' blobs first if over budget.
    final oldestPrefixes = _reports
        .where((r) => r.id != reportId)
        .toList()
        .reversed
        .map((r) => LocalBlobStore.reportPrefix(r.id))
        .toList();

    await blobs.ensureCapacity(
      incomingBytes: incoming,
      evictablePrefixesOldestFirst: oldestPrefixes,
    );

    // Replace any existing blobs for this id, then write photos.
    await blobs.deletePrefix(LocalBlobStore.reportPrefix(reportId));
    for (final photo in savedPhotos) {
      await blobs.put(
        LocalBlobStore.reportPhotoKey(reportId, photo.index),
        photo.bytes,
      );
    }

    final saved = SavedReport(
      id: reportId,
      createdAt: now,
      report: report,
      photos: savedPhotos,
    );

    _reports.removeWhere((r) => r.id == reportId);
    _reports.insert(0, saved);

    // Cap history (metadata + blobs).
    while (_reports.length > maxReports) {
      final dropped = _reports.removeLast();
      await _deleteFully(dropped.id);
    }

    // If eviction deleted blob prefixes for still-listed reports, drop those
    // reports from the list when their photos vanished entirely.
    await _dropOrphanedAfterEviction();

    await _persistMeta(saved);
    await _persistIds();
    notifyListeners();
    return saved;
  }

  Future<void> delete(String id) async {
    await ensureLoaded();
    _reports.removeWhere((r) => r.id == id);
    await _deleteFully(id);
    await _persistIds();
    notifyListeners();
  }

  /// Wipe every saved report and its photo blobs (privacy / reset).
  Future<void> clearAll() async {
    await ensureLoaded();
    final ids = _reports.map((r) => r.id).toList();
    for (final id in ids) {
      await _deleteFully(id);
    }
    _reports.clear();
    await _persistIds();
    notifyListeners();
  }

  Future<void> _dropOrphanedAfterEviction() async {
    final blobs = LocalBlobStore.instance;
    final doomed = <String>[];
    for (final r in _reports) {
      if (r.photos.isEmpty) continue;
      final keys = blobs.keysWithPrefix(LocalBlobStore.reportPrefix(r.id));
      if (keys.isEmpty) doomed.add(r.id);
    }
    for (final id in doomed) {
      _reports.removeWhere((r) => r.id == id);
      await _deleteMetaOnly(id);
    }
  }

  Future<SavedReport?> _hydrateFromMeta(Map<String, dynamic> map) async {
    final id = map['id'] as String? ?? '';
    if (id.isEmpty) return null;
    final report = AnalysisReport.fromJson(
      (map['report'] as Map<String, dynamic>?) ?? const {},
    );
    final createdAt =
        DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now();
    final rawPhotos = map['photos'] as List<dynamic>? ?? const [];
    final photos = <SavedPhoto>[];

    for (final item in rawPhotos) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final index = (m['index'] as num?)?.round() ?? photos.length;
      final label = m['label'] as String? ?? 'Photo';
      final slot = _slotFromName(m['slotId'] as String?);
      // Prefer blob store; fall back to legacy inline base64.
      var bytes = await LocalBlobStore.instance.get(
        LocalBlobStore.reportPhotoKey(id, index),
      );
      if (bytes == null || bytes.isEmpty) {
        final b64 = m['bytesB64'] as String? ?? '';
        if (b64.isNotEmpty) {
          try {
            bytes = base64Decode(b64);
          } catch (_) {
            bytes = null;
          }
        }
      }
      if (bytes == null || bytes.isEmpty) continue;
      photos.add(
        SavedPhoto(index: index, label: label, slotId: slot, bytes: bytes),
      );
    }

    return SavedReport(
      id: id,
      createdAt: createdAt,
      report: report,
      photos: photos,
    );
  }

  Future<void> _migrateLegacyIfNeeded(SharedPreferences prefs) async {
    final already = prefs.getStringList(_idsKey);
    if (already != null && already.isNotEmpty) return;

    final legacyIds = prefs.getStringList(_legacyIdsKey);
    if (legacyIds == null || legacyIds.isEmpty) return;

    debugPrint('ReportStore migrating ${legacyIds.length} legacy reports…');
    final migratedIds = <String>[];

    for (final id in legacyIds) {
      final raw = prefs.getString('$_legacyPrefix$id');
      if (raw == null || raw.isEmpty) continue;
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final legacy = SavedReport.fromJson(map);
        // Write photos to blob store.
        for (final photo in legacy.photos) {
          if (photo.bytes.isEmpty) continue;
          await LocalBlobStore.instance.put(
            LocalBlobStore.reportPhotoKey(legacy.id, photo.index),
            photo.bytes,
          );
        }
        await prefs.setString(
          '$_metaPrefix${legacy.id}',
          jsonEncode(legacy.toMetaJson()),
        );
        migratedIds.add(legacy.id);
        await prefs.remove('$_legacyPrefix$id');
      } catch (e) {
        debugPrint('ReportStore migrate skip $id: $e');
      }
    }

    if (migratedIds.isNotEmpty) {
      await prefs.setStringList(_idsKey, migratedIds);
    }
    await prefs.remove(_legacyIdsKey);
  }

  Future<void> _persistMeta(SavedReport report) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_metaPrefix${report.id}',
        jsonEncode(report.toMetaJson()),
      );
    } catch (e) {
      debugPrint('ReportStore persist meta failed: $e');
      throw StorageFullException(
        'Could not save report metadata: $e',
        usedBytes: LocalBlobStore.instance.totalBytes,
        limitBytes: LocalBlobStore.instance.budgetBytes,
      );
    }
  }

  Future<void> _persistIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_idsKey, _reports.map((r) => r.id).toList());
  }

  Future<void> _deleteFully(String id) async {
    await LocalBlobStore.instance.deletePrefix(LocalBlobStore.reportPrefix(id));
    await _deleteMetaOnly(id);
  }

  Future<void> _deleteMetaOnly(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_metaPrefix$id');
    // Clean legacy key if present.
    await prefs.remove('$_legacyPrefix$id');
  }

  static CaptureShotId? _slotFromName(String? name) {
    if (name == null || name.isEmpty) return null;
    for (final v in CaptureShotId.values) {
      if (v.name == name) return v;
    }
    return null;
  }
}
