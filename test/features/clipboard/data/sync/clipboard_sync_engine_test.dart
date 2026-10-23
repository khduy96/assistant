import 'package:event_notice/core/data/sqlite_sync_state_store.dart';
import 'package:event_notice/core/sync/data/parse_config.dart';
import 'package:event_notice/core/sync/data/parse_sync_engine.dart';
import 'package:event_notice/core/sync/domain/entities/sync_status.dart';
import 'package:event_notice/core/sync/domain/sync_channel.dart';
import 'package:event_notice/features/clipboard/data/datasources/clip_local_data_source.dart';
import 'package:event_notice/features/clipboard/data/repositories/clipboard_repository_impl.dart';
import 'package:event_notice/features/clipboard/data/sync/clip_group_sync_collection.dart';
import 'package:event_notice/features/clipboard/data/sync/clip_sync_collection.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_group.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../core/sync/fake_parse_server.dart';
import '../../../../core/sync/fakes.dart';
import '../clip_db.dart';

/// The clipboard's new collections behind the real [ParseSyncEngine] and a
/// fake Back4App, registered the way the app registers them: the GĐ4 cases
/// for the old `pending_deletes` rows and the group-before-clip order.
void main() {
  useFfiSqlite();

  late ClipDb db;
  late FixedClock clock;
  late ClipLocalDataSource source;
  late ClipboardRepositoryImpl repo;
  late SqliteSyncStateStore state;
  late FakeParseServer server;
  late MemorySyncCollection todos;
  late MemorySyncCollection notes;

  setUp(() async {
    db = await ClipDb.open();
    clock = FixedClock(DateTime(2026, 10, 22, 9));
    source = ClipLocalDataSource(db.db);
    repo = ClipboardRepositoryImpl(source, clock);
    state = SqliteSyncStateStore(db.db);
    server = await FakeParseServer.start();
    todos = MemorySyncCollection('TodoItem');
    notes = MemorySyncCollection('NoteItem');
  });

  tearDown(() async {
    await todos.close();
    await notes.close();
    await repo.dispose();
    await db.close();
    await server.stop();
  });

  ParseSyncEngine engine() => ParseSyncEngine(
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
      SyncChannel.single(todos),
      SyncChannel.single(notes),
    ],
    clock: clock,
  );

  ClipItem clip(String id, {String? groupId, bool isSaved = true}) => ClipItem(
    id: id,
    content: 'nội dung $id',
    type: ClipType.text,
    createdAt: clock.now(),
    updatedAt: clock.now(),
    isSaved: isSaved,
    groupId: groupId,
  );

  ClipGroup clipGroup(String id, String name) => ClipGroup(
    id: id,
    name: name,
    color: 0xFF5B8DEF,
    createdAt: clock.now(),
    updatedAt: clock.now(),
  );

  group('dữ liệu do bản cũ để lại', () {
    test('pending_deletes của Clip và ClipGroup do bản cũ xếp hàng: lượt sync '
        'đầu gửi đủ DELETE và xoá hết dòng chờ', () async {
      final groupObject = server.seed('ClipGroup', {
        'space': 'nha',
        'localId': 'g-cu',
        'name': 'Nhóm cũ',
      });
      final clipObject = server.seed('Clip', {
        'space': 'nha',
        'localId': 'c-cu',
        'content': 'clip cũ',
      });
      final raw = await db.raw;
      // The old build queued them in one table, clip first.
      await raw.insert('pending_deletes', {
        'remote_id': clipObject,
        'class_name': 'Clip',
        'queued_at': 1,
      });
      await raw.insert('pending_deletes', {
        'remote_id': groupObject,
        'class_name': 'ClipGroup',
        'queued_at': 2,
      });

      final status = await engine().sync();

      expect(status.state, SyncState.ok);
      expect(server.requests.where((r) => r.startsWith('DELETE')), [
        'DELETE ClipGroup',
        'DELETE Clip',
      ]);
      expect(server.deletedIds, unorderedEquals([groupObject, clipObject]));
      expect(server.classOf('Clip'), isEmpty);
      expect(server.classOf('ClipGroup'), isEmpty);
      expect(await raw.query('pending_deletes'), isEmpty);
    });

    test('dòng clip và nhóm do bản cũ ghi: đã đồng bộ thì không đẩy lại, '
        'chưa đồng bộ thì đẩy', () async {
      final raw = await db.raw;
      final at = DateTime(2026, 10, 1).millisecondsSinceEpoch;
      await raw.insert('groups', {
        'id': 'g-cu',
        'name': 'Nhóm cũ',
        'color': 0xFF5B8DEF,
        'created_at': at,
        'updated_at': at,
        'sort_order': 0,
        'remote_id': 'obj-g-cu',
        'dirty': 0,
      });
      server.classOf('ClipGroup')['obj-g-cu'] = {
        'objectId': 'obj-g-cu',
        'space': 'nha',
        'localId': 'g-cu',
        'updatedAt': '2026-01-01T00:00:00.000Z',
      };
      await raw.insert('clips', {
        'id': 'c-moi',
        'content': 'chưa đẩy',
        'type': 'text',
        'created_at': at,
        'updated_at': at,
        'is_saved': 1,
        'is_pinned': 0,
        'group_id': 'g-cu',
        'copy_count': 0,
        'dirty': 1,
      });

      final status = await engine().sync();

      expect(status.state, SyncState.ok);
      expect(server.requests.where((r) => !r.startsWith('GET')).toList(), [
        'POST Clip',
        'POST SyncMeta',
      ]);
      final pushed = server.classOf('Clip').values.single;
      expect(pushed['groupLocalId'], 'g-cu');
      expect((await source.clipById('c-moi'))!.dirty, isFalse);
      expect((await source.groupById('g-cu'))!.remoteId, 'obj-g-cu');
    });
  });

  group('kênh chung Clip/ClipGroup', () {
    Map<String, Object?> remoteGroup(String localId, String name) {
      final now = clock.now().millisecondsSinceEpoch;
      return {
        'space': 'nha',
        'localId': localId,
        'name': name,
        'color': 0xFF5B8DEF,
        'groupCreatedAt': now,
        'groupUpdatedAt': now,
        'sortOrder': 0,
      };
    }

    Map<String, Object?> remoteClip(String localId, {String? groupLocalId}) {
      final now = clock.now().millisecondsSinceEpoch;
      return {
        'space': 'nha',
        'localId': localId,
        'content': 'từ máy kia',
        'kind': 'text',
        'clipCreatedAt': now,
        'clipUpdatedAt': now,
        'isSaved': true,
        'isPinned': false,
        'groupLocalId': groupLocalId,
        'copyCount': 0,
      };
    }

    test(
      'máy kia tạo nhóm mới cùng clip trong nhóm: sau một lượt pull clip nằm '
      'đúng nhóm',
      () async {
        final sync = engine();
        await sync.sync();
        // On the server the clip is even older than its group: the order
        // comes from the channel, not from the server.
        server.seed('Clip', remoteClip('c-may-kia', groupLocalId: 'g-may-kia'));
        server.seed('ClipGroup', remoteGroup('g-may-kia', 'Công việc'));
        server.bump('nha', 'ClipGroup');
        server.bump('nha', 'Clip');

        final status = await sync.sync();

        expect(status.state, SyncState.ok);
        expect((await source.groups()).single.name, 'Công việc');
        final stored = (await source.clips()).single;
        expect(stored.groupId, 'g-may-kia');
        expect(stored.dirty, isFalse);
      },
    );

    test('chỉ một lớp đổi thì vẫn kéo cả hai, dùng cursor chung', () async {
      final sync = engine();
      await sync.sync();
      server.seed('Clip', remoteClip('c-may-kia'));
      server.bump('nha', 'Clip');
      server.requests.clear();

      await sync.sync();

      expect(server.requests.toSet(), {
        'GET SyncMeta',
        'GET Clip',
        'GET ClipGroup',
      });
      final settings = await state.readAll();
      expect(
        settings['sync_cursor_nha'],
        server.classOf('Clip').values.single['updatedAt'],
      );
      expect(settings.containsKey('sync_cursor_nha_Clip'), isFalse);
      expect(settings.containsKey('sync_cursor_nha_ClipGroup'), isFalse);
    });

    test('nhóm đổi tên ở máy kia thì clip vẫn ở trong nhóm', () async {
      final sync = engine();
      final groupObject = server.seed(
        'ClipGroup',
        remoteGroup('g-may-kia', 'Công việc'),
      );
      server.seed('Clip', remoteClip('c-may-kia', groupLocalId: 'g-may-kia'));
      await sync.sync();
      expect((await source.clips()).single.groupId, 'g-may-kia');

      server.classOf('ClipGroup')[groupObject]!
        ..['name'] = 'Việc nhà'
        ..['groupUpdatedAt'] = clock
            .now()
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch
        ..['updatedAt'] = '2026-01-01T01:00:00.000Z';
      server.bump('nha', 'ClipGroup');
      await sync.sync();

      expect((await source.groups()).single.name, 'Việc nhà');
      expect((await source.clips()).single.groupId, 'g-may-kia');
    });

    test('đẩy nhóm mới cùng clip trong nhóm: clip vẫn trong nhóm ở cả hai '
        'phía', () async {
      await repo.saveGroup(clipGroup('g1', 'Công việc'));
      await repo.saveClip(clip('c1', groupId: 'g1'));

      await engine().sync();

      final local = (await source.clips()).single;
      expect(local.groupId, 'g1');
      expect(local.dirty, isFalse);
      expect(local.remoteId, isNotNull);
      expect(server.classOf('Clip').values.single['groupLocalId'], 'g1');
      expect((await source.groups()).single.remoteId, isNotNull);
    });
  });

  group('đẩy', () {
    test('theo thứ tự đăng ký ClipGroup, Clip, TodoItem, NoteItem; mỗi lớp xoá '
        'trước rồi mới tạo/sửa', () async {
      final raw = await db.raw;
      await raw.insert('pending_deletes', {
        'remote_id': 'obj-c-cu',
        'class_name': 'Clip',
        'queued_at': 1,
      });
      await raw.insert('pending_deletes', {
        'remote_id': 'obj-g-cu',
        'class_name': 'ClipGroup',
        'queued_at': 2,
      });
      await repo.saveClip(clip('c1'));
      await repo.saveGroup(clipGroup('g1', 'Nhóm mới'));
      todos.edit('t1', {'title': 'việc'});
      notes.edit('n1', {'body': 'ghi chú'});
      notes.tombstones.add('obj-n-cu');

      final status = await engine().sync();

      expect(status.state, SyncState.ok);
      expect(status.pushed, 7);
      final push = server.requests.takeWhile((r) => !r.endsWith('SyncMeta'));
      expect(push, [
        'DELETE ClipGroup',
        'POST ClipGroup',
        'DELETE Clip',
        'POST Clip',
        'POST TodoItem',
        'DELETE NoteItem',
        'POST NoteItem',
      ]);
    });

    test('object Clip và ClipGroup trên server mang đúng các field cũ cộng '
        'space', () async {
      await repo.saveGroup(clipGroup('g1', 'Công việc'));
      await repo.saveClip(clip('c1', groupId: 'g1'));

      await engine().sync();

      final pushedClip = server.classOf('Clip').values.single;
      expect(
        pushedClip.keys.toSet().difference({
          'objectId',
          'createdAt',
          'updatedAt',
        }),
        {
          'space',
          'localId',
          'content',
          'kind',
          'clipCreatedAt',
          'clipUpdatedAt',
          'isSaved',
          'isPinned',
          'groupLocalId',
          'note',
          'copyCount',
        },
      );
      expect(pushedClip['space'], 'nha');
      final pushedGroup = server.classOf('ClipGroup').values.single;
      expect(
        pushedGroup.keys.toSet().difference({
          'objectId',
          'createdAt',
          'updatedAt',
        }),
        {
          'space',
          'localId',
          'name',
          'color',
          'groupCreatedAt',
          'groupUpdatedAt',
          'sortOrder',
        },
      );
    });

    test('clip tạm không bao giờ được đẩy', () async {
      await repo.saveClip(clip('tam', isSaved: false), share: false);

      await engine().sync();

      expect(server.requests.where((r) => r.endsWith(' Clip')).toSet(), {
        'GET Clip',
      });
      expect(server.classOf('Clip'), isEmpty);
    });

    test('bỏ lưu clip đã đẩy thì object của nó bị xoá trên server', () async {
      await repo.saveClip(clip('c1'));
      final sync = engine();
      await sync.sync();
      final objectId = (await source.clipById('c1'))!.remoteId!;

      await repo.detachFromServer('c1');
      await repo.saveClip(clip('c1', isSaved: false));
      await sync.sync();

      expect(server.deletedIds, [objectId]);
      expect(server.classOf('Clip'), isEmpty);
      expect((await source.clipById('c1'))!.remoteId, isNull);
    });
  });

  test('localChanges của engine nghe thay đổi local của clipboard, bỏ qua '
      'thay đổi do sync áp vào', () async {
    final sync = engine();
    var fired = 0;
    final sub = sync.localChanges.listen((_) => fired++);
    addTearDown(sub.cancel);

    await repo.saveClip(clip('c1'));
    await repo.saveGroup(clipGroup('g1', 'Nhóm'));
    // A new temp clip stays on this device: nothing to push.
    await repo.saveClip(clip('tam', isSaved: false), share: false);
    await Future<void>.delayed(Duration.zero);
    expect(fired, 2);

    fired = 0;
    server.seed('Clip', {
      'space': 'nha',
      'localId': 'c-may-kia',
      'content': 'từ máy kia',
      'isSaved': true,
    });
    server.bump('nha', 'Clip');
    await sync.sync();
    await Future<void>.delayed(Duration.zero);
    expect(fired, 0);
  });
}
