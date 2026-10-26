import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/usecase.dart';
import 'package:event_notice/core/sync/data/state_store_sync_preferences.dart';
import 'package:event_notice/core/sync/domain/sync_state_store.dart';
import 'package:event_notice/core/sync/domain/usecases/get_auto_sync_choice.dart';
import 'package:event_notice/core/sync/domain/usecases/set_auto_sync_choice.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

/// A [SyncStateStore] whose every call throws.
class _ThrowingSyncStateStore implements SyncStateStore {
  @override
  Future<Map<String, String>> readAll() async => throw StateError('readAll');

  @override
  Future<String?> read(String key) async => throw StateError('read');

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('write');
}

void main() {
  late MemorySyncStateStore store;
  late StateStoreSyncPreferences preferences;

  setUp(() {
    store = MemorySyncStateStore();
    preferences = StateStoreSyncPreferences(store);
  });

  test('key là sync_auto', () {
    expect(StateStoreSyncPreferences.autoSyncKey, 'sync_auto');
  });

  test('chưa có key thì đọc ra null', () async {
    expect(await preferences.autoSync(), isNull);
  });

  test('true ghi "1", false ghi "0", đọc lại đúng', () async {
    await preferences.setAutoSync(true);
    expect(store.values['sync_auto'], '1');
    expect(await preferences.autoSync(), isTrue);

    await preferences.setAutoSync(false);
    expect(store.values['sync_auto'], '0');
    expect(await preferences.autoSync(), isFalse);
  });

  test('giá trị khác "1"/"0" thì đọc ra null', () async {
    for (final value in ['', 'true', 'false', '2', ' 1', 'on']) {
      store.values['sync_auto'] = value;
      expect(await preferences.autoSync(), isNull, reason: 'value "$value"');
    }
  });

  test('chỉ thêm key sync_auto, không đụng key khác', () async {
    store.values.addAll({
      'sync_req_2026-10': '41',
      'sync_cursor_nha': 'iso',
      'sync_last_at': '123',
    });
    final before = {...store.values};

    await preferences.setAutoSync(false);

    expect(store.values, {...before, 'sync_auto': '0'});
  });

  test('không đọc giá trị từ key khác', () async {
    store.values.addAll({'sync_auto_nha': '1', 'auto_sync': '1'});
    expect(await preferences.autoSync(), isNull);
  });

  group('qua use case, store ném lỗi', () {
    late StateStoreSyncPreferences broken;

    setUp(() => broken = StateStoreSyncPreferences(_ThrowingSyncStateStore()));

    test(
      'write ném lỗi thì SetAutoSyncChoice trả Err(StorageFailure)',
      () async {
        final result = await SetAutoSyncChoice(broken)(true);
        expect(result.failureOrNull, isA<StorageFailure>());
      },
    );

    test(
      'read ném lỗi thì GetAutoSyncChoice trả Err(StorageFailure)',
      () async {
        final result = await GetAutoSyncChoice(broken)(const NoParams());
        expect(result.failureOrNull, isA<StorageFailure>());
      },
    );
  });
}
