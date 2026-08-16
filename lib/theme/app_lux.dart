import 'package:flutter/material.dart';

/// FirstSign calm-luxury design system.
///
/// Single source of truth for colors, radii, spacing, shadows, borders,
/// and shared component styles across Home, Report, Quote, Contractor,
/// Capture / Quick Scan, and related surfaces.
abstract final class AppLux {
  // ── Surfaces ─────────────────────────────────────────────────────────────
  static const bg = Color(0xFFFAF7F2);
  static const surface = Color(0xFFFFFFFF);
  static const cardFill = Color(0xFFFCFAF7);
  static const stone = Color(0xFF3A322B);
  static const stoneDeep = Color(0xFF2E2722);

  // ── Ink ──────────────────────────────────────────────────────────────────
  static const charcoal = Color(0xFF1C1917);
  static const charcoalMid = Color(0xFF292524);
  static const body = Color(0xFF57534E);
  static const muted = Color(0xFFA8A29E);
  static const icon = Color(0xFFB0A89E);

  // ── Accents ──────────────────────────────────────────────────────────────
  static const teal = Color(0xFF0F766E);
  static const tealBright = Color(0xFF14B8A6);
  static const tealDeep = Color(0xFF115E59);
  static const tealMist = Color(0xFFF0FDFA);
  static const tealLine = Color(0xFF99F6E4);
  static const gold = Color(0xFFB45309);
  static const goldSoft = Color(0xFFF8EEDC);
  static const goldLine = Color(0xFFE8D5A8);

  // ── Borders ──────────────────────────────────────────────────────────────
  static const border = Color(0xFFEDE6DB);
  static const borderSoft = Color(0xFFF3EEE6);
  static const borderWidth = 0.75;
  static const borderWidthStrong = 1.0;

  // ── Semantic ─────────────────────────────────────────────────────────────
  static const danger = Color(0xFFB91C1C);
  static const dangerSoft = Color(0xFFFEF2F2);
  static const warning = Color(0xFFD97706);
  static const success = teal;
  static const disclaimerInk = Color(0xFF78350F);

  // ── Radii ────────────────────────────────────────────────────────────────
  static const radiusSm = 10.0;
  static const radiusMd = 12.0;
  static const radiusLg = 14.0;
  static const radiusXl = 16.0;
  static const radius2xl = 18.0;
  static const radius3xl = 20.0;
  static const radiusCard = 18.0;
  static const radiusHero = 24.0;
  static const radiusPill = 99.0;

  // ── Spacing ──────────────────────────────────────────────────────────────
  static const spaceXs = 6.0;
  static const spaceSm = 8.0;
  static const spaceMd = 12.0;
  static const spaceLg = 16.0;
  static const spaceXl = 20.0;
  static const space2xl = 24.0;
  static const space3xl = 32.0;
  static const sectionGap = 28.0;
  static const pagePaddingH = 24.0;
  static const pagePaddingV = 18.0;

  // ── Type scale (logical sizes) ────────────────────────────────────────────
  static const titleLg = 22.0;
  static const titleMd = 17.0;
  static const titleSm = 15.5;
  static const bodyLg = 15.0;
  static const bodyMd = 13.5;
  static const bodySm = 12.5;
  static const caption = 12.0;
  static const overline = 10.5;

  /// Hero condition score (Apple Health / Robinhood scale).
  static const scoreDisplay = 64.0;

