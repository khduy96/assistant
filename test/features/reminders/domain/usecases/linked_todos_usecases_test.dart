import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/features/reminders/domain/usecases/complete_linked_todos.dart';
import 'package:event_notice/features/reminders/domain/usecases/find_open_linked_todos.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

const _disk = StorageFailure('disk');

void main() {
  late FakeLinkedTodos todos;

  setUp(() {
    todos = FakeLinkedTodos({
      'd1': ['Nộp báo cáo', 'Gửi email'],
    });
  });

  group('FindOpenLinkedTodos', () {
    test('trả nguyên danh sách tên việc của port', () async {
      final find = FindOpenLinkedTodos(todos);

      expect((await find('d1')).valueOrNull, ['Nộp báo cáo', 'Gửi email']);
    });

    test('không có việc nào liên kết thì danh sách rỗng', () async {
      expect((await FindOpenLinkedTodos(todos)('d2')).valueOrNull, isEmpty);
    });

    test('lỗi của port được trả lại', () async {
      todos.failure = _disk;

      expect(
        await FindOpenLinkedTodos(todos)('d1'),
        const Err<List<String>>(_disk),
      );
    });
  });

  group('CompleteLinkedTodos', () {
    test('chuyển đúng id cho port và trả Ok', () async {
      final complete = CompleteLinkedTodos(todos);

      expect(await complete('d1'), const Ok<void>(null));
      expect(todos.completed, ['d1']);
      expect(todos.open['d1'], isNull);
    });

    test('không có việc nào liên kết vẫn là Ok', () async {
      expect(await CompleteLinkedTodos(todos)('d2'), const Ok<void>(null));
      expect(todos.completed, ['d2']);
    });

    test('lỗi của port được trả lại, lời gọi vẫn được ghi', () async {
      todos.failure = _disk;

      expect(await CompleteLinkedTodos(todos)('d1'), const Err<void>(_disk));
      expect(todos.completed, ['d1']);
      expect(todos.open['d1'], ['Nộp báo cáo', 'Gửi email']);
    });
  });
}
