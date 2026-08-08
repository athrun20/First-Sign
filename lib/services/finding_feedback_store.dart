import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local-only homeowner feedback on findings ("Looks wrong").
///
/// Used to calibrate accuracy over time — no network upload.
class FindingFeedbackStore extends ChangeNotifier {
  FindingFeedbackStore._();
  static final FindingFeedbackStore instance = FindingFeedbackStore._();

  static const _prefsKey = 'pillar_finding_feedback_v1';

  final Map<String, String> _flags = {}; // key → 'wrong' | 'helpful'
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      _flags.clear();
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        for (final e in map.entries) {
          _flags[e.key] = e.value.toString();
        }
      }
      _loaded = true;
    } catch (e) {
      debugPrint('FindingFeedbackStore load failed: $e');
      _loaded = true;
    }
  }

  String _key({
    required String? reportId,
    required String title,
    required String location,
  }) {
    final rid = (reportId ?? 'live').trim();
    return '$rid|${title.trim().toLowerCase()}|${location.trim().toLowerCase()}';
  }

  bool isMarkedWrong({
    required String? reportId,
    required String title,
    required String location,
  }) {
    return _flags[_key(reportId: reportId, title: title, location: location)] ==
        'wrong';
  }

  Future<void> markWrong({
    required String? reportId,
    required String title,
    required String location,
  }) async {
    await ensureLoaded();
    final k = _key(reportId: reportId, title: title, location: location);
    _flags[k] = 'wrong';
    await _persist();
    notifyListeners();
  }

  Future<void> clearFlag({
    required String? reportId,
    required String title,
    required String location,
  }) async {
    await ensureLoaded();
    final k = _key(reportId: reportId, title: title, location: location);
    _flags.remove(k);
    await _persist();
    notifyListeners();
  }

  Future<void> clearAll() async {
    await ensureLoaded();
    _flags.clear();
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_flags));
    } catch (e) {
      debugPrint('FindingFeedbackStore save failed: $e');
    }
  }
}
