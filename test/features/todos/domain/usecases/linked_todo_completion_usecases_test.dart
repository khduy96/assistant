import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/features/todos/domain/entities/todo.dart';
import 'package:event_notice/features/todos/domain/usecases/complete_todos_linked_to.dart';
import 'package:event_notice/features/todos/domain/usecases/find_open_todos_linked_to.dart';
import 'package:event_notice/features/todos/domain/usecases/set_todo_done.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

final _t0 = DateTime(2026, 10, 22, 8);

DateTime _min(int m) => _t0.add(Duration(minutes: m));

Todo _todo(
  String id, {
  bool done = false,
  TodoPriority priority = TodoPriority.normal,
  DateTime? completedAt,
  String? reminderId,
  int createdMin = 0,
}) => Todo(
  id: id,
  title: id,
  done: done,
  priority: priority,
  completedAt: completedAt,
  reminderId: reminderId,
  createdAt: _min(createdMin),
  updatedAt: _min(createdMin),
);

/// Saves normally until [failAfter] saves went through, then fails every save.
class _FailingLaterRepository extends InMemoryTodoRepository {
  _FailingLaterRepository(super.initial, {required this.failAfter});

  final int failAfter;
  int _saves = 0;

  @override
  Future<Result<void>> save(Todo todo) async {
    if (_saves++ >= failAfter) return const Err(StorageFailure('disk full'));
    return super.save(todo);
  }
}

/// Like `TodoRepositoryImpl` when the file cannot be written: every save
/// lands in memory, then reports a failure. [landed] stands in for what the
/// memory ends up holding, e.g. an edit made while the write was failing.
class _KeepsFailedSaveRepository extends InMemoryTodoRepository {
  _KeepsFailedSaveRepository(super.initial, {Todo Function(Todo)? landed})
    : _landed = landed ?? ((t) => t);

  final Todo Function(Todo) _landed;

  @override
  Future<Result<void>> save(Todo todo) async {
    await super.save(_landed(todo));
    return const Err(StorageFailure('disk full'));
  }
}

