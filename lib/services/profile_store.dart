import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight homeowner profile for quote autofill.
class ProfileStore extends ChangeNotifier {
  ProfileStore._();
  static final ProfileStore instance = ProfileStore._();

  static const _nameKey = 'pillar_profile_name';
  static const _phoneKey = 'pillar_profile_phone';
  static const _emailKey = 'pillar_profile_email';
  static const _addressKey = 'pillar_profile_address';

  String name = '';
  String phone = '';
  String email = '';
  String address = '';
  bool _loaded = false;

  bool get isLoaded => _loaded;
  bool get hasAny =>
      name.trim().isNotEmpty ||
      phone.trim().isNotEmpty ||
      email.trim().isNotEmpty;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      name = prefs.getString(_nameKey) ?? '';
      phone = prefs.getString(_phoneKey) ?? '';
      email = prefs.getString(_emailKey) ?? '';
      address = prefs.getString(_addressKey) ?? '';
      _loaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('ProfileStore load failed: $e');
      _loaded = true;
    }
  }

  Future<void> save({
    required String name,
    required String phone,
    required String email,
    required String address,
  }) async {
    this.name = name.trim();
    this.phone = phone.trim();
    this.email = email.trim();
    this.address = address.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_nameKey, this.name);
      await prefs.setString(_phoneKey, this.phone);
      await prefs.setString(_emailKey, this.email);
      await prefs.setString(_addressKey, this.address);
    } catch (e) {
      debugPrint('ProfileStore save failed: $e');
    }
    notifyListeners();
  }
}
