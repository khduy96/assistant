import 'package:event_notice/features/todos/data/mappers/todo_mapper.dart';
import 'package:event_notice/features/todos/data/models/todo_model.dart';
import 'package:event_notice/features/todos/domain/entities/todo.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime day(int offsetDays) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + offsetDays);
}

/// Một việc vừa tạo xong: createdAt và updatedAt là lúc này.
Todo todo({
  required String id,
  required String title,
  String note = '',
  bool done = false,
  TodoPriority priority = TodoPriority.normal,
  DateTime? dueDate,
  DateTime? completedAt,
  String? reminderId,
}) {
  final now = DateTime.now();
  return Todo(
    id: id,
    title: title,
    note: note,
    done: done,
    priority: priority,
    dueDate: dueDate,
    completedAt: completedAt,
    reminderId: reminderId,
    createdAt: now,
    updatedAt: now,
  );
}

/// Dạng lưu trong todos.json và dạng gửi lên Back4App, qua tầng data.
Map<String, Object?> toJson(Todo t) => TodoMapper.toModel(t).toJson();
Map<String, Object?> toParse(Todo t) => TodoMapper.toModel(t).toParse();
Todo fromJson(Map<String, Object?> j) =>
    TodoMapper.toEntity(TodoModel.fromJson(j, now: DateTime.now()));
Todo fromParse(Map<String, Object?> j) =>
    TodoMapper.toEntity(TodoModel.fromParse(j, now: DateTime.now()));

void main() {
  test('việc quá hạn khi hạn đã trôi qua', () {
    final t = todo(id: 't1', title: 'Gửi báo giá', dueDate: day(-1));
    expect(t.isOverdue(DateTime.now()), isTrue);
    expect(t.isDueToday(DateTime.now()), isFalse);
  });

  test('việc đến hạn hôm nay', () {
    final t = todo(id: 't1', title: 'Gửi báo giá', dueDate: day(0));
    expect(t.isDueToday(DateTime.now()), isTrue);
    expect(t.isOverdue(DateTime.now()), isFalse);
  });

  test('việc đã xong thì không tính quá hạn', () {
    final t = todo(
      id: 't1',
      title: 'Gửi báo giá',
      dueDate: day(-3),
      done: true,
    );
    expect(t.isOverdue(DateTime.now()), isFalse);
  });

  test('việc chưa đặt hạn thì không quá hạn', () {
    expect(todo(id: 't1', title: 'Dọn bàn').isOverdue(DateTime.now()), isFalse);
  });

  test('lưu và đọc lại giữ nguyên dữ liệu', () {
    final t = todo(
      id: 't1',
      title: 'Gửi báo giá',
      note: 'kèm bảng chiết khấu',
      priority: TodoPriority.high,
      dueDate: day(2),
      done: true,
      completedAt: DateTime(2026, 1, 2, 9, 30),
    );

    final back = fromJson(toJson(t));

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
    final t = todo(id: 't1', title: 'Gửi báo giá', reminderId: 'r9');

    expect(fromJson(toJson(t)).reminderId, 'r9');
    expect(fromParse({...toParse(t), 'objectId': 'srv1'}).reminderId, 'r9');
  });

  test('việc cũ chưa có liên kết thì đọc lại vẫn rỗng', () {
    final old = fromJson({'id': 't1', 'title': 'Dọn bàn'});
    expect(old.reminderId, isNull);
  });
}
