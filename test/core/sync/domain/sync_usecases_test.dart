import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/core/domain/usecase.dart';
import 'package:event_notice/core/sync/domain/entities/sync_settings.dart';
import 'package:event_notice/core/sync/domain/entities/sync_status.dart';
import 'package:event_notice/core/sync/domain/sync_channel.dart';
import 'package:event_notice/core/sync/domain/usecases/get_month_requests.dart';
import 'package:event_notice/core/sync/domain/usecases/get_sync_settings.dart';
import 'package:event_notice/core/sync/domain/usecases/has_pending_changes.dart';
import 'package:event_notice/core/sync/domain/usecases/run_sync.dart';
import 'package:event_notice/core/sync/domain/usecases/watch_local_changes.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

void main() {
  late FakeSyncEngine engine;

  setUp(() => engine = FakeSyncEngine());
  tearDown(() => engine.changes.close());

  group('RunSync', () {
    test('mặc định không kéo đầy đủ, trả trạng thái của engine', () async {
      engine.status = const SyncStatus(state: SyncState.ok, pushed: 2);

      final result = await RunSync(engine)(const RunSyncParams());

      expect(result.valueOrNull?.pushed, 2);
      expect(engine.fullRequests, [false]);
    });

    test('full: true thì engine được yêu cầu kéo đầy đủ', () async {
      await RunSync(engine)(const RunSyncParams(full: true));
      expect(engine.fullRequests, [true]);
    });

    test('mặc định là chu kỳ bấm tay, có kiểm server', () async {
      await RunSync(engine)(const RunSyncParams());
      expect(engine.syncCalls, [(full: false, auto: false, checkRemote: true)]);
    });

    test('auto và checkRemote được chuyển nguyên xuống engine', () async {
      await RunSync(engine)(
        const RunSyncParams(auto: true, checkRemote: false),
      );
      await RunSync(engine)(const RunSyncParams(full: true, auto: true));
      expect(engine.syncCalls, [
        (full: false, auto: true, checkRemote: false),
        (full: true, auto: true, checkRemote: true),
      ]);
      expect(engine.fullRequests, [false, true]);
    });

    test('trạng thái paused của engine được trả nguyên', () async {
      engine.status = const SyncStatus(state: SyncState.paused, message: 'x');
      final result = await RunSync(engine)(const RunSyncParams(auto: true));
      expect(result.valueOrNull?.state, SyncState.paused);
    });

    test('chu kỳ lỗi vẫn là Ok, lỗi nằm trong trạng thái', () async {
      engine.status = const SyncStatus(
        state: SyncState.error,
        message: 'Không có kết nối mạng',
      );
      final result = await RunSync(engine)(const RunSyncParams());
      expect(result.valueOrNull?.message, 'Không có kết nối mạng');
    });

    test('engine ném lỗi thì trả Err(UnexpectedFailure)', () async {
      engine.error = StateError('hỏng');
      final result = await RunSync(engine)(const RunSyncParams());
      expect(result.failureOrNull, isA<UnexpectedFailure>());
    });
  });

  group('HasPendingChanges', () {
    test('trả lời theo engine', () async {
      engine.pending = true;
      expect(await HasPendingChanges(engine)(const NoParams()), const Ok(true));
      engine.pending = false;
      expect(
        await HasPendingChanges(engine)(const NoParams()),
        const Ok(false),
      );
    });

    test('đọc lỗi thì trả Err(StorageFailure)', () async {
      engine.error = StateError('db đóng');
      final result = await HasPendingChanges(engine)(const NoParams());
      expect(result.failureOrNull, isA<StorageFailure>());
    });
  });

  group('GetMonthRequests', () {
    test('trả số request của tháng', () async {
      engine.monthRequests = 41;
      expect(await GetMonthRequests(engine)(const NoParams()), const Ok(41));
    });

    test('đọc lỗi thì trả Err(StorageFailure)', () async {
      engine.error = StateError('db đóng');
      final result = await GetMonthRequests(engine)(const NoParams());
      expect(result.failureOrNull, isA<StorageFailure>());
    });
  });

  test('WatchLocalChanges chuyển tiếp luồng của engine', () async {
    final result = await WatchLocalChanges(engine)(const NoParams());
    var fired = 0;
    final sub = result.valueOrNull!.listen((_) => fired++);
    engine.changes.add(null);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(fired, 1);
  });

  test('GetSyncSettings trả cấu hình của engine', () async {
    engine.settings = const SyncSettings(
      isConfigured: false,
      autoSync: false,
      space: 'van-phong',
    );
    final settings = (await GetSyncSettings(engine)(
      const NoParams(),
    )).valueOrNull!;
    expect(settings.isConfigured, isFalse);
    expect(settings.autoSync, isFalse);
    expect(settings.space, 'van-phong');
  });

  group('SyncChannel', () {
    test('single dùng cursor riêng, shared dùng cursor chung', () {
      final todo = MemorySyncCollection('TodoItem');
      final group = MemorySyncCollection('ClipGroup');
      final clip = MemorySyncCollection('Clip');

      final single = SyncChannel.single(todo);
      final shared = SyncChannel.shared([group, clip]);

      expect(single.shared, isFalse);
      expect(single.collections, [todo]);
      expect(shared.shared, isTrue);
      expect(shared.collections, [group, clip]);
    });
  });

  test('SyncStatus.withMonthRequests giữ nguyên các trường còn lại', () {
    final at = DateTime(2026, 10, 22, 9);
    final status = SyncStatus(
      state: SyncState.ok,
      lastSyncAt: at,
      pushed: 1,
      pulled: 2,
    ).withMonthRequests(7);
    expect(status.state, SyncState.ok);
    expect(status.lastSyncAt, at);
    expect(status.pushed, 1);
    expect(status.pulled, 2);
    expect(status.monthRequests, 7);
    expect(status.isRunning, isFalse);
  });
}
