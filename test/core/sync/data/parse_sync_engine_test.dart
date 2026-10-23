import 'dart:io';

import 'package:event_notice/core/data/app_database.dart';
import 'package:event_notice/core/data/sqlite_sync_state_store.dart';
import 'package:event_notice/core/sync/data/parse_config.dart';
import 'package:event_notice/core/sync/data/parse_sync_engine.dart';
import 'package:event_notice/core/sync/domain/entities/sync_status.dart';
import 'package:event_notice/core/sync/domain/sync_channel.dart';
import 'package:event_notice/features/clipboard/data/datasources/clip_local_data_source.dart';
import 'package:event_notice/features/clipboard/data/models/clip_model.dart';
import 'package:event_notice/features/clipboard/data/repositories/clipboard_repository_impl.dart';
import 'package:event_notice/features/clipboard/data/sync/clip_group_sync_collection.dart';
import 'package:event_notice/features/clipboard/data/sync/clip_sync_collection.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_group.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../fake_parse_server.dart';
import '../fakes.dart';

/// The engine over the real clipboard database, two in-memory lists standing
/// in for todos and notes, and a fake Back4App — registered the way the app
/// registers them.
///
/// The clipboard's own cases (old `pending_deletes` rows, the shared
/// Clip/ClipGroup channel, temp clips) are in
/// test/features/clipboard/data/sync/clipboard_sync_engine_test.dart.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dir;
  late AppDatabase db;
  late ClipLocalDataSource source;
  late ClipboardRepositoryImpl clips;
  late SqliteSyncStateStore state;
  late FakeParseServer server;
  late FixedClock clock;
  late MemorySyncCollection todos;
  late MemorySyncCollection notes;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('parse_sync_engine_test');
    db = AppDatabase.atPath('${dir.path}/test.db');
    clock = FixedClock(DateTime(2026, 10, 22, 9));
    source = ClipLocalDataSource(db);
    clips = ClipboardRepositoryImpl(source, clock);
    state = SqliteSyncStateStore(db);
    server = await FakeParseServer.start();
    todos = MemorySyncCollection('TodoItem');
    notes = MemorySyncCollection('NoteItem');
  });

  tearDown(() async {
    await todos.close();
    await notes.close();
    await clips.dispose();
    await db.close();
    await server.stop();
    await dir.delete(recursive: true);
  });

  ParseConfig config({String? serverUrl, String appId = 'app'}) => ParseConfig(
    appId: appId,
    clientKey: 'key',
    serverUrl: serverUrl ?? server.url,
    space: 'nha',
  );

  ParseSyncEngine engine({ParseConfig? withConfig}) => ParseSyncEngine(
    config: withConfig ?? config(),
    state: state,
    channels: [
      SyncChannel.shared([
        ClipGroupSyncCollection(clips, clock),
        ClipSyncCollection(clips, clock),
      ]),
      SyncChannel.single(todos),
      SyncChannel.single(notes),
    ],
    clock: clock,
  );

  /// Writes the `settings` rows straight into the table, as an older build
  /// left them.
  Future<void> legacySettings(Map<String, String> rows) async {
    final raw = await db.database;
    for (final MapEntry(:key, :value) in rows.entries) {
      await raw.insert('settings', {'key': key, 'value': value});
    }
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  ClipItem clip(String id, String content, {bool isSaved = true}) => ClipItem(
    id: id,
    content: content,
    type: ClipType.text,
    createdAt: clock.now(),
    updatedAt: clock.now(),
    isSaved: isSaved,
  );

  ClipGroup clipGroup(String id, String name) => ClipGroup(
    id: id,
    name: name,
    color: 0xFF5B8DEF,
    createdAt: clock.now(),
    updatedAt: clock.now(),
  );

  group('dữ liệu do bản cũ để lại', () {
    test('settings như bản cũ: chu kỳ không có thay đổi chỉ gửi GET SyncMeta, '
        'bộ đếm request của tháng được cộng tiếp', () async {
      final metaId = server.seed('SyncMeta', {
        'space': 'nha',
        'rev_Clip': 3,
        'rev_ClipGroup': 1,
        'rev_TodoItem': 2,
        'rev_NoteItem': 5,
      });
      // A clip pushed long ago: on the server, nothing left to push.
      final at = DateTime(2026, 10, 1);
      await (await db.database).insert(
        'clips',
        ClipModel(
          id: 'c-cu',
          content: 'đã đồng bộ',
          type: ClipType.text,
          createdAt: at,
          updatedAt: at,
          isSaved: true,
          remoteId: 'obj-c-cu',
          dirty: false,
        ).toMap(),
      );
      final legacy = {
        'sync_meta_id_nha': metaId,
        'sync_rev_nha_Clip': '3',
        'sync_rev_nha_ClipGroup': '1',
        'sync_rev_nha_TodoItem': '2',
        'sync_rev_nha_NoteItem': '5',
        'sync_cursor_nha': '2026-01-01T00:00:01.000Z',
        'sync_cursor_nha_TodoItem': '2026-01-01T00:00:02.000Z',
        'sync_cursor_nha_NoteItem': '2026-01-01T00:00:03.000Z',
        'sync_full_at_nha':
            '${clock.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch}',
        'sync_meta_bump_nha': '',
        'sync_inflight': '[]',
        'sync_last_at':
            '${clock.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch}',
        'sync_req_2026-10': '41',
      };
      await legacySettings(legacy);

      final status = await engine().sync();

      expect(status.state, SyncState.ok);
      expect(server.requests, ['GET SyncMeta']);
      expect(status.monthRequests, 42);
      expect(await engine().requestsThisMonth(), 42);

      final after = await state.readAll();
      expect(after['sync_req_2026-10'], '42');
      expect(after['sync_last_at'], '${clock.now().millisecondsSinceEpoch}');
      for (final key in [
        'sync_meta_id_nha',
        'sync_rev_nha_Clip',
        'sync_rev_nha_ClipGroup',
        'sync_rev_nha_TodoItem',
        'sync_rev_nha_NoteItem',
        'sync_cursor_nha',
        'sync_cursor_nha_TodoItem',
        'sync_cursor_nha_NoteItem',
        'sync_full_at_nha',
        'sync_inflight',
      ]) {
        expect(after[key], legacy[key], reason: key);
      }
      expect((await source.clips()).single.remoteId, 'obj-c-cu');
    });
  });

  group('đẩy', () {
    test('theo thứ tự đăng ký ClipGroup, Clip, TodoItem, NoteItem; mỗi lớp xoá '
        'trước rồi mới tạo/sửa', () async {
      final raw = await db.database;
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
      await clips.saveClip(clip('c1', 'clip mới'));
      await clips.saveGroup(clipGroup('g1', 'Nhóm mới'));
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
      expect(notes.tombstones, isEmpty);
      expect(await todos.dirtyRecords(), isEmpty);
      expect(server.classOf('TodoItem').values.single['space'], 'nha');
    });
  });

  test(
    'kênh riêng dùng cursor sync_cursor_<space>_<Class>, chỉ kéo lớp đã đổi',
    () async {
      final sync = engine();
      await sync.sync();
      server.seed('TodoItem', {
        'space': 'nha',
        'localId': 't-may-kia',
        'title': 'từ máy kia',
      });
      server.bump('nha', 'TodoItem');
      server.requests.clear();

      await sync.sync();

      expect(server.requests.toSet(), {'GET SyncMeta', 'GET TodoItem'});
      expect(todos.applied.single['localId'], 't-may-kia');
      final settings = await state.readAll();
      expect(
        settings['sync_cursor_nha_TodoItem'],
        server.classOf('TodoItem').values.single['updatedAt'],
      );
      expect(settings['sync_rev_nha_TodoItem'], '1');
      expect(settings.containsKey('sync_cursor_nha'), isFalse);
    },
  );

  group('hasLocalChanges', () {
    test(
      'còn bump SyncMeta chưa gửi thì vẫn true, không gửi request nào',
      () async {
        await state.write('sync_meta_bump_nha', '["Clip"]');
        final sync = engine();

        expect(await sync.hasLocalChanges(), isTrue);
        expect(server.requests, isEmpty);

        await state.write('sync_meta_bump_nha', '');
        expect(await sync.hasLocalChanges(), isFalse);
        expect(server.requests, isEmpty);
      },
    );

    test('bump còn treo được gửi ở chu kỳ sau rồi xoá', () async {
      final metaId = server.seed('SyncMeta', {'space': 'nha', 'rev_Clip': 4});
      await legacySettings({
        'sync_meta_id_nha': metaId,
        'sync_meta_bump_nha': '["Clip"]',
      });
      final sync = engine();

      await sync.sync();

      expect(server.requests.first, 'PUT SyncMeta');
      expect(server.classOf('SyncMeta')[metaId]!['rev_Clip'], 5);
      expect(await state.read('sync_meta_bump_nha'), '');
      expect(await sync.hasLocalChanges(), isFalse);
    });

    test('thay đổi của collection ngoài clipboard cũng tính', () async {
      final sync = engine();
      expect(await sync.hasLocalChanges(), isFalse);
      notes.tombstones.add('obj-n');
      expect(await sync.hasLocalChanges(), isTrue);
      notes.tombstones.clear();
      todos.edit('t1', {'title': 'việc'});
      expect(await sync.hasLocalChanges(), isTrue);
    });
  });

  test('localChanges gộp thay đổi local của mọi collection, bỏ qua thay đổi do '
      'sync áp vào', () async {
    final sync = engine();
    var fired = 0;
    final sub = sync.localChanges.listen((_) => fired++);
    addTearDown(sub.cancel);

    await clips.saveClip(clip('c1', 'đã lưu'));
    await clips.saveGroup(clipGroup('g1', 'Nhóm'));
    todos.edit('t1', {'title': 'việc'});
    notes.edit('n1', {'body': 'ghi chú'});
    // A new temp clip stays on this device: nothing to push. Capturing one
    // stores it this way.
    await clips.saveClip(
      clip('tam', 'copy tự động', isSaved: false),
      share: false,
    );
    await settle();
    expect(fired, 4);

    fired = 0;
    server.seed('Clip', {
      'space': 'nha',
      'localId': 'c-may-kia',
      'content': 'từ máy kia',
      'isSaved': true,
    });
    server.bump('nha', 'Clip');
    await sync.sync();
    await settle();
    expect(fired, 0);
  });

  group('lỗi và trạng thái', () {
    test('chưa cấu hình thì không gửi request nào', () async {
      final status = await engine(withConfig: config(appId: '')).sync();

      expect(status.state, SyncState.notConfigured);
      expect(status.message, 'Chưa nhập App ID và Client Key của Back4App');
      expect(server.requests, isEmpty);
    });

    test('đang chạy thì lần gọi thứ hai trả trạng thái đang đồng bộ', () async {
      final sync = engine();
      final first = sync.sync();
      final second = await sync.sync();
      await first;

      expect(second.state, SyncState.running);
      expect(second.message, 'Đang đồng bộ…');
    });

    test('không kết nối được thì báo mất mạng', () async {
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final url = 'http://127.0.0.1:${closed.port}';
      await closed.close();

      final status = await engine(withConfig: config(serverUrl: url)).sync();

      expect(status.state, SyncState.error);
      expect(status.message, 'Không có kết nối mạng');
    });

    test('settings phản ánh cấu hình', () {
      final settings = engine().settings;
      expect(settings.isConfigured, isTrue);
      expect(settings.autoSync, isTrue);
      expect(settings.space, 'nha');
    });
  });
}
