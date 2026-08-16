import 'package:flutter_test/flutter_test.dart';
import 'package:pillar_ai/services/onboarding_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await OnboardingStore.instance.resetLocal();
    await OnboardingStore.instance.debugReload();
  });

  group('OnboardingStore.shouldAutoShow', () {
    test('shows for first-run with no reports and not done', () async {
      final store = OnboardingStore.instance;
      expect(store.isDone, isFalse);
      expect(store.shouldAutoShow(reportCount: 0), isTrue);
      expect(store.shouldAutoShow(reportCount: 1), isFalse);
    });

    test('markDone stops auto-show even with zero reports', () async {
      final store = OnboardingStore.instance;
      await store.markDone();
      expect(store.isDone, isTrue);
      expect(store.shouldAutoShow(reportCount: 0), isFalse);
    });
  });
}
