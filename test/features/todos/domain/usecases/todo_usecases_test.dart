import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/core/domain/usecase.dart';
import 'package:event_notice/features/todos/domain/entities/todo.dart';
import 'package:event_notice/features/todos/domain/usecases/add_todo.dart';
import 'package:event_notice/features/todos/domain/usecases/clear_done_todos.dart';
import 'package:event_notice/features/todos/domain/usecases/get_todos.dart';
import 'package:event_notice/features/todos/domain/usecases/link_reminder.dart';
import 'package:event_notice/features/todos/domain/usecases/new_todo_id.dart';
import 'package:event_notice/features/todos/domain/usecases/remove_todo.dart';
import 'package:event_notice/features/todos/domain/usecases/save_todo.dart';
import 'package:event_notice/features/todos/domain/usecases/set_todo_done.dart';
import 'package:event_notice/features/todos/domain/usecases/watch_todos.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

final _t0 = DateTime(2026, 10, 22, 8);

DateTime _min(int m) => _t0.add(Duration(minutes: m));

Todo _todo(
  String id, {
  bool done = false,
  TodoPriority priority = TodoPriority.normal,
  DateTime? due,
  DateTime? completedAt,
  String? reminderId,
  int createdMin = 0,
}) => Todo(
  id: id,
  title: id,
  done: done,
  priority: priority,
  dueDate: due,
  completedAt: completedAt,
  reminderId: reminderId,
  createdAt: _min(createdMin),
  updatedAt: _min(createdMin),
);

List<String> _ids(Result<List<Todo>> r) => [
  for (final t in r.valueOrNull!) t.id,
];

