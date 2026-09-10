import 'package:pillar_ai/models/property_memory_enums.dart';

/// Normalized region in image space (0–1). Prefer LTRB-derived `{l,t,w,h}`.
class RegionNorm {
  final double left;
  final double top;
  final double width;
  final double height;

  const RegionNorm({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  double get right => left + width;
  double get bottom => top + height;
  double get area => width * height;

  /// Intersection-over-union with another region (0 if either has no area).
  double iou(RegionNorm other) {
    final x1 = left > other.left ? left : other.left;
    final y1 = top > other.top ? top : other.top;
    final x2 = right < other.right ? right : other.right;
    final y2 = bottom < other.bottom ? bottom : other.bottom;
    final iw = x2 - x1;
    final ih = y2 - y1;
    if (iw <= 0 || ih <= 0) return 0;
    final inter = iw * ih;
    final union = area + other.area - inter;
    if (union <= 0) return 0;
    return inter / union;
  }

  factory RegionNorm.fromJson(Map<String, dynamic> json) {
    // Accept both {l,t,w,h} and {x,y,w,h} / {left,top,width,height}.
    double n(String a, [String? b, String? c]) =>
        (json[a] as num?)?.toDouble() ??
        (b != null ? (json[b] as num?)?.toDouble() : null) ??
        (c != null ? (json[c] as num?)?.toDouble() : null) ??
        0.0;
    return RegionNorm(
      left: n('l', 'x', 'left'),
      top: n('t', 'y', 'top'),
      width: n('w', 'width'),
      height: n('h', 'height'),
    );
  }

  Map<String, dynamic> toJson() => {
        'l': left,
        't': top,
        'w': width,
        'h': height,
      };
}

class PmProperty {
  final String id;
  final String displayName;
  final String? addressLine;
  final PropertyLifecycleState lifecycleState;
  final String? baselineScanId;
  final DateTime? baselineEstablishedAt;
  final String? lastCheckInScanId;
  final DateTime? lastCheckInAt;
  final int openObservationCount;
  final Map<String, int> prioritySummary;
  final OverallConditionSignal overallConditionSignal;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int featureGeneration;

  const PmProperty({
    required this.id,
    required this.displayName,
    this.addressLine,
    required this.lifecycleState,
    this.baselineScanId,
    this.baselineEstablishedAt,
    this.lastCheckInScanId,
    this.lastCheckInAt,
    this.openObservationCount = 0,
    this.prioritySummary = const {},
    this.overallConditionSignal = OverallConditionSignal.incompleteCoverage,
    required this.createdAt,
    required this.updatedAt,
    this.featureGeneration = 1,
  });

  PmProperty copyWith({
    String? displayName,
    String? addressLine,
    PropertyLifecycleState? lifecycleState,
    String? baselineScanId,
    DateTime? baselineEstablishedAt,
    String? lastCheckInScanId,
    DateTime? lastCheckInAt,
    int? openObservationCount,
    Map<String, int>? prioritySummary,
    OverallConditionSignal? overallConditionSignal,
    DateTime? updatedAt,
    int? featureGeneration,
    bool clearBaseline = false,
  }) {
    return PmProperty(
      id: id,
      displayName: displayName ?? this.displayName,
      addressLine: addressLine ?? this.addressLine,
      lifecycleState: lifecycleState ?? this.lifecycleState,
      baselineScanId:
          clearBaseline ? null : (baselineScanId ?? this.baselineScanId),
      baselineEstablishedAt: clearBaseline
          ? null
          : (baselineEstablishedAt ?? this.baselineEstablishedAt),
      lastCheckInScanId: lastCheckInScanId ?? this.lastCheckInScanId,
      lastCheckInAt: lastCheckInAt ?? this.lastCheckInAt,
      openObservationCount: openObservationCount ?? this.openObservationCount,
      prioritySummary: prioritySummary ?? this.prioritySummary,
      overallConditionSignal:
          overallConditionSignal ?? this.overallConditionSignal,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      featureGeneration: featureGeneration ?? this.featureGeneration,
    );
  }

  factory PmProperty.fromJson(Map<String, dynamic> json) {
    final rawPri = json['prioritySummary'] as Map<String, dynamic>? ?? const {};
    return PmProperty(
      id: json['id'] as String? ?? 'property_unknown',
      displayName: json['displayName'] as String? ?? 'My home',
      addressLine: json['addressLine'] as String?,
      lifecycleState: PropertyLifecycleState.fromStorage(
        json['lifecycleState'] as String?,
      ),
      baselineScanId: json['baselineScanId'] as String?,
      baselineEstablishedAt:
          DateTime.tryParse(json['baselineEstablishedAt'] as String? ?? ''),
      lastCheckInScanId: json['lastCheckInScanId'] as String?,
      lastCheckInAt: DateTime.tryParse(json['lastCheckInAt'] as String? ?? ''),
      openObservationCount:
          (json['openObservationCount'] as num?)?.round() ?? 0,
      prioritySummary: {
        for (final e in rawPri.entries) e.key: (e.value as num?)?.round() ?? 0,
      },
      overallConditionSignal: OverallConditionSignal.fromStorage(
        json['overallConditionSignal'] as String?,
      ),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      featureGeneration: (json['featureGeneration'] as num?)?.round() ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        if (addressLine != null) 'addressLine': addressLine,
        'lifecycleState': lifecycleState.toStorage(),
        if (baselineScanId != null) 'baselineScanId': baselineScanId,
        if (baselineEstablishedAt != null)
          'baselineEstablishedAt': baselineEstablishedAt!.toIso8601String(),
        if (lastCheckInScanId != null) 'lastCheckInScanId': lastCheckInScanId,
        if (lastCheckInAt != null)
          'lastCheckInAt': lastCheckInAt!.toIso8601String(),
        'openObservationCount': openObservationCount,
        'prioritySummary': prioritySummary,
        'overallConditionSignal': overallConditionSignal.toStorage(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'featureGeneration': featureGeneration,
      };
}

class PmSurface {
  final String id;
  final String propertyId;
  final SurfaceType type;
  final String? label;
  final SurfacePresence presence;
  final String? twinRegionId;
  final DateTime? lastObservedAt;
  final ImageQualityBand? latestCoverageQuality;
  final int openObservationCount;

  const PmSurface({
    required this.id,
    required this.propertyId,
    required this.type,
    this.label,
    this.presence = SurfacePresence.present,
    this.twinRegionId,
    this.lastObservedAt,
    this.latestCoverageQuality,
    this.openObservationCount = 0,
  });

  PmSurface copyWith({
    String? label,
    SurfacePresence? presence,
    String? twinRegionId,
    DateTime? lastObservedAt,
    ImageQualityBand? latestCoverageQuality,
    int? openObservationCount,
  }) {
    return PmSurface(
      id: id,
      propertyId: propertyId,
      type: type,
      label: label ?? this.label,
      presence: presence ?? this.presence,
      twinRegionId: twinRegionId ?? this.twinRegionId,
      lastObservedAt: lastObservedAt ?? this.lastObservedAt,
      latestCoverageQuality:
          latestCoverageQuality ?? this.latestCoverageQuality,
      openObservationCount: openObservationCount ?? this.openObservationCount,
    );
  }

  factory PmSurface.fromJson(Map<String, dynamic> json) => PmSurface(
        id: json['id'] as String? ?? 'surface_unknown',
        propertyId: json['propertyId'] as String? ?? '',
        type: SurfaceType.fromStorage(json['type'] as String?),
        label: json['label'] as String?,
        presence: SurfacePresence.fromStorage(json['presence'] as String?),
        twinRegionId: json['twinRegionId'] as String?,
        lastObservedAt:
            DateTime.tryParse(json['lastObservedAt'] as String? ?? ''),
        latestCoverageQuality: json['latestCoverageQuality'] == null
            ? null
            : ImageQualityBand.fromStorage(
                json['latestCoverageQuality'] as String?,
              ),
        openObservationCount:
            (json['openObservationCount'] as num?)?.round() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'propertyId': propertyId,
        'type': type.toStorage(),
        if (label != null) 'label': label,
        'presence': presence.toStorage(),
        if (twinRegionId != null) 'twinRegionId': twinRegionId,
        if (lastObservedAt != null)
          'lastObservedAt': lastObservedAt!.toIso8601String(),
        if (latestCoverageQuality != null)
          'latestCoverageQuality': latestCoverageQuality!.toStorage(),
        'openObservationCount': openObservationCount,
      };
}

class PmCoverageZone {
  final String zoneId;
  final SurfaceType? surfaceType;
  final CaptureZoneStatus status;
  final ImageQualityBand? quality;

  const PmCoverageZone({
    required this.zoneId,
    this.surfaceType,
    required this.status,
    this.quality,
  });

  factory PmCoverageZone.fromJson(Map<String, dynamic> json) => PmCoverageZone(
        zoneId: json['zoneId'] as String? ?? '',
        surfaceType: json['surfaceType'] == null
            ? null
            : SurfaceType.fromStorage(json['surfaceType'] as String?),
        status: CaptureZoneStatus.fromStorage(json['status'] as String?),
        quality: json['quality'] == null
            ? null
            : ImageQualityBand.fromStorage(json['quality'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'zoneId': zoneId,
        if (surfaceType != null) 'surfaceType': surfaceType!.toStorage(),
        'status': status.toStorage(),
        if (quality != null) 'quality': quality!.toStorage(),
      };
}

class PmCoverageReport {
  final bool meetsBaselineMinimum;
  final int photoCount;
  final List<PmCoverageZone> zones;
  final List<String> notes;

  const PmCoverageReport({
    required this.meetsBaselineMinimum,
    required this.photoCount,
    this.zones = const [],
    this.notes = const [],
  });

  bool zoneCaptured(String zoneId) {
    for (final z in zones) {
      if (z.zoneId == zoneId &&
          (z.status == CaptureZoneStatus.captured ||
              z.status == CaptureZoneStatus.lowQuality)) {
        return true;
      }
    }
    return false;
  }

  bool surfaceAdequatelyRecaptured(SurfaceType type) {
    for (final z in zones) {
      if (z.surfaceType == type &&
          z.status == CaptureZoneStatus.captured &&
          (z.quality == null || z.quality!.isAdequate)) {
        return true;
      }
    }
    // Slot-based fallback: elevation slots imply siding/etc. coverage.
    return false;
  }

  bool surfaceMissing(SurfaceType type) {
    final related = zones.where((z) => z.surfaceType == type).toList();
    if (related.isEmpty) return true;
    return related.every((z) => z.status == CaptureZoneStatus.missing);
  }

  factory PmCoverageReport.fromJson(Map<String, dynamic> json) {
    final raw = json['zones'] as List<dynamic>? ?? const [];
    return PmCoverageReport(
      meetsBaselineMinimum: json['meetsBaselineMinimum'] as bool? ?? false,
      photoCount: (json['photoCount'] as num?)?.round() ?? 0,
      zones: raw
          .map((e) => PmCoverageZone.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      notes: (json['notes'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'meetsBaselineMinimum': meetsBaselineMinimum,
        'photoCount': photoCount,
        'zones': zones.map((z) => z.toJson()).toList(),
        if (notes.isNotEmpty) 'notes': notes,
      };
}

class PmScan {
  final String id;
  final String propertyId;
  final ScanMode mode;
  final DateTime capturedAt;
  final ScanProcessingStatus processingStatus;
  final String? sourceSavedReportId;
  final SeasonalContext seasonalContext;
  final PmCoverageReport coverageReport;
  final List<String> photoIds;

  const PmScan({
    required this.id,
    required this.propertyId,
    required this.mode,
    required this.capturedAt,
    this.processingStatus = ScanProcessingStatus.complete,
    this.sourceSavedReportId,
    this.seasonalContext = SeasonalContext.unknown,
    required this.coverageReport,
    this.photoIds = const [],
  });

  factory PmScan.fromJson(Map<String, dynamic> json) => PmScan(
        id: json['id'] as String? ?? 'scan_unknown',
        propertyId: json['propertyId'] as String? ?? '',
        mode: ScanMode.fromStorage(json['mode'] as String?),
        capturedAt: DateTime.tryParse(json['capturedAt'] as String? ?? '') ??
            DateTime.now(),
        processingStatus: ScanProcessingStatus.fromStorage(
          json['processingStatus'] as String?,
        ),
        sourceSavedReportId: json['sourceSavedReportId'] as String?,
        seasonalContext:
            SeasonalContext.fromStorage(json['seasonalContext'] as String?),
        coverageReport: PmCoverageReport.fromJson(
          (json['coverageReport'] as Map<String, dynamic>?) ?? const {},
        ),
        photoIds: (json['photoIds'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'propertyId': propertyId,
        'mode': mode.toStorage(),
        'capturedAt': capturedAt.toIso8601String(),
        'processingStatus': processingStatus.toStorage(),
        if (sourceSavedReportId != null)
          'sourceSavedReportId': sourceSavedReportId,
        'seasonalContext': seasonalContext.toStorage(),
        'coverageReport': coverageReport.toJson(),
        'photoIds': photoIds,
      };
}

class PmObservation {
  final String id;
  final String propertyId;
  final String surfaceId;
  final SurfaceType surfaceType;
  final String title;
  final String description;
  final ObservationCategory category;
  final SeverityBand severityBand;
  final ObservationStatus status;
  final ConfidenceBand confidence;
  final String? zoneHint;
  final LocalizationType localizationType;
  final String? twinAnchorId;
  final RegionNorm? regionNorm;
  final String firstSeenScanId;
  final DateTime firstSeenAt;
  final String? lastSeenScanId;
  final DateTime? lastSeenAt;
  final String? lastVerifiedScanId;
  final DateTime? lastVerifiedAt;
  final bool userDismissed;
  final bool userCorrected;
  final ActorType origin;
  final String? sourceIssueFingerprint;
  final String? captureSlot;

  const PmObservation({
    required this.id,
    required this.propertyId,
    required this.surfaceId,
    required this.surfaceType,
    required this.title,
    this.description = '',
    required this.category,
    required this.severityBand,
    required this.status,
    required this.confidence,
    this.zoneHint,
    this.localizationType = LocalizationType.unlocalized,
    this.twinAnchorId,
    this.regionNorm,
    required this.firstSeenScanId,
    required this.firstSeenAt,
    this.lastSeenScanId,
    this.lastSeenAt,
    this.lastVerifiedScanId,
    this.lastVerifiedAt,
    this.userDismissed = false,
    this.userCorrected = false,
    this.origin = ActorType.ai,
    this.sourceIssueFingerprint,
    this.captureSlot,
  });

  bool get isOpenForMatch =>
      !userDismissed && status != ObservationStatus.resolved;

  PmObservation copyWith({
    String? surfaceId,
    SurfaceType? surfaceType,
    String? title,
    String? description,
    ObservationCategory? category,
    SeverityBand? severityBand,
    ObservationStatus? status,
    ConfidenceBand? confidence,
    String? zoneHint,
    LocalizationType? localizationType,
    String? twinAnchorId,
    RegionNorm? regionNorm,
    String? lastSeenScanId,
    DateTime? lastSeenAt,
    String? lastVerifiedScanId,
    DateTime? lastVerifiedAt,
    bool? userDismissed,
    bool? userCorrected,
    String? captureSlot,
  }) {
    return PmObservation(
      id: id,
      propertyId: propertyId,
      surfaceId: surfaceId ?? this.surfaceId,
      surfaceType: surfaceType ?? this.surfaceType,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      severityBand: severityBand ?? this.severityBand,
      status: status ?? this.status,
      confidence: confidence ?? this.confidence,
      zoneHint: zoneHint ?? this.zoneHint,
      localizationType: localizationType ?? this.localizationType,
      twinAnchorId: twinAnchorId ?? this.twinAnchorId,
      regionNorm: regionNorm ?? this.regionNorm,
      firstSeenScanId: firstSeenScanId,
      firstSeenAt: firstSeenAt,
      lastSeenScanId: lastSeenScanId ?? this.lastSeenScanId,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      lastVerifiedScanId: lastVerifiedScanId ?? this.lastVerifiedScanId,
      lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
      userDismissed: userDismissed ?? this.userDismissed,
      userCorrected: userCorrected ?? this.userCorrected,
      origin: origin,
      sourceIssueFingerprint: sourceIssueFingerprint,
      captureSlot: captureSlot ?? this.captureSlot,
    );
  }

  factory PmObservation.fromJson(Map<String, dynamic> json) => PmObservation(
        id: json['id'] as String? ?? 'obs_unknown',
        propertyId: json['propertyId'] as String? ?? '',
        surfaceId: json['surfaceId'] as String? ?? '',
        surfaceType: SurfaceType.fromStorage(json['surfaceType'] as String?),
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        category: ObservationCategory.fromStorage(json['category'] as String?),
        severityBand: SeverityBand.fromStorage(json['severityBand'] as String?),
        status: ObservationStatus.fromStorage(json['status'] as String?),
        confidence: ConfidenceBand.fromStorage(json['confidence'] as String?),
        zoneHint: json['zoneHint'] as String?,
        localizationType:
            LocalizationType.fromStorage(json['localizationType'] as String?),
        twinAnchorId: json['twinAnchorId'] as String?,
        regionNorm: json['regionNorm'] is Map
            ? RegionNorm.fromJson(
                Map<String, dynamic>.from(json['regionNorm'] as Map),
              )
            : null,
        firstSeenScanId: json['firstSeenScanId'] as String? ?? '',
        firstSeenAt: DateTime.tryParse(json['firstSeenAt'] as String? ?? '') ??
            DateTime.now(),
        lastSeenScanId: json['lastSeenScanId'] as String?,
        lastSeenAt: DateTime.tryParse(json['lastSeenAt'] as String? ?? ''),
        lastVerifiedScanId: json['lastVerifiedScanId'] as String?,
        lastVerifiedAt:
            DateTime.tryParse(json['lastVerifiedAt'] as String? ?? ''),
        userDismissed: json['userDismissed'] as bool? ?? false,
        userCorrected: json['userCorrected'] as bool? ?? false,
        origin: ActorType.fromStorage(json['origin'] as String?),
        sourceIssueFingerprint: json['sourceIssueFingerprint'] as String?,
        captureSlot: json['captureSlot'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'propertyId': propertyId,
        'surfaceId': surfaceId,
        'surfaceType': surfaceType.toStorage(),
        'title': title,
        'description': description,
        'category': category.toStorage(),
        'severityBand': severityBand.toStorage(),
        'status': status.toStorage(),
        'confidence': confidence.toStorage(),
        if (zoneHint != null) 'zoneHint': zoneHint,
        'localizationType': localizationType.toStorage(),
        if (twinAnchorId != null) 'twinAnchorId': twinAnchorId,
        if (regionNorm != null) 'regionNorm': regionNorm!.toJson(),
        'firstSeenScanId': firstSeenScanId,
        'firstSeenAt': firstSeenAt.toIso8601String(),
        if (lastSeenScanId != null) 'lastSeenScanId': lastSeenScanId,
        if (lastSeenAt != null) 'lastSeenAt': lastSeenAt!.toIso8601String(),
        if (lastVerifiedScanId != null)
          'lastVerifiedScanId': lastVerifiedScanId,
        if (lastVerifiedAt != null)
          'lastVerifiedAt': lastVerifiedAt!.toIso8601String(),
        'userDismissed': userDismissed,
        'userCorrected': userCorrected,
        'origin': origin.toStorage(),
        if (sourceIssueFingerprint != null)
          'sourceIssueFingerprint': sourceIssueFingerprint,
        if (captureSlot != null) 'captureSlot': captureSlot,
      };
}

class PmEvidence {
  final String id;
  final String observationId;
  final String scanId;
  final String photoKey;
  final DateTime capturedAt;
  final ImageQualityBand imageQuality;
  final LocalizationType localizationType;
  final RegionNorm? regionNorm;
  final String modelExplanation;
  final Map<String, dynamic>? rawModelOutputs;
  final bool isInvalidated;
  final int? photoIndex;

  const PmEvidence({
    required this.id,
    required this.observationId,
    required this.scanId,
    required this.photoKey,
    required this.capturedAt,
    this.imageQuality = ImageQualityBand.usable,
    this.localizationType = LocalizationType.unlocalized,
    this.regionNorm,
    this.modelExplanation = '',
    this.rawModelOutputs,
    this.isInvalidated = false,
    this.photoIndex,
  });

  factory PmEvidence.fromJson(Map<String, dynamic> json) => PmEvidence(
        id: json['id'] as String? ?? 'ev_unknown',
        observationId: json['observationId'] as String? ?? '',
        scanId: json['scanId'] as String? ?? '',
        photoKey: json['photoKey'] as String? ?? '',
        capturedAt: DateTime.tryParse(json['capturedAt'] as String? ?? '') ??
            DateTime.now(),
        imageQuality:
            ImageQualityBand.fromStorage(json['imageQuality'] as String?),
        localizationType:
            LocalizationType.fromStorage(json['localizationType'] as String?),
        regionNorm: json['regionNorm'] is Map
            ? RegionNorm.fromJson(
                Map<String, dynamic>.from(json['regionNorm'] as Map),
              )
            : null,
        modelExplanation: json['modelExplanation'] as String? ?? '',
        rawModelOutputs: json['rawModelOutputs'] is Map
            ? Map<String, dynamic>.from(json['rawModelOutputs'] as Map)
            : null,
        isInvalidated: json['isInvalidated'] as bool? ?? false,
        photoIndex: (json['photoIndex'] as num?)?.round(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'observationId': observationId,
        'scanId': scanId,
        'photoKey': photoKey,
        'capturedAt': capturedAt.toIso8601String(),
        'imageQuality': imageQuality.toStorage(),
        'localizationType': localizationType.toStorage(),
        if (regionNorm != null) 'regionNorm': regionNorm!.toJson(),
        'modelExplanation': modelExplanation,
        if (rawModelOutputs != null) 'rawModelOutputs': rawModelOutputs,
        'isInvalidated': isInvalidated,
        if (photoIndex != null) 'photoIndex': photoIndex,
      };
}

class PmObservationEvent {
  final String id;
  final String propertyId;
  final String observationId;
  final String? scanId;
  final ObservationEventType eventType;
  final ObservationStatus? fromStatus;
  final ObservationStatus? toStatus;
  final SeverityBand? fromSeverity;
  final SeverityBand? toSeverity;
  final ActorType actor;
  final String summary;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  const PmObservationEvent({
    required this.id,
    required this.propertyId,
    required this.observationId,
    this.scanId,
    required this.eventType,
    this.fromStatus,
    this.toStatus,
    this.fromSeverity,
    this.toSeverity,
    this.actor = ActorType.ai,
    this.summary = '',
    this.payload = const {},
    required this.createdAt,
  });

  factory PmObservationEvent.fromJson(Map<String, dynamic> json) =>
      PmObservationEvent(
        id: json['id'] as String? ?? 'evt_unknown',
        propertyId: json['propertyId'] as String? ?? '',
        observationId: json['observationId'] as String? ?? '',
        scanId: json['scanId'] as String?,
        eventType:
            ObservationEventType.fromStorage(json['eventType'] as String?),
        fromStatus: json['fromStatus'] == null
            ? null
            : ObservationStatus.fromStorage(json['fromStatus'] as String?),
        toStatus: json['toStatus'] == null
            ? null
            : ObservationStatus.fromStorage(json['toStatus'] as String?),
        fromSeverity: json['fromSeverity'] == null
            ? null
            : SeverityBand.fromStorage(json['fromSeverity'] as String?),
        toSeverity: json['toSeverity'] == null
            ? null
            : SeverityBand.fromStorage(json['toSeverity'] as String?),
        actor: ActorType.fromStorage(json['actor'] as String?),
        summary: json['summary'] as String? ?? '',
        payload: json['payload'] is Map
            ? Map<String, dynamic>.from(json['payload'] as Map)
            : const {},
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'propertyId': propertyId,
        'observationId': observationId,
        if (scanId != null) 'scanId': scanId,
        'eventType': eventType.toStorage(),
        if (fromStatus != null) 'fromStatus': fromStatus!.toStorage(),
        if (toStatus != null) 'toStatus': toStatus!.toStorage(),
        if (fromSeverity != null) 'fromSeverity': fromSeverity!.toStorage(),
        if (toSeverity != null) 'toSeverity': toSeverity!.toStorage(),
        'actor': actor.toStorage(),
        'summary': summary,
        'payload': payload,
        'createdAt': createdAt.toIso8601String(),
      };
}

/// Internal detection produced by the mapper (not persisted as its own table).
class PmDetection {
  final String title;
  final String description;
  final SurfaceType surfaceType;
  final ObservationCategory category;
  final SeverityBand severityBand;
  final ConfidenceBand confidence;
  final ImageQualityBand imageQuality;
  final LocalizationType localizationType;
  final RegionNorm? regionNorm;
  final String? twinAnchorId;
  final String? zoneHint;
  final String? captureSlot;
  final int? photoIndex;
  final String? sourceIssueFingerprint;
  final String modelExplanation;

  const PmDetection({
    required this.title,
    this.description = '',
    required this.surfaceType,
    required this.category,
    required this.severityBand,
    required this.confidence,
    this.imageQuality = ImageQualityBand.usable,
    this.localizationType = LocalizationType.unlocalized,
    this.regionNorm,
    this.twinAnchorId,
    this.zoneHint,
    this.captureSlot,
    this.photoIndex,
    this.sourceIssueFingerprint,
    this.modelExplanation = '',
  });

  factory PmDetection.fromJson(Map<String, dynamic> json) => PmDetection(
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        surfaceType: SurfaceType.fromStorage(json['surfaceType'] as String?),
        category: ObservationCategory.fromStorage(json['category'] as String?),
        severityBand: SeverityBand.fromStorage(json['severityBand'] as String?),
        confidence: ConfidenceBand.fromStorage(json['confidence'] as String?),
        imageQuality:
            ImageQualityBand.fromStorage(json['imageQuality'] as String?),
        localizationType:
            LocalizationType.fromStorage(json['localizationType'] as String?),
        regionNorm: json['regionNorm'] is Map
            ? RegionNorm.fromJson(
                Map<String, dynamic>.from(json['regionNorm'] as Map),
              )
            : null,
        twinAnchorId: json['twinAnchorId'] as String?,
        zoneHint: json['zoneHint'] as String?,
        captureSlot: json['captureSlot'] as String?,
        photoIndex: (json['photoIndex'] as num?)?.round(),
        sourceIssueFingerprint: json['sourceIssueFingerprint'] as String?,
        modelExplanation: json['modelExplanation'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'surfaceType': surfaceType.toStorage(),
        'category': category.toStorage(),
        'severityBand': severityBand.toStorage(),
        'confidence': confidence.toStorage(),
        'imageQuality': imageQuality.toStorage(),
        'localizationType': localizationType.toStorage(),
        if (regionNorm != null) 'regionNorm': regionNorm!.toJson(),
        if (twinAnchorId != null) 'twinAnchorId': twinAnchorId,
        if (zoneHint != null) 'zoneHint': zoneHint,
        if (captureSlot != null) 'captureSlot': captureSlot,
        if (photoIndex != null) 'photoIndex': photoIndex,
        if (sourceIssueFingerprint != null)
          'sourceIssueFingerprint': sourceIssueFingerprint,
        'modelExplanation': modelExplanation,
      };
}

/// Single-document persistence for one property per install.
class PmPropertyMemoryBundle {
  final PmProperty property;
  final List<PmSurface> surfaces;
  final List<PmScan> scans;
  final List<PmObservation> observations;
  final List<PmEvidence> evidence;
  final List<PmObservationEvent> events;

  const PmPropertyMemoryBundle({
    required this.property,
    this.surfaces = const [],
    this.scans = const [],
    this.observations = const [],
    this.evidence = const [],
    this.events = const [],
  });

  PmPropertyMemoryBundle copyWith({
    PmProperty? property,
    List<PmSurface>? surfaces,
    List<PmScan>? scans,
    List<PmObservation>? observations,
    List<PmEvidence>? evidence,
    List<PmObservationEvent>? events,
  }) {
    return PmPropertyMemoryBundle(
      property: property ?? this.property,
      surfaces: surfaces ?? this.surfaces,
      scans: scans ?? this.scans,
      observations: observations ?? this.observations,
      evidence: evidence ?? this.evidence,
      events: events ?? this.events,
    );
  }

  factory PmPropertyMemoryBundle.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) parse) {
      final raw = json[key] as List<dynamic>? ?? const [];
      return [
        for (final e in raw)
          parse(Map<String, dynamic>.from(e as Map)),
      ];
    }

    return PmPropertyMemoryBundle(
      property: PmProperty.fromJson(
        (json['property'] as Map<String, dynamic>?) ?? const {},
      ),
      surfaces: list('surfaces', PmSurface.fromJson),
      scans: list('scans', PmScan.fromJson),
      observations: list('observations', PmObservation.fromJson),
      evidence: list('evidence', PmEvidence.fromJson),
      events: list('events', PmObservationEvent.fromJson),
    );
  }

  Map<String, dynamic> toJson() => {
        'property': property.toJson(),
        'surfaces': surfaces.map((e) => e.toJson()).toList(),
        'scans': scans.map((e) => e.toJson()).toList(),
        'observations': observations.map((e) => e.toJson()).toList(),
        'evidence': evidence.map((e) => e.toJson()).toList(),
        'events': events.map((e) => e.toJson()).toList(),
      };
}

/// Result of a reconcile pass.
class PmReconcileResult {
  final PmPropertyMemoryBundle bundle;
  final List<PmObservationEvent> newEvents;
  final ScanMode mode;

  const PmReconcileResult({
    required this.bundle,
    required this.newEvents,
    required this.mode,
  });
}
