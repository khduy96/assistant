import 'package:event_notice/features/notes/data/models/note_model.dart';
import 'package:event_notice/features/notes/domain/entities/note.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 22, 8);

NoteModel _full() => NoteModel(
  id: 'n1',
  title: 'Bảng',
  body: '| a | b |',
  pinned: true,
  markdown: true,
  color: NoteColor.pink,
  createdAt: DateTime(2026, 10, 1, 8),
  updatedAt: DateTime(2026, 10, 20, 17, 45, 30, 500),
  remoteId: 'obj-1',
  dirty: false,
);

void main() {
  group('NoteModel JSON', () {
    test('toJson ghi đủ mười khoá như notes.json cũ', () {
      expect(_full().toJson(), {
        'id': 'n1',
        'title': 'Bảng',
        'body': '| a | b |',
        'pinned': true,
        'markdown': true,
        'color': 'pink',
        'createdAt': '2026-10-01T08:00:00.000',
        'updatedAt': '2026-10-20T17:45:30.500',
        'remoteId': 'obj-1',
        'dirty': false,
      });
    });

    test('round-trip giữ mọi khoá', () {
      final json = _full().toJson();
      expect(NoteModel.fromJson(json, now: _now).toJson(), json);
    });

    test('ghi chú cũ thiếu markdown thì là văn bản thường', () {
      final old = NoteModel.fromJson({
        'id': 'n2',
        'title': 'Cũ',
        'body': 'xin chào',
      }, now: _now);
      expect(old.markdown, isFalse);
    });

    test('file từ trước khi có sync thiếu dirty thì coi là chưa đẩy', () {
      final old = NoteModel.fromJson({'id': 'n2'}, now: _now);
      expect(old.dirty, isTrue);
      expect(old.remoteId, isNull);
    });

    test('giá trị mặc định khi thiếu khoá', () {
      final old = NoteModel.fromJson({'id': 'n2'}, now: _now);
      expect(old.title, '');
      expect(old.body, '');
      expect(old.pinned, isFalse);
      expect(old.color, NoteColor.none);
    });

    test('thiếu mốc thời gian thì lấy mốc truyền vào', () {
      final old = NoteModel.fromJson({'id': 'n2'}, now: _now);
      expect(old.createdAt, _now);
      expect(old.updatedAt, _now);
    });

    test('thiếu updatedAt thì lấy createdAt', () {
      final old = NoteModel.fromJson({
        'id': 'n2',
        'createdAt': '2026-01-04T10:00:00.000',
      }, now: _now);
      expect(old.createdAt, DateTime(2026, 1, 4, 10));
      expect(old.updatedAt, DateTime(2026, 1, 4, 10));
    });

    test('createdAt không đọc được thì lấy mốc truyền vào', () {
      final old = NoteModel.fromJson({
        'id': 'n2',
        'createdAt': 'không phải ngày',
      }, now: _now);
      expect(old.createdAt, _now);
      expect(old.updatedAt, _now);
    });

    test('màu lạ thì coi là không màu', () {
      final old = NoteModel.fromJson({'id': 'n2', 'color': 'cam'}, now: _now);
      expect(old.color, NoteColor.none);
    });
  });

  group('NoteModel Parse', () {
    test('toParse có đúng các field của NoteItem', () {
      final note = _full();
      expect(note.toParse(), {
        'localId': 'n1',
        'title': 'Bảng',
        'body': '| a | b |',
        'pinned': true,
        'markdown': true,
        'color': 'pink',
        'noteCreatedAt': note.createdAt.millisecondsSinceEpoch,
        'noteUpdatedAt': note.updatedAt.millisecondsSinceEpoch,
      });
    });

    test('fromParse đọc lại đủ field, lấy objectId làm remoteId và sạch', () {
      final note = _full();
      final back = NoteModel.fromParse({
        ...note.toParse(),
        'objectId': 'obj-9',
      }, now: _now);
      expect(back.toJson(), {
        ...note.toJson(),
        'remoteId': 'obj-9',
        'dirty': false,
      });
    });

    test('bản trên server thiếu field thì dùng mặc định và mốc truyền vào', () {
      final back = NoteModel.fromParse({'localId': 'n3'}, now: _now);
      expect(back.title, '');
      expect(back.body, '');
      expect(back.pinned, isFalse);
      expect(back.markdown, isFalse);
      expect(back.color, NoteColor.none);
      expect(back.createdAt, _now);
      expect(back.updatedAt, _now);
      expect(back.remoteId, isNull);
      expect(back.dirty, isFalse);
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
