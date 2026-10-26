import 'package:event_notice/features/notes/data/mappers/note_mapper.dart';
import 'package:event_notice/features/notes/data/models/note_model.dart';
import 'package:event_notice/features/notes/domain/entities/note.dart';
import 'package:flutter_test/flutter_test.dart';

final _created = DateTime(2026, 10, 1, 8);
final _updated = DateTime(2026, 10, 20, 17, 45);

Note _note() => Note(
  id: 'n1',
  title: 'Họp',
  body: '## Việc',
  pinned: true,
  markdown: true,
  color: NoteColor.green,
  createdAt: _created,
  updatedAt: _updated,
);

NoteModel _stored({String? remoteId = 'obj-1', bool dirty = false}) =>
    NoteModel(
      id: 'n1',
      title: 'Họp cũ',
      body: 'bản cũ',
      createdAt: _created,
      updatedAt: _created,
      remoteId: remoteId,
      dirty: dirty,
    );

void main() {
  group('NoteMapper.toModel', () {
    test('giữ remoteId của bản đã lưu và bật dirty', () {
      final model = NoteMapper.toModel(_note(), stored: _stored());
      expect(model.remoteId, 'obj-1');
      expect(model.dirty, isTrue);
    });

    test('lấy nội dung từ entity, không lấy từ bản đã lưu', () {
      final model = NoteMapper.toModel(_note(), stored: _stored());
      expect(model.id, 'n1');
      expect(model.title, 'Họp');
      expect(model.body, '## Việc');
      expect(model.pinned, isTrue);
      expect(model.markdown, isTrue);
      expect(model.color, NoteColor.green);
      expect(model.createdAt, _created);
      expect(model.updatedAt, _updated);
    });

    test('ghi chú mới chưa có remoteId và là dirty', () {
      final model = NoteMapper.toModel(_note());
      expect(model.remoteId, isNull);
      expect(model.dirty, isTrue);
    });

    test('bản đã lưu chưa từng đẩy thì vẫn chưa có remoteId', () {
      final model = NoteMapper.toModel(
        _note(),
        stored: _stored(remoteId: null, dirty: true),
      );
      expect(model.remoteId, isNull);
      expect(model.dirty, isTrue);
    });
  });

  group('NoteMapper.toEntity', () {
    test('chép đủ field của ghi chú, bỏ remoteId và dirty', () {
      final model = NoteMapper.toModel(_note(), stored: _stored());
      expect(NoteMapper.toEntity(model), _note());
    });

    test('kết quả không phụ thuộc trạng thái sync', () {
      final a = NoteModel(
        id: 'n1',
        createdAt: _created,
        updatedAt: _updated,
        remoteId: 'obj-1',
        dirty: false,
      );
      final b = NoteModel(id: 'n1', createdAt: _created, updatedAt: _updated);
      expect(NoteMapper.toEntity(a), NoteMapper.toEntity(b));
    });
  });
}
