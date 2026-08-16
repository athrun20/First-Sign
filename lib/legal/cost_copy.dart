/// Canonical money language for photo-screening planning ranges.
///
/// Dollar amounts in FirstSign are directional conversation starters from
/// photos — never a contractor bid, quote, or inspection price.
abstract final class CostCopy {
  /// Short label next to any dollar amount.
  static const shortLabel = 'Planning range';

  /// One-line honesty note beside a range.
  static const inlineNote =
      'Directional only from photos — not a contractor bid or inspection price.';

  /// Shown when evidence is too weak to support a dollar range.
  static const withheld = 'Planning range withheld — weak photo evidence';

  /// Footnote under report cards, PDFs, and quote summaries.
  static const footnote =
      'Ranges are screening ballparks for conversation only. A site visit sets real scope and price.';

  /// True when [raw] is empty, TBD, or otherwise not a usable dollar range.
  static bool isWithheldRange(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return true;
    final lower = t.toLowerCase();
    if (lower == '—' || lower == '-' || lower == '–') return true;
    return lower == 'tbd' || lower.startsWith('tbd');
  }

  /// Strip leftover "planning range" / parenthetical framing from stored text.
  static String stripDecorations(String raw) {
    return raw
        .replaceAll(RegExp(r'\s*\(.*?\)\s*'), ' ')
        .replaceAll(RegExp('planning range', caseSensitive: false), '')
        .replaceAll(RegExp('screening estimate.*', caseSensitive: false), '')
        .trim();
  }

  /// Compact dollar text, or [withheld] — never invents a number.
  static String compact(String raw) {
    if (isWithheldRange(raw)) return withheld;
    final cleaned = stripDecorations(raw);
    return cleaned.isEmpty ? withheld : cleaned;
  }

  /// `[shortLabel] $1,200 – $3,200`, or [withheld].
  static String labeled(String raw) {
    if (isWithheldRange(raw)) return withheld;
    final cleaned = stripDecorations(raw);
    if (cleaned.isEmpty) return withheld;
    final lower = cleaned.toLowerCase();
    if (lower.startsWith('planning range')) return cleaned;
    return '$shortLabel $cleaned';
  }
}
