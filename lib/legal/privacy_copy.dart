import 'cost_copy.dart';
import 'product_copy.dart';

/// On-device privacy / data-use copy and shared screening disclaimers.
///
/// Single source of truth so Home, Report, PDF, Quote, and Privacy stay aligned
/// with real product behavior (local-first storage + Formspree quote email).
abstract final class PrivacyCopy {
  // ── Privacy (data location) ──────────────────────────────────────────────

  static const title = 'Privacy & data';

  /// One-line privacy summary (home footer, profile chip, privacy header).
  static const shortLine =
      'Photos and reports stay on this device by default. Quote requests email '
      'your contact details and a report summary to our team; a copy is also '
      'saved on this device.';

  static const body = '''
${ProductCopy.displayName} is built local-first.

• Photos you capture are stored on this device (compressed) so you can reopen reports and resume a scan.
• Analysis runs on-device using image features. If a Google Cloud Vision API key is set at build time, images may be sent to Google for that analysis pass only.
• Profile details (name, phone, email, address) stay on this device and autofill quote requests — they are not shared until you submit a quote.
• When you request a quote, we email your contact details and a report summary (score, top findings, planning range) via Formspree to our team, and send a short confirmation to the email you entered. A contractor lead is also saved on this device for follow-up tools. There is no full cloud backup of photos or reports.
• Shared PDFs leave your device when you export or share them. Treat them like any other file you send.
• Demo Mode uses illustrated sample images, not a real property.

You can delete reports from Your reports. Clearing site data (web) or uninstalling the app removes local storage.

This is an AI exterior screening tool — not a licensed home inspection, appraisal, insurance assessment, or engineering report. Confirm findings on-site before major repairs or purchase decisions.
''';

  /// Profile screen intro under the title.
  static const profileIntro =
      'Saved on this device for faster quote requests. Shared with our team '
      'only when you submit a quote.';

  /// Report history empty-state privacy note.
  static const reportsStayLocal =
      'Private by design — assessments stay on this device until you export a '
      'PDF or request a quote.';

  // ── Screening disclaimers (consistent everywhere) ────────────────────────

  /// Short chip / footer reminder.
  static const screeningReminder =
      'Screening only — not a licensed inspection. Confirm findings on-site.';

  /// Canonical long disclaimer for report UI + PDF + shared surfaces.
  static const screeningDisclaimer =
      '${ProductCopy.displayName} is an AI-assisted exterior screening tool based only on the photos you submit. '
      'It is not a licensed home inspection, appraisal, engineering report, insurance assessment, '
      'or contractor bid. Confidence scores reflect photo evidence strength — not a guarantee. '
      'Confirm every finding on-site with a qualified pro before repairs, claims, or purchase decisions.';

  /// Short chip/badge text for report headers and PDF.
  static const screeningBadge = 'Photo screening · not an inspection';

  /// Planning-range footnote (report cards, PDF). Canonical text in [CostCopy].
  static const planningRangeNote = CostCopy.footnote;

  // ── Quote request ────────────────────────────────────────────────────────

  static const quoteIntro =
      'Share your contact details so we can arrange a contractor quote. '
      '${CostCopy.inlineNote}';

  static const quoteFootnote =
      'Submitting emails your name, phone, email, address, score, top findings, '
      'and planning range to our team, and sends you a short confirmation at the '
      'email you enter. A copy is also saved on this device for contractor '
      'follow-up. Your photos and full report stay on this device unless you '
      'export a PDF or share them.';

  /// Confirmation after successful remote send.
  static const quoteSentBody =
      'Your quote request was emailed to our team with a report summary '
      '(score, findings, planning range). A short confirmation may also arrive '
      'at the email you entered. A contractor can follow up using the details '
      'you shared. Photos stay on this device unless you export them.';

  /// Confirmation when only saved locally.
  static const quoteSavedLocalBody =
      'Your details are saved on this device as a contractor lead. '
      'If email is not set up in this build (or the send failed), share your PDF '
      'from the report, or open Pro tools to follow up from this phone/browser.';

  /// PDF closing line.
  static const pdfShareNote =
      'Share this PDF with a contractor, or request a quote in ${ProductCopy.displayName} to '
      'email a summary to our team for follow-up.';

  // ── Closer photo / limited visibility (presentation only) ───────────────

  static const closerPhotoTitle = 'Closer photo needed';

  static const closerPhotoBody =
      'This screening used a limited or dark view. Move closer, add more light, '
      'and retake the main elevations for a stronger result.';

  static const closerPhotoAction = 'Retake photos';

  /// Soft capture-flow hint. Does not block continue.
  static const closerPhotoCaptureTip =
      'Low detail detected — a closer or better-lit shot will improve accuracy.';
}
