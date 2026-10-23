import 'dart:async';
import 'dart:io';

import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/features/todos/data/datasources/todo_local_data_source.dart';
import 'package:event_notice/features/todos/data/models/todo_model.dart';
import 'package:event_notice/features/todos/data/repositories/todo_repository_impl.dart';
import 'package:event_notice/features/todos/domain/entities/todo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/fakes.dart';

final _t0 = DateTime(2026, 10, 22, 8);

Todo _todo(String id, {String title = 'việc', bool done = false}) =>
    Todo(id: id, title: title, done: done, createdAt: _t0, updatedAt: _t0);

/// Counts the events a stream fires.
class _Counter {
  _Counter(Stream<void> stream) {
    _sub = stream.listen((_) => count++);
  }

  late final StreamSubscription<void> _sub;
  int count = 0;

  Future<void> cancel() => _sub.cancel();
}

/// Lets the broadcast streams deliver what they have queued.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late Directory dir;
  late String path;
  late TodoRepositoryImpl repo;

  TodoRepositoryImpl open() =>
      TodoRepositoryImpl(TodoLocalDataSource(FakeClock(_t0), path: path));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('todo_repo_test');
    path = '${dir.path}/todos.json';
    repo = open();
  });

  tearDown(() async {
    await repo.dispose();
    await dir.delete(recursive: true);
  });

  /// Writes the file as an older run (or a sync) left it.
  Future<void> seed(List<TodoModel> todos) async {
    final seeded = open();
    await seeded.init();
    for (final t in todos) {
      await seeded.putFromSync(t);
    }
    await seeded.dispose();
  }

  TodoModel synced(String id, {bool done = false}) => TodoModel(
    id: id,
    title: 'đã đẩy',
    done: done,
    createdAt: _t0,
    updatedAt: _t0,
    remoteId: 'obj-$id',
    dirty: false,
  );

  group('nạp', () {
    test('init đọc file đã lưu', () async {
      await seed([synced('a')]);
      await repo.init();
      expect(repo.models.single.remoteId, 'obj-a');
    });

    test('getAll tự nạp nếu chưa init', () async {
      await seed([synced('a')]);
      final all = await repo.getAll();
      expect(all.valueOrNull?.single.id, 'a');
    });

    test('ensureLoaded chỉ đọc file một lần', () async {
      await seed([synced('a')]);
      await Future.wait([repo.ensureLoaded(), repo.ensureLoaded()]);
      await File(path).delete();
      await repo.ensureLoaded();
      expect(repo.models, hasLength(1));
    });

    test('nạp xong thì báo changes', () async {
      final changes = _Counter(repo.changes);
      await repo.init();
      await _settle();
      expect(changes.count, 1);
      await changes.cancel();
    });

    test('file hỏng thì danh sách rỗng, không lỗi', () async {
      await File(path).writeAsString('{"items": [');
      final all = await repo.getAll();
      expect(all.valueOrNull, isEmpty);
    });

    test('thao tác phía sync trước khi nạp thì báo lỗi', () {
      expect(() => repo.putFromSync(synced('a')), throwsStateError);
    });
  });

  group('save', () {
    test(
      'việc mới là dirty, chưa có remoteId, và được ghi xuống file',
      () async {
        expect(await repo.save(_todo('a')), const Ok<void>(null));

        final model = repo.models.single;
        expect(model.dirty, isTrue);
        expect(model.remoteId, isNull);

        final reopened = open();
        final all = await reopened.getAll();
        expect(all.valueOrNull, [_todo('a')]);
        await reopened.dispose();
      },
    );

    test('sửa việc đã đẩy thì giữ remoteId và bật dirty', () async {
      await seed([synced('a')]);
      await repo.save(_todo('a', title: 'đã sửa'));

      final model = repo.models.single;
      expect(model.title, 'đã sửa');
      expect(model.remoteId, 'obj-a');
      expect(model.dirty, isTrue);
    });

    test('getAll trả entity không kèm trạng thái sync', () async {
      await seed([synced('a')]);
      final all = await repo.getAll();
      expect(all.valueOrNull, [
        Todo(id: 'a', title: 'đã đẩy', createdAt: _t0, updatedAt: _t0),
      ]);
    });

    test('ghi file lỗi thì trả StorageFailure', () async {
      // A directory where the file should be: the write cannot succeed.
      await Directory(path).create();
      final result = await repo.save(_todo('a'));
      expect(result.failureOrNull, isA<StorageFailure>());
    });
  });

  group('delete', () {
    test('việc chưa từng đẩy thì không tạo tombstone', () async {
      await repo.save(_todo('a'));
      await repo.delete('a');
      expect(repo.models, isEmpty);
      expect(repo.tombstones, isEmpty);
    });

    test('việc đã đẩy thì để lại tombstone theo id và remoteId', () async {
      await seed([synced('a')]);
      await repo.delete('a');
      expect(repo.models, isEmpty);
      expect(repo.tombstones.single.toJson(), {'id': 'a', 'remoteId': 'obj-a'});

      final reopened = open();
      await reopened.init();
      expect(reopened.tombstones.single.remoteId, 'obj-a');
      await reopened.dispose();
    });

    test('xoá id không có thì không lỗi và không báo thay đổi', () async {
      await repo.init();
      await _settle();
      final changes = _Counter(repo.changes);
      expect(await repo.delete('không-có'), const Ok<void>(null));
      await _settle();
      expect(changes.count, 0);
      await changes.cancel();
    });
  });

  group('deleteAll', () {
    test('xoá nhiều việc, tombstone chỉ cho việc có remoteId', () async {
      await seed([
        synced('a', done: true),
        synced('b'),
        synced('c', done: true),
      ]);
      await repo.init();
      await repo.save(_todo('d', done: true));

      expect(await repo.deleteAll(['a', 'c', 'd']), const Ok<void>(null));
      expect(repo.models.map((t) => t.id), ['b']);
      expect(repo.tombstones.map((t) => t.toJson()), [
        {'id': 'a', 'remoteId': 'obj-a'},
        {'id': 'c', 'remoteId': 'obj-c'},
      ]);

      final reopened = open();
      await reopened.init();
      expect(reopened.models.map((t) => t.id), ['b']);
      expect(reopened.tombstones, hasLength(2));
      await reopened.dispose();
    });

    test('ghi file một lần và báo thay đổi một lần', () async {
      await seed([synced('a'), synced('b'), synced('c')]);
      await repo.init();
      await _settle();
      final changes = _Counter(repo.changes);
      final local = _Counter(repo.localChanges);

      await repo.deleteAll(['a', 'b']);
      await _settle();
      expect(changes.count, 1);
      expect(local.count, 1);
      await changes.cancel();
      await local.cancel();
    });

    test('bỏ qua id không có, danh sách rỗng thì không ghi gì', () async {
      await seed([synced('a')]);
      await repo.init();
      await _settle();
      final changes = _Counter(repo.changes);

      expect(await repo.deleteAll(const []), const Ok<void>(null));
      expect(await repo.deleteAll(['x', 'y']), const Ok<void>(null));
      await _settle();
      expect(changes.count, 0);
      expect(repo.models, hasLength(1));
      expect(repo.tombstones, isEmpty);
      await changes.cancel();
    });
  });

  group('sự kiện', () {
    late _Counter changes;
    late _Counter local;

    setUp(() async {
      await seed([synced('s')]);
      await repo.init();
      await _settle();
      changes = _Counter(repo.changes);
      local = _Counter(repo.localChanges);
    });

    tearDown(() async {
      await changes.cancel();
      await local.cancel();
    });

    test('người dùng lưu thì bắn cả changes và localChanges', () async {
      await repo.save(_todo('a'));
      await _settle();
      expect(changes.count, 1);
      expect(local.count, 1);
    });

    test('người dùng xoá thì bắn cả changes và localChanges', () async {
      await repo.delete('s');
      await _settle();
      expect(changes.count, 1);
      expect(local.count, 1);
    });

    test('thao tác do sync áp vào chỉ bắn changes', () async {
      await repo.putFromSync(synced('b'));
      await repo.removeFromSync('b');
      await repo.clearTombstone('x');
      await _settle();
      expect(changes.count, 3);
      expect(local.count, 0);
    });

    test('ghi file lỗi vẫn báo thay đổi, vì bộ nhớ đã đổi', () async {
      await File(path).delete();
      await Directory(path).create();
      final result = await repo.save(_todo('a'));
      await _settle();
      expect(result.isErr, isTrue);
      expect(repo.models.map((t) => t.id), containsAll(['s', 'a']));
      expect(changes.count, 1);
      expect(local.count, 1);
    });
  });
}