void main() {
  const storageFailure = StorageFailure('disk');
  final now = DateTime(2026, 10, 22, 14, 30);
  late FakeClock clock;

  setUp(() => clock = FakeClock(now));

  CompleteTodosLinkedTo complete(InMemoryTodoRepository repo) =>
      CompleteTodosLinkedTo(
        FindOpenTodosLinkedTo(repo),
        SetTodoDone(repo, clock),
        repo,
        clock,
      );

  group('FindOpenTodosLinkedTo', () {
    test(
      'chỉ trả việc chưa xong trỏ tới đúng nhắc nhở, theo thứ tự hiển thị',
      () async {
        final repo = InMemoryTodoRepository([
          _todo('old', reminderId: 'r1'),
          _todo('done', done: true, completedAt: _min(5), reminderId: 'r1'),
          _todo('other', reminderId: 'r2'),
          _todo('plain'),
          _todo(
            'high',
            priority: TodoPriority.high,
            createdMin: 3,
            reminderId: 'r1',
          ),
        ]);

        final result = await FindOpenTodosLinkedTo(repo)('r1');

        expect([for (final t in result.valueOrNull!) t.id], ['high', 'old']);
      },
    );

    test('không có việc nào trỏ tới thì trả danh sách rỗng', () async {
      final repo = InMemoryTodoRepository([_todo('plain')]);

      final result = await FindOpenTodosLinkedTo(repo)('r1');

      expect(result.valueOrNull, isEmpty);
    });

    test('lỗi của repository được trả lại nguyên vẹn', () async {
      final repo = InMemoryTodoRepository()..failure = storageFailure;

      expect(
        await FindOpenTodosLinkedTo(repo)('r1'),
        const Err<List<Todo>>(storageFailure),
      );
    });
  });

  group('CompleteTodosLinkedTo', () {
    test(
      'việc chưa xong trỏ tới nhắc nhở thì thành đã xong, đóng dấu lúc này',
      () async {
        final repo = InMemoryTodoRepository([_todo('a', reminderId: 'r1')]);

        final result = await complete(repo)('r1');

        expect(result, const Ok<void>(null));
        final saved = repo['a']!;
        expect(saved.done, isTrue);
        expect(saved.completedAt, now);
        expect(saved.updatedAt, now);
        expect(saved.reminderId, 'r1');
        expect(repo.writes, 1);
      },
    );

    test(
      'việc đã xong từ trước thì không ghi lại, giữ completedAt (AC8)',
      () async {
        final before = _todo(
          'a',
          done: true,
          completedAt: _min(30),
          reminderId: 'r1',
        );
        final repo = InMemoryTodoRepository([before]);

        final result = await complete(repo)('r1');

        expect(result.isOk, isTrue);
        expect(repo['a'], before);
        expect(repo.writes, 0);
      },
    );

    test(
      'không có việc nào trỏ tới thì trả Ok và không ghi gì (AC9)',
      () async {
        final repo = InMemoryTodoRepository([_todo('plain')]);

        final result = await complete(repo)('r1');

        expect(result, const Ok<void>(null));
        expect(repo.writes, 0);
      },
    );

    test('nhiều việc cùng trỏ tới thì tick hết', () async {
      final repo = InMemoryTodoRepository([
        _todo('a', reminderId: 'r1'),
        _todo('b', reminderId: 'r1', createdMin: 1),
        _todo('c', done: true, completedAt: _min(10), reminderId: 'r1'),
      ]);

      final result = await complete(repo)('r1');

      expect(result.isOk, isTrue);
      expect(repo['a']!.done, isTrue);
      expect(repo['a']!.completedAt, now);
      expect(repo['b']!.done, isTrue);
      expect(repo['b']!.completedAt, now);
      expect(repo['c']!.completedAt, _min(10));
      expect(repo.writes, 2);
    });

    test(
      'việc trỏ tới nhắc nhở khác hoặc không trỏ tới đâu thì không bị đụng',
      () async {
        final other = _todo('other', reminderId: 'r2');
        final plain = _todo('plain');
        final repo = InMemoryTodoRepository([
          other,
          plain,
          _todo('mine', reminderId: 'r1'),
        ]);

        await complete(repo)('r1');

        expect(repo['other'], other);
        expect(repo['plain'], plain);
        expect(repo['mine']!.done, isTrue);
        expect(repo.writes, 1);
      },
    );

    test('repository lỗi khi đọc thì trả Err', () async {
      final repo = InMemoryTodoRepository([_todo('a', reminderId: 'r1')])
        ..failure = storageFailure;

      expect(await complete(repo)('r1'), const Err<void>(storageFailure));
    });

    test('lưu lỗi giữa chừng thì dừng ở lỗi đầu tiên và trả Err', () async {
      final repo = _FailingLaterRepository([
        _todo('a', reminderId: 'r1'),
        _todo('b', reminderId: 'r1', createdMin: 1),
        _todo('c', reminderId: 'r1', createdMin: 2),
      ], failAfter: 1);

      final result = await complete(repo)('r1');

      expect(result, const Err<void>(StorageFailure('disk full')));
      // Thứ tự hiển thị: a (cũ nhất) được lưu, b lỗi, c không được thử.
      expect(repo['a']!.done, isTrue);
      expect(repo['b']!.done, isFalse);
      expect(repo['c']!.done, isFalse);
      expect(repo._saves, 2);
    });

    test('lưu lỗi mà bộ nhớ vẫn giữ dấu tick thì đặt việc về như cũ, làm '
        'lại sẽ tick tiếp (AC11)', () async {
      final before = _todo('a', reminderId: 'r1');
      final repo = _KeepsFailedSaveRepository([before]);

      final result = await complete(repo)('r1');

      expect(result, const Err<void>(StorageFailure('disk full')));
      expect(repo['a'], before.copyWith(updatedAt: now));
      final open = await FindOpenTodosLinkedTo(repo)('r1');
      expect([for (final t in open.valueOrNull!) t.id], ['a']);
    });

    test('bản đặt lại mang updatedAt lúc đặt lại, mới hơn bản tick lỗi, để '
        'sync đẩy nó đè các bản cũ hơn', () async {
      final later = now.add(const Duration(seconds: 1));
      final repo = _KeepsFailedSaveRepository(
        [_todo('a', reminderId: 'r1')],
        // Đồng hồ nhích lên sau lần tick, trước lần đặt lại.
        landed: (t) {
          clock.current = later;
          return t;
        },
      );

      await complete(repo)('r1');

      final restored = repo['a']!;
      expect(restored.done, isFalse);
      expect(restored.completedAt, isNull);
      expect(restored.updatedAt, later);
      expect(repo.writes, 2);
    });

    test('bộ nhớ giữ một bản sửa khác dấu tick thì không đặt lại', () async {
      final repo = _KeepsFailedSaveRepository([
        _todo('a', reminderId: 'r1'),
      ], landed: (t) => t.copyWith(title: 'sửa trong lúc ghi lỗi'));

      final result = await complete(repo)('r1');

      expect(result.isErr, isTrue);
      expect(repo['a']!.title, 'sửa trong lúc ghi lỗi');
      expect(repo['a']!.done, isTrue);
      expect(repo.writes, 1);
    });
  });
}
