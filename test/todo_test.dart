import 'package:event_notice/models/todo.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime day(int offsetDays) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + offsetDays);
}

void main() {
  test('việc quá hạn khi hạn đã trôi qua', () {
    final t = Todo(id: 't1', title: 'Gửi báo giá', dueDate: day(-1));
    expect(t.isOverdue, isTrue);
    expect(t.isDueToday, isFalse);
  });

  test('việc đến hạn hôm nay', () {
    final t = Todo(id: 't1', title: 'Gửi báo giá', dueDate: day(0));
    expect(t.isDueToday, isTrue);
    expect(t.isOverdue, isFalse);
  });

  test('việc đã xong thì không tính quá hạn', () {
    final t = Todo(
      id: 't1',
      title: 'Gửi báo giá',
      dueDate: day(-3),
      done: true,
    );
    expect(t.isOverdue, isFalse);
  });

  test('việc chưa đặt hạn thì không quá hạn', () {
    expect(Todo(id: 't1', title: 'Dọn bàn').isOverdue, isFalse);
  });

  test('lưu và đọc lại giữ nguyên dữ liệu', () {
    final t = Todo(
      id: 't1',
      title: 'Gửi báo giá',
      note: 'kèm bảng chiết khấu',
      priority: TodoPriority.high,
      dueDate: day(2),
      done: true,
      completedAt: DateTime(2026, 1, 2, 9, 30),
    );

    final back = Todo.fromJson(t.toJson());

    expect(back.id, t.id);
    expect(back.title, t.title);
    expect(back.note, t.note);
    expect(back.priority, TodoPriority.high);
    expect(back.dueDate, t.dueDate);
    expect(back.done, isTrue);
    expect(back.completedAt, t.completedAt);
    expect(back.createdAt, t.createdAt);
  });

  test('việc đã chuyển thành nhắc nhở giữ được liên kết', () {
    final t = Todo(id: 't1', title: 'Gửi báo giá', reminderId: 'r9');

    expect(Todo.fromJson(t.toJson()).reminderId, 'r9');
    expect(
      Todo.fromParse({...t.toParse(), 'objectId': 'srv1'}).reminderId,
      'r9',
    );
  });

  test('việc cũ chưa có liên kết thì đọc lại vẫn rỗng', () {
    final old = Todo.fromJson({'id': 't1', 'title': 'Dọn bàn'});
    expect(old.reminderId, isNull);
  });
}
