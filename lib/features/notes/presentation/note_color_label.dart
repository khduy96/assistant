import 'package:flutter/material.dart';

import '../domain/entities/note.dart';

/// The Vietnamese name of each [NoteColor], shown as the swatch tooltip.
extension NoteColorLabel on NoteColor {
  String get label => switch (this) {
    NoteColor.none => 'Không màu',
    NoteColor.yellow => 'Vàng',
    NoteColor.green => 'Xanh lá',
    NoteColor.blue => 'Xanh dương',
    NoteColor.pink => 'Hồng',
    NoteColor.purple => 'Tím',
  };
}

/// Background tint for each [NoteColor], picked to stay readable in both the
/// light and the dark theme.
Color? noteColorOf(NoteColor color, ColorScheme scheme) {
  final dark = scheme.brightness == Brightness.dark;
  return switch (color) {
    NoteColor.none => null,
    NoteColor.yellow =>
      dark ? const Color(0xFF4A3F14) : const Color(0xFFFEF3C7),
    NoteColor.green => dark ? const Color(0xFF16402C) : const Color(0xFFD1FAE5),
    NoteColor.blue => dark ? const Color(0xFF17334F) : const Color(0xFFDBEAFE),
    NoteColor.pink => dark ? const Color(0xFF4A1F2E) : const Color(0xFFFCE7F3),
    NoteColor.purple =>
      dark ? const Color(0xFF32224F) : const Color(0xFFEDE9FE),
  };
}
