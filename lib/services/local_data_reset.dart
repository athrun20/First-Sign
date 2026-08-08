import 'package:flutter/foundation.dart';

import 'branding_store.dart';
import 'capture_draft_store.dart';
import 'contractor_store.dart';
import 'finding_feedback_store.dart';
import 'lead_store.dart';
import 'local_blob_store.dart';
import 'onboarding_store.dart';
import 'profile_store.dart';
import 'report_store.dart';

/// One-tap privacy wipe for everything FirstSign stores on this device.
abstract final class LocalDataReset {
  /// Deletes reports, leads, drafts, branding logo, profile contact fields,
  /// invitee contractors, finding feedback, onboarding flag, and binary blobs.
  static Future<void> wipeAllOnDevice() async {
    await LocalBlobStore.instance.init();

    await ReportStore.instance.clearAll();
    await LeadStore.instance.clearAll();
    await ContractorStore.instance.clearAll();
    await CaptureDraftStore.instance.clear();
    await BrandingStore.instance.clearLogo();
    await ProfileStore.instance.save(
      name: '',
      phone: '',
      email: '',
      address: '',
    );
    await FindingFeedbackStore.instance.clearAll();
    await OnboardingStore.instance.resetLocal();

    try {
      await LocalBlobStore.instance.clearAll();
    } catch (e) {
      debugPrint('LocalDataReset blob wipe: $e');
    }
  }
}