  // ── Shadows ──────────────────────────────────────────────────────────────
  static List<BoxShadow> cardShadow({double intensity = 1}) => [
    BoxShadow(
      color: charcoal.withValues(alpha: 0.035 * intensity),
      blurRadius: 24,
      offset: const Offset(0, 10),
    ),
    BoxShadow(
      color: charcoal.withValues(alpha: 0.015 * intensity),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];

  static List<BoxShadow> softShadow({double intensity = 1}) => [
    BoxShadow(
      color: charcoal.withValues(alpha: 0.03 * intensity),
      blurRadius: 28,
      offset: const Offset(0, 12),
    ),
    BoxShadow(
      color: charcoal.withValues(alpha: 0.012 * intensity),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];

  // ── Decorations ──────────────────────────────────────────────────────────
  static BoxDecoration card({
    double radius = radiusCard,
    Color? color,
    bool elevated = true,
  }) => BoxDecoration(
    color: color ?? surface,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: border, width: borderWidth),
    boxShadow: elevated ? cardShadow() : null,
  );

  static BoxDecoration softCard({double radius = radiusCard}) => BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: border, width: borderWidth),
    boxShadow: softShadow(),
  );

  static BoxDecoration mistCard({double radius = radius2xl}) => BoxDecoration(
    color: tealMist,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: teal.withValues(alpha: 0.18), width: borderWidth),
  );

  static BoxDecoration goldNote({double radius = radiusLg}) => BoxDecoration(
    color: goldSoft.withValues(alpha: 0.65),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: gold.withValues(alpha: 0.18), width: borderWidth),
  );

  // ── Typography ───────────────────────────────────────────────────────────
  static const TextStyle appBarTitle = TextStyle(
    fontSize: titleMd,
    fontWeight: FontWeight.w600,
    color: charcoal,
    letterSpacing: -0.2,
    height: 1.2,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: charcoal,
    letterSpacing: -0.25,
    height: 1.25,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 16.5,
    fontWeight: FontWeight.w600,
    color: charcoal,
    letterSpacing: -0.3,
    height: 1.25,
  );

  static const TextStyle bodyText = TextStyle(
    fontSize: bodyLg,
    height: 1.55,
    color: body,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.0,
  );

  static const TextStyle captionText = TextStyle(
    fontSize: 13,
    height: 1.45,
    color: muted,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.0,
  );

  static const TextStyle overlineText = TextStyle(
    fontSize: overline,
    fontWeight: FontWeight.w600,
    color: muted,
    letterSpacing: 0.6,
    height: 1.2,
  );

  // ── Buttons ──────────────────────────────────────────────────────────────
  static ButtonStyle primaryButton({double minHeight = 52}) =>
      FilledButton.styleFrom(
        backgroundColor: teal,
        foregroundColor: Colors.white,
        disabledBackgroundColor: teal.withValues(alpha: 0.45),
        disabledForegroundColor: Colors.white.withValues(alpha: 0.9),
        elevation: 0,
        minimumSize: Size(double.infinity, minHeight),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
        ),
        textStyle: const TextStyle(
          fontSize: 15.5,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.1,
        ),
      );

  static ButtonStyle secondaryButton({double minHeight = 48}) =>
      OutlinedButton.styleFrom(
        foregroundColor: body,
        backgroundColor: cardFill,
        side: BorderSide(color: border.withValues(alpha: 0.95), width: 0.85),
        elevation: 0,
        minimumSize: Size(0, minHeight),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        textStyle: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.05,
        ),
      );

  static ButtonStyle ghostButton() => TextButton.styleFrom(
    foregroundColor: body,
    textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
  );

  // ── Chips ────────────────────────────────────────────────────────────────
  static BoxDecoration chip({required bool selected}) => BoxDecoration(
    color: selected ? tealMist : bg,
    borderRadius: BorderRadius.circular(radiusLg),
    border: Border.all(
      color: selected ? teal.withValues(alpha: 0.45) : border,
      width: selected ? 1.1 : borderWidth,
    ),
  );

  // ── Section header widget builder ────────────────────────────────────────
  static Widget sectionHeader(
    String title, {
    String? trailing,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
  }) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(child: Text(title, style: sectionTitle)),
          if (trailing != null)
            Text(
              trailing,
              style: captionText.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: muted,
              ),
            ),
        ],
      ),
    );
  }

  // ── Empty state ──────────────────────────────────────────────────────────
  static Widget emptyState({
    required IconData icon,
    required String title,
    required String body,
    Widget? action,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
      decoration: card(radius: radiusHero),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: tealMist,
              shape: BoxShape.circle,
              border: Border.all(
                color: teal.withValues(alpha: 0.16),
                width: borderWidth,
              ),
            ),
            child: Icon(icon, color: teal, size: 26),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: cardTitle.copyWith(fontSize: 17),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: bodyText.copyWith(fontSize: bodyMd),
          ),
          if (action != null) ...[const SizedBox(height: 20), action],
        ],
      ),
    );
  }

  // ── Loading card ─────────────────────────────────────────────────────────
  static Widget loadingCard({required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(radius2xl),
        border: Border.all(color: border, width: borderWidth),
        boxShadow: softShadow(),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: teal),
          ),
          const SizedBox(height: 14),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: charcoal,
              letterSpacing: -0.1,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
