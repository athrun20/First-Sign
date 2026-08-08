import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'storage_exception.dart';

/// Cross-platform binary store for photos / logos (Hive → IndexedDB on web).
///
/// Keeps large base64 blobs **out** of SharedPreferences / localStorage.
class LocalBlobStore {
  LocalBlobStore._();
  static final LocalBlobStore instance = LocalBlobStore._();

  static const _boxName = 'pillar_blobs_v2';

  Box<dynamic>? _box;
  bool _ready = false;

  bool get isReady => _ready;

  Future<void> init() async {
    if (_ready) return;
    try {
      await Hive.initFlutter();
    } catch (_) {
      // Unit tests / hosts without path_provider — use a local directory.
      Hive.init('.dart_tool/pillar_hive');
    }
    _box = await Hive.openBox<dynamic>(_boxName);
    _ready = true;
  }

  Box<dynamic> get _b {
    final box = _box;
    if (box == null || !box.isOpen) {
      throw StateError('LocalBlobStore not initialized. Call init() first.');
    }
    return box;
  }

  Future<void> put(String key, Uint8List bytes) async {
    await init();
    await _b.put(key, bytes);
  }

  Future<Uint8List?> get(String key) async {
    await init();
    final v = _b.get(key);
    if (v == null) return null;
    if (v is Uint8List) return v;
    if (v is List<int>) return Uint8List.fromList(v);
    return null;
  }

  Future<void> delete(String key) async {
    await init();
    await _b.delete(key);
  }

  Future<void> deleteKeys(Iterable<String> keys) async {
    await init();
    await _b.deleteAll(keys);
  }

  Future<void> deletePrefix(String prefix) async {
    await init();
    final keys = _b.keys
        .whereType<String>()
        .where((k) => k.startsWith(prefix))
        .toList();
    if (keys.isNotEmpty) await _b.deleteAll(keys);
  }

  /// Delete every blob in the box (privacy wipe).
  Future<void> clearAll() async {
    await init();
    await _b.clear();
  }

  List<String> keysWithPrefix(String prefix) {
    if (!_ready) return const [];
    return _b.keys
        .whereType<String>()
        .where((k) => k.startsWith(prefix))
        .toList();
  }

  int bytesForKey(String key) {
    if (!_ready) return 0;
    final v = _b.get(key);
    if (v is Uint8List) return v.lengthInBytes;
    if (v is List) return v.length;
    return 0;
  }

  int get totalBytes {
    if (!_ready) return 0;
    var sum = 0;
    for (final k in _b.keys) {
      sum += bytesForKey(k as String);
    }
    return sum;
  }

  int get budgetBytes => StorageLimits.blobBudgetBytes(isWeb: kIsWeb);

  double get usageRatio {
    final b = budgetBytes;
    if (b <= 0) return 0;
    return (totalBytes / b).clamp(0.0, 2.0);
  }

  /// Ensures [incomingBytes] fit under the soft budget by deleting oldest
  /// report photo prefixes when needed. [evictablePrefixes] oldest-first.
  Future<void> ensureCapacity({
    required int incomingBytes,
    required List<String> evictablePrefixesOldestFirst,
  }) async {
    await init();
    final limit = budgetBytes;
    var used = totalBytes;
    if (used + incomingBytes <= limit) return;

    for (final prefix in evictablePrefixesOldestFirst) {
      if (used + incomingBytes <= limit) break;
      final keys = keysWithPrefix(prefix);
      if (keys.isEmpty) continue;
      var freed = 0;
      for (final k in keys) {
        freed += bytesForKey(k);
      }
      await deletePrefix(prefix);
      used = (used - freed).clamp(0, used);
      debugPrint('LocalBlobStore evicted $prefix (~$freed bytes)');
    }

    if (totalBytes + incomingBytes > limit) {
      throw StorageFullException(
        'Blob budget exceeded',
        usedBytes: totalBytes + incomingBytes,
        limitBytes: limit,
      );
    }
  }

  // ── Key helpers ──────────────────────────────────────────────────────────

  static String reportPhotoKey(String reportId, int index) =>
      'report/$reportId/p$index';

  static String reportPrefix(String reportId) => 'report/$reportId/';

  static String draftPhotoKey(int index) => 'draft/p$index';

  static String draftPrefix() => 'draft/';

  static String leadPhotoKey(String leadId, int index) =>
      'lead/$leadId/p$index';

  static String leadPrefix(String leadId) => 'lead/$leadId/';

  static const brandingLogoKey = 'branding/logo';
}
