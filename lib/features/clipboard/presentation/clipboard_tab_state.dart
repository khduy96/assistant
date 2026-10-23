import 'package:flutter/material.dart';

import 'clipboard_controller.dart';

/// The four lists inside the clipboard tab.
enum ClipboardSection {
  temp('Tạm', Icons.history_rounded),
  saved('Đã lưu', Icons.bookmark_rounded),
  pinned('Ghim', Icons.push_pin_rounded),
  groups('Nhóm', Icons.folder_rounded);

  const ClipboardSection(this.label, this.icon);

  final String label;
  final IconData icon;

  int countIn(ClipboardController clips) => switch (this) {
    ClipboardSection.temp => clips.tempCount,
    ClipboardSection.saved => clips.savedCount,
    ClipboardSection.pinned => clips.pinnedCount,
    ClipboardSection.groups => clips.groups.length,
  };
}

/// What the clipboard tab remembers: the search box and which list is open.
///
/// It lives above the tab because the app bar and the floating button belong
/// to the shared scaffold and have to follow the section — and because one
/// query serves all four lists, so switching them keeps what was typed.
class ClipboardTabState extends ChangeNotifier {
  final TextEditingController search = TextEditingController();

  ClipboardSection _section = ClipboardSection.temp;
  ClipboardSection get section => _section;

  void goTo(ClipboardSection value) {
    if (_section == value) return;
    _section = value;
    notifyListeners();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }
}
