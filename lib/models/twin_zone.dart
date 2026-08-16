/// Zones on the interactive digital twin and analysis mapping.
enum TwinZone { none, roof, siding, windows, foundation, gutters }

extension TwinZoneLabel on TwinZone {
  /// Homeowner surface name shared by chips, empty copy, and findings.
  String get surfaceLabel {
    switch (this) {
      case TwinZone.roof:
        return 'Roof';
      case TwinZone.siding:
        return 'Siding';
      case TwinZone.windows:
        return 'Windows';
      case TwinZone.foundation:
        return 'Foundation';
      case TwinZone.gutters:
        return 'Gutters';
      case TwinZone.none:
        return 'All zones';
    }
  }
}

/// Presentation copy for the digital twin — no analysis logic.
abstract final class TwinZoneCopy {
  static const tapHelper = 'Tap a surface to see findings for that area.';

  static String noIssuesLine(TwinZone zone) =>
      'No issues flagged on ${zone.surfaceLabel} from these photos.';
}
