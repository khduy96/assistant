import 'dart:convert';
import 'dart:io';

import 'package:event_notice/core/data/app_paths.dart';
import 'package:event_notice/core/sync/domain/sync_collection.dart';
import 'package:event_notice/features/todos/data/datasources/todo_local_data_source.dart';
import 'package:event_notice/features/todos/data/models/todo_model.dart';
import 'package:event_notice/features/todos/domain/entities/todo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/fakes.dart';

const _fixtures = 'test/features/todos/data/fixtures';

final _now = DateTime(2026, 10, 22, 8);

/// Puts the app's files in a test directory instead of the real one.
class _TempPaths extends AppPaths {
  const _TempPaths(this.dir);

  final String dir;

  @override
  Future<String> supportFile(String fileName) async => '$dir/$fileName';
}

void main() {
  late Directory dir;
  late String path;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('todo_data_test');
    path = '${dir.path}/todos.json';
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  /// Copies a fixture to the test file, so the original is never written.
  Future<void> useFixture(String name) => File('$_fixtures/$name').copy(path);

  TodoLocalDataSource source() =>
      TodoLocalDataSource(FakeClock(_now), path: path);

  test('tên file là todos.json', () async {
    final source = TodoLocalDataSource(
      FakeClock(_now),
      paths: _TempPaths(dir.path),
    );
    await source.save(const [], const []);
    expect(await File('${dir.path}/todos.json').exists(), isTrue);
  });

  test('không có file thì rỗng', () async {
    final saved = await source().load();
    expect(saved.items, isEmpty);
    expect(saved.deleted, isEmpty);
  });

  test('bare list cũ không mất việc nào', () async {
    await useFixture('todos_bare_list.json');
    final saved = await source().load();

    expect(saved.items.map((t) => t.id), ['old-1', 'old-2', 'old-3']);
    expect(saved.deleted, isEmpty);

    final [a, b, c] = saved.items;
    expect(a.title, 'Nộp báo cáo');
    expect(a.note, 'gửi chị Lan');
    expect(a.done, isFalse);
    expect(a.priority, TodoPriority.high);
    expect(a.dueDate, DateTime(2026, 1, 5, 17, 30));
    expect(a.completedAt, isNull);
    expect(a.createdAt, DateTime(2026, 1, 2, 8));
    expect(a.updatedAt, DateTime(2026, 1, 3, 9, 30));
    // Trước khi có sync: chưa đẩy.
    for (final t in saved.items) {
      expect(t.dirty, isTrue);
      expect(t.remoteId, isNull);
      expect(t.reminderId, isNull);
    }
    // Priority lạ thì là normal; thiếu updatedAt thì lấy createdAt.
    expect(b.done, isTrue);
    expect(b.priority, TodoPriority.normal);
    expect(b.completedAt, DateTime(2026, 1, 4, 11));
    expect(b.updatedAt, DateTime(2026, 1, 4, 10));
    // Thiếu priority thì là normal; thiếu mốc thì lấy giờ của Clock.
    expect(c.priority, TodoPriority.normal);
    expect(c.note, '');
    expect(c.createdAt, _now);
    expect(c.updatedAt, _now);
  });

  test('dạng {items, deleted} giữ cả việc lẫn tombstone', () async {
    await useFixture('todos_items_deleted.json');
    final saved = await source().load();

    final [t1, t2] = saved.items;
    expect(t1.id, 't1');
    expect(t1.done, isTrue);
    expect(t1.priority, TodoPriority.low);
    expect(t1.dueDate, DateTime(2026, 10, 21));
    expect(t1.completedAt, DateTime(2026, 10, 20, 17, 45, 30, 500));
    expect(t1.reminderId, 'rem-1');
    expect(t1.remoteId, 'obj-t1');
    expect(t1.dirty, isFalse);
    expect(t2.remoteId, isNull);
    expect(t2.dirty, isTrue);
    expect(saved.deleted.single.localId, 'gone-1');
    expect(saved.deleted.single.remoteId, 'obj-gone-1');
  });

  test('file hỏng thì rỗng', () async {
    await useFixture('todos_corrupt.json');
    final saved = await source().load();
    expect(saved.items, isEmpty);
    expect(saved.deleted, isEmpty);
  });

  test('một việc không đọc được thì cả file coi là hỏng, như bản cũ', () async {
    await File(path).writeAsString(
      jsonEncode([
        {'id': 'ok'},
        {'title': 'thiếu id'},
      ]),
    );
    final saved = await source().load();
    expect(saved.items, isEmpty);
  });

  test('round-trip giữ nguyên mọi khoá của việc và tombstone', () async {
    await useFixture('todos_items_deleted.json');
    final original = jsonDecode(await File(path).readAsString()) as Map;

    final saved = await source().load();
    final copy = '${dir.path}/copy.json';
    await TodoLocalDataSource(
      FakeClock(_now),
      path: copy,
    ).save(saved.items, saved.deleted);

    final written = jsonDecode(await File(copy).readAsString()) as Map;
    expect(written.keys, ['items', 'deleted']);
    for (final item in written['items'] as List) {
      expect((item as Map).keys, [
        'id',
        'title',
        'note',
        'done',
        'priority',
        'dueDate',
        'completedAt',
        'reminderId',
        'createdAt',
        'updatedAt',
        'remoteId',
        'dirty',
      ]);
    }
    expect(written, original);
  });

  test('bare list ghi lại thành {items, deleted} đủ khoá', () async {
    await useFixture('todos_bare_list.json');
    final saved = await source().load();
    await source().save(saved.items, saved.deleted);

    final written = jsonDecode(await File(path).readAsString()) as Map;
    expect(written['deleted'], isEmpty);
    final items = (written['items'] as List).cast<Map<String, dynamic>>();
    expect(items.map((e) => e['id']), ['old-1', 'old-2', 'old-3']);
    expect(items.first, {
      'id': 'old-1',
      'title': 'Nộp báo cáo',
      'note': 'gửi chị Lan',
      'done': false,
      'priority': 'high',
      'dueDate': '2026-01-05T17:30:00.000',
      'completedAt': null,
      'reminderId': null,
      'createdAt': '2026-01-02T08:00:00.000',
      'updatedAt': '2026-01-03T09:30:00.000',
      'remoteId': null,
      'dirty': true,
    });
    expect(items[1]['priority'], 'normal');
  });

  test('ghi xong đọc lại được đúng như trước', () async {
    final todo = TodoModel(
      id: 't1',
      title: 'Nộp báo cáo',
      priority: TodoPriority.high,
      dueDate: DateTime(2026, 10, 3, 17),
      createdAt: DateTime(2026, 10, 1),
      updatedAt: DateTime(2026, 10, 2),
      remoteId: 'obj-1',
      dirty: false,
    );
    await source().save(
      [todo],
      [const SyncTombstone(localId: 'x', remoteId: 'obj-x')],
    );
    final saved = await source().load();
    expect(saved.items.single.toJson(), todo.toJson());
    expect(saved.deleted.single.toJson(), {'id': 'x', 'remoteId': 'obj-x'});
  });
}
