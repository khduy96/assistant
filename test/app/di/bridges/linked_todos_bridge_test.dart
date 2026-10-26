import 'dart:io';

import 'package:event_notice/app/di/bridges/linked_todos_bridge.dart';
import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/features/todos/data/datasources/todo_local_data_source.dart';
import 'package:event_notice/features/todos/data/models/todo_model.dart';
import 'package:event_notice/features/todos/data/repositories/todo_repository_impl.dart';
import 'package:event_notice/features/todos/domain/usecases/complete_todos_linked_to.dart';
import 'package:event_notice/features/todos/domain/usecases/find_open_todos_linked_to.dart';
import 'package:event_notice/features/todos/domain/usecases/set_todo_done.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../features/todos/domain/fakes.dart';

/// When the todos were written.
final _t0 = DateTime(2026, 10, 22, 8);

/// When the deadline is marked done.
final _t1 = DateTime(2026, 10, 24, 12, 45);

/// A todo already pushed to Back4App, so nothing is waiting to be sent.
TodoModel _synced(
  String id, {
  String? title,
  bool done = false,
  String? reminderId,
}) => TodoModel(
  id: id,
  title: title ?? id,
  done: done,
  completedAt: done ? _t0 : null,
  reminderId: reminderId,
  createdAt: _t0,
  updatedAt: _t0,
  remoteId: 'obj-$id',
  dirty: false,
);

/// Lets the broadcast streams deliver what they have queued.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late Directory dir;
  late String path;
  late FakeClock clock;
  late TodoRepositoryImpl repo;
  late LinkedTodosBridge bridge;

  TodoRepositoryImpl open() =>
      TodoRepositoryImpl(TodoLocalDataSource(FakeClock(_t0), path: path));

  /// Writes the file as a sync left it, then loads it into [repo].
  Future<void> seed(List<TodoModel> todos) async {
    final seeded = open();
    await seeded.init();
    for (final t in todos) {
      await seeded.putFromSync(t);
    }
    await seeded.dispose();
    await repo.init();
  }

  TodoModel model(String id) => repo.models.singleWhere((m) => m.id == id);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('linked_todos_bridge');
    // One level down, so a test can take the folder away to make writes fail.
    await Directory('${dir.path}/data').create();
    path = '${dir.path}/data/todos.json';
    clock = FakeClock(_t1);
    repo = open();
    final findOpen = FindOpenTodosLinkedTo(repo);
    bridge = LinkedTodosBridge(
      findOpen,
      CompleteTodosLinkedTo(findOpen, SetTodoDone(repo, clock), repo, clock),
    );
  });

  tearDown(() async {
    await repo.dispose();
    await dir.delete(recursive: true);
  });

  group('openTitlesFor', () {
    test('chỉ trả tên việc chưa xong trỏ tới deadline', () async {
      await seed([
        _synced('a', title: 'Viết báo cáo', reminderId: 'd1'),
        _synced('b', title: 'Đã nộp', done: true, reminderId: 'd1'),
        _synced('c', title: 'Việc khác', reminderId: 'd2'),
        _synced('e', title: 'Không liên kết'),
      ]);

      expect((await bridge.openTitlesFor('d1')).valueOrNull, ['Viết báo cáo']);
      expect((await bridge.openTitlesFor('x')).valueOrNull, isEmpty);
    });
  });

  group('completeFor', () {
    test('việc liên kết thành done, chờ đẩy lên Back4App, localChanges báo '
        'sau khi đã lưu (AC7)', () async {
      await seed([
        _synced('a', reminderId: 'd1'),
        _synced('c', reminderId: 'd2'),
      ]);
      final seenDone = <bool>[];
      final sub = repo.localChanges.listen(
        (_) => seenDone.add(model('a').done),
      );
      addTearDown(sub.cancel);
      await _settle();
      expect(seenDone, isEmpty);

      final result = await bridge.completeFor('d1');
      await _settle();

      expect(result, const Ok<void>(null));
      expect(seenDone, [true]);
      final a = model('a');
      expect(a.done, isTrue);
      expect(a.completedAt, _t1);
      expect(a.updatedAt, _t1);
      expect(a.dirty, isTrue);
      expect(a.remoteId, 'obj-a');
      expect(a.reminderId, 'd1');
      // Việc trỏ tới deadline khác không bị đụng.
      expect(model('c').done, isFalse);
      expect(model('c').dirty, isFalse);

      // Đã ghi xuống todos.json.
      final reopened = open();
      addTearDown(reopened.dispose);
      await reopened.init();
      final stored = reopened.models.singleWhere((m) => m.id == 'a');
      expect(stored.done, isTrue);
      expect(stored.dirty, isTrue);
    });

    test('việc đã xong từ trước thì giữ nguyên, không báo localChanges '
        '(AC8)', () async {
      await seed([_synced('b', done: true, reminderId: 'd1')]);
      var local = 0;
      final sub = repo.localChanges.listen((_) => local++);
      addTearDown(sub.cancel);

      expect(await bridge.completeFor('d1'), const Ok<void>(null));
      await _settle();

      expect(local, 0);
      expect(model('b').completedAt, _t0);
      expect(model('b').updatedAt, _t0);
      expect(model('b').dirty, isFalse);
    });

    test('không có việc nào trỏ tới thì Ok, không ghi gì (AC9)', () async {
      await seed([_synced('e')]);
      var local = 0;
      final sub = repo.localChanges.listen((_) => local++);
      addTearDown(sub.cancel);

      expect(await bridge.completeFor('d1'), const Ok<void>(null));
      await _settle();

      expect(local, 0);
      expect(model('e').dirty, isFalse);
    });

    test('không ghi được todos.json thì trả Err', () async {
      await seed([_synced('a', reminderId: 'd1')]);
      await Directory('${dir.path}/data').delete(recursive: true);

      final result = await bridge.completeFor('d1');

      expect(result.failureOrNull, isA<StorageFailure>());
    });

    test('ghi lỗi rồi làm lại thì việc được ghi xuống todos.json, không báo '
        'Ok khi việc vẫn chưa xong (AC11)', () async {
      await seed([_synced('a', reminderId: 'd1')]);
      final original = await File(path).readAsBytes();
      await Directory('${dir.path}/data').delete(recursive: true);

      final first = await bridge.completeFor('d1');
      expect(first.failureOrNull, isA<StorageFailure>());
      // Việc chưa lưu được thì vẫn được kể là đang mở.
      expect((await bridge.openTitlesFor('d1')).valueOrNull, ['a']);

      // Ổ đĩa trở lại như cũ, người dùng bấm "Đã thực hiện" lần nữa.
      await Directory('${dir.path}/data').create();
      await File(path).writeAsBytes(original);

      expect(await bridge.completeFor('d1'), const Ok<void>(null));
      final reopened = open();
      addTearDown(reopened.dispose);
      await reopened.init();
      final stored = reopened.models.single;
      expect(stored.done, isTrue);
      expect(stored.completedAt, _t1);
      expect(stored.dirty, isTrue);
    });
  });
}