void main() {
  const storageFailure = StorageFailure('disk');
  final now = DateTime(2026, 10, 22, 14, 30);
  late FakeClock clock;

  setUp(() => clock = FakeClock(now));

  group('GetTodos', () {
    test('sắp theo thứ tự hiển thị', () async {
      final repo = InMemoryTodoRepository([
        _todo('doneOld', done: true, completedAt: _min(5)),
        _todo('plain', createdMin: 1),
        _todo('doneNew', done: true, completedAt: _min(50)),
        _todo('due', due: _min(120)),
        _todo('high', priority: TodoPriority.high, createdMin: 3),
        _todo('low', priority: TodoPriority.low),
      ]);

      final result = await GetTodos(repo)(const NoParams());

      expect(_ids(result), [
        'high',
        'due',
        'plain',
        'low',
        'doneNew',
        'doneOld',
      ]);
    });

    test('lỗi của repository được trả lại nguyên vẹn', () async {
      final repo = InMemoryTodoRepository()..failure = storageFailure;
      expect(
        await GetTodos(repo)(const NoParams()),
        const Err<List<Todo>>(storageFailure),
      );
    });
  });

  group('WatchTodos', () {
    test('bắn sau mỗi lần repository đổi', () async {
      final repo = InMemoryTodoRepository();
      final stream = (await WatchTodos(repo)(const NoParams())).valueOrNull!;
      var fired = 0;
      final sub = stream.listen((_) => fired++);

      await repo.save(_todo('a'));
      await repo.delete('a');

      expect(fired, 2);
      await sub.cancel();
      await repo.dispose();
    });
  });

  group('AddTodo', () {
    test(
      'cắt khoảng trắng hai đầu, id mới, createdAt = updatedAt = now',
      () async {
        final repo = InMemoryTodoRepository();
        final add = AddTodo(repo, SequentialIdGenerator(), clock);

        final result = await add('  Mua sữa \n');

        final todo = result.valueOrNull!;
        expect(todo.id, 'id-1');
        expect(todo.title, 'Mua sữa');
        expect(todo.note, '');
        expect(todo.done, isFalse);
        expect(todo.priority, TodoPriority.normal);
        expect(todo.dueDate, isNull);
        expect(todo.reminderId, isNull);
        expect(todo.createdAt, now);
        expect(todo.updatedAt, now);
        expect(repo['id-1'], todo);
      },
    );

    test('tiêu đề rỗng hoặc chỉ có khoảng trắng thì bỏ qua', () async {
      final repo = InMemoryTodoRepository();
      final ids = SequentialIdGenerator();
      final add = AddTodo(repo, ids, clock);

      expect(await add(''), const Ok<Todo?>(null));
      expect(await add('   \t\n'), const Ok<Todo?>(null));

      expect(repo.length, 0);
      expect(repo.writes, 0);
      // No id was spent on the ignored input.
      expect(ids.newId(), 'id-1');
    });

    test('lỗi khi lưu được trả lại', () async {
      final repo = InMemoryTodoRepository()..failure = storageFailure;
      final add = AddTodo(repo, SequentialIdGenerator(), clock);
      expect(await add('Việc'), const Err<Todo?>(storageFailure));
    });
  });

  group('SaveTodo', () {
    test('lưu với updatedAt = now, giữ nguyên các field khác', () async {
      final repo = InMemoryTodoRepository();
      final todo = _todo(
        'a',
        priority: TodoPriority.high,
        due: _min(60),
        reminderId: 'r1',
      );

      expect(await SaveTodo(repo, clock)(todo), const Ok<void>(null));

      expect(repo['a'], todo.copyWith(updatedAt: now));
      expect(repo['a']!.createdAt, todo.createdAt);
    });

    test('thay bản cũ cùng id', () async {
      final repo = InMemoryTodoRepository([_todo('a')]);
      await SaveTodo(repo, clock)(_todo('a').copyWith(title: 'Đã sửa'));
      expect(repo.length, 1);
      expect(repo['a']!.title, 'Đã sửa');
    });

    test('lỗi khi lưu được trả lại', () async {
      final repo = InMemoryTodoRepository()..failure = storageFailure;
      expect(
        await SaveTodo(repo, clock)(_todo('a')),
        const Err<void>(storageFailure),
      );
    });
  });

  group('SetTodoDone', () {
    test('done = true đặt completedAt = now và updatedAt = now', () async {
      final repo = InMemoryTodoRepository([_todo('a')]);

      await SetTodoDone(repo, clock)((todo: _todo('a'), done: true));

      final saved = repo['a']!;
      expect(saved.done, isTrue);
      expect(saved.completedAt, now);
      expect(saved.updatedAt, now);
    });

    test('done = false xoá completedAt, updatedAt = now', () async {
      final finished = _todo('a', done: true, completedAt: _min(5));
      final repo = InMemoryTodoRepository([finished]);

      await SetTodoDone(repo, clock)((todo: finished, done: false));

      final saved = repo['a']!;
      expect(saved.done, isFalse);
      expect(saved.completedAt, isNull);
      expect(saved.updatedAt, now);
    });
  });

  group('LinkReminder', () {
    test('ghi id nhắc nhở, updatedAt = now', () async {
      final repo = InMemoryTodoRepository([_todo('a')]);

      await LinkReminder(repo, clock)((todo: _todo('a'), reminderId: 'r1'));

      expect(repo['a']!.reminderId, 'r1');
      expect(repo['a']!.updatedAt, now);
    });

    test('null gỡ liên kết', () async {
      final linked = _todo('a', reminderId: 'r1');
      final repo = InMemoryTodoRepository([linked]);

      await LinkReminder(repo, clock)((todo: linked, reminderId: null));

      expect(repo['a']!.reminderId, isNull);
      expect(repo['a']!.updatedAt, now);
    });

    test('cùng reminderId thì không ghi gì', () async {
      final linked = _todo('a', reminderId: 'r1');
      final repo = InMemoryTodoRepository([linked]);
      final link = LinkReminder(repo, clock);

      expect(
        await link((todo: linked, reminderId: 'r1')),
        const Ok<void>(null),
      );
      expect(
        await link((todo: _todo('b'), reminderId: null)),
        const Ok<void>(null),
      );

      expect(repo.writes, 0);
      expect(repo['a'], linked);
    });
  });

  group('RemoveTodo', () {
    test('xoá đúng việc theo id', () async {
      final repo = InMemoryTodoRepository([_todo('a'), _todo('b')]);

      expect(await RemoveTodo(repo)('a'), const Ok<void>(null));

      expect(repo['a'], isNull);
      expect(repo['b'], isNotNull);
      expect(repo.deleted, ['a']);
    });
  });

  group('ClearDoneTodos', () {
    test('xoá mọi việc đã xong và trả về số việc đã xoá', () async {
      final repo = InMemoryTodoRepository([
        _todo('open'),
        _todo('d1', done: true),
        _todo('d2', done: true),
      ]);

      final result = await ClearDoneTodos(repo)(const NoParams());

      expect(result, const Ok(2));
      expect(repo.length, 1);
      expect(repo['open'], isNotNull);
      expect(repo.deleted, unorderedEquals(['d1', 'd2']));
      expect(repo.writes, 1);
    });

    test('không có việc nào đã xong thì trả 0 và không ghi gì', () async {
      final repo = InMemoryTodoRepository([_todo('open')]);

      expect(await ClearDoneTodos(repo)(const NoParams()), const Ok(0));
      expect(
        await ClearDoneTodos(InMemoryTodoRepository())(const NoParams()),
        const Ok(0),
      );

      expect(repo.writes, 0);
      expect(repo.length, 1);
    });

    test('lỗi khi đọc được trả lại', () async {
      final repo = InMemoryTodoRepository([_todo('d', done: true)])
        ..failure = storageFailure;
      expect(
        await ClearDoneTodos(repo)(const NoParams()),
        const Err<int>(storageFailure),
      );
    });
  });

  group('NewTodoId', () {
    test('lấy id từ IdGenerator', () async {
      final newId = NewTodoId(SequentialIdGenerator());
      expect(await newId(const NoParams()), const Ok('id-1'));
      expect(await newId(const NoParams()), const Ok('id-2'));
    });
  });
}
