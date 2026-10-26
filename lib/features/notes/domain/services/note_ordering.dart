import '../entities/note.dart';

/// The order notes are listed in: pinned first, then most recently edited.
abstract final class NoteOrdering {
  static int compare(Note a, Note b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    return b.updatedAt.compareTo(a.updatedAt);
  }

  /// [notes] as a new list in display order.
  static List<Note> sorted(Iterable<Note> notes) =>
      notes.toList()..sort(compare);
}
