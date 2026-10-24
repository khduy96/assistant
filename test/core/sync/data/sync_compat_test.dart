import 'dart:io';

import 'package:event_notice/core/data/app_database.dart';
import 'package:event_notice/core/data/sqlite_sync_state_store.dart';
import 'package:event_notice/core/sync/data/parse_config.dart';
import 'package:event_notice/core/sync/data/parse_sync_engine.dart';
import 'package:event_notice/core/sync/domain/entities/sync_budget.dart';
import 'package:event_notice/core/sync/domain/entities/sync_status.dart';
import 'package:event_notice/core/sync/domain/sync_channel.dart';
import 'package:event_notice/features/clipboard/data/datasources/clip_local_data_source.dart';
import 'package:event_notice/features/clipboard/data/repositories/clipboard_repository_impl.dart';
import 'package:event_notice/features/clipboard/data/sync/clip_group_sync_collection.dart';
import 'package:event_notice/features/clipboard/data/sync/clip_sync_collection.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_group.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_item.dart';
import 'package:event_notice/features/todos/data/datasources/todo_local_data_source.dart';
import 'package:event_notice/features/todos/data/repositories/todo_repository_impl.dart';
import 'package:event_notice/features/todos/data/sync/todo_sync_collection.dart';
import 'package:event_notice/features/todos/domain/entities/todo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../fake_parse_server.dart';
import '../fakes.dart';

/// One device of the space: the real clipboard database, the real todo list,
/// an in-memory list for the notes, and its engine.
class _Device {
  _Device({
    required this.name,
    required this.db,
    required this.source,
    required this.clips,
    required this.todos,
    required this.notes,
    required this.engine,
    required this.legacy,
  });

  final String name;
  final AppDatabase db;
  final ClipLocalDataSource source;
  final ClipboardRepositoryImpl clips;
  final TodoRepositoryImpl todos;
  final MemorySyncCollection notes;
  final ParseSyncEngine engine;

  /// Speaks the protocol of the build at commit 158d0e0.
  final bool legacy;

  /// One cycle as this build runs it: the new build's automatic cycle, or
  /// the only kind of cycle the old build had.
  Future<SyncStatus> sync() => legacy ? engine.sync() : engine.sync(auto: true);

  Future<Map<String, String>> todoTitles() async {
    await todos.ensureLoaded();
    return {for (final todo in todos.models) todo.id: todo.title};
  }

  Future<Map<String, String>> savedClips() async => {
    for (final clip in await source.clips())
      if (clip.isSaved) clip.id: clip.content,
  };

  Future<Set<String>> groupIds() async => {
    for (final group in await source.groups()) group.id,
  };

  Set<String> noteIds() => notes.rows.keys.toSet();
}

