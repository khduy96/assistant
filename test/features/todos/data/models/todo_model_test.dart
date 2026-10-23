import 'package:event_notice/features/todos/data/models/todo_model.dart';
import 'package:event_notice/features/todos/domain/entities/todo.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 22, 8);

TodoModel _full() => TodoModel(
  id: 't1',
  title: 'Nộp báo cáo',
  note: 'gửi chị Lan',
  done: true,
  priority: TodoPriority.high,
  dueDate: DateTime(2026, 10, 21, 17, 30),
  completedAt: DateTime(2026, 10, 20, 17, 45, 30, 500),
  reminderId: 'rem-1',
  createdAt: DateTime(2026, 10, 1, 8),
  updatedAt: DateTime(2026, 10, 20, 17, 45, 30, 500),
  remoteId: 'obj-1',
  dirty: false,
);

void main() {
  group('TodoModel JSON', () {
    test('toJson ghi đủ mười hai khoá như todos.json cũ', () {
      expect(_full().toJson(), {
        'id': 't1',
        'title': 'Nộp báo cáo',
        'note': 'gửi chị Lan',
        'done': true,
        'priority': 'high',
        'dueDate': '2026-10-21T17:30:00.000',
        'completedAt': '2026-10-20T17:45:30.500',
        'reminderId': 'rem-1',
        'createdAt': '2026-10-01T08:00:00.000',
        'updatedAt': '2026-10-20T17:45:30.500',
        'remoteId': 'obj-1',
        'dirty': false,
      });
    });

    test('field trống vẫn ghi khoá với giá trị null', () {
      final json = TodoModel(
        id: 't2',
        createdAt: _now,
        updatedAt: _now,
      ).toJson();
      expect(json['dueDate'], isNull);
      expect(json['completedAt'], isNull);
      expect(json['reminderId'], isNull);
      expect(json['remoteId'], isNull);
      expect(json.keys, hasLength(12));
    });

    test('round-trip giữ mọi khoá', () {
      final json = _full().toJson();
      expect(TodoModel.fromJson(json, now: _now).toJson(), json);
    });

    test('file từ trước khi có sync thiếu dirty thì coi là chưa đẩy', () {
      final old = TodoModel.fromJson({'id': 't2'}, now: _now);
      expect(old.dirty, isTrue);
      expect(old.remoteId, isNull);
    });

    test('giá trị mặc định khi thiếu khoá', () {
      final old = TodoModel.fromJson({'id': 't2'}, now: _now);
      expect(old.title, '');
      expect(old.note, '');
      expect(old.done, isFalse);
      expect(old.priority, TodoPriority.normal);
      expect(old.dueDate, isNull);
      expect(old.completedAt, isNull);
      expect(old.reminderId, isNull);
    });

    test('priority lạ thì coi là normal', () {
      for (final bad in <Object>['khẩn', 'HIGH', 2, true]) {
        final old = TodoModel.fromJson({
          'id': 't2',
          'priority': bad,
        }, now: _now);
        expect(old.priority, TodoPriority.normal, reason: '$bad');
      }
    });

    test('đọc đủ ba mức priority theo tên', () {
      for (final p in TodoPriority.values) {
        final read = TodoModel.fromJson({
          'id': 't2',
          'priority': p.name,
        }, now: _now);
        expect(read.priority, p);
      }
    });

    test('thiếu mốc thời gian thì lấy mốc truyền vào', () {
      final old = TodoModel.fromJson({'id': 't2'}, now: _now);
      expect(old.createdAt, _now);
      expect(old.updatedAt, _now);
    });

    test('thiếu updatedAt thì lấy createdAt', () {
      final old = TodoModel.fromJson({
        'id': 't2',
        'createdAt': '2026-01-04T10:00:00.000',
      }, now: _now);
      expect(old.createdAt, DateTime(2026, 1, 4, 10));
      expect(old.updatedAt, DateTime(2026, 1, 4, 10));
    });

    test('ngày không đọc được thì coi như không có', () {
      final old = TodoModel.fromJson({
        'id': 't2',
        'dueDate': 'mai',
        'completedAt': 'hôm qua',
        'createdAt': 'không phải ngày',
      }, now: _now);
      expect(old.dueDate, isNull);
      expect(old.completedAt, isNull);
      expect(old.createdAt, _now);
      expect(old.updatedAt, _now);
    });

    test('thiếu id thì báo lỗi, để cả file bị coi là hỏng', () {
      expect(
        () => TodoModel.fromJson({'title': 'không id'}, now: _now),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('TodoModel Parse', () {
    test(
      'toParse có đúng các field của TodoItem, thời gian tính bằng millis',
      () {
        final todo = _full();
        expect(todo.toParse(), {
          'localId': 't1',
          'title': 'Nộp báo cáo',
          'note': 'gửi chị Lan',
          'done': true,
          'priority': 'high',
          'dueDate': DateTime(2026, 10, 21, 17, 30).millisecondsSinceEpoch,
          'completedAt': todo.completedAt!.millisecondsSinceEpoch,
          'reminderId': 'rem-1',
          'todoCreatedAt': todo.createdAt.millisecondsSinceEpoch,
          'todoUpdatedAt': todo.updatedAt.millisecondsSinceEpoch,
        });
      },
    );

    test('toParse ghi null cho hạn, lúc xong và nhắc nhở chưa có', () {
      final parse = TodoModel(
        id: 't2',
        createdAt: _now,
        updatedAt: _now,
      ).toParse();
      expect(parse['dueDate'], isNull);
      expect(parse['completedAt'], isNull);
      expect(parse['reminderId'], isNull);
      expect(parse.keys, hasLength(10));
    });

    test('fromParse đọc lại đủ field, lấy objectId làm remoteId và sạch', () {
      final todo = _full();
      final back = TodoModel.fromParse({
        ...todo.toParse(),
        'objectId': 'obj-9',
      }, now: _now);
      expect(back.toJson(), {
        ...todo.toJson(),
        'remoteId': 'obj-9',
        'dirty': false,
      });
    });

    test('bản trên server thiếu field thì dùng mặc định và mốc truyền vào', () {
      final back = TodoModel.fromParse({'localId': 't3'}, now: _now);
      expect(back.title, '');
      expect(back.note, '');
      expect(back.done, isFalse);
      expect(back.priority, TodoPriority.normal);
      expect(back.dueDate, isNull);
      expect(back.completedAt, isNull);
      expect(back.reminderId, isNull);
      expect(back.createdAt, _now);
      expect(back.updatedAt, _now);
      expect(back.remoteId, isNull);
      expect(back.dirty, isFalse);
    });

    test('priority lạ trên server thì coi là normal', () {
      final back = TodoModel.fromParse({
        'localId': 't3',
        'priority': 'urgent',
      }, now: _now);
      expect(back.priority, TodoPriority.normal);
    });

    test('thời gian không phải số thì coi như không có', () {
      final back = TodoModel.fromParse({
        'localId': 't3',
        'dueDate': '2026-10-21',
        'todoUpdatedAt': 'hôm qua',
      }, now: _now);
      expect(back.dueDate, isNull);
      expect(back.updatedAt, _now);
    });
  });

  test('copyWith chỉ đổi trạng thái sync', () {
    final synced = _full().copyWith(remoteId: 'obj-2', dirty: true);
    expect(synced.toJson(), {
      ..._full().toJson(),
      'remoteId': 'obj-2',
      'dirty': true,
    });
  });
}
