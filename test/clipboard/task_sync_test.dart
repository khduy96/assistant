import 'dart:io';

import 'package:event_notice/clipboard/data/app_database.dart';
import 'package:event_notice/clipboard/data/clip_repository.dart';
import 'package:event_notice/clipboard/sync/parse_config.dart';
import 'package:event_notice/clipboard/sync/sync_service.dart';
import 'package:event_notice/models/note.dart';
import 'package:event_notice/services/note_storage.dart';
import 'package:event_notice/services/note_store.dart';
import 'package:event_notice/services/todo_storage.dart';
import 'package:event_notice/services/todo_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_parse_server.dart';

/// Việc cần làm và ghi chú đi nhờ vòng đồng bộ của clipboard, nhưng chúng nằm
/// trong file JSON chứ không phải SQLite — nên luồng riêng của chúng được thử
/// ở đây, trên cùng một fake Back4App.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dir;
  late AppDatabase db;
  late FakeParseServer server;
  late TodoStore todos;
  late NoteStore notes;
  late SyncService sync;

  /// Cơ sở dữ liệu của những "máy" dựng thêm trong bài test, phải đóng trước
  /// khi xoá thư mục tạm — Windows không cho xoá file đang mở.
  final extraDbs = <AppDatabase>[];

  /// Dựng lại đúng bộ store đọc từ những file JSON đó — đóng vai máy thứ hai,
  /// hoặc chính máy này sau khi mở lại app.
  Future<(TodoStore, NoteStore, SyncService)> secondDevice() async {
    final otherTodos =
        TodoStore(storage: TodoStorage(path: '${dir.path}/todos2.json'));
    final otherNotes =
        NoteStore(storage: NoteStorage(path: '${dir.path}/notes2.json'));
    await otherTodos.init();
    await otherNotes.init();
    final otherDb = AppDatabase.atPath('${dir.path}/test2.db');
    extraDbs.add(otherDb);
    return (
      otherTodos,
      otherNotes,
      SyncService(
        repository: ClipRepository(db: otherDb),
        config: ParseConfig(
          appId: 'app',
          clientKey: 'key',
          serverUrl: server.url,
          space: 'nha',
        ),
        collections: [otherTodos.syncCollection, otherNotes.syncCollection],
      ),
    );
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('task_sync_test');
    db = AppDatabase.atPath('${dir.path}/test.db');
    server = await FakeParseServer.start();
    todos = TodoStore(storage: TodoStorage(path: '${dir.path}/todos.json'));
    notes = NoteStore(storage: NoteStorage(path: '${dir.path}/notes.json'));
    await todos.init();
    await notes.init();
    sync = SyncService(
      repository: ClipRepository(db: db),
      config: ParseConfig(
        appId: 'app',
        clientKey: 'key',
        serverUrl: server.url,
        space: 'nha',
      ),
      collections: [todos.syncCollection, notes.syncCollection],
    );
  });

  tearDown(() async {
    await db.close();
    for (final extra in extraDbs) {
      await extra.close();
    }
    extraDbs.clear();
    await server.stop();
    await dir.delete(recursive: true);
  });

  test('đẩy việc và ghi chú mới lên rồi đánh dấu đã sạch', () async {
    await todos.add('mua sữa');
    await notes.upsert(Note(id: 'n1', title: 'Wifi', body: '12345678'));

    final status = await sync.sync();
    expect(status.state, SyncState.ok);

    final remoteTodo = server.classOf('TodoItem').values.single;
    expect(remoteTodo['title'], 'mua sữa');
    expect(remoteTodo['space'], 'nha');
    // Parse tự giữ hai tên này, nên bản thân app phải dùng tên khác.
    expect(remoteTodo['todoUpdatedAt'], isA<num>());

    final remoteNote = server.classOf('NoteItem').values.single;
    expect(remoteNote['title'], 'Wifi');
    expect(remoteNote['body'], '12345678');

    expect(todos.todos.single.dirty, isFalse);
    expect(todos.todos.single.remoteId, isNotNull);
    expect(notes.notes.single.dirty, isFalse);
    expect(notes.notes.single.remoteId, isNotNull);
  });

  test('sync lần hai không tạo bản sao', () async {
    await todos.add('một lần thôi');
    await notes.upsert(Note(id: 'n1', body: 'một lần thôi'));
    await sync.sync();
    await sync.sync();

    expect(server.classOf('TodoItem'), hasLength(1));
    expect(server.classOf('NoteItem'), hasLength(1));
  });

  test('máy thứ hai kéo được việc và ghi chú về', () async {
    await todos.add('gọi điện cho mẹ');
    await notes.upsert(Note(id: 'n1', title: 'Ý tưởng', body: 'làm app'));
    await sync.sync();

    final (otherTodos, otherNotes, otherSync) = await secondDevice();
    await otherSync.sync();

    expect(otherTodos.todos.single.title, 'gọi điện cho mẹ');
    expect(otherNotes.notes.single.title, 'Ý tưởng');
    // Vừa kéo về thì không có gì để đẩy lại.
    expect(otherTodos.todos.single.dirty, isFalse);
    expect(otherNotes.notes.single.dirty, isFalse);
  });

  test('tick xong ở máy này thì máy kia cũng thấy đã xong', () async {
    await todos.add('quét nhà');
    await sync.sync();
    final (otherTodos, _, otherSync) = await secondDevice();
    await otherSync.sync();
    expect(otherTodos.todos.single.done, isFalse);

    await todos.setDone(todos.todos.single, true);
    await sync.sync();
    await otherSync.sync();

    expect(otherTodos.todos.single.done, isTrue);
    expect(otherTodos.todos.single.completedAt, isNotNull);
  });

  test('xoá ở máy này thì object trên server và máy kia cũng mất', () async {
    await todos.add('việc thừa');
    await notes.upsert(Note(id: 'n1', body: 'ghi chú thừa'));
    await sync.sync();
    final (otherTodos, otherNotes, otherSync) = await secondDevice();
    await otherSync.sync();
    expect(otherTodos.todos, hasLength(1));

    await todos.remove(todos.todos.single.id);
    await notes.remove('n1');
    await sync.sync();

    expect(server.classOf('TodoItem'), isEmpty);
    expect(server.classOf('NoteItem'), isEmpty);

    await otherSync.sync();
    expect(otherTodos.todos, isEmpty);
    expect(otherNotes.notes, isEmpty);
  });

  test('sửa tại máy này thắng bản cũ hơn trên server', () async {
    await todos.add('bản cũ');
    await sync.sync();
    final (otherTodos, _, otherSync) = await secondDevice();
    await otherSync.sync();

    // Máy kia sửa trước, máy này sửa sau — bản sau phải thắng.
    await otherTodos.upsert(otherTodos.todos.single..title = 'bản của máy kia');
    await otherSync.sync();

    final mine = todos.todos.single..title = 'bản mới nhất';
    await todos.upsert(mine);
    await sync.sync();
    await otherSync.sync();

    expect(todos.todos.single.title, 'bản mới nhất');
    expect(otherTodos.todos.single.title, 'bản mới nhất');
  });

  test('việc chưa kịp đẩy lên KHÔNG bị bước đối chiếu xoá nhầm', () async {
    await todos.add('đã đồng bộ');
    await sync.sync();
    await todos.add('vừa gõ xong, chưa sync');

    await sync.sync();

    expect(todos.todos, hasLength(2));
    expect(server.classOf('TodoItem'), hasLength(2));
  });
}