/// A device on the new build and one on the build at commit 158d0e0, on the
/// same space. The old build is played by the new engine set to its
/// protocol: never one pass, never automatic, always asking the server.
///
/// Nothing on the wire changed (classes, fields, the `Increment` on
/// `SyncMeta`), so what is checked here is that the two ways of pulling see
/// each other's writes, deletes included.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dir;
  late FakeParseServer server;
  late FixedClock clock;
  final devices = <_Device>[];

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sync_compat_test');
    server = FakeParseServer.memory();
    clock = FixedClock(DateTime(2026, 10, 22, 9));
  });

  tearDown(() async {
    for (final device in devices) {
      await device.notes.close();
      await device.clips.dispose();
      await device.todos.dispose();
      await device.db.close();
    }
    devices.clear();
    await dir.delete(recursive: true);
  });

  Future<_Device> device(String name, {required bool legacy}) async {
    final db = AppDatabase.atPath('${dir.path}/$name.db');
    final source = ClipLocalDataSource(db);
    final clips = ClipboardRepositoryImpl(source, clock);
    final todos = TodoRepositoryImpl(
      TodoLocalDataSource(clock, path: '${dir.path}/$name-todos.json'),
    );
    await todos.init();
    final notes = MemorySyncCollection('NoteItem');
    final engine = ParseSyncEngine(
      config: ParseConfig(
        appId: 'app',
        clientKey: 'key',
        serverUrl: server.url,
        space: 'nha',
      ),
      state: SqliteSyncStateStore(db),
      channels: [
        SyncChannel.shared([
          ClipGroupSyncCollection(clips, clock),
          ClipSyncCollection(clips, clock),
        ]),
        SyncChannel.single(TodoSyncCollection(todos, clock)),
        SyncChannel.single(notes),
      ],
      clock: clock,
      httpClientFactory: () => server.client(tag: name),
      onePassMaxRows: legacy ? 0 : 500,
    );
    final created = _Device(
      name: name,
      db: db,
      source: source,
      clips: clips,
      todos: todos,
      notes: notes,
      engine: engine,
      legacy: legacy,
    );
    devices.add(created);
    return created;
  }

  /// Moves the shared clock on, so every edit gets a later timestamp.
  void tick() => clock.current = clock.current.add(const Duration(minutes: 1));

  Future<void> saveTodo(_Device on, String id, String title) async {
    await on.todos.ensureLoaded();
    final stored = on.todos.models.where((t) => t.id == id).firstOrNull;
    await on.todos.save(
      Todo(
        id: id,
        title: title,
        createdAt: stored?.createdAt ?? clock.now(),
        updatedAt: clock.now(),
      ),
    );
  }

  Future<void> saveClip(_Device on, String id, {String? groupId}) =>
      on.clips.saveClip(
        ClipItem(
          id: id,
          content: 'clip $id',
          type: ClipType.text,
          createdAt: clock.now(),
          updatedAt: clock.now(),
          isSaved: true,
          groupId: groupId,
        ),
      );

  Future<void> saveGroup(_Device on, String id) => on.clips.saveGroup(
    ClipGroup(
      id: id,
      name: 'nhóm $id',
      color: 0xFF5B8DEF,
      createdAt: clock.now(),
      updatedAt: clock.now(),
    ),
  );

  Map<String, Object?> onServer(String className, String field) => {
    for (final row in server.classOf(className).values)
      row['localId']! as String: row[field],
  };

  /// Both devices hold what the server holds, class by class.
  Future<void> expectConverged(_Device a, _Device b) async {
    final todos = onServer('TodoItem', 'title');
    final clips = onServer('Clip', 'content');
    final groups = onServer('ClipGroup', 'name').keys.toSet();
    final notes = onServer('NoteItem', 'localId').keys.toSet();
    for (final d in [a, b]) {
      expect(await d.todoTitles(), todos, reason: '${d.name}: TodoItem');
      expect(await d.savedClips(), clips, reason: '${d.name}: Clip');
      expect(await d.groupIds(), groups, reason: '${d.name}: ClipGroup');
      expect(d.noteIds(), notes, reason: '${d.name}: NoteItem');
      expect(await d.engine.hasLocalChanges(), isFalse, reason: d.name);
    }
  }

  test('tạo, sửa và xoá ở cả hai phía đều hội tụ', () async {
    final a = await device('A', legacy: false);
    final b = await device('B', legacy: true);

    await saveTodo(a, 'a1', 'việc của A');
    await saveClip(a, 'ca');
    a.notes.edit('na', {'body': 'ghi chú của A'});
    await saveTodo(b, 'b1', 'việc của B');
    await saveGroup(b, 'gb');
    await saveClip(b, 'cb', groupId: 'gb');
    b.notes.edit('nb', {'body': 'ghi chú của B'});

    for (final d in [a, b, a]) {
      expect((await d.sync()).state, SyncState.ok);
    }
    expect(onServer('TodoItem', 'title'), {
      'a1': 'việc của A',
      'b1': 'việc của B',
    });
    await expectConverged(a, b);
    expect(
      (await a.source.clips()).firstWhere((c) => c.id == 'cb').groupId,
      'gb',
    );

    tick();
    await saveTodo(a, 'b1', 'A sửa việc của B');
    await a.clips.deleteClips(['cb']);
    await saveTodo(b, 'a1', 'B sửa việc của A');
    await b.todos.delete('b1');
    b.notes.delete('na');
    await saveTodo(b, 'b2', 'việc mới của B');

    for (final d in [a, b, a]) {
      expect((await d.sync()).state, SyncState.ok);
    }

    // B's delete of b1 went out after A's edit of it: the delete stands.
    expect(onServer('TodoItem', 'title'), {
      'a1': 'B sửa việc của A',
      'b2': 'việc mới của B',
    });
    expect(onServer('Clip', 'content').keys, ['ca']);
    expect(onServer('NoteItem', 'localId').keys, ['nb']);
    await expectConverged(a, b);
  });

  for (final newer in ['A', 'B']) {
    test('sửa cùng một việc ở hai máy: bản có updatedAt của app mới hơn '
        '(máy $newer) thắng ở cả hai máy', () async {
      final a = await device('A', legacy: false);
      final b = await device('B', legacy: true);
      await saveTodo(a, 't1', 'bản đầu');
      await a.sync();
      await b.sync();
      expect(await b.todoTitles(), {'t1': 'bản đầu'});

      final (first, second) = newer == 'A' ? (b, a) : (a, b);
      tick();
      await saveTodo(first, 't1', 'bản cũ hơn của ${first.name}');
      tick();
      await saveTodo(second, 't1', 'bản mới hơn của ${second.name}');

      await first.sync();
      await second.sync();
      await first.sync();

      expect(onServer('TodoItem', 'title'), {'t1': 'bản mới hơn của $newer'});
      await expectConverged(a, b);
    });
  }

  test('máy vừa đẩy không kéo lại dữ liệu của chính mình khi không ai khác '
      'ghi, ở cả hai bản', () async {
    final a = await device('A', legacy: false);
    final b = await device('B', legacy: true);
    for (final d in [a, b, a]) {
      await d.sync();
    }

    for (final (writer, reader) in [(a, b), (b, a)]) {
      tick();
      await saveTodo(writer, 't-${writer.name}', 'của ${writer.name}');
      await saveClip(writer, 'c-${writer.name}');
      final from = server.log.length;

      await writer.sync();

      final cycle = [for (final request in server.log.skip(from)) '$request'];
      expect(cycle, [
        'POST Clip',
        'POST TodoItem',
        'PUT SyncMeta',
        'GET SyncMeta',
      ], reason: writer.name);

      // The other device sees it on its next cycle.
      await reader.sync();
      expect(
        (await reader.todoTitles())['t-${writer.name}'],
        'của ${writer.name}',
      );
    }
    await expectConverged(a, b);
  });

  test('bản ghi có trên server mà bộ đếm không tăng tới được máy A ở lần '
      'pull đầy đủ khi đến hạn budget.fullPullEvery', () async {
    final every = SyncBudget.configured.fullPullEvery(SyncBudgetLevel.normal);
    expect(every, lessThanOrEqualTo(const Duration(hours: 24)));
    final a = await device('A', legacy: false);
    final start = clock.now();
    await a.sync();

    server.seed('TodoItem', {
      'space': 'nha',
      'localId': 't-khong-bump',
      'title': 'đẩy mà không tăng bộ đếm',
      'todoCreatedAt': start.millisecondsSinceEpoch,
      'todoUpdatedAt': start.millisecondsSinceEpoch,
    });

    clock.current = start.add(every - const Duration(minutes: 1));
    await a.sync();
    expect(await a.todoTitles(), isEmpty);

    clock.current = start.add(every);
    await a.sync();
    expect(await a.todoTitles(), {'t-khong-bump': 'đẩy mà không tăng bộ đếm'});
  });
}
