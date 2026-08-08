import 'package:flutter/material.dart';

import 'app_lux.dart';

/// Compatibility aliases for [AppLux].
///
/// Prefer [AppLux] in new code. This file remains so older imports and
/// analysis-server caches do not break after the theme consolidation.
@Deprecated('Use AppLux instead')
abstract final class AppColors {
  static const background = AppLux.bg;
  static const primary = AppLux.charcoal;
  static const accent = AppLux.teal;
  static const secondary = AppLux.border;
  static const success = AppLux.teal;
  static const warning = AppLux.warning;
  static const danger = AppLux.danger;

  static const textPrimary = AppLux.charcoal;
  static const textSecondary = AppLux.body;
  static const textMuted = AppLux.muted;
  static const border = AppLux.border;
  static const surface = AppLux.surface;
  static const surfaceElevated = AppLux.surface;

  static const accentSoft = AppLux.tealMist;
  static const navySoft = AppLux.charcoalMid;
  static const glass = Color(0xCCFFFFFF);
  static const glassBorder = Color(0x33FFFFFF);
}
