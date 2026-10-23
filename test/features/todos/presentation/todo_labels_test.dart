import 'package:event_notice/features/todos/domain/entities/todo.dart';
import 'package:event_notice/features/todos/presentation/todo_labels.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture.dart';

void main() {
  test('nhãn mức ưu tiên giữ nguyên văn', () {
    expect(TodoPriority.low.label, 'Thấp');
    expect(TodoPriority.normal.label, 'Bình thường');
    expect(TodoPriority.high.label, 'Quan trọng');
  });

  group('dueLabel (now = 22/10/2026 09:30)', () {
    String label(DateTime due, {bool done = false}) =>
        dueLabel(todo('a', due: due, done: done), due, t0);

    test('hạn cả ngày hôm nay', () {
      expect(label(DateTime(2026, 10, 22)), 'Hôm nay');
    });

    test('hạn có giờ hôm nay, chưa tới', () {
      expect(label(DateTime(2026, 10, 22, 18)), 'Hôm nay 18:00');
    });

    test('hạn có giờ hôm nay, đã qua giờ', () {
      expect(label(DateTime(2026, 10, 22, 8)), 'Quá hạn 22/10/2026 08:00');
    });

    test('hạn cả ngày hôm qua', () {
      expect(label(DateTime(2026, 10, 21)), 'Quá hạn 21/10/2026');
    });

    test('hạn sau này, có và không có giờ', () {
      expect(label(DateTime(2026, 10, 25)), 'Hạn 25/10/2026');
      expect(label(DateTime(2026, 10, 25, 7, 5)), 'Hạn 25/10/2026 07:05');
    });

    test('việc đã xong thì không quá hạn, không "Hôm nay"', () {
      expect(label(DateTime(2026, 10, 21), done: true), 'Hạn 21/10/2026');
      expect(
        label(DateTime(2026, 10, 22, 8), done: true),
        'Hạn 22/10/2026 08:00',
      );
    });
  });

  group('alarmLabel (now = 22/10/2026 09:30)', () {
    test('chưa chuyển thành nhắc nhở thì không có nhãn', () {
      expect(alarmLabel(null, t0), isNull);
    });

    test('đang tắt', () {
      expect(alarmLabel(linked('r', enabled: false), t0), 'Nhắc · đang tắt');
      expect(
        alarmLabel(linked('r', isDeadline: true, enabled: false), t0),
        'Deadline · đang tắt',
      );
    });

    test('không còn lần báo nào', () {
      expect(alarmLabel(linked('r'), t0), 'Nhắc · đã qua');
    });

    test('đếm ngược tới lần báo tới', () {
      expect(alarmLabel(linked('r', next: at(120)), t0), 'Nhắc · còn 2 giờ');
      expect(
        alarmLabel(linked('r', isDeadline: true, next: at(27 * 60)), t0),
        'Deadline · còn 1 ngày 3 giờ',
      );
      expect(alarmLabel(linked('r', next: at(-1)), t0), 'Nhắc · đã qua');
    });
  });
}
