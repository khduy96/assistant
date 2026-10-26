import 'package:event_notice/features/notes/domain/entities/note.dart';
import 'package:flutter_test/flutter_test.dart';

final _at = DateTime(2026, 10, 22, 9);

Note _note({
  String id = 'n',
  String title = '',
  String body = '',
  bool markdown = false,
}) => Note(
  id: id,
  title: title,
  body: body,
  markdown: markdown,
  createdAt: _at,
  updatedAt: _at,
);

void main() {
  group('Note markdown', () {
    // Ported from test/note_test.dart:22-37.
    test('tiêu đề suy ra bỏ cú pháp markdown', () {
      final note = _note(
        id: 'n3',
        body: '## Họp nhóm\nnội dung',
        markdown: true,
      );
      expect(note.displayTitle, 'Họp nhóm');
    });

    test('preview bỏ cú pháp, văn bản thường giữ nguyên', () {
      final md = _note(
        id: 'n4',
        body: '- **việc** một\n- [tài liệu](https://a.b)',
        markdown: true,
      );
      expect(md.preview, 'việc một\ntài liệu');

      final plain = _note(id: 'n5', body: '- **việc** một', markdown: false);
      expect(plain.preview, '- **việc** một');
    });
  });

  group('displayTitle', () {
    test('ưu tiên tiêu đề, bỏ khoảng trắng hai đầu', () {
      expect(_note(title: '  Mua sắm ', body: 'sữa').displayTitle, 'Mua sắm');
    });

    test('không có tiêu đề thì lấy dòng đầu không rỗng của nội dung', () {
      expect(_note(body: '\n  \n  dòng hai \nba').displayTitle, 'dòng hai');
    });

    test('văn bản thường giữ nguyên cú pháp ở dòng đầu', () {
      expect(_note(body: '## Họp nhóm').displayTitle, '## Họp nhóm');
    });

    test('không có gì thì là "Ghi chú không tên"', () {
      expect(_note(title: ' ', body: ' \n ').displayTitle, 'Ghi chú không tên');
    });
  });

  group('isEmpty', () {
    test('tiêu đề và nội dung chỉ có khoảng trắng thì rỗng', () {
      expect(_note(title: '  ', body: '\n\t ').isEmpty, isTrue);
    });

    test('có tiêu đề hoặc nội dung thì không rỗng', () {
      expect(_note(title: 'a').isEmpty, isFalse);
      expect(_note(body: 'b').isEmpty, isFalse);
    });
  });

  group('matches', () {
    final note = _note(title: 'Họp Nhóm', body: 'Mang LAPTOP');

    test('query rỗng hoặc toàn khoảng trắng khớp mọi ghi chú', () {
      expect(note.matches(''), isTrue);
      expect(note.matches('   '), isTrue);
    });

    test('khớp tiêu đề hoặc nội dung, không phân biệt hoa thường', () {
      expect(note.matches('nhóm'), isTrue);
      expect(note.matches('  laptop '), isTrue);
      expect(note.matches('bút'), isFalse);
    });
  });

  group('copyWith', () {
    test('giữ id và các field không truyền, chỉ đổi field được truyền', () {
      final base = Note(
        id: 'n1',
        title: 't',
        body: 'b',
        pinned: true,
        markdown: true,
        color: NoteColor.pink,
        createdAt: _at,
        updatedAt: _at,
      );
      final later = _at.add(const Duration(hours: 1));

      final edited = base.copyWith(body: 'mới', updatedAt: later);

      expect(edited.id, 'n1');
      expect(edited.title, 't');
      expect(edited.body, 'mới');
      expect(edited.pinned, isTrue);
      expect(edited.markdown, isTrue);
      expect(edited.color, NoteColor.pink);
      expect(edited.createdAt, _at);
      expect(edited.updatedAt, later);
      // The original is untouched.
      expect(base.body, 'b');
      expect(base.updatedAt, _at);
    });

    test('copyWith không tham số cho bản bằng nhau theo giá trị', () {
      final base = _note(id: 'n1', title: 't');
      expect(base.copyWith(), base);
      expect(base.copyWith().hashCode, base.hashCode);
      expect(base.copyWith(title: 'khác'), isNot(base));
    });
  });

  test('giá trị mặc định giống bản cũ', () {
    final note = Note(id: 'n', createdAt: _at, updatedAt: _at);
    expect(note.title, '');
    expect(note.body, '');
    expect(note.pinned, isFalse);
    expect(note.markdown, isFalse);
    expect(note.color, NoteColor.none);
  });
}
