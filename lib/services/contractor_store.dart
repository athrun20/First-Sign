import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/analysis_models.dart';
import '../models/contractor_models.dart';
import 'contractor_matching.dart';

/// Local-first invite-only contractor directory.
///
/// Metadata only (no photo blobs). SharedPreferences JSON list — same spirit
/// as [LeadStore] / [ProfileStore], without network or quote wiring yet.
class ContractorStore extends ChangeNotifier {
  ContractorStore._();
  static final ContractorStore instance = ContractorStore._();

  static const _prefsKey = 'pillar_contractors_v1';

  final List<Contractor> _contractors = [];
  bool _loaded = false;
  bool _loading = false;

  List<Contractor> get contractors => List.unmodifiable(_contractors);
  bool get isLoaded => _loaded;
  bool get isLoading => _loading;
  bool get isEmpty => _contractors.isEmpty;

  List<Contractor> get activeContractors =>
      _contractors.where((c) => c.isActive).toList(growable: false);

  Contractor? byId(String id) {
    for (final c in _contractors) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      _contractors.clear();
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        for (final item in list) {
          try {
            final map = item is Map<String, dynamic>
                ? item
                : Map<String, dynamic>.from(item as Map);
            _contractors.add(Contractor.fromJson(map));
          } catch (e) {
            debugPrint('ContractorStore skip item: $e');
          }
        }
        _contractors.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
      _loaded = true;
    } catch (e) {
      debugPrint('ContractorStore load failed: $e');
      _loaded = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Insert or replace by id (newest-first when newly added).
  Future<void> add(Contractor contractor) async {
    await ensureLoaded();
    final i = _contractors.indexWhere((c) => c.id == contractor.id);
    if (i >= 0) {
      _contractors[i] = contractor;
    } else {
      _contractors.insert(0, contractor);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> update(Contractor contractor) async {
    await ensureLoaded();
    final i = _contractors.indexWhere((c) => c.id == contractor.id);
    if (i < 0) return;
    _contractors[i] = contractor;
    await _persist();
    notifyListeners();
  }

  /// Soft-remove from the invite network (keeps record for audit / re-invite).
  Future<void> deactivate(String id) async {
    await ensureLoaded();
    final i = _contractors.indexWhere((c) => c.id == id);
    if (i < 0) return;
    _contractors[i] = _contractors[i].copyWith(isActive: false);
    await _persist();
    notifyListeners();
  }

  Future<void> reactivate(String id) async {
    await ensureLoaded();
    final i = _contractors.indexWhere((c) => c.id == id);
    if (i < 0) return;
    _contractors[i] = _contractors[i].copyWith(isActive: true);
    await _persist();
    notifyListeners();
  }

  /// Hard delete one invitee.
  Future<void> remove(String id) async {
    await ensureLoaded();
    _contractors.removeWhere((c) => c.id == id);
    await _persist();
    notifyListeners();
  }

  /// Privacy wipe — all invitee records on this device.
  Future<void> clearAll() async {
    await ensureLoaded();
    _contractors.clear();
    await _persist();
    notifyListeners();
  }

  /// Convenience: match active contractors for a report + property address.
  ///
  /// Does not send email or create leads — ranking only.
  Future<List<ContractorMatch>> matchForReport({
    required AnalysisReport report,
    String propertyAddress = '',
    int topFindingLimit = ContractorMatching.defaultTopFindingLimit,
  }) async {
    await ensureLoaded();
    return matchContractors(
      contractors: activeContractors,
      report: report,
      propertyAddress: propertyAddress,
      topFindingLimit: topFindingLimit,
    );
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_contractors.map((c) => c.toJson()).toList());
      await prefs.setString(_prefsKey, encoded);
    } catch (e) {
      debugPrint('ContractorStore persist failed: $e');
    }
  }

  /// Test helper — inject in-memory state without touching prefs.
  @visibleForTesting
  void debugReplaceAll(List<Contractor> list) {
    _contractors
      ..clear()
      ..addAll(list);
    _loaded = true;
    _loading = false;
  }
}
