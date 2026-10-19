import 'package:event_notice/models/note.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Note markdown', () {
    test('cờ markdown đi qua JSON và Parse', () {
      final note = Note(id: 'n1', title: 'Bảng', body: '| a | b |', markdown: true);

      expect(Note.fromJson(note.toJson()).markdown, isTrue);
      expect(note.toParse()['markdown'], isTrue);
      expect(
        Note.fromParse({...note.toParse(), 'objectId': 'x'}).markdown,
        isTrue,
      );
    });

    test('ghi chú cũ không có cờ thì coi như văn bản thường', () {
      final old = Note.fromJson({'id': 'n2', 'title': 'Cũ', 'body': 'xin chào'});
      expect(old.markdown, isFalse);
    });

    test('tiêu đề suy ra bỏ cú pháp markdown', () {
      final note = Note(id: 'n3', body: '## Họp nhóm\nnội dung', markdown: true);
      expect(note.displayTitle, 'Họp nhóm');
    });

    test('preview bỏ cú pháp, văn bản thường giữ nguyên', () {
      final md = Note(
        id: 'n4',
        body: '- **việc** một\n- [tài liệu](https://a.b)',
        markdown: true,
      );
      expect(md.preview, 'việc một\ntài liệu');

      final plain = Note(id: 'n5', body: '- **việc** một', markdown: false);
      expect(plain.preview, '- **việc** một');
    });
  });
}
