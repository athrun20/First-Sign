import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../legal/privacy_copy.dart';
import '../theme/app_lux.dart';

/// Full privacy / data-use explainer for homeowners.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppLux.bg,
      appBar: AppBar(
        backgroundColor: AppLux.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppLux.charcoal,
        title: Text(
          PrivacyCopy.title,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: AppLux.titleMd,
            letterSpacing: -0.2,
            color: AppLux.charcoal,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppLux.pagePaddingH,
          8,
          AppLux.pagePaddingH,
          40,
        ),
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: AppLux.mistCard(radius: AppLux.radius2xl),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppLux.surface.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(AppLux.radiusMd),
                    border: Border.all(
                      color: AppLux.teal.withValues(alpha: 0.14),
                      width: AppLux.borderWidth,
                    ),
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    size: 20,
                    color: AppLux.teal,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    PrivacyCopy.shortLine,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                      color: AppLux.tealDeep,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            decoration: AppLux.card(radius: AppLux.radius3xl),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How we handle your data',
                  style: GoogleFonts.inter(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: AppLux.charcoal,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  PrivacyCopy.body.trim(),
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    height: 1.55,
                    color: AppLux.body,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: AppLux.goldNote(radius: AppLux.radiusXl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  PrivacyCopy.screeningReminder,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                    color: AppLux.disclaimerInk,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  PrivacyCopy.screeningDisclaimer,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                    color: AppLux.disclaimerInk.withValues(alpha: 0.92),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
