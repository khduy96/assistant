import 'package:event_notice/features/notes/domain/entities/note.dart';
import 'package:event_notice/features/notes/presentation/note_color_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('NoteColor.label giữ nhãn tiếng Việt cũ', () {
    expect(
      {for (final c in NoteColor.values) c: c.label},
      {
        NoteColor.none: 'Không màu',
        NoteColor.yellow: 'Vàng',
        NoteColor.green: 'Xanh lá',
        NoteColor.blue: 'Xanh dương',
        NoteColor.pink: 'Hồng',
        NoteColor.purple: 'Tím',
      },
    );
  });

  test('noteColorOf: không màu thì null, sáng/tối khác nhau', () {
    final light = ColorScheme.fromSeed(seedColor: Colors.blue);
    final dark = ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.dark,
    );

    expect(noteColorOf(NoteColor.none, light), isNull);
    expect(noteColorOf(NoteColor.none, dark), isNull);
    expect(noteColorOf(NoteColor.yellow, light), const Color(0xFFFEF3C7));
    expect(noteColorOf(NoteColor.yellow, dark), const Color(0xFF4A3F14));
    expect(noteColorOf(NoteColor.purple, light), const Color(0xFFEDE9FE));
    expect(noteColorOf(NoteColor.purple, dark), const Color(0xFF32224F));
  });
}
