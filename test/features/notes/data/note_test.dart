import 'package:event_notice/features/notes/data/models/note_model.dart';
import 'package:event_notice/features/notes/domain/entities/note.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mốc thời gian cố định cho các ghi chú dựng trong test.
final t = DateTime(2026, 10, 22, 9, 30);

void main() {
  group('Note markdown', () {
    test('cờ markdown đi qua JSON và Parse', () {
      final note = NoteModel(
        id: 'n1',
        title: 'Bảng',
        body: '| a | b |',
        markdown: true,
        createdAt: t,
        updatedAt: t,
      );

      expect(NoteModel.fromJson(note.toJson(), now: t).markdown, isTrue);
      expect(note.toParse()['markdown'], isTrue);
      expect(
        NoteModel.fromParse({...note.toParse(), 'objectId': 'x'}, now: t)
            .markdown,
        isTrue,
      );
    });

    test('ghi chú cũ không có cờ thì coi như văn bản thường', () {
      final old = NoteModel.fromJson(
        {'id': 'n2', 'title': 'Cũ', 'body': 'xin chào'},
        now: t,
      );
      expect(old.markdown, isFalse);
    });

    test('tiêu đề suy ra bỏ cú pháp markdown', () {
      final note = Note(
        id: 'n3',
        body: '## Họp nhóm\nnội dung',
        markdown: true,
        createdAt: t,
        updatedAt: t,
      );
      expect(note.displayTitle, 'Họp nhóm');
    });

    test('preview bỏ cú pháp, văn bản thường giữ nguyên', () {
      final md = Note(
        id: 'n4',
        body: '- **việc** một\n- [tài liệu](https://a.b)',
        markdown: true,
        createdAt: t,
        updatedAt: t,
      );
      expect(md.preview, 'việc một\ntài liệu');

      final plain = Note(
        id: 'n5',
        body: '- **việc** một',
        markdown: false,
        createdAt: t,
        updatedAt: t,
      );
      expect(plain.preview, '- **việc** một');
    });
  });
}
