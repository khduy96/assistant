import 'dart:io';

import 'package:event_notice/core/data/app_database.dart';
import 'package:event_notice/core/data/sqlite_sync_state_store.dart';
import 'package:event_notice/core/data/system_clock.dart';
import 'package:event_notice/core/data/uuid_id_generator.dart';
import 'package:event_notice/core/sync/data/parse_config.dart';
import 'package:event_notice/core/sync/data/parse_sync_engine.dart';
import 'package:event_notice/core/sync/domain/entities/sync_status.dart';
import 'package:event_notice/core/sync/domain/sync_channel.dart';
import 'package:event_notice/features/clipboard/data/datasources/clip_local_data_source.dart';
import 'package:event_notice/features/clipboard/data/repositories/clipboard_repository_impl.dart';
import 'package:event_notice/features/clipboard/data/sync/clip_group_sync_collection.dart';
import 'package:event_notice/features/clipboard/data/sync/clip_sync_collection.dart';
import 'package:event_notice/features/notes/data/datasources/note_local_data_source.dart';
import 'package:event_notice/features/notes/data/repositories/note_repository_impl.dart';
import 'package:event_notice/features/notes/data/sync/note_sync_collection.dart';
import 'package:event_notice/features/notes/domain/entities/note.dart';
import 'package:event_notice/features/notes/domain/usecases/delete_note.dart';
import 'package:event_notice/features/notes/domain/usecases/get_notes.dart';
import 'package:event_notice/features/notes/domain/usecases/new_note.dart';
import 'package:event_notice/features/notes/domain/usecases/save_note.dart';
import 'package:event_notice/features/notes/domain/usecases/search_notes.dart';
import 'package:event_notice/features/notes/domain/usecases/set_note_pinned.dart';
import 'package:event_notice/features/notes/domain/usecases/watch_notes.dart';
import 'package:event_notice/features/notes/presentation/notes_controller.dart';
import 'package:event_notice/features/todos/data/datasources/todo_local_data_source.dart';
import 'package:event_notice/features/todos/data/repositories/todo_repository_impl.dart';
import 'package:event_notice/features/todos/data/sync/todo_sync_collection.dart';
import 'package:event_notice/features/todos/domain/usecases/add_todo.dart';
import 'package:event_notice/features/todos/domain/usecases/clear_done_todos.dart';
import 'package:event_notice/features/todos/domain/usecases/draft_reminder_from_todo.dart';
import 'package:event_notice/features/todos/domain/usecases/find_linked_reminder.dart';
import 'package:event_notice/features/todos/domain/usecases/get_todos.dart';
import 'package:event_notice/features/todos/domain/usecases/link_reminder.dart';
import 'package:event_notice/features/todos/domain/usecases/new_todo_id.dart';
import 'package:event_notice/features/todos/domain/usecases/remove_linked_reminder.dart';
import 'package:event_notice/features/todos/domain/usecases/remove_todo.dart';
import 'package:event_notice/features/todos/domain/usecases/save_todo.dart';
import 'package:event_notice/features/todos/domain/usecases/set_linked_reminder_enabled.dart';
import 'package:event_notice/features/todos/domain/usecases/set_todo_done.dart';
import 'package:event_notice/features/todos/domain/usecases/watch_linked_reminders.dart';
import 'package:event_notice/features/todos/domain/usecases/watch_todos.dart';
import 'package:event_notice/features/todos/presentation/todos_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../features/todos/domain/fakes.dart' show FakeLinkedReminderRepository;
import '../fake_parse_server.dart';

