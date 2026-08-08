import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pillar_ai/services/local_blob_store.dart';
import 'package:pillar_ai/services/storage_exception.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await LocalBlobStore.instance.init();
  });

  tearDown(() async {
    final store = LocalBlobStore.instance;
    await store.deleteKeys(
      store.keysWithPrefix('report/') +
          store.keysWithPrefix('draft/') +
          store.keysWithPrefix('lead/') +
          [LocalBlobStore.brandingLogoKey],
    );
  });

  test('put/get/delete photo blobs', () async {
    final store = LocalBlobStore.instance;
    final key = LocalBlobStore.reportPhotoKey('r1', 0);
    final bytes = Uint8List.fromList(List.generate(64, (i) => i));
    await store.put(key, bytes);
    final got = await store.get(key);
    expect(got, isNotNull);
    expect(got!.length, 64);
    expect(got[10], 10);
    await store.delete(key);
    expect(await store.get(key), isNull);
  });

  test('deletePrefix removes report photos', () async {
    final store = LocalBlobStore.instance;
    await store.put(LocalBlobStore.reportPhotoKey('r2', 0), Uint8List(8));
    await store.put(LocalBlobStore.reportPhotoKey('r2', 1), Uint8List(8));
    await store.put(LocalBlobStore.reportPhotoKey('r3', 0), Uint8List(8));
    await store.deletePrefix(LocalBlobStore.reportPrefix('r2'));
    expect(await store.get(LocalBlobStore.reportPhotoKey('r2', 0)), isNull);
    expect(await store.get(LocalBlobStore.reportPhotoKey('r3', 0)), isNotNull);
  });

  test('ensureCapacity throws when over budget and nothing to evict', () async {
    final store = LocalBlobStore.instance;
    // Force a tiny budget scenario by requesting huge incoming with no eviction.
    expect(
      () => store.ensureCapacity(
        incomingBytes: store.budgetBytes + 1,
        evictablePrefixesOldestFirst: const [],
      ),
      throwsA(isA<StorageFullException>()),
    );
  });

  test('StorageLimits are tighter on web-shaped budgets', () {
    expect(
      StorageLimits.blobBudgetBytes(isWeb: true),
      lessThan(StorageLimits.blobBudgetBytes(isWeb: false)),
    );
    expect(
      StorageLimits.maxReports(isWeb: true),
      lessThanOrEqualTo(StorageLimits.maxReports(isWeb: false)),
    );
    expect(StorageLimits.maxPhotoBytes(isWeb: true), lessThan(200 * 1024));
  });
}
