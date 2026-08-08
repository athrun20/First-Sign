/// Thrown when local persistence cannot accept more photo/report data.
class StorageFullException implements Exception {
  final String message;
  final int? usedBytes;
  final int? limitBytes;

  const StorageFullException(this.message, {this.usedBytes, this.limitBytes});

  @override
  String toString() => message;

  /// Homeowner-facing copy for snackbars.
  String get userMessage {
    if (usedBytes != null && limitBytes != null && limitBytes! > 0) {
      final usedMb = (usedBytes! / (1024 * 1024)).toStringAsFixed(1);
      final limitMb = (limitBytes! / (1024 * 1024)).toStringAsFixed(0);
      return 'Device storage is full ($usedMb / $limitMb MB). '
          'Delete older reports and try again.';
    }
    return 'Device storage is full. Delete older reports and try again.';
  }
}

/// Soft limits for local photo/report persistence (especially web).
abstract final class StorageLimits {
  /// Soft cap on total blob bytes (photos + logo). Prefer eviction under this.
  static int blobBudgetBytes({required bool isWeb}) =>
      isWeb ? 28 * 1024 * 1024 : 120 * 1024 * 1024;

  /// Max saved homeowner reports kept on device.
  static int maxReports({required bool isWeb}) => isWeb ? 12 : 20;

  /// Max photos kept on a single report / lead / draft.
  static const maxPhotosPerReport = 8;

  /// Target max bytes per compressed exterior photo.
  static int maxPhotoBytes({required bool isWeb}) =>
      isWeb ? 140 * 1024 : 220 * 1024;

  /// Long-edge cap when compressing for storage.
  static int maxPhotoSide({required bool isWeb}) => isWeb ? 900 : 1100;

  /// Draft photos can be smaller (resume only).
  static int maxDraftPhotoSide({required bool isWeb}) => isWeb ? 720 : 900;

  static int maxDraftPhotoBytes({required bool isWeb}) =>
      isWeb ? 100 * 1024 : 160 * 1024;

  /// Branding logo budget.
  static const maxLogoBytes = 180 * 1024;
  static const maxLogoSide = 512;
}
