import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../legal/cost_copy.dart';
import '../legal/privacy_copy.dart';
import '../legal/product_copy.dart';
import '../models/lead_models.dart';
import '../theme/app_lux.dart';

/// Homeowner-facing confirmation after a quote request is submitted.
class QuoteConfirmationScreen extends StatelessWidget {
  /// [deliveredRemotely] is true when Formspree (or the configured endpoint)
  /// accepted the request; false when the lead was saved only on-device.
  const QuoteConfirmationScreen({
    super.key,
    required this.lead,
    this.deliveredRemotely = true,
  });

  final QuoteLead lead;

  /// True when Formspree (or configured endpoint) accepted the request.
  /// False when the request was saved locally only (offline / config / error).
  final bool deliveredRemotely;

  @override
  Widget build(BuildContext context) {
    final firstName = lead.name.trim().split(RegExp(r'\s+')).first;
    final greet = firstName.isEmpty ? 'there' : firstName;

    return Scaffold(
      backgroundColor: AppLux.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppLux.pagePaddingH,
            20,
            AppLux.pagePaddingH,
            16,
          ),
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 8),
                            Container(
                              width: 84,
                              height: 84,
                              decoration: BoxDecoration(
                                color: AppLux.tealMist,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppLux.teal.withValues(alpha: 0.18),
                                  width: AppLux.borderWidth,
                                ),
                              ),
                              child: const Icon(
                                Icons.check_circle_rounded,
                                size: 44,
                                color: AppLux.teal,
                              ),
                            ),
                            const SizedBox(height: 22),
                            Text(
                              deliveredRemotely
                                  ? 'Request sent'
                                  : 'Request saved',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: AppLux.charcoal,
                                letterSpacing: -0.55,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              ProductCopy.displayName,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppLux.teal,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              deliveredRemotely
                                  ? 'Thanks, $greet. ${PrivacyCopy.quoteSentBody}'
                                  : 'Thanks, $greet. ${PrivacyCopy.quoteSavedLocalBody}',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                height: 1.55,
                                color: AppLux.body,
                                fontWeight: FontWeight.w400,
                                letterSpacing: 0.02,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                12,
                                14,
                                12,
                              ),
                              decoration: AppLux.goldNote(
                                radius: AppLux.radiusXl,
                              ),
                              child: Text(
                                PrivacyCopy.screeningReminder,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  height: 1.45,
                                  fontWeight: FontWeight.w600,
                                  color: AppLux.disclaimerInk,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(
                                18,
                                16,
                                18,
                                16,
                              ),
                              decoration: AppLux.card(radius: AppLux.radius3xl),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'What we shared',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppLux.charcoal,
                                      letterSpacing: -0.15,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _row(Icons.home_outlined, lead.address),
                                  const SizedBox(height: 10),
                                  _row(Icons.phone_outlined, lead.phone),
                                  const SizedBox(height: 10),
                                  _row(Icons.email_outlined, lead.email),
                                  const SizedBox(height: 10),
                                  _row(
                                    Icons.schedule_rounded,
                                    lead.preferredContact,
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 14),
                                    child: Divider(
                                      height: 1,
                                      thickness: AppLux.borderWidth,
                                      color: AppLux.border,
                                    ),
                                  ),
                                  Text(
                                    'Report snapshot',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppLux.muted,
                                      letterSpacing: 0.1,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Score ${lead.overallScore} · '
                                    '${lead.findingsCount} findings · '
                                    '${lead.photoCount} photos',
                                    style: GoogleFonts.inter(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppLux.charcoal,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    CostCopy.labeled(lead.estimatedRepairRange),
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: AppLux.body,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    CostCopy.inlineNote,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      height: 1.4,
                                      color: AppLux.muted,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    CostCopy.footnote,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      height: 1.4,
                                      color: AppLux.muted,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  style: AppLux.primaryButton(),
                  child: Text(
                    'Back to home',
                    style: GoogleFonts.inter(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) {
    final value = text.trim().isEmpty ? '—' : text.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppLux.icon),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: AppLux.charcoal,
            ),
          ),
        ),
      ],
    );
  }
}
