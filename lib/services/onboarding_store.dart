import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks first-run welcome / tips completion (local only, no account).
class OnboardingStore extends ChangeNotifier {
  OnboardingStore._();
  static final OnboardingStore instance = OnboardingStore._();

  static const _doneKey = 'pillar_onboarding_v1_done';

  bool _done = false;
  bool _loaded = false;

  bool get isLoaded => _loaded;
  bool get isDone => _done;

  /// Auto-show when the user has not finished onboarding and has no reports yet.
  /// Returning users with saved reports are left alone (home stays fully usable).
  bool shouldAutoShow({required int reportCount}) {
    if (!_loaded) return false;
    if (_done) return false;
    return reportCount == 0;
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _done = prefs.getBool(_doneKey) ?? false;
      _loaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('OnboardingStore load failed: $e');
      _loaded = true;
    }
  }

  Future<void> markDone() async {
    if (_done) return;
    _done = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_doneKey, true);
    } catch (e) {
      debugPrint('OnboardingStore save failed: $e');
    }
    notifyListeners();
  }

  /// Privacy wipe / full local reset.
  Future<void> resetLocal() async {
    _done = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_doneKey);
    } catch (e) {
      debugPrint('OnboardingStore reset failed: $e');
    }
    notifyListeners();
  }
}
