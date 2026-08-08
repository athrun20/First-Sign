import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'image_codec_util.dart';
import 'local_blob_store.dart';
import 'storage_exception.dart';

/// App-wide white-label branding for PDF reports and settings.
///
/// Company name stays in SharedPreferences; logo bytes live in [LocalBlobStore].
class BrandingStore {
  BrandingStore._();
  static final BrandingStore instance = BrandingStore._();

  static const _nameKey = 'pillar_branding_name';
  static const _legacyLogoKey = 'pillar_branding_logo_b64';

  String companyName = 'Atlanta Construction Pros';
  Uint8List? logoBytes;
  bool _loaded = false;

  bool get hasLogo => logoBytes != null && logoBytes!.isNotEmpty;
  bool get isLoaded => _loaded;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      await LocalBlobStore.instance.init();
      final prefs = await SharedPreferences.getInstance();
      companyName = prefs.getString(_nameKey) ?? 'Atlanta Construction Pros';

      logoBytes = await LocalBlobStore.instance.get(
        LocalBlobStore.brandingLogoKey,
      );
      if (logoBytes == null || logoBytes!.isEmpty) {
        // Migrate legacy base64 logo out of prefs.
        final b64 = prefs.getString(_legacyLogoKey);
        if (b64 != null && b64.isNotEmpty) {
          try {
            final bytes = base64Decode(b64);
            await LocalBlobStore.instance.put(
              LocalBlobStore.brandingLogoKey,
              bytes,
            );
            logoBytes = bytes;
            await prefs.remove(_legacyLogoKey);
          } catch (_) {}
        }
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

    Uint8List? nextLogo = logoBytes;
    if (nextLogo != null && nextLogo.isNotEmpty) {
      nextLogo = await ImageCodecUtil.compressForStorage(
        nextLogo,
        maxSide: StorageLimits.maxLogoSide,
        maxBytes: StorageLimits.maxLogoBytes,
      );
    }

    this.logoBytes = (nextLogo == null || nextLogo.isEmpty) ? null : nextLogo;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_nameKey, this.companyName);
      await prefs.remove(_legacyLogoKey);

      if (this.logoBytes == null) {
        await LocalBlobStore.instance.delete(LocalBlobStore.brandingLogoKey);
      } else {
        await LocalBlobStore.instance.put(
          LocalBlobStore.brandingLogoKey,
          this.logoBytes!,
        );
      }
    } on StorageFullException {
      rethrow;
    } catch (e) {
      debugPrint('BrandingStore save failed: $e');
    }
  }

  Future<void> clearLogo() async {
    logoBytes = null;
    try {
      await LocalBlobStore.instance.delete(LocalBlobStore.brandingLogoKey);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_legacyLogoKey);
    } catch (_) {}
  }
}
