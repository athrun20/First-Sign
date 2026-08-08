import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/capture_models.dart';
import 'image_codec_util.dart';
import 'local_blob_store.dart';
import 'report_store.dart';
import 'storage_exception.dart';

/// In-progress guided capture so users can resume after leaving the flow.
///
/// Photo bytes → [LocalBlobStore]; checklist metadata → SharedPreferences.
class CaptureDraftStore extends ChangeNotifier {
  CaptureDraftStore._();
  static final CaptureDraftStore instance = CaptureDraftStore._();

  static const _metaKey = 'pillar_capture_draft_meta_v2';
  static const _legacyKey = 'pillar_capture_draft_v1';

  List<CapturePhoto> _photos = [];
  CaptureShotId? _focusSlot;
  DateTime? _updatedAt;
  bool _loaded = false;

  List<CapturePhoto> get photos => List.unmodifiable(_photos);
  CaptureShotId? get focusSlot => _focusSlot;
  DateTime? get updatedAt => _updatedAt;
  bool get isLoaded => _loaded;
  bool get hasDraft => _photos.isNotEmpty;

  int get filledCount => _photos.length;

  String get relativeLabel {
    final t = _updatedAt;
    if (t == null) return '';
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      await LocalBlobStore.instance.init();
      final prefs = await SharedPreferences.getInstance();
      await _migrateLegacy(prefs);

      final raw = prefs.getString(_metaKey);
      if (raw == null || raw.isEmpty) {
        _loaded = true;
        return;
      }
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _updatedAt = DateTime.tryParse(map['updatedAt'] as String? ?? '');
      _focusSlot = _slotFromName(map['focusSlot'] as String?);
      final list = map['photos'] as List<dynamic>? ?? const [];
      _photos = [];
      for (final item in list) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final index = (m['index'] as num?)?.round() ?? _photos.length;
        final label = m['label'] as String? ?? 'Photo ${index + 1}';
        final slot = _slotFromName(m['slotId'] as String?);
        final bytes = await LocalBlobStore.instance.get(
          LocalBlobStore.draftPhotoKey(index),
        );
        if (bytes == null || bytes.isEmpty) continue;
        _photos.add(
          CapturePhoto(
            file: XFile.fromData(
              bytes,
              name: 'draft_$index.jpg',
              mimeType: 'image/jpeg',
            ),
            label: label,
            index: index,
            slotId: slot,
          ),
        );
      }
    } catch (e) {
      debugPrint('CaptureDraftStore load failed: $e');
      _photos = [];
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  /// Persist current checklist photos (compressed into blob store).
  Future<void> saveDraft({
    required List<CapturePhoto> photos,
    CaptureShotId? focusSlot,
  }) async {
    _photos = List.of(photos);
    _focusSlot = focusSlot;
    _updatedAt = DateTime.now();

    try {
      await LocalBlobStore.instance.init();
      final limited = photos.take(StorageLimits.maxPhotosPerReport).toList();
      final encoded = <Map<String, dynamic>>[];
      final compressedList = <({int index, Uint8List bytes})>[];
      var incoming = 0;

      for (final p in limited) {
        try {
          final raw = await p.file.readAsBytes();
          final compressed = await ImageCodecUtil.compressForStorage(
            raw,
            maxSide: StorageLimits.maxDraftPhotoSide(isWeb: kIsWeb),
            maxBytes: StorageLimits.maxDraftPhotoBytes(isWeb: kIsWeb),
          );
          if (compressed.isEmpty) continue;
          compressedList.add((index: p.index, bytes: compressed));
          incoming += compressed.lengthInBytes;
          encoded.add({
            'index': p.index,
            'label': p.label,
            'slotId': p.slotId?.name,
          });
        } catch (e) {
          debugPrint('CaptureDraftStore skip photo: $e');
        }
      }

      if (encoded.isEmpty) {
        await clear();
        return;
      }

      final oldestReportPrefixes = ReportStore.instance.reports.reversed
          .map((r) => LocalBlobStore.reportPrefix(r.id))
          .toList();

      await LocalBlobStore.instance.ensureCapacity(
        incomingBytes: incoming,
        evictablePrefixesOldestFirst: oldestReportPrefixes,
      );

      await LocalBlobStore.instance.deletePrefix(LocalBlobStore.draftPrefix());
      for (final item in compressedList) {
        await LocalBlobStore.instance.put(
          LocalBlobStore.draftPhotoKey(item.index),
          item.bytes,
        );
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _metaKey,
        jsonEncode({
          'updatedAt': _updatedAt!.toIso8601String(),
          'focusSlot': focusSlot?.name,
          'photos': encoded,
        }),
      );
    } on StorageFullException {
      rethrow;
    } catch (e) {
      debugPrint('CaptureDraftStore save failed: $e');
    }
    notifyListeners();
  }

  Future<void> clear() async {
    _photos = [];
    _focusSlot = null;
    _updatedAt = null;
    try {
      await LocalBlobStore.instance.deletePrefix(LocalBlobStore.draftPrefix());
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_metaKey);
      await prefs.remove(_legacyKey);
    } catch (e) {
      debugPrint('CaptureDraftStore clear failed: $e');
    }
    notifyListeners();
  }

  Future<void> _migrateLegacy(SharedPreferences prefs) async {
    final raw = prefs.getString(_legacyKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final list = map['photos'] as List<dynamic>? ?? const [];
      final metaPhotos = <Map<String, dynamic>>[];
      for (final item in list) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final b64 = m['bytesB64'] as String? ?? '';
        if (b64.isEmpty) continue;
        final index = (m['index'] as num?)?.round() ?? metaPhotos.length;
        final bytes = base64Decode(b64);
        await LocalBlobStore.instance.put(
          LocalBlobStore.draftPhotoKey(index),
          bytes,
        );
        metaPhotos.add({
          'index': index,
          'label': m['label'],
          'slotId': m['slotId'],
        });
      }
      if (metaPhotos.isNotEmpty) {
        await prefs.setString(
          _metaKey,
          jsonEncode({
            'updatedAt': map['updatedAt'],
            'focusSlot': map['focusSlot'],
            'photos': metaPhotos,
          }),
        );
      }
      await prefs.remove(_legacyKey);
      debugPrint('CaptureDraftStore migrated legacy draft');
    } catch (e) {
      debugPrint('CaptureDraftStore migrate failed: $e');
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
