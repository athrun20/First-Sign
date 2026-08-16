import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide white-label branding for PDF reports and settings.
///
/// Persisted locally so logo + company name survive restarts.
class BrandingStore {
  BrandingStore._();
  static final BrandingStore instance = BrandingStore._();

  static const _nameKey = 'pillar_branding_name';
  static const _logoKey = 'pillar_branding_logo_b64';

  String companyName = 'Atlanta Construction Pros';
  Uint8List? logoBytes;
  bool _loaded = false;

  bool get hasLogo => logoBytes != null && logoBytes!.isNotEmpty;
  bool get isLoaded => _loaded;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      companyName = prefs.getString(_nameKey) ?? 'Atlanta Construction Pros';
      final b64 = prefs.getString(_logoKey);
      if (b64 != null && b64.isNotEmpty) {
        logoBytes = base64Decode(b64);
      }
      _loaded = true;
    } catch (e) {
      debugPrint('BrandingStore load failed: $e');
      _loaded = true;
    }
  }

  Future<void> save({required String companyName, Uint8List? logoBytes}) async {
    this.companyName = companyName.trim().isEmpty
        ? 'Atlanta Construction Pros'
        : companyName.trim();
    this.logoBytes = (logoBytes == null || logoBytes.isEmpty)
        ? null
        : Uint8List.fromList(logoBytes);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_nameKey, this.companyName);
      if (this.logoBytes == null) {
        await prefs.remove(_logoKey);
      } else {
        await prefs.setString(_logoKey, base64Encode(this.logoBytes!));
      }
    } catch (e) {
      debugPrint('BrandingStore save failed: $e');
    }
  }

  Future<void> clearLogo() async {
    logoBytes = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_logoKey);
    } catch (e) {
      debugPrint('BrandingStore clearLogo failed: $e');
    }
  }
}
