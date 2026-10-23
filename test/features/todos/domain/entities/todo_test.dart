import 'package:event_notice/features/todos/domain/entities/todo.dart';
import 'package:flutter_test/flutter_test.dart';

final _created = DateTime(2026, 10, 1, 9);

/// The fixed "now" every check below is made against: 22/10/2026 14:30.
final _now = DateTime(2026, 10, 22, 14, 30);

Todo _todo({DateTime? due, bool done = false}) => Todo(
  id: 't',
  title: 'Việc',
  done: done,
  dueDate: due,
  createdAt: _created,
  updatedAt: _created,
);

void main() {
  group('Todo.hasDueTime', () {
    test('00:00 nghĩa là chưa chọn giờ', () {
      expect(_todo(due: DateTime(2026, 10, 22)).hasDueTime, isFalse);
    });

    test('có giờ hoặc phút khác 0 thì là có giờ', () {
      expect(_todo(due: DateTime(2026, 10, 22, 9)).hasDueTime, isTrue);
      expect(_todo(due: DateTime(2026, 10, 22, 0, 5)).hasDueTime, isTrue);
    });

    test('không có hạn thì không có giờ', () {
      expect(_todo().hasDueTime, isFalse);
    });
  });

  group('Todo.isOverdue', () {
    test('có giờ: so tới phút', () {
      expect(
        _todo(due: DateTime(2026, 10, 22, 14, 29)).isOverdue(_now),
        isTrue,
      );
      expect(
        _todo(due: DateTime(2026, 10, 22, 14, 31)).isOverdue(_now),
        isFalse,
      );
      // Exactly now is not yet past.
      expect(_todo(due: _now).isOverdue(_now), isFalse);
    });

    test('chỉ có ngày: chỉ quá hạn khi đã qua cả ngày', () {
      expect(_todo(due: DateTime(2026, 10, 22)).isOverdue(_now), isFalse);
      expect(_todo(due: DateTime(2026, 10, 21)).isOverdue(_now), isTrue);
      expect(_todo(due: DateTime(2026, 10, 23)).isOverdue(_now), isFalse);
    });

    test('việc đã xong không bao giờ quá hạn', () {
      expect(
        _todo(due: DateTime(2026, 10, 1, 8), done: true).isOverdue(_now),
        isFalse,
      );
      expect(
        _todo(due: DateTime(2026, 10, 1), done: true).isOverdue(_now),
        isFalse,
      );
    });

    test('không có hạn thì không quá hạn', () {
      expect(_todo().isOverdue(_now), isFalse);
    });
  });

  group('Todo.isDueToday', () {
    test('hạn trong ngày của now, có giờ hay không đều đúng', () {
      expect(_todo(due: DateTime(2026, 10, 22)).isDueToday(_now), isTrue);
      expect(_todo(due: DateTime(2026, 10, 22, 9)).isDueToday(_now), isTrue);
      expect(
        _todo(due: DateTime(2026, 10, 22, 23, 59)).isDueToday(_now),
        isTrue,
      );
    });

    test('ngày khác thì sai', () {
      expect(
        _todo(due: DateTime(2026, 10, 21, 23, 59)).isDueToday(_now),
        isFalse,
      );
      expect(_todo(due: DateTime(2026, 10, 23)).isDueToday(_now), isFalse);
      expect(_todo(due: DateTime(2025, 10, 22)).isDueToday(_now), isFalse);
    });

    test('việc đã xong hoặc không có hạn thì sai', () {
      expect(
        _todo(due: DateTime(2026, 10, 22), done: true).isDueToday(_now),
        isFalse,
      );
      expect(_todo().isDueToday(_now), isFalse);
    });
  });

  group('Todo.copyWith', () {
    final full = Todo(
      id: 't',
      title: 'Viết báo cáo',
      note: 'gửi chị Lan',
      done: true,
      priority: TodoPriority.high,
      dueDate: DateTime(2026, 10, 25, 17),
      completedAt: DateTime(2026, 10, 22, 10),
      reminderId: 'r1',
      createdAt: _created,
      updatedAt: DateTime(2026, 10, 22, 10),
    );

    test('không truyền gì thì bằng bản cũ, id không đổi', () {
      final copy = full.copyWith();
      expect(copy, full);
      expect(copy.hashCode, full.hashCode);
      expect(identical(copy, full), isFalse);
    });

    test('thay từng field', () {
      final at = DateTime(2026, 11, 1);
      final copy = full.copyWith(
        title: 'Mới',
        note: 'ghi chú',
        done: false,
        priority: TodoPriority.low,
        dueDate: at,
        completedAt: at,
        reminderId: 'r2',
        createdAt: at,
        updatedAt: at,
      );
      expect(copy.id, 't');
      expect(copy.title, 'Mới');
      expect(copy.note, 'ghi chú');
      expect(copy.done, isFalse);
      expect(copy.priority, TodoPriority.low);
      expect(copy.dueDate, at);
      expect(copy.completedAt, at);
      expect(copy.reminderId, 'r2');
      expect(copy.createdAt, at);
      expect(copy.updatedAt, at);
    });

    test('null tường minh xoá dueDate, completedAt, reminderId', () {
      final copy = full.copyWith(
        dueDate: null,
        completedAt: null,
        reminderId: null,
      );
      expect(copy.dueDate, isNull);
      expect(copy.completedAt, isNull);
      expect(copy.reminderId, isNull);
      expect(copy.title, full.title);
    });

    test('bản gốc không bị đổi', () {
      full.copyWith(title: 'khác', reminderId: null);
      expect(full.title, 'Viết báo cáo');
      expect(full.reminderId, 'r1');
    });
  });

  test(
    'mặc định: chưa xong, ưu tiên bình thường, không hạn, không liên kết',
    () {
      final todo = Todo(
        id: 'x',
        title: 'Việc',
        createdAt: _created,
        updatedAt: _created,
      );
      expect(todo.note, '');
      expect(todo.done, isFalse);
      expect(todo.priority, TodoPriority.normal);
      expect(todo.dueDate, isNull);
      expect(todo.completedAt, isNull);
      expect(todo.reminderId, isNull);
    },
  );

  test('TodoPriority giữ thứ tự low < normal < high', () {
    expect(TodoPriority.values, [
      TodoPriority.low,
      TodoPriority.normal,
      TodoPriority.high,
    ]);
  });
}
