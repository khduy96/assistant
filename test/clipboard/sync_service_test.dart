import 'dart:io';

import 'package:event_notice/clipboard/data/app_database.dart';
import 'package:event_notice/clipboard/data/clip_repository.dart';
import 'package:event_notice/clipboard/sync/parse_config.dart';
import 'package:event_notice/clipboard/sync/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_parse_server.dart';

/// End-to-end sync over the real SQLite schema and a fake Back4App.
///
/// "Xoá là xoá hẳn" removes rows on both sides, so these tests exist mainly to
/// prove nothing gets deleted that should not be.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dir;
  late AppDatabase db;
  late ClipRepository repo;
  late FakeParseServer server;
  late SyncService sync;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('clip_sync_test');
    db = AppDatabase.atPath('${dir.path}/test.db');
    repo = ClipRepository(db: db);
    server = await FakeParseServer.start();
    sync = SyncService(
      repository: repo,
      config: ParseConfig(
        appId: 'app',
        clientKey: 'key',
        serverUrl: server.url,
        space: 'nha',
      ),
    );
  });

  tearDown(() async {
    await db.close();
    await server.stop();
    await dir.delete(recursive: true);
  });

  Map<String, Map<String, Object?>> clipsOnServer() => server.classOf('Clip');

  test('đẩy clip mới lên rồi đánh dấu đã sạch', () async {
    await repo.createManual('xin chào');

    final status = await sync.sync();

    expect(status.state, SyncState.ok);
    expect(clipsOnServer(), hasLength(1));
    final remote = clipsOnServer().values.single;
    expect(remote['content'], 'xin chào');
    expect(remote['space'], 'nha');
    // Không còn cột tombstone trên server.
    expect(remote.containsKey('deleted'), isFalse);

    final local = (await repo.loadClips()).single;
    expect(local.dirty, isFalse);
    expect(local.remoteId, isNotNull);
  });

  test('sync lần hai không tạo bản sao', () async {
    await repo.createManual('một lần thôi');
    await sync.sync();
    await sync.sync();
    expect(clipsOnServer(), hasLength(1));
  });

  test('xoá clip đã sync thì object trên server cũng biến mất', () async {
    await repo.createManual('sẽ bị xoá');
    await sync.sync();
    final item = (await repo.loadClips()).single;

    await repo.delete(item);
    expect(await repo.pendingDeletes(), hasLength(1));

    await sync.sync();

    expect(clipsOnServer(), isEmpty);
    expect(server.deletedIds, hasLength(1));
    expect(await repo.pendingDeletes(), isEmpty);
    expect(await repo.loadClips(), isEmpty);
  });

  test('hoàn tác sau khi xoá thì clip quay lại và được đẩy lên như bản mới',
      () async {
    await repo.createManual('lỡ tay xoá');
    await sync.sync();
    final item = (await repo.loadClips()).single;

    await repo.delete(item);
    await repo.restore(item);
    // Hoàn tác trước khi sync thì huỷ luôn lệnh xoá đang chờ.
    expect(await repo.pendingDeletes(), isEmpty);

    await sync.sync();

    expect(await repo.loadClips(), hasLength(1));
    expect(clipsOnServer(), hasLength(1));
    expect(server.deletedIds, isEmpty);
  });

  test('clip bị thiết bị khác xoá thì máy này cũng bỏ đi', () async {
    await repo.createManual('của thiết bị kia');
    await sync.sync();
    // Thiết bị kia xoá hẳn object rồi tăng bộ đếm thay đổi.
    clipsOnServer().clear();
    server.bump('nha', 'Clip');

    await sync.sync();

    expect(await repo.loadClips(), isEmpty);
  });

  test('clip chưa kịp đẩy lên KHÔNG bị bước đối chiếu xoá nhầm', () async {
    await repo.createManual('đã đồng bộ');
    await sync.sync();
    // Clip mới, chưa từng lên server — server không hề biết nó.
    await repo.createManual('vừa copy xong, chưa sync');

    await sync.sync();

    final contents = (await repo.loadClips()).map((c) => c.content).toList();
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

    final local = (await repo.loadClips()).single;
    expect(local.content, 'gửi từ điện thoại');
    expect(local.isPinned, isTrue);
    expect(local.dirty, isFalse);
  });

  test('sửa tại máy này thắng bản cũ hơn trên server', () async {
    await repo.createManual('bản gốc');
    await sync.sync();
    final item = (await repo.loadClips()).single;

    // Server còn bản cũ, máy này vừa sửa.
    await repo.updateContent(item, 'bản sửa tại máy này');
    await sync.sync();

    expect((await repo.loadClips()).single.content, 'bản sửa tại máy này');
    expect(clipsOnServer().values.single['content'], 'bản sửa tại máy này');
  });

  test('xoá nhóm cũng xoá object nhóm trên server', () async {
    await repo.createGroup('Công việc', 0xFF5B8DEF, 0);
    await sync.sync();
    expect(server.classOf('ClipGroup'), hasLength(1));

    await repo.deleteGroup((await repo.loadGroups()).single);
    await sync.sync();

    expect(server.classOf('ClipGroup'), isEmpty);
    expect(await repo.loadGroups(), isEmpty);
  });

  group('tiết kiệm request', () {
    test('clip tạm không lên server', () async {
      await repo.capture('copy tự động');

      await sync.sync();

      expect(clipsOnServer(), isEmpty);
      expect(server.requests.where((r) => r == 'POST Clip'), isEmpty);
    });

    test('bỏ lưu clip đã sync thì object trên server bị xoá', () async {
      final item = await repo.createManual('đã lưu');
      await sync.sync();
      expect(clipsOnServer(), hasLength(1));

      final temp = await repo.unsave((await repo.loadClips()).single);
      expect(temp.remoteId, isNull);
      await sync.sync();

      expect(clipsOnServer(), isEmpty);
      // Vẫn còn ở máy này dưới dạng clip tạm.
      expect((await repo.loadClips()).single.id, item.id);
    });

    test('clip mới được tạo thẳng, không truy vấn trước', () async {
      await repo.createManual('mới tinh');
      await sync.sync();

      final push = server.requests.takeWhile((r) => r != 'POST Clip');
      expect(push.where((r) => r == 'GET Clip'), isEmpty);
    });

    test('chu kỳ không có thay đổi chỉ tốn 1 request', () async {
      await repo.createManual('có sẵn');
      await sync.sync();
      server.requests.clear();

      final status = await sync.sync();

      expect(server.requests, ['GET SyncMeta']);
      expect(status.state, SyncState.ok);
    });

    test('không kéo lại thứ chính máy này vừa đẩy', () async {
      await sync.sync();
      await repo.createManual('vừa thêm');
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

      expect((await repo.loadClips()).single.content, 'máy kia thêm');
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
      expect(await repo.loadClips(), isEmpty);

      await sync.sync(full: true);
      expect((await repo.loadClips()).single.content, 'từ bản cũ');
    });

    test('lần tạo trước không rõ kết quả thì tra trước, không tạo bản sao',
        () async {
      final item = await repo.createManual('đã tới server');
      // Lần trước POST đã tới nơi nhưng app chết trước khi lưu objectId.
      server.seed('Clip', item.toParse('nha'));
      await repo.putSetting('sync_inflight', '["Clip/${item.id}"]');

      await sync.sync();

      expect(clipsOnServer(), hasLength(1));
      expect((await repo.loadClips()).single.remoteId, isNotNull);
      expect((await repo.loadSettings())['sync_inflight'], '[]');
    });

    test('đếm request vào tổng của tháng', () async {
      await repo.createManual('đếm');

      final first = await sync.sync();
      expect(first.monthRequests, server.requests.length);

      final second = await sync.sync();
      expect(second.monthRequests, server.requests.length);
      expect(await sync.requestsThisMonth(), server.requests.length);
    });

    test('biết còn thay đổi chưa đẩy mà không cần hỏi server', () async {
      // Clip tạm không tính: nó không bao giờ lên server.
      await repo.capture('copy tự động');
      expect(await sync.hasLocalChanges(), isFalse);

      final item = await repo.createManual('mới lưu');
      expect(await sync.hasLocalChanges(), isTrue);

      await sync.sync();
      expect(await sync.hasLocalChanges(), isFalse);

      await repo.delete((await repo.loadClips()).firstWhere((c) => c.id == item.id));
      server.requests.clear();
      expect(await sync.hasLocalChanges(), isTrue);
      expect(server.requests, isEmpty);
    });
  });
}
