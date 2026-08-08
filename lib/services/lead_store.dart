import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/analysis_models.dart';
import '../models/capture_models.dart';
import '../models/lead_models.dart';
import '../models/saved_report.dart';
import 'local_blob_store.dart';
import 'storage_exception.dart';

/// Local-first lead pipeline.
///
/// Lead metadata stays in SharedPreferences; photo bytes live in
/// [LocalBlobStore] (same pattern as reports).
class LeadStore extends ChangeNotifier {
  LeadStore._();
  static final LeadStore instance = LeadStore._();

  static const _prefsKey = 'pillar_ai_leads_meta_v2';
  static const _legacyKey = 'pillar_ai_leads_v1';

  final List<QuoteLead> _leads = [];
  bool _loaded = false;
  bool _loading = false;

  List<QuoteLead> get leads => List.unmodifiable(_leads);
  bool get isLoaded => _loaded;
  bool get isLoading => _loading;

  int countForStatus(String status) {
    if (status == 'All') return _leads.length;
    return _leads.where((l) => l.status == status).length;
  }

  QuoteLead? byId(String id) {
    for (final l in _leads) {
      if (l.id == id) return l;
    }
    return null;
  }

  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      await LocalBlobStore.instance.init();
      final prefs = await SharedPreferences.getInstance();
      await _migrateLegacy(prefs);

      final raw = prefs.getString(_prefsKey);
      _leads.clear();
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        for (final item in list) {
          final map = item is Map<String, dynamic>
              ? item
              : Map<String, dynamic>.from(item as Map);
          final lead = await _hydrateLead(map);
          if (lead != null) _leads.add(lead);
        }
        _leads.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
      _loaded = true;
    } catch (e) {
      debugPrint('LeadStore load failed: $e');
      _loaded = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> add(QuoteLead lead) async {
    await ensureLoaded();

    final photos = lead.photos.take(StorageLimits.maxPhotosPerReport).toList();
    var incoming = 0;
    for (final p in photos) {
      incoming += p.bytes.lengthInBytes;
    }

    final oldest = _leads
        .map((l) => LocalBlobStore.leadPrefix(l.id))
        .toList()
        .reversed
        .toList();

    await LocalBlobStore.instance.ensureCapacity(
      incomingBytes: incoming,
      evictablePrefixesOldestFirst: oldest,
    );

    await LocalBlobStore.instance.deletePrefix(
      LocalBlobStore.leadPrefix(lead.id),
    );
    for (final photo in photos) {
      if (photo.bytes.isEmpty) continue;
      await LocalBlobStore.instance.put(
        LocalBlobStore.leadPhotoKey(lead.id, photo.index),
        photo.bytes,
      );
    }

    final stored = lead.copyWith(photos: photos);
    _leads.insert(0, stored);
    await _persistMeta();
    notifyListeners();
  }

  Future<void> update(QuoteLead lead) async {
    await ensureLoaded();
    final i = _leads.indexWhere((l) => l.id == lead.id);
    if (i < 0) return;
    _leads[i] = lead;
    await _persistMeta();
    notifyListeners();
  }

  Future<void> updateStatus(String id, String status) async {
    final lead = byId(id);
    if (lead == null) return;
    lead.status = status;
    await _persistMeta();
    notifyListeners();
  }

  Future<void> updateContractorNotes(String id, String notes) async {
    final lead = byId(id);
    if (lead == null) return;
    lead.contractorNotes = notes;
    await _persistMeta();
    notifyListeners();
  }

  /// Wipe every lead and lead photo blobs (privacy / reset).
  Future<void> clearAll() async {
    await ensureLoaded();
    for (final lead in List<QuoteLead>.from(_leads)) {
      await LocalBlobStore.instance.deletePrefix(
        LocalBlobStore.leadPrefix(lead.id),
      );
    }
    _leads.clear();
    await _persistMeta();
    notifyListeners();
  }

  Future<QuoteLead?> _hydrateLead(Map<String, dynamic> json) async {
    final id = json['id'] as String? ?? '';
    if (id.isEmpty) return null;
    final rawPhotos = json['photos'] as List<dynamic>? ?? const [];
    final photos = <SavedPhoto>[];
    for (final item in rawPhotos) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final index = (m['index'] as num?)?.round() ?? photos.length;
      var bytes = await LocalBlobStore.instance.get(
        LocalBlobStore.leadPhotoKey(id, index),
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
        SavedPhoto(
          index: index,
          label: m['label'] as String? ?? 'Photo',
          slotId: _slotFromName(m['slotId'] as String?),
          bytes: bytes,
        ),
      );
    }

    return QuoteLead(
      id: id,
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
      photos: photos,
    );
  }

  Future<void> _persistMeta() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_leads.map(_leadMetaJson).toList());
      await prefs.setString(_prefsKey, encoded);
    } catch (e) {
      debugPrint('LeadStore persist failed: $e');
      throw StorageFullException(
        'Could not save lead: $e',
        usedBytes: LocalBlobStore.instance.totalBytes,
        limitBytes: LocalBlobStore.instance.budgetBytes,
      );
    }
  }

  Map<String, dynamic> _leadMetaJson(QuoteLead l) => {
    'id': l.id,
    'name': l.name,
    'phone': l.phone,
    'email': l.email,
    'address': l.address,
    'preferredContact': l.preferredContact,
    'homeownerNotes': l.homeownerNotes,
    'contractorNotes': l.contractorNotes,
    'status': l.status,
    'createdAt': l.createdAt.toIso8601String(),
    'reportSnapshot': l.reportSnapshot.toJson(),
    'savedReportId': l.savedReportId,
    'photos': l.photos.map((p) => p.toMetaJson()).toList(),
    'storage': 'blob_v2',
  };

  Future<void> _migrateLegacy(SharedPreferences prefs) async {
    if (prefs.containsKey(_prefsKey)) return;
    final raw = prefs.getString(_legacyKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final metaList = <Map<String, dynamic>>[];
      for (final item in list) {
        final map = item is Map<String, dynamic>
            ? item
            : Map<String, dynamic>.from(item as Map);
        final lead = QuoteLead.fromJson(map);
        for (final photo in lead.photos) {
          if (photo.bytes.isEmpty) continue;
          await LocalBlobStore.instance.put(
            LocalBlobStore.leadPhotoKey(lead.id, photo.index),
            photo.bytes,
          );
        }
        metaList.add(_leadMetaJson(lead));
      }
      await prefs.setString(_prefsKey, jsonEncode(metaList));
      await prefs.remove(_legacyKey);
      debugPrint('LeadStore migrated ${metaList.length} legacy leads');
    } catch (e) {
      debugPrint('LeadStore migrate failed: $e');
    }
  }

  static CaptureShotId? _slotFromName(String? name) {
    if (name == null || name.isEmpty) return null;
    for (final v in CaptureShotId.values) {
      if (v.name == name) return v;
    }
    return null;
  }
}
