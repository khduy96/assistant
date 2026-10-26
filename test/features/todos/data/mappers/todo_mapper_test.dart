import 'package:event_notice/features/todos/data/mappers/todo_mapper.dart';
import 'package:event_notice/features/todos/data/models/todo_model.dart';
import 'package:event_notice/features/todos/domain/entities/todo.dart';
import 'package:flutter_test/flutter_test.dart';

final _created = DateTime(2026, 10, 1, 8);
final _updated = DateTime(2026, 10, 20, 17, 45);

Todo _todo() => Todo(
  id: 't1',
  title: 'Họp',
  note: 'phòng 3',
  done: true,
  priority: TodoPriority.high,
  dueDate: DateTime(2026, 10, 21, 9),
  completedAt: DateTime(2026, 10, 20, 17, 45),
  reminderId: 'rem-1',
  createdAt: _created,
  updatedAt: _updated,
);

TodoModel _stored({String? remoteId = 'obj-1', bool dirty = false}) =>
    TodoModel(
      id: 't1',
      title: 'Họp cũ',
      note: 'bản cũ',
      createdAt: _created,
      updatedAt: _created,
      remoteId: remoteId,
      dirty: dirty,
    );

void main() {
  group('TodoMapper.toModel', () {
    test('giữ remoteId của bản đã lưu và bật dirty', () {
      final model = TodoMapper.toModel(_todo(), stored: _stored());
      expect(model.remoteId, 'obj-1');
      expect(model.dirty, isTrue);
    });

    test('lấy nội dung từ entity, không lấy từ bản đã lưu', () {
      final model = TodoMapper.toModel(_todo(), stored: _stored());
      expect(model.id, 't1');
      expect(model.title, 'Họp');
      expect(model.note, 'phòng 3');
      expect(model.done, isTrue);
      expect(model.priority, TodoPriority.high);
      expect(model.dueDate, DateTime(2026, 10, 21, 9));
      expect(model.completedAt, DateTime(2026, 10, 20, 17, 45));
      expect(model.reminderId, 'rem-1');
      expect(model.createdAt, _created);
      expect(model.updatedAt, _updated);
    });

    test('việc mới chưa có remoteId và là dirty', () {
      final model = TodoMapper.toModel(_todo());
      expect(model.remoteId, isNull);
      expect(model.dirty, isTrue);
    });

    test('bản đã lưu chưa từng đẩy thì vẫn chưa có remoteId', () {
      final model = TodoMapper.toModel(
        _todo(),
        stored: _stored(remoteId: null, dirty: true),
      );
      expect(model.remoteId, isNull);
      expect(model.dirty, isTrue);
    });

    test('field đã xoá trên entity thì cũng trống trong model', () {
      final cleared = _todo().copyWith(
        dueDate: null,
        completedAt: null,
        reminderId: null,
      );
      final model = TodoMapper.toModel(cleared, stored: _stored());
      expect(model.dueDate, isNull);
      expect(model.completedAt, isNull);
      expect(model.reminderId, isNull);
    });
  });

  group('TodoMapper.toEntity', () {
    test('chép đủ field của việc, bỏ remoteId và dirty', () {
      final model = TodoMapper.toModel(_todo(), stored: _stored());
      expect(TodoMapper.toEntity(model), _todo());
    });

    test('kết quả không phụ thuộc trạng thái sync', () {
      final a = TodoModel(
        id: 't1',
        createdAt: _created,
        updatedAt: _updated,
        remoteId: 'obj-1',
        dirty: false,
      );
      final b = TodoModel(id: 't1', createdAt: _created, updatedAt: _updated);
      expect(TodoMapper.toEntity(a), TodoMapper.toEntity(b));
    });
  });
}
