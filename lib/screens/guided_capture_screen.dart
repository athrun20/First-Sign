import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../models/capture_models.dart';
import '../services/capture_assistant_service.dart';
import '../services/capture_draft_store.dart';
import '../services/photo_quality_service.dart';
import '../services/storage_exception.dart';
import '../theme/app_lux.dart';
import '../widgets/closer_photo_tip.dart';
import '../widgets/smart_capture_assistant.dart';
import 'photo_review_screen.dart';

/// Quick Scan tokens — aliases of [AppLux].
abstract final class _QsLux {
  static const bg = AppLux.bg;
  static const surface = AppLux.surface;
  static const border = AppLux.border;
  static const charcoal = AppLux.charcoal;
  static const body = AppLux.body;
  static const muted = AppLux.muted;
  static const teal = AppLux.teal;
  static const tealMist = AppLux.tealMist;
  static const gold = AppLux.gold;
  static const goldSoft = AppLux.goldSoft;
}

/// Guided multi-photo capture: checklist, tips, progress, quality gates.
///
/// Set [singlePhotoMode] for Quick Scan (one photo, optional area tag).
class GuidedCaptureScreen extends StatefulWidget {
  const GuidedCaptureScreen({
    super.key,
    this.seedPhotos = const [],
    this.focusSlot,
    this.retakeMode = false,
    this.retakeFindingTitle,
    this.singlePhotoMode = false,
  });

  /// Pre-fill checklist from a previous capture (retake flow).
  final List<CapturePhoto> seedPhotos;

  /// Jump focus to this slot (e.g. roof) when retaking a weak finding.
  final CaptureShotId? focusSlot;

  /// Finding-linked re-capture: seed other shots, clear [focusSlot], return
  /// photos to the report for re-analysis instead of a full new capture.
  final bool retakeMode;

  /// Finding title shown in the retake banner (e.g. "Missing / Damaged Shingles").
  final String? retakeFindingTitle;

  /// Quick Scan: one photo of any exterior area (bypasses full 6-shot checklist).
  final bool singlePhotoMode;

  @override
  State<GuidedCaptureScreen> createState() => _GuidedCaptureScreenState();
}

class _GuidedCaptureScreenState extends State<GuidedCaptureScreen> {
  final _picker = ImagePicker();

  late List<CaptureSlot> _slots;
  final List<ExtraCloseup> _extraCloseups = [];

  /// Slot focused for tips / next action (index into [_slots]).
  int _focusIndex = 0;
  bool _busy = false;
  String? _busyLabel;

  /// Quick Scan optional area tag (improves analysis slot binding).
  int _quickAreaIndex = 0;

  /// Short-lived Smart Capture Assistant feedback after a quality check.
  AssistantAdvice? _flashFeedback;
  Timer? _flashTimer;

  bool get _isQuickScan => widget.singlePhotoMode && !widget.retakeMode;

  QuickScanAreaOption get _quickArea =>
      kQuickScanAreaOptions[_quickAreaIndex.clamp(
        0,
        kQuickScanAreaOptions.length - 1,
      )];

  @override
  void initState() {
    super.initState();
    _slots = _isQuickScan
        ? [CaptureSlot(def: kQuickScanShotDef)]
        : [for (final def in kGuidedShotChecklist) CaptureSlot(def: def)];
    _applySeedPhotos();
    if (widget.focusSlot != null) {
      final i = _slots.indexWhere((s) => s.def.id == widget.focusSlot);
      if (i >= 0) {
        _focusIndex = i;
        // Retake mode: clear the focused slot so the homeowner must replace it.
        if (widget.retakeMode && _slots[i].photo != null) {
          _slots[i] = _slots[i].copyWith(clearPhoto: true);
        }
      }
      // Quick Scan: map focus slot to an area chip when possible.
      if (_isQuickScan) {
        final areaIdx = kQuickScanAreaOptions.indexWhere(
          (o) => o.slotId == widget.focusSlot,
        );
        if (areaIdx >= 0) _quickAreaIndex = areaIdx;
      }
    } else {
      final empty = _slots.indexWhere((s) => !s.isReady);
      if (empty >= 0) _focusIndex = empty;
    }
    if (widget.retakeMode) {
      _flashFeedback = AssistantAdvice(
        tone: AssistantTone.progress,
        headline: widget.retakeFindingTitle != null
            ? 'Retake for “${widget.retakeFindingTitle}”'
            : 'Retake this finding’s photo',
        body: _focusSlot.def.tip,
        icon: Icons.photo_camera_front_outlined,
      );
    } else if (_isQuickScan) {
      _flashFeedback = const AssistantAdvice(
        tone: AssistantTone.progress,
        headline: 'Quick Scan · one clear photo',
        body:
            'Capture the exterior area that concerns you. Tag the zone optionally, '
            'then continue for a calm, focused screening.',
        icon: Icons.bolt_rounded,
      );
    }
  }

