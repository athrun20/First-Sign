import 'package:shared_preferences/shared_preferences.dart';

/// Feature flag for Property Memory v1 dual-write.
///
/// Default **false** — existing scan/report behavior is unchanged until enabled.
class PropertyMemoryFlags {
  PropertyMemoryFlags._();

  static const prefsKey = 'pm_enabled_v1';

  /// Async getter; defaults to false when unset.
  static Future<bool> get isEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefsKey) ?? false;
  }

  /// Test / debug helper to flip the flag.
  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKey, value);
  }
}
