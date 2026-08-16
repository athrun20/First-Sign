import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../legal/privacy_copy.dart';
import '../theme/app_lux.dart';

/// Report-level closer-photo card (warm paper, teal accent).
class CloserPhotoTipCard extends StatelessWidget {
  const CloserPhotoTipCard({super.key, required this.onRetake});

  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('closer-photo-tip'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppLux.cardFill,
        borderRadius: BorderRadius.circular(AppLux.radius2xl),
        border: Border.all(
          color: AppLux.teal.withValues(alpha: 0.22),
          width: 0.85,
        ),
        boxShadow: AppLux.softShadow(intensity: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppLux.tealMist,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.photo_camera_outlined,
                  color: AppLux.teal,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  PrivacyCopy.closerPhotoTitle,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppLux.charcoal,
                    letterSpacing: -0.25,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            PrivacyCopy.closerPhotoBody,
            style: GoogleFonts.inter(
              fontSize: 13.5,
              height: 1.5,
              color: AppLux.body,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: onRetake,
            style: AppLux.primaryButton(minHeight: 48),
            child: Text(
              PrivacyCopy.closerPhotoAction,
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// Soft capture / review hint. Does not block continue.
class CloserPhotoCaptureHint extends StatelessWidget {
  const CloserPhotoCaptureHint({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('closer-photo-capture-hint'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppLux.tealMist,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppLux.teal.withValues(alpha: 0.18),
          width: 0.75,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.wb_twilight_outlined,
            size: 18,
            color: AppLux.teal,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              PrivacyCopy.closerPhotoCaptureTip,
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.45,
                color: AppLux.charcoalMid,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
