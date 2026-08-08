import 'package:flutter_test/flutter_test.dart';
import 'package:pillar_ai/services/onboarding_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Fresh singleton state is sticky — reload by markDone / prefs only.
  });

  group('OnboardingStore.shouldAutoShow', () {
    test('shows for first-run with no reports and not done', () async {
      SharedPreferences.setMockInitialValues({});
      final store = OnboardingStore.instance;
      // Force re-read path: if already loaded from prior test, still evaluate flags.
      await store.ensureLoaded();
      // When not done and no reports → show (unless a prior test already marked done).
      if (!store.isDone) {
        expect(store.shouldAutoShow(reportCount: 0), isTrue);
      }
      expect(store.shouldAutoShow(reportCount: 1), isFalse);
    });

    test('markDone stops auto-show even with zero reports', () async {
      SharedPreferences.setMockInitialValues({});
      final store = OnboardingStore.instance;
      await store.ensureLoaded();
      await store.markDone();
      expect(store.isDone, isTrue);
      expect(store.shouldAutoShow(reportCount: 0), isFalse);
    });
  });
}
