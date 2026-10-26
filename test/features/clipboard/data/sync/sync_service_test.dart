import 'dart:io';

import 'package:event_notice/core/data/app_database.dart';
import 'package:event_notice/core/data/sqlite_sync_state_store.dart';
import 'package:event_notice/core/data/system_clock.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/core/sync/data/parse_config.dart';
import 'package:event_notice/core/sync/data/parse_sync_engine.dart';
import 'package:event_notice/core/sync/domain/entities/sync_status.dart';
import 'package:event_notice/core/sync/domain/sync_channel.dart';
import 'package:event_notice/features/clipboard/data/clip_id_generator.dart';
import 'package:event_notice/features/clipboard/data/datasources/clip_local_data_source.dart';
import 'package:event_notice/features/clipboard/data/mappers/clip_mapper.dart';
import 'package:event_notice/features/clipboard/data/repositories/clipboard_repository_impl.dart';
import 'package:event_notice/features/clipboard/data/sync/clip_group_sync_collection.dart';
import 'package:event_notice/features/clipboard/data/sync/clip_sync_collection.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_group.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_item.dart';
import 'package:event_notice/features/clipboard/domain/usecases/add_manual_clip.dart';
import 'package:event_notice/features/clipboard/domain/usecases/capture_clip.dart';
import 'package:event_notice/features/clipboard/domain/usecases/create_clip_group.dart';
import 'package:event_notice/features/clipboard/domain/usecases/delete_clip.dart';
import 'package:event_notice/features/clipboard/domain/usecases/delete_clip_group.dart';
import 'package:event_notice/features/clipboard/domain/usecases/restore_clip.dart';
import 'package:event_notice/features/clipboard/domain/usecases/unsave_clip.dart';
import 'package:event_notice/features/clipboard/domain/usecases/update_clip_content.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../core/sync/fake_parse_server.dart';

