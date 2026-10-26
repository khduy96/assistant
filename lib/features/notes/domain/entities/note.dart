/// Colour a note is tagged with. The data layer stores it by name, so the
/// palette can change without breaking old files.
enum NoteColor { none, yellow, green, blue, pink, purple }

/// Drops the Markdown syntax from one line so it can be shown as plain text in
/// a card or a title. Deliberately rough: this is a preview, not a renderer.
String _stripMarkdown(String line) {
  var s = line.trim();
  s = s.replaceFirst(RegExp(r'^\s{0,3}(#{1,6}\s+|>\s?|[-*+]\s+|\d+\.\s+)'), '');
  s = s.replaceAll(RegExp(r'^\s*[-*_]{3,}\s*$'), '');
  // [text](url) and ![alt](url) keep only the visible part.
  s = s.replaceAllMapped(
      RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1) ?? '');
  s = s.replaceAll(RegExp(r'(\*\*|__|\*|_|`|~~)'), '');
  return s.trim();
}

/// A free-form note. It never rings and has no schedule — it is just text the
/// user wants to keep, optionally pinned to the top of the list.
///
/// Immutable: edits go through [copyWith]. Sync state (the server id, whether
/// the local copy is ahead) lives in the data layer, not here.
class Note {
  const Note({
    required this.id,
    this.title = '',
    this.body = '',
    this.pinned = false,
    this.markdown = false,
    this.color = NoteColor.none,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String body;
  final bool pinned;

  /// True when [body] is written in Markdown and should be rendered instead of
  /// shown as plain text. Old notes default to false, so nothing changes look.
  final bool markdown;

  final NoteColor color;

  final DateTime createdAt;

  /// Bumped on every edit; drives the sort order and the card subtitle, and is
  /// what the sync uses to settle conflicts.
  final DateTime updatedAt;

  /// A note with no title falls back to its first line in the list.
  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    final firstLine = body
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) return 'Ghi chú không tên';
    return markdown ? _stripMarkdown(firstLine) : firstLine;
  }

  /// The few lines shown under the title on a card. A Markdown note is
  /// stripped of its syntax first, so the card reads as text and not as `##`.
  String get preview {
    final text = body.trim();
    if (!markdown) return text;
    return text
        .split('\n')
        .map(_stripMarkdown)
        .where((l) => l.isNotEmpty)
        .join('\n');
  }

  bool get isEmpty => title.trim().isEmpty && body.trim().isEmpty;

  /// True when [query] appears in the title or the body, ignoring case.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return title.toLowerCase().contains(q) || body.toLowerCase().contains(q);
  }

  /// A copy with the given fields replaced. The id never changes.
  Note copyWith({
    String? title,
    String? body,
    bool? pinned,
    bool? markdown,
    NoteColor? color,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Note(
    id: id,
    title: title ?? this.title,
    body: body ?? this.body,
    pinned: pinned ?? this.pinned,
    markdown: markdown ?? this.markdown,
    color: color ?? this.color,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is Note &&
      other.id == id &&
      other.title == title &&
      other.body == body &&
      other.pinned == pinned &&
      other.markdown == markdown &&
      other.color == color &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    body,
    pinned,
    markdown,
    color,
    createdAt,
    updatedAt,
  );

  @override
  String toString() => 'Note($id, pinned: $pinned, updatedAt: $updatedAt)';
}
