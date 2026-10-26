import 'package:flutter/material.dart';

import '../domain/entities/clip_group.dart';
import '../domain/entities/clip_item.dart';

/// The Vietnamese name and the icon of each [ClipType], for the cards and the
/// type filter.
extension ClipTypeLabel on ClipType {
  String get label => switch (this) {
    ClipType.text => 'Văn bản',
    ClipType.link => 'Liên kết',
    ClipType.email => 'Email',
    ClipType.phone => 'Số điện thoại',
    ClipType.number => 'Số',
    ClipType.color => 'Màu',
    ClipType.code => 'Mã / Code',
  };

  IconData get icon => switch (this) {
    ClipType.text => Icons.notes_rounded,
    ClipType.link => Icons.link_rounded,
    ClipType.email => Icons.alternate_email_rounded,
    ClipType.phone => Icons.phone_rounded,
    ClipType.number => Icons.tag_rounded,
    ClipType.color => Icons.palette_rounded,
    ClipType.code => Icons.code_rounded,
  };
}

/// A group's ARGB colour as a Flutter [Color].
extension ClipGroupColor on ClipGroup {
  Color get materialColor => Color(color);
}