/// End-to-end sync over the real SQLite schema and a fake Back4App.
///
/// "Xoá là xoá hẳn" removes rows on both sides, so these tests exist mainly to
/// prove nothing gets deleted that should not be.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dir;
  late AppDatabase db;
  late ClipLocalDataSource source;
  late ClipboardRepositoryImpl repo;
  late FakeParseServer server;
  late SqliteSyncStateStore state;
  late ParseSyncEngine sync;

  const clock = SystemClock();
  final ids = ClipIdGenerator(clock);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('clip_sync_test');
    db = AppDatabase.atPath('${dir.path}/test.db');
    source = ClipLocalDataSource(db);
    repo = ClipboardRepositoryImpl(source, clock);
    state = SqliteSyncStateStore(db);
    server = await FakeParseServer.start();
    sync = ParseSyncEngine(
      config: ParseConfig(
        appId: 'app',
        clientKey: 'key',
        serverUrl: server.url,
        space: 'nha',
      ),
      state: state,
      channels: [
        SyncChannel.shared([
          ClipGroupSyncCollection(repo, clock),
          ClipSyncCollection(repo, clock),
        ]),
      ],
      clock: clock,
    );
  });

  tearDown(() async {
    await repo.dispose();
    await db.close();
    await server.stop();
    await dir.delete(recursive: true);
  });

  Map<String, Map<String, Object?>> clipsOnServer() => server.classOf('Clip');

  /// The value of a call that has to succeed here.
  Future<T> ok<T>(Future<Result<T>> pending) async => switch (await pending) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };

  // What the user does, through the use cases the app runs it with.
  Future<ClipItem> createManual(String content) =>
      ok(AddManualClip(repo, ids, clock)((content: content, groupId: null)));
  Future<ClipItem?> capture(String content) =>
      ok(CaptureClip(repo, ids, clock)(content));
  Future<void> delete(ClipItem item) => ok(DeleteClip(repo)(item));
  Future<ClipItem> restore(ClipItem item) => ok(RestoreClip(repo, clock)(item));
  Future<ClipItem> unsave(ClipItem item) => ok(UnsaveClip(repo, clock)(item));
  Future<ClipItem> updateContent(ClipItem item, String content) => ok(
        UpdateClipContent(repo, clock)(
          (clip: item, content: content, note: null),
        ),
      );
  Future<ClipGroup> createGroup(String name, int color) =>
      ok(CreateClipGroup(repo, ids, clock)((name: name, color: color)));
  Future<void> deleteGroup(ClipGroup group) =>
      ok(DeleteClipGroup(repo, clock)(group));

  /// The clips and groups as the user sees them. `source.clips()` gives the
  /// stored rows, with their sync state.
  Future<List<ClipItem>> loadClips() => ok(repo.getClips());
  Future<List<ClipGroup>> loadGroups() => ok(repo.getGroups());

  /// Server deletes still queued, of either class.
  Future<List<String>> pendingDeletes() async => [
        ...await repo.pendingDeletes('Clip'),
        ...await repo.pendingDeletes('ClipGroup'),
      ];

  test('đẩy clip mới lên rồi đánh dấu đã sạch', () async {
    await createManual('xin chào');

    final status = await sync.sync();

    expect(status.state, SyncState.ok);
    expect(clipsOnServer(), hasLength(1));
    final remote = clipsOnServer().values.single;
    expect(remote['content'], 'xin chào');
    expect(remote['space'], 'nha');
    // Không còn cột tombstone trên server.
    expect(remote.containsKey('deleted'), isFalse);

    final local = (await source.clips()).single;
    expect(local.dirty, isFalse);
    expect(local.remoteId, isNotNull);
  });

  test('sync lần hai không tạo bản sao', () async {
    await createManual('một lần thôi');
    await sync.sync();
    await sync.sync();
    expect(clipsOnServer(), hasLength(1));
  });

  test('xoá clip đã sync thì object trên server cũng biến mất', () async {
    await createManual('sẽ bị xoá');
    await sync.sync();
    final item = (await loadClips()).single;

    await delete(item);
    expect(await pendingDeletes(), hasLength(1));

    await sync.sync();

    expect(clipsOnServer(), isEmpty);
    expect(server.deletedIds, hasLength(1));
    expect(await pendingDeletes(), isEmpty);
    expect(await loadClips(), isEmpty);
  });

  test('hoàn tác sau khi xoá thì clip quay lại và được đẩy lên như bản mới',
      () async {
    await createManual('lỡ tay xoá');
    await sync.sync();
    final item = (await loadClips()).single;

    await delete(item);
    await restore(item);
    // Hoàn tác trước khi sync thì huỷ luôn lệnh xoá đang chờ.
    expect(await pendingDeletes(), isEmpty);

    await sync.sync();

    expect(await loadClips(), hasLength(1));
    expect(clipsOnServer(), hasLength(1));
    expect(server.deletedIds, isEmpty);
  });

  test('clip bị thiết bị khác xoá thì máy này cũng bỏ đi', () async {
    await createManual('của thiết bị kia');
    await sync.sync();
    // Thiết bị kia xoá hẳn object rồi tăng bộ đếm thay đổi.
    clipsOnServer().clear();
    server.bump('nha', 'Clip');

    await sync.sync();

    expect(await loadClips(), isEmpty);
  });

  test('clip chưa kịp đẩy lên KHÔNG bị bước đối chiếu xoá nhầm', () async {
    await createManual('đã đồng bộ');
    await sync.sync();
    // Clip mới, chưa từng lên server — server không hề biết nó.
    await createManual('vừa copy xong, chưa sync');

    await sync.sync();

    final contents = (await loadClips()).map((c) => c.content).toList();
    expect(contents, containsAll(['đã đồng bộ', 'vừa copy xong, chưa sync']));
  });

  test('kéo về clip do thiết bị khác tạo', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    server.seed('Clip', {
      'space': 'nha',
      'localId': 'tu-dien-thoai',
      'content': 'gửi từ điện thoại',
      'kind': 'text',
      'clipCreatedAt': now,
      'clipUpdatedAt': now,
      'isSaved': true,
      'isPinned': true,
      'copyCount': 0,
    });

    await sync.sync();

    final local = (await source.clips()).single;
    expect(local.content, 'gửi từ điện thoại');
    expect(local.isPinned, isTrue);
    expect(local.dirty, isFalse);
  });

  test('sửa tại máy này thắng bản cũ hơn trên server', () async {
    await createManual('bản gốc');
    await sync.sync();
    final item = (await loadClips()).single;

    // Server còn bản cũ, máy này vừa sửa.
    await updateContent(item, 'bản sửa tại máy này');
    await sync.sync();

    expect((await loadClips()).single.content, 'bản sửa tại máy này');
    expect(clipsOnServer().values.single['content'], 'bản sửa tại máy này');
  });

  test('xoá nhóm cũng xoá object nhóm trên server', () async {
    await createGroup('Công việc', 0xFF5B8DEF);
    await sync.sync();
    expect(server.classOf('ClipGroup'), hasLength(1));

    await deleteGroup((await loadGroups()).single);
    await sync.sync();

    expect(server.classOf('ClipGroup'), isEmpty);
    expect(await loadGroups(), isEmpty);
  });

  group('tiết kiệm request', () {
    test('clip tạm không lên server', () async {
      await capture('copy tự động');

      await sync.sync();

      expect(clipsOnServer(), isEmpty);
      expect(server.requests.where((r) => r == 'POST Clip'), isEmpty);
    });

    test('bỏ lưu clip đã sync thì object trên server bị xoá', () async {
      final item = await createManual('đã lưu');
      await sync.sync();
      expect(clipsOnServer(), hasLength(1));

      final temp = await unsave((await loadClips()).single);
      expect((await source.clipById(temp.id))!.remoteId, isNull);
      await sync.sync();

      expect(clipsOnServer(), isEmpty);
      // Vẫn còn ở máy này dưới dạng clip tạm.
      expect((await loadClips()).single.id, item.id);
    });

    test('clip mới được tạo thẳng, không truy vấn trước', () async {
      await createManual('mới tinh');
      await sync.sync();

      final push = server.requests.takeWhile((r) => r != 'POST Clip');
      expect(push.where((r) => r == 'GET Clip'), isEmpty);
    });

    test('chu kỳ không có thay đổi chỉ tốn 1 request', () async {
      await createManual('có sẵn');
      await sync.sync();
      server.requests.clear();

      final status = await sync.sync();

      expect(server.requests, ['GET SyncMeta']);
      expect(status.state, SyncState.ok);
    });

    test('không kéo lại thứ chính máy này vừa đẩy', () async {
      await sync.sync();
      await createManual('vừa thêm');
      server.requests.clear();

      await sync.sync();

      expect(server.requests, ['POST Clip', 'PUT SyncMeta', 'GET SyncMeta']);
    });

    test('máy khác đổi lớp nào thì chỉ kéo lớp đó', () async {
      await sync.sync();
      final now = DateTime.now().millisecondsSinceEpoch;
      server.seed('Clip', {
        'space': 'nha',
        'localId': 'tu-may-kia',
        'content': 'máy kia thêm',
        'kind': 'text',
        'clipCreatedAt': now,
        'clipUpdatedAt': now,
        'isSaved': true,
      });
      server.bump('nha', 'Clip');
      server.requests.clear();

      await sync.sync();

      expect((await loadClips()).single.content, 'máy kia thêm');
      expect(server.requests.toSet(),
          {'GET SyncMeta', 'GET Clip', 'GET ClipGroup'});
    });

    test('thiếu bump (máy chạy bản cũ) thì đồng bộ đầy đủ vẫn bắt được',
        () async {
      await sync.sync();
      final now = DateTime.now().millisecondsSinceEpoch;
      server.seed('Clip', {
        'space': 'nha',
        'localId': 'ban-cu',
        'content': 'từ bản cũ',
        'kind': 'text',
        'clipCreatedAt': now,
        'clipUpdatedAt': now,
        'isSaved': true,
      });

      await sync.sync();
      expect(await loadClips(), isEmpty);

      await sync.sync(full: true);
      expect((await loadClips()).single.content, 'từ bản cũ');
    });

    test('lần tạo trước không rõ kết quả thì tra trước, không tạo bản sao',
        () async {
      final item = await createManual('đã tới server');
      // Lần trước POST đã tới nơi nhưng app chết trước khi lưu objectId.
      server.seed('Clip', {
        'space': 'nha',
        ...ClipMapper.toModel(item).toParse(),
      });
      await state.write('sync_inflight', '["Clip/${item.id}"]');

      await sync.sync();

      expect(clipsOnServer(), hasLength(1));
      expect((await source.clips()).single.remoteId, isNotNull);
      expect((await state.readAll())['sync_inflight'], '[]');
    });

    test('đếm request vào tổng của tháng', () async {
      await createManual('đếm');

      final first = await sync.sync();
      expect(first.monthRequests, server.requests.length);

      final second = await sync.sync();
      expect(second.monthRequests, server.requests.length);
      expect(await sync.requestsThisMonth(), server.requests.length);
    });

    test('biết còn thay đổi chưa đẩy mà không cần hỏi server', () async {
      // Clip tạm không tính: nó không bao giờ lên server.
      await capture('copy tự động');
      expect(await sync.hasLocalChanges(), isFalse);

      final item = await createManual('mới lưu');
      expect(await sync.hasLocalChanges(), isTrue);

      await sync.sync();
      expect(await sync.hasLocalChanges(), isFalse);

      await delete((await loadClips()).firstWhere((c) => c.id == item.id));
      server.requests.clear();
      expect(await sync.hasLocalChanges(), isTrue);
      expect(server.requests, isEmpty);
    });
  });
}
