import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/onboarding_store.dart';
import '../theme/app_lux.dart';

/// Shows the calm first-run / “How it works” sheet.
///
/// Does not block Home forever — user can skip anytime. Marks onboarding done
/// when dismissed (skip or primary), unless [markComplete] is false.
Future<void> showFirstSignOnboarding(
  BuildContext context, {
  bool markComplete = true,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppLux.charcoal.withValues(alpha: 0.28),
    builder: (ctx) {
      return _OnboardingSheet(
        onDismiss: () async {
          if (markComplete) {
            await OnboardingStore.instance.markDone();
          }
          if (ctx.mounted) Navigator.of(ctx).pop();
        },
      );
    },
  );
}

class _OnboardingSheet extends StatelessWidget {
  const _OnboardingSheet({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      decoration: const BoxDecoration(
        color: AppLux.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: AppLux.border, width: AppLux.borderWidth),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppLux.border,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(
              children: [
                const SizedBox(width: 8),
                Text(
                  'Welcome to FirstSign',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppLux.muted,
                    letterSpacing: 0.2,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: onDismiss,
                  style: TextButton.styleFrom(
                    foregroundColor: AppLux.body,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                  child: Text(
                    'Skip',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(22, 4, 22, 16 + bottom),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A calm way to screen\nyour home’s exterior.',
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppLux.charcoal,
                      letterSpacing: -0.6,
                      height: 1.18,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No account needed. Photos and reports stay on this device '
                    'until you choose to request a quote through FirstSign.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      height: 1.5,
                      color: AppLux.body,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 22),
                  AppLux.sectionHeader('Choose your path'),
                  const SizedBox(height: 10),
                  const _PathCard(
                    icon: Icons.photo_library_outlined,
                    badge: 'Recommended',
                    badgeTeal: true,
                    title: 'Full Assessment',
                    detail: '6 guided photos · about 2–3 minutes',
                    body:
                        'Walk around the home with gentle prompts. '
                        'More angles mean a fuller story and stronger confidence.',
                  ),
                  const SizedBox(height: 12),
                  const _PathCard(
                    icon: Icons.bolt_rounded,
                    badge: 'Faster',
                    badgeTeal: false,
                    title: 'Quick Scan',
                    detail: '1 photo · any exterior area',
                    body:
                        'A lighter screen when you want a fast look. '
                        'Helpful, but lower confidence than a full walk-around.',
                  ),
                  const SizedBox(height: 22),
                  AppLux.sectionHeader('How it works'),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    decoration: AppLux.card(radius: 20),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: const Column(
                      children: [
                        _MiniStep(
                          number: '1',
                          title: 'Capture',
                          body: 'Full Assessment or a single Quick Scan photo.',
                        ),
                        _MiniStepDivider(),
                        _MiniStep(
                          number: '2',
                          title: 'AI screening',
                          body:
                              'Likely findings with severity and confidence — '
                              'not a licensed inspection.',
                        ),
                        _MiniStepDivider(),
                        _MiniStep(
                          number: '3',
                          title: 'Report & next steps',
                          body:
                              'Clear story, PDF share, and optional quote request.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onDismiss,
                      style: AppLux.primaryButton(),
                      child: Text(
                        'Continue to FirstSign',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 15.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      'Reopen these tips anytime from Home or Profile.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppLux.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PathCard extends StatelessWidget {
  const _PathCard({
    required this.icon,
    required this.badge,
    required this.badgeTeal,
    required this.title,
    required this.detail,
    required this.body,
  });

  final IconData icon;
  final String badge;
  final bool badgeTeal;
  final String title;
  final String detail;
  final String body;

  @override
  Widget build(BuildContext context) {
    final badgeBg = badgeTeal ? AppLux.tealMist : AppLux.goldSoft;
    final badgeFg = badgeTeal ? AppLux.teal : AppLux.gold;
    final badgeBorder = badgeTeal
        ? AppLux.teal.withValues(alpha: 0.16)
        : AppLux.gold.withValues(alpha: 0.2);

    return Container(
      width: double.infinity,
      decoration: AppLux.card(radius: 20),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppLux.tealMist,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppLux.teal.withValues(alpha: 0.14),
                width: AppLux.borderWidth,
              ),
            ),
            child: Icon(icon, color: AppLux.teal, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: AppLux.charcoal,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: badgeBorder,
                          width: AppLux.borderWidth,
                        ),
                      ),
                      child: Text(
                        badge,
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: badgeFg,
                          letterSpacing: 0.15,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppLux.teal,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    height: 1.45,
                    color: AppLux.body,
                    fontWeight: FontWeight.w400,
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

class _MiniStep extends StatelessWidget {
  const _MiniStep({
    required this.number,
    required this.title,
    required this.body,
  });

  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppLux.tealMist,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppLux.teal.withValues(alpha: 0.14),
              width: AppLux.borderWidth,
            ),
          ),
          child: Text(
            number,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppLux.teal,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppLux.charcoal,
                  letterSpacing: -0.15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  height: 1.4,
                  color: AppLux.body,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniStepDivider extends StatelessWidget {
  const _MiniStepDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 10, bottom: 10),
      child: Container(
        height: 12,
        width: 1.5,
        margin: const EdgeInsets.only(left: 12),
        color: AppLux.border,
      ),
    );
  }
}
