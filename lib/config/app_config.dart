/// Compile-time app configuration (dart-defines / dart-define-from-file).
///
/// **Quote email (Formspree)**
/// ```bash
/// # Copy the example, paste your form URL, then run:
/// copy formspree.env.example.json formspree.env.json
/// flutter run -d edge --dart-define-from-file=formspree.env.json
/// ```
/// Or pass flags:
/// ```bash
/// flutter run -d edge --dart-define=FORMSPREE_ENDPOINT=https://formspree.io/f/xxxx
/// ```
///
/// **Optional Cloud Vision** (same env file as Formspree)
/// ```bash
/// # formspree.env.json → "GOOGLE_VISION_API_KEY": "AIza..."
/// flutter run -d windows --dart-define-from-file=formspree.env.json
/// # or: --dart-define=GOOGLE_VISION_API_KEY=...
/// ```
/// See `docs/VISION_API_SETUP.md`.
abstract final class AppConfig {
  /// Team inbox used in Formspree form settings + payload metadata.
  static const quoteTeamEmail = String.fromEnvironment(
    'QUOTE_TEAM_EMAIL',
    defaultValue: 'sanchezj24@live.com',
  );

  /// Raw contractor Formspree value (full URL or form id).
  static const formspreeEndpointRaw = String.fromEnvironment(
    'FORMSPREE_ENDPOINT',
  );

  /// Optional second form for homeowner confirmation / autoresponse.
  static const formspreeConfirmEndpointRaw = String.fromEnvironment(
    'FORMSPREE_CONFIRM_ENDPOINT',
  );

  /// Optional form used to fan-out invitee (matched contractor) lead emails.
  ///
  /// When blank, invitee notifications reuse [formspreeEndpoint] (best-effort
  /// via `_cc` / `email` fields). A dedicated form keeps team submissions clean.
  static const formspreeContractorNotifyEndpointRaw = String.fromEnvironment(
    'FORMSPREE_CONTRACTOR_NOTIFY_ENDPOINT',
  );

  /// Normalized contractor endpoint (empty when not set).
  static String get formspreeEndpoint =>
      normalizeFormspreeEndpoint(formspreeEndpointRaw);

  /// Normalized confirm endpoint; falls back to primary when blank.
  static String get formspreeConfirmEndpoint {
    final c = normalizeFormspreeEndpoint(formspreeConfirmEndpointRaw);
    if (c.isNotEmpty) return c;
    return formspreeEndpoint;
  }

  /// Normalized invitee-notify endpoint; falls back to primary when blank.
  static String get formspreeContractorNotifyEndpoint {
    final n = normalizeFormspreeEndpoint(formspreeContractorNotifyEndpointRaw);
    if (n.isNotEmpty) return n;
    return formspreeEndpoint;
  }

  static bool get quoteEmailConfigured =>
      isValidFormspreeEndpoint(formspreeEndpoint);

  static bool get hasDedicatedConfirmEndpoint {
    final c = normalizeFormspreeEndpoint(formspreeConfirmEndpointRaw);
    final p = formspreeEndpoint;
    return isValidFormspreeEndpoint(c) && c != p;
  }

  static bool get hasDedicatedContractorNotifyEndpoint {
    final n = normalizeFormspreeEndpoint(formspreeContractorNotifyEndpointRaw);
    final p = formspreeEndpoint;
    return isValidFormspreeEndpoint(n) && n != p;
  }

  /// Accepts full URL or bare form id (`xyzabcde` → `https://formspree.io/f/xyzabcde`).
  static String normalizeFormspreeEndpoint(String raw) {
    var t = raw.trim();
    if (t.isEmpty) return '';
    if (t.contains('YOUR_FORM_ID') || t.contains('xxxxxxxx')) return '';

    // Bare form hash / id
    if (!t.contains('://') && !t.contains('/')) {
      final id = t.replaceAll(RegExp('[^a-zA-Z0-9]'), '');
      if (id.length < 6) return '';
      t = 'https://formspree.io/f/$id';
    }

    // formspree.io/f/xxx without scheme
    if (t.startsWith('formspree.io/')) {
      t = 'https://$t';
    }

    final uri = Uri.tryParse(t);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return '';
    if (uri.scheme != 'https' && uri.scheme != 'http') return '';
    return uri.toString();
  }

  static bool isValidFormspreeEndpoint(String endpoint) {
    final t = normalizeFormspreeEndpoint(endpoint);
    if (t.isEmpty) return false;
    final uri = Uri.tryParse(t);
    if (uri == null) return false;
    // Prefer Formspree hosts; still allow custom form backends on https.
    final host = uri.host.toLowerCase();
    if (host.contains('formspree.io') || host.contains('formspree.com')) {
      return uri.pathSegments.isNotEmpty;
    }
    return uri.scheme == 'https' && uri.path.isNotEmpty;
  }
}