  bool get _retakeFocusReady {
    if (!widget.retakeMode || widget.focusSlot == null) return false;
    final i = _slots.indexWhere((s) => s.def.id == widget.focusSlot);
    if (i < 0) return false;
    return _slots[i].isReady;
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    super.dispose();
  }

  void _setFlashFeedback(
    AssistantAdvice advice, {
    Duration hold = const Duration(seconds: 6),
  }) {
    _flashTimer?.cancel();
    setState(() => _flashFeedback = advice);
    _flashTimer = Timer(hold, () {
      if (!mounted) return;
      setState(() => _flashFeedback = null);
    });
  }

  void _setFocus(int index) {
    if (index < 0 || index >= _slots.length) return;
    setState(() {
      _focusIndex = index;
      // Clear flash when user switches shots so tips stay relevant.
      _flashFeedback = null;
    });
    _flashTimer?.cancel();
  }

  bool get _hasLowDetailAccepted {
    for (final slot in _slots) {
      if (slot.photo != null && (slot.quality?.isDarkOrLowDetail ?? false)) {
        return true;
      }
    }
    for (final extra in _extraCloseups) {
      if (extra.quality?.isDarkOrLowDetail ?? false) return true;
    }
    return false;
  }

  void _applySeedPhotos() {
    if (widget.seedPhotos.isEmpty) return;
    if (_isQuickScan && _slots.isNotEmpty && _slots.first.photo == null) {
      final first = widget.seedPhotos.first;
      _slots[0] = CaptureSlot(
        def: _slots[0].def,
        photo: first.file,
        quality: const PhotoQualityResult(ok: true),
      );
      return;
    }
    for (final photo in widget.seedPhotos) {
      final slotId = photo.slotId;
      if (slotId == null) continue;
      final i = _slots.indexWhere((s) => s.def.id == slotId);
      if (i < 0) continue;
      // Required checklist slots: first match only.
      if (_slots[i].photo != null && slotId == CaptureShotId.problemCloseup) {
        _extraCloseups.add(ExtraCloseup(photo: photo.file));
        continue;
      }
      if (_slots[i].photo == null) {
        _slots[i] = CaptureSlot(
          def: _slots[i].def,
          photo: photo.file,
          quality: const PhotoQualityResult(ok: true),
        );
      } else if (slotId == CaptureShotId.problemCloseup) {
        _extraCloseups.add(ExtraCloseup(photo: photo.file));
      }
    }
    // Seed photos without slot → extras.
    for (final photo in widget.seedPhotos) {
      if (photo.slotId != null) continue;
      _extraCloseups.add(ExtraCloseup(photo: photo.file));
    }
  }

  int get _filledRequired =>
      _slots.where((s) => s.def.required && s.isReady).length;

  int get _requiredTotal => _slots.where((s) => s.def.required).length;

  double get _progress =>
      _requiredTotal == 0 ? 0 : _filledRequired / _requiredTotal;

  bool get _canContinue {
    if (widget.retakeMode) {
      // Finding retake: focused replacement shot must be ready (or any photo
      // if no focus was specified).
      if (widget.focusSlot != null) return _retakeFocusReady;
      return _slots.any((s) => s.isReady) || _extraCloseups.isNotEmpty;
    }
    // Quick Scan: a single accepted photo is enough.
    if (_isQuickScan) {
      return _slots.any((s) => s.isReady);
    }
    return _slots.every((s) => !s.def.required || s.isReady) &&
        _extraCloseups.every((e) => e.isReady);
  }