/// Việc cần làm và ghi chú đi nhờ vòng đồng bộ của clipboard, nhưng chúng nằm
/// trong file JSON chứ không phải SQLite — nên luồng riêng của chúng được thử
/// ở đây, trên cùng một fake Back4App.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dir;
  late AppDatabase db;
  late FakeParseServer server;
  late TodoRepositoryImpl todoRepo;
  late TodosController todos;
  late NoteRepositoryImpl noteRepo;
  late NotesController notes;
  late ParseSyncEngine sync;

  /// Kho việc và kho ghi chú của máy dựng gần nhất bằng [secondDevice].
  late TodoRepositoryImpl otherTodoRepo;
  late NoteRepositoryImpl otherNoteRepo;

  const clock = SystemClock();

  /// Cơ sở dữ liệu của những "máy" dựng thêm trong bài test, phải đóng trước
  /// khi xoá thư mục tạm — Windows không cho xoá file đang mở.
  final extraDbs = <AppDatabase>[];

  /// Việc cần làm của một "máy": kho đọc file JSON ở [path] và controller mà
  /// tab việc dùng, nối với nhau bằng các use case thật. Không có nhắc nhở
  /// nào để liên kết.
  Future<(TodoRepositoryImpl, TodosController)> todosAt(String path) async {
    final repo = TodoRepositoryImpl(TodoLocalDataSource(clock, path: path));
    final links = FakeLinkedReminderRepository();
    const ids = UuidIdGenerator();
    final controller = TodosController(
      getTodos: GetTodos(repo),
      watchTodos: WatchTodos(repo),
      addTodo: AddTodo(repo, ids, clock),
      saveTodo: SaveTodo(repo, clock),
      setTodoDone: SetTodoDone(repo, clock),
      linkReminder: LinkReminder(repo, clock),
      removeTodo: RemoveTodo(repo),
      clearDoneTodos: ClearDoneTodos(repo),
      newTodoId: NewTodoId(ids),
      draftReminderFromTodo: DraftReminderFromTodo(clock),
      findLinkedReminder: FindLinkedReminder(links),
      setLinkedReminderEnabled: SetLinkedReminderEnabled(links),
      removeLinkedReminder: RemoveLinkedReminder(links),
      watchLinkedReminders: WatchLinkedReminders(links),
      clock: clock,
    );
    await repo.init();
    await controller.init();
    return (repo, controller);
  }

  /// Ghi chú của một "máy": kho đọc file JSON ở [path] và controller mà tab
  /// ghi chú dùng, nối với nhau bằng các use case thật.
  Future<(NoteRepositoryImpl, NotesController)> notesAt(String path) async {
    final repo = NoteRepositoryImpl(NoteLocalDataSource(clock, path: path));
    final controller = NotesController(
      getNotes: GetNotes(repo),
      searchNotes: SearchNotes(repo),
      saveNote: SaveNote(repo, clock),
      deleteNote: DeleteNote(repo),
      setNotePinned: SetNotePinned(repo, clock),
      watchNotes: WatchNotes(repo),
      newNote: NewNote(const UuidIdGenerator(), clock),
    );
    await repo.init();
    await controller.init();
    return (repo, controller);
  }

  /// Ghi chú vừa gõ xong trong editor; khi lưu, SaveNote đặt lại updatedAt.
  Note note(String id, {String title = '', String body = ''}) {
    final now = clock.now();
    return Note(
      id: id,
      title: title,
      body: body,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Dựng lại đúng bộ store đọc từ những file JSON đó — đóng vai máy thứ hai,
  /// hoặc chính máy này sau khi mở lại app.
  /// Engine của một "máy": clipboard trong [database], cùng việc cần làm và
  /// ghi chú của máy đó, theo đúng thứ tự app đăng ký.
  ParseSyncEngine engineFor(
    AppDatabase database,
    TodoRepositoryImpl todoRepository,
    NoteRepositoryImpl noteRepository,
  ) {
    final clips = ClipboardRepositoryImpl(ClipLocalDataSource(database), clock);
    return ParseSyncEngine(
      config: ParseConfig(
        appId: 'app',
        clientKey: 'key',
        serverUrl: server.url,
        space: 'nha',
      ),
      state: SqliteSyncStateStore(database),
      channels: [
        SyncChannel.shared([
          ClipGroupSyncCollection(clips, clock),
          ClipSyncCollection(clips, clock),
        ]),
        SyncChannel.single(TodoSyncCollection(todoRepository, clock)),
        SyncChannel.single(NoteSyncCollection(noteRepository, clock)),
      ],
      clock: clock,
    );
  }

  Future<(TodosController, NotesController, ParseSyncEngine)>
      secondDevice() async {
    final (todoRepo, otherTodos) = await todosAt('${dir.path}/todos2.json');
    otherTodoRepo = todoRepo;
    final (repo, otherNotes) = await notesAt('${dir.path}/notes2.json');
    otherNoteRepo = repo;
    final otherDb = AppDatabase.atPath('${dir.path}/test2.db');
    extraDbs.add(otherDb);
    return (
      otherTodos,
      otherNotes,
      engineFor(otherDb, otherTodoRepo, otherNoteRepo),
    );
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('task_sync_test');
    db = AppDatabase.atPath('${dir.path}/test.db');
    server = await FakeParseServer.start();
    (todoRepo, todos) = await todosAt('${dir.path}/todos.json');
    (noteRepo, notes) = await notesAt('${dir.path}/notes.json');
    sync = engineFor(db, todoRepo, noteRepo);
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
    await notes.save(note('n1', title: 'Wifi', body: '12345678'));

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

    expect(todoRepo.models.single.dirty, isFalse);
    expect(todoRepo.models.single.remoteId, isNotNull);
    expect(noteRepo.models.single.dirty, isFalse);
    expect(noteRepo.models.single.remoteId, isNotNull);
  });

  test('sync lần hai không tạo bản sao', () async {
    await todos.add('một lần thôi');
    await notes.save(note('n1', body: 'một lần thôi'));
    await sync.sync();
    await sync.sync();

    expect(server.classOf('TodoItem'), hasLength(1));
    expect(server.classOf('NoteItem'), hasLength(1));
  });

  test('máy thứ hai kéo được việc và ghi chú về', () async {
    await todos.add('gọi điện cho mẹ');
    await notes.save(note('n1', title: 'Ý tưởng', body: 'làm app'));
    await sync.sync();

    final (otherTodos, otherNotes, otherSync) = await secondDevice();
    await otherSync.sync();

    expect(otherTodos.todos.single.title, 'gọi điện cho mẹ');
    expect(otherNotes.notes.single.title, 'Ý tưởng');
    // Vừa kéo về thì không có gì để đẩy lại.
    expect(otherTodoRepo.models.single.dirty, isFalse);
    expect(otherNoteRepo.models.single.dirty, isFalse);
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
    await notes.save(note('n1', body: 'ghi chú thừa'));
    await sync.sync();
    final (otherTodos, otherNotes, otherSync) = await secondDevice();
    await otherSync.sync();
    expect(otherTodos.todos, hasLength(1));

    await todos.remove(todos.todos.single.id);
    await notes.delete('n1');
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
    await otherTodos.save(
      otherTodos.todos.single.copyWith(title: 'bản của máy kia'),
    );
    await otherSync.sync();

    final mine = todos.todos.single.copyWith(title: 'bản mới nhất');
    await todos.save(mine);
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