  List<CapturePhoto> get _allCapturePhotos {
    final list = <CapturePhoto>[];
    for (final s in _slots) {
      if (s.photo == null) continue;
      if (_isQuickScan) {
        list.add(
          CapturePhoto(
            file: s.photo!,
            slotId: _quickArea.slotId,
            label: _quickArea.label,
            index: list.length,
          ),
        );
        continue;
      }
      list.add(
        CapturePhoto(
          file: s.photo!,
          slotId: s.def.id,
          label: s.def.title,
          index: list.length,
        ),
      );
    }
    if (_isQuickScan) return list;
    for (var i = 0; i < _extraCloseups.length; i++) {
      list.add(
        CapturePhoto(
          file: _extraCloseups[i].photo,
          slotId: CaptureShotId.problemCloseup,
          label: _extraCloseups.length == 1
              ? 'Extra close-up'
              : 'Extra close-up ${i + 1}',
          index: list.length,
        ),
      );
    }
    return list;
  }

  List<XFile> get _allPhotos => _allCapturePhotos.map((p) => p.file).toList();

  CaptureSlot get _focusSlot => _slots[_focusIndex.clamp(0, _slots.length - 1)];

  void _focusNextEmpty() {
    final empty = _slots.indexWhere((s) => !s.isReady);
    if (empty >= 0) {
      _setFocus(empty);
    }
  }

  String get _sessionSuggestion => CaptureAssistantService.sessionSuggestion(
    slots: _slots,
    filledRequired: _filledRequired,
    requiredTotal: _requiredTotal,
    extraCount: _extraCloseups.length,
    focusId: _focusSlot.def.id,
  );

  Future<void> _withBusy(String label, Future<void> Function() work) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyLabel = label;
    });
    try {
      await work();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
      }
    }
  }

  Future<void> _assignToSlot(int index, XFile file) async {
    final quality = await PhotoQualityService.check(file);
    if (!mounted) return;

    final def = _slots[index].def;
    final feedback = CaptureAssistantService.feedbackForQuality(
      quality,
      shotTitle: def.title,
    );
    // Show assistant feedback immediately while user decides on warnings.
    _setFlashFeedback(feedback);
    setState(() => _focusIndex = index);

    var accepted = quality.ok;
    var acceptedWithWarnings = false;
    if (!quality.ok || quality.hasWarnings) {
      final decision = await _showQualityDialog(
        title: def.title,
        quality: quality,
        feedback: feedback,
      );
      if (!mounted) return;
      if (decision == null || decision == _QualityChoice.retake) {
        _setFlashFeedback(
          CaptureAssistantService.adviceForShot(def, filled: false),
          hold: const Duration(seconds: 4),
        );
        return;
      }
      accepted = true;
      acceptedWithWarnings = true;
    }

    setState(() {
      _slots[index] = _slots[index].copyWith(
        photo: file,
        quality: quality,
        acceptedWithWarnings: acceptedWithWarnings || quality.hasWarnings,
      );
    });
    await _persistDraft();

    _setFlashFeedback(
      CaptureAssistantService.feedbackForQuality(
        quality,
        shotTitle: def.title,
        acceptedWithWarnings: acceptedWithWarnings || quality.hasWarnings,
      ),
    );

    // Advance focus to next empty when this slot is good.
    if (accepted) {
      final next = _slots.indexWhere((s) => !s.isReady);
      if (next >= 0 && next != index) {
        // Brief pause so user sees feedback, then coach the next shot.
        await Future<void>.delayed(const Duration(milliseconds: 450));
        if (!mounted) return;
        _setFocus(next);
        _setFlashFeedback(
          CaptureAssistantService.adviceForShot(
            _slots[next].def,
            filled: false,
          ),
          hold: const Duration(seconds: 5),
        );
      }
    }
  }

  Future<void> _addExtraCloseup(XFile file) async {
    final quality = await PhotoQualityService.check(file);
    if (!mounted) return;

    final feedback = CaptureAssistantService.feedbackForQuality(
      quality,
      shotTitle: 'Extra close-up',
    );
    _setFlashFeedback(feedback);

    if (!quality.ok || quality.hasWarnings) {
      final decision = await _showQualityDialog(
        title: 'Extra close-up',
        quality: quality,
        feedback: feedback,
      );
      if (!mounted) return;
      if (decision == null || decision == _QualityChoice.retake) return;
    }

    setState(() {
      _extraCloseups.add(
        ExtraCloseup(
          photo: file,
          quality: quality,
          acceptedWithWarnings: !quality.ok || quality.hasWarnings,
        ),
      );
    });
    await _persistDraft();
    _setFlashFeedback(
      CaptureAssistantService.feedbackForQuality(
        quality,
        shotTitle: 'Extra close-up',
        acceptedWithWarnings: !quality.ok || quality.hasWarnings,
      ),
    );
  }

  Future<_QualityChoice?> _showQualityDialog({
    required String title,
    required PhotoQualityResult quality,
    AssistantAdvice? feedback,
  }) {
    final hardFail = !quality.ok;
    final advice =
        feedback ??
        CaptureAssistantService.feedbackForQuality(quality, shotTitle: title);
    final score = CaptureAssistantService.qualityScore(quality);

    return showModalBottomSheet<_QualityChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(advice.icon, color: advice.accentColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        advice.headline,
                        style: GoogleFonts.inter(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppLux.charcoal,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: advice.accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Score $score',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: advice.accentColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Smart Capture Assistant · $title',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppLux.body,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  advice.body,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    height: 1.4,
                    color: AppLux.charcoal,
                  ),
                ),
                if (quality.warnings.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final w in quality.warnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '•  ',
                            style: GoogleFonts.inter(
                              color: advice.accentColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              w,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                height: 1.4,
                                color: AppLux.charcoal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                if (advice.quickTips.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  for (final t in advice.quickTips.take(2))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('→  '),
                          Expanded(
                            child: Text(
                              t,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                height: 1.35,
                                color: AppLux.body,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, _QualityChoice.retake),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppLux.teal,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    hardFail ? 'Retake photo' : 'Got it — retake',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, _QualityChoice.useAnyway),
                  child: Text(
                    hardFail ? 'Use this photo anyway' : 'Keep this photo',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: AppLux.body,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _takeWithCamera(int index) async {
    await _withBusy('Opening camera…', () async {
      try {
        final file = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: kIsWeb ? null : 88,
          maxWidth: kIsWeb ? null : 2400,
          requestFullMetadata: false,
        );
        if (file == null || !mounted) return;
        await _assignToSlot(index, file);
      } catch (e) {
        _toast('Camera unavailable: $e. Try gallery instead.');
      }
    });
  }

  Future<void> _pickGalleryForSlot(int index) async {
    await _withBusy('Opening gallery…', () async {
      try {
        final file = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: kIsWeb ? null : 88,
          maxWidth: kIsWeb ? null : 2400,
          requestFullMetadata: false,
        );
        if (file == null || !mounted) return;
        await _assignToSlot(index, file);
      } catch (e) {
        _toast('Could not open gallery: $e');
      }
    });
  }

  /// Multi-select: fills empty required slots in order, then extras.
  Future<void> _pickMultiFromGallery() async {
    await _withBusy('Opening gallery…', () async {
      try {
        final files = await _picker.pickMultiImage(
          imageQuality: kIsWeb ? null : 88,
          maxWidth: kIsWeb ? null : 2400,
          requestFullMetadata: false,
        );
        if (files.isEmpty || !mounted) return;

        var cursor = 0;
        for (var i = 0; i < _slots.length && cursor < files.length; i++) {
          if (_slots[i].isReady) continue;
          await _assignToSlot(i, files[cursor]);
          cursor++;
          if (!mounted) return;
        }
        // Remaining → extra close-ups
        while (cursor < files.length) {
          await _addExtraCloseup(files[cursor]);
          cursor++;
          if (!mounted) return;
        }
        if (mounted) {
          _toast('Photos added to empty checklist slots.');
          _focusNextEmpty();
        }
      } catch (e) {
        _toast('Could not pick photos: $e');
      }
    });
  }

  Future<void> _addExtraFromCamera() async {
    await _withBusy('Opening camera…', () async {
      try {
        final file = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: kIsWeb ? null : 88,
          maxWidth: kIsWeb ? null : 2400,
          requestFullMetadata: false,
        );
        if (file == null || !mounted) return;
        await _addExtraCloseup(file);
      } catch (e) {
        _toast('Camera unavailable: $e');
      }
    });
  }

  Future<void> _addExtraFromGallery() async {
    await _withBusy('Opening gallery…', () async {
      try {
        final files = await _picker.pickMultiImage(
          imageQuality: kIsWeb ? null : 88,
          maxWidth: kIsWeb ? null : 2400,
          requestFullMetadata: false,
        );
        for (final f in files) {
          if (!mounted) return;
          await _addExtraCloseup(f);
        }
      } catch (e) {
        _toast('Could not pick photos: $e');
      }
    });
  }

  void _clearSlot(int index) {
    _flashTimer?.cancel();
    setState(() {
      _slots[index] = _slots[index].copyWith(clearPhoto: true);
      _focusIndex = index;
      _flashFeedback = CaptureAssistantService.adviceForShot(
        _slots[index].def,
        filled: false,
      );
    });
    _persistDraft();
  }

  void _removeExtra(int index) {
    setState(() => _extraCloseups.removeAt(index));
    _persistDraft();
  }

  Future<void> _persistDraft() async {
    final photos = _allCapturePhotos;
    if (photos.isEmpty) {
      await CaptureDraftStore.instance.clear();
      return;
    }
    try {
      await CaptureDraftStore.instance.saveDraft(
        photos: photos,
        focusSlot: _focusSlot.def.id,
      );
    } on StorageFullException catch (e) {
      if (!mounted) return;
      _toast(e.userMessage);
    }
  }

  void _continue() {
    if (widget.retakeMode) {
      if (!_retakeFocusReady && widget.focusSlot != null) {
        _toast('Take a new ${_focusSlot.def.shortLabel} photo first.');
        final i = _slots.indexWhere((s) => s.def.id == widget.focusSlot);
        if (i >= 0) _setFocus(i);
        return;
      }
      if (_allCapturePhotos.isEmpty) {
        _toast('Add at least one photo before re-running analysis.');
        return;
      }
      CaptureDraftStore.instance.clear();
      Navigator.of(context).pop<List<CapturePhoto>>(_allCapturePhotos);
      return;
    }

    if (!_canContinue) {
      if (_isQuickScan) {
        _toast('Add one clear photo of the area you want screened.');
        return;
      }
      final missing = _slots
          .where((s) => s.def.required && !s.isReady)
          .map((s) => s.def.shortLabel)
          .join(', ');
      _toast(
        missing.isEmpty
            ? 'Finish photo checks before continuing.'
            : 'Still need: $missing',
      );
      _focusNextEmpty();
      return;
    }
    // Checklist complete — clear in-progress draft before review.
    CaptureDraftStore.instance.clear();
    final photos = _allCapturePhotos;
    if (_isQuickScan) {
      // Soft fade into review — keeps Quick Scan feeling intentional.
      Navigator.of(context).push(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 420),
          reverseTransitionDuration: const Duration(milliseconds: 280),
          pageBuilder: (context, animation, secondaryAnimation) {
            return PhotoReviewScreen(
              photos: photos,
              lowDetailHint: _hasLowDetailAccepted,
            );
          },
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.03),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
          settings: RouteSettings(name: '/photo-review', arguments: photos),
        ),
      );
      return;
    }
    Navigator.of(context).pushNamed(
      '/photo-review',
      arguments: {
        'photos': photos,
        'lowDetailHint': _hasLowDetailAccepted,
      },
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter()),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showShotActions(int index) async {
    final slot = _slots[index];
    _setFocus(index);
    final tips = CaptureAssistantService.quickTipsFor(slot.def.id);
    final advice = CaptureAssistantService.adviceForShot(
      slot.def,
      filled: slot.isReady,
      quality: slot.quality,
      acceptedWithWarnings: slot.acceptedWithWarnings,
    );

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            advice.icon,
                            size: 20,
                            color: advice.accentColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              slot.def.title,
                              style: GoogleFonts.inter(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: AppLux.charcoal,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        advice.body,
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          height: 1.4,
                          color: AppLux.body,
                        ),
                      ),
                      if (tips.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Quick tips',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppLux.muted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        for (final t in tips.take(2))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '· $t',
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                height: 1.35,
                                color: AppLux.body,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.photo_camera_rounded,
                    color: AppLux.teal,
                  ),
                  title: Text(
                    slot.isFilled ? 'Retake with camera' : 'Take with camera',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _takeWithCamera(index);
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.photo_library_outlined,
                    color: AppLux.charcoal,
                  ),
                  title: Text(
                    slot.isFilled
                        ? 'Replace from gallery'
                        : 'Choose from gallery',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickGalleryForSlot(index);
                  },
                ),
                if (slot.isFilled)
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline_rounded,
                      color: Color(0xFFDC2626),
                    ),
                    title: Text(
                      'Remove photo',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFDC2626),
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _clearSlot(index);
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final focus = _focusSlot;

    return Scaffold(
      backgroundColor: AppLux.bg,
      appBar: AppBar(
        backgroundColor: _isQuickScan ? _QsLux.bg : null,
        surfaceTintColor: Colors.transparent,
        elevation: _isQuickScan ? 0 : null,
        title: Text(
          widget.retakeMode
              ? 'Fix this finding'
              : _isQuickScan
              ? 'Quick Scan'
              : 'Guided capture',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: _isQuickScan ? 17 : null,
            letterSpacing: _isQuickScan ? -0.2 : null,
            color: _isQuickScan ? _QsLux.charcoal : null,
          ),
        ),
        iconTheme: _isQuickScan
            ? const IconThemeData(color: _QsLux.charcoal)
            : null,
        actions: [
          if (!widget.retakeMode && !_isQuickScan)
            IconButton(
              tooltip: 'Multi-select from gallery',
              onPressed: _busy ? null : _pickMultiFromGallery,
              icon: Icon(
                Icons.photo_library_outlined,
                size: 20,
                color: AppLux.charcoalMid.withValues(alpha: 0.85),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (widget.retakeMode)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppLux.teal.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.auto_fix_high_rounded,
                        color: AppLux.teal,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.retakeFindingTitle != null
                                  ? 'Retaking for “${widget.retakeFindingTitle}”'
                                  : 'Finding re-capture',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppLux.charcoal,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Replace the ${_focusSlot.def.title.toLowerCase()} shot in good light, then re-run analysis. Other angles stay from your last set.',
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                height: 1.35,
                                color: AppLux.body,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              // Progress / guidance header
              if (_isQuickScan)
                _buildQuickScanHeader()
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.retakeMode
                                  ? (_retakeFocusReady
                                        ? 'New ${_focusSlot.def.shortLabel} ready — re-run analysis'
                                        : 'Take a new ${_focusSlot.def.shortLabel} photo')
                                  : '$_filledRequired of $_requiredTotal ready',
                              style: GoogleFonts.inter(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: AppLux.charcoal,
                                letterSpacing: -0.25,
                              ),
                            ),
                          ),
                          if (!widget.retakeMode)
                            Text(
                              '${(_progress * 100).round()}%',
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppLux.muted,
                                letterSpacing: -0.1,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: _progress,
                          minHeight: 5,
                          backgroundColor: AppLux.borderSoft,
                          color: AppLux.teal,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Roof, walls, gutters & foundation — multi-angle screening.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppLux.muted,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

              // Capture coach + checklist
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    _isQuickScan ? 18 : 14,
                    20,
                    _isQuickScan ? 16 : 12,
                  ),
                  children: [
                    Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SmartCaptureAssistant(
                              shot: focus.def,
                              shotNumber: _focusIndex + 1,
                              totalShots: _slots.length,
                              filled: focus.isReady,
                              quality: focus.quality,
                              acceptedWithWarnings: focus.acceptedWithWarnings,
                              flashFeedback: _flashFeedback,
                              sessionSuggestion: _isQuickScan
                                  ? (_canContinue
                                        ? 'Photo looks ready. Tag the area if you like, then continue to screening.'
                                        : 'Take or choose one clear photo — full elevation or a focused close-up.')
                                  : _sessionSuggestion,
                              onCamera: _busy
                                  ? null
                                  : () => _takeWithCamera(_focusIndex),
                              onGallery: _busy
                                  ? null
                                  : () => _pickGalleryForSlot(_focusIndex),
                            ),
                            if (_hasLowDetailAccepted) ...[
                              const SizedBox(height: 14),
                              const CloserPhotoCaptureHint(),
                            ],
                            if (_isQuickScan) ...[
                              const SizedBox(height: 28),
                              _buildQuickScanAreaCard(),
                            ] else ...[
                              const SizedBox(height: 22),
                              Text(
                                'CHECKLIST',
                                style: GoogleFonts.inter(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppLux.muted,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(height: 10),
                              for (var i = 0; i < _slots.length; i++)
                                _SlotTile(
                                  index: i,
                                  slot: _slots[i],
                                  focused: i == _focusIndex,
                                  onTap: () => _showShotActions(i),
                                ),
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  Text(
                                    'Extra close-ups',
                                    style: GoogleFonts.inter(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppLux.charcoal,
                                      letterSpacing: -0.15,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Optional',
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                      color: AppLux.muted,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Add a problem area if you already see one.',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppLux.muted,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (_extraCloseups.isEmpty)
                                Text(
                                  'None yet',
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    color: AppLux.muted.withValues(alpha: 0.85),
                                  ),
                                )
                              else
                                SizedBox(
                                  height: 88,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _extraCloseups.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(width: 8),
                                    itemBuilder: (context, i) {
                                      return _ExtraThumb(
                                        photo: _extraCloseups[i].photo,
                                        onRemove: () => _removeExtra(i),
                                      );
                                    },
                                  ),
                                ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed:
                                          _busy ? null : _addExtraFromCamera,
                                      icon: const Icon(
                                        Icons.photo_camera_outlined,
                                        size: 17,
                                      ),
                                      label: const Text('Camera'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppLux.charcoalMid,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        side: const BorderSide(
                                          color: AppLux.border,
                                          width: 0.85,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed:
                                          _busy ? null : _addExtraFromGallery,
                                      icon: const Icon(
                                        Icons.add_photo_alternate_outlined,
                                        size: 17,
                                      ),
                                      label: const Text('Gallery'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppLux.charcoalMid,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        side: const BorderSide(
                                          color: AppLux.border,
                                          width: 0.85,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Continue bar
              Container(
                padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + bottom),
                decoration: BoxDecoration(
                  color: _isQuickScan ? _QsLux.surface : AppLux.surface,
                  border: Border(
                    top: BorderSide(
                      color: _isQuickScan ? _QsLux.border : AppLux.border,
                      width: 0.75,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppLux.charcoal.withValues(alpha: 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Align(
                  alignment: Alignment.center,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!_canContinue)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              widget.retakeMode
                                  ? 'Capture a new ${_focusSlot.def.shortLabel} shot, then re-run analysis.'
                                  : _isQuickScan
                                  ? 'Add one clear photo to continue.'
                                  : 'Complete all 6 shots to continue.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: _isQuickScan
                                    ? _QsLux.muted
                                    : AppLux.muted,
                              ),
                            ),
                          )
                        else if (_isQuickScan)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              'Tagged: ${_quickArea.label}'
                              '${_quickArea.hint.isNotEmpty ? ' · ${_quickArea.hint}' : ''}',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: _QsLux.body,
                                height: 1.4,
                              ),
                            ),
                          ),
                        FilledButton(
                          onPressed: (_busy || !_canContinue) ? null : _continue,
                          style: FilledButton.styleFrom(
                            backgroundColor: _canContinue
                                ? (_isQuickScan ? _QsLux.teal : AppLux.tealDeep)
                                : const Color(0xFFD6D3D1),
                            disabledBackgroundColor: const Color(0xFFE7E5E4),
                            foregroundColor: Colors.white,
                            disabledForegroundColor: const Color(0xFFA8A29E),
                            minimumSize: const Size(double.infinity, 52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                _isQuickScan ? 16 : 14,
                              ),
                            ),
                            elevation: 0,
                            textStyle: GoogleFonts.inter(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.15,
                            ),
                          ),
                          child: Text(
                            widget.retakeMode
                                ? (_canContinue
                                      ? 'Re-run analysis with new photo'
                                      : 'Retake ${_focusSlot.def.shortLabel} first')
                                : _isQuickScan
                                ? (_canContinue
                                      ? 'Continue to screening'
                                      : 'Add a photo first')
                                : (_canContinue
                                      ? 'Review ${_allPhotos.length} photos'
                                      : 'Review photos'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_busy)
            Container(
              color: Colors.black.withValues(alpha: _isQuickScan ? 0.28 : 0.25),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(_isQuickScan ? 18 : 16),
                    border: _isQuickScan
                        ? Border.all(color: _QsLux.border, width: 0.75)
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: _isQuickScan ? _QsLux.teal : AppLux.teal,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _busyLabel ?? 'Working…',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: _isQuickScan
                              ? _QsLux.charcoal
                              : AppLux.charcoal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Calm luxury header for single-photo Quick Scan only.
  Widget _buildQuickScanHeader() {
    final ready = _canContinue;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: _QsLux.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _QsLux.border, width: 0.75),
          boxShadow: [
            BoxShadow(
              color: _QsLux.charcoal.withValues(alpha: 0.03),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: ready
                        ? _QsLux.tealMist
                        : _QsLux.goldSoft.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    ready ? Icons.check_rounded : Icons.bolt_rounded,
                    size: 20,
                    color: ready ? _QsLux.teal : _QsLux.gold,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ready
                            ? 'Photo ready for screening'
                            : 'One photo · calm & focused',
                        style: GoogleFonts.inter(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: _QsLux.charcoal,
                          letterSpacing: -0.25,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        ready ? '1 of 1 captured' : 'Step 1 of 1',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: ready ? _QsLux.teal : _QsLux.muted,
                          letterSpacing: 0.15,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: ready ? 1.0 : 0.12,
                minHeight: 5,
                backgroundColor: _QsLux.border,
                color: _QsLux.teal,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              ready
                  ? 'Optional: refine the area tag below, then continue for a focused single-angle screening.'
                  : 'Photograph any exterior concern — wall, roof, or close-up. '
                        'Single-angle screening is faster; a full 6-shot set is more thorough.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: _QsLux.body,
                height: 1.5,
                letterSpacing: 0.05,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Refined optional problem-area tag chips (Quick Scan only).
  Widget _buildQuickScanAreaCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: _QsLux.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _QsLux.border, width: 0.75),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Area tag',
                style: GoogleFonts.inter(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: _QsLux.charcoal,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _QsLux.goldSoft.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Optional',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _QsLux.gold,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Helps screening prioritize the right systems. Leave as General if you are unsure.',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: _QsLux.body,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < kQuickScanAreaOptions.length; i++)
                _QuickAreaChip(
                  option: kQuickScanAreaOptions[i],
                  selected: _quickAreaIndex == i,
                  onTap: () => setState(() => _quickAreaIndex = i),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact luxury chip for Quick Scan area tags.
class _QuickAreaChip extends StatelessWidget {
  const _QuickAreaChip({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final QuickScanAreaOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? _QsLux.tealMist : _QsLux.bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? _QsLux.teal.withValues(alpha: 0.45)
                  : _QsLux.border,
              width: selected ? 1.1 : 0.75,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                option.label,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? _QsLux.teal : _QsLux.charcoal,
                  letterSpacing: -0.1,
                ),
              ),
              if (option.hint.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  option.hint,
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    color: selected
                        ? _QsLux.teal.withValues(alpha: 0.75)
                        : _QsLux.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum _QualityChoice { retake, useAnyway }

// ─────────────────────────────────────────────────────────────────────────────

class _SlotTile extends StatelessWidget {
  const _SlotTile({
    required this.index,
    required this.slot,
    required this.focused,
    required this.onTap,
  });

  final int index;
  final CaptureSlot slot;
  final bool focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ready = slot.isReady;
    final hasPhoto = slot.isFilled;
    final warn =
        hasPhoto &&
        slot.quality != null &&
        (!slot.quality!.ok || slot.quality!.hasWarnings);

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: AppLux.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(11, 11, 12, 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: focused
                    ? AppLux.teal.withValues(alpha: 0.4)
                    : AppLux.border,
                width: focused ? 1.25 : 0.85,
              ),
            ),
            child: Row(
              children: [
                // Status / thumb
                SizedBox(
                  width: 48,
                  height: 48,
                  child: Stack(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppLux.cardFill,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: AppLux.border,
                            width: 0.75,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: hasPhoto
                            ? _Thumb(photo: slot.photo!)
                            : Center(
                                child: Text(
                                  '${index + 1}',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w800,
                                    color: AppLux.muted,
                                  ),
                                ),
                              ),
                      ),
                      if (ready)
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: AppLux.teal,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        slot.def.title,
                        style: GoogleFonts.inter(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppLux.charcoal,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ready
                            ? CaptureAssistantService.qualityBadge(
                                slot.quality,
                                accepted: slot.acceptedWithWarnings,
                              )
                            : slot.def.tip,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          height: 1.3,
                          color: ready
                              ? (warn ? AppLux.warning : AppLux.teal)
                              : AppLux.body,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  hasPhoto
                      ? Icons.more_horiz_rounded
                      : Icons.add_a_photo_outlined,
                  color: const Color(0xFF94A3B8),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.photo});
  final XFile photo;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: photo.readAsBytes(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return Image.memory(
          snap.data!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
        );
      },
    );
  }
}

class _ExtraThumb extends StatelessWidget {
  const _ExtraThumb({required this.photo, required this.onRemove});
  final XFile photo;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppLux.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: _Thumb(photo: photo),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: Material(
            color: Colors.black.withValues(alpha: 0.55),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
