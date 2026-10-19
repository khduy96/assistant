/// Colour a note is tagged with. Stored by name so the palette can change
/// without breaking old files.
enum NoteColor { none, yellow, green, blue, pink, purple }

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
class Note {
  Note({
    required this.id,
    this.title = '',
    this.body = '',
    this.pinned = false,
    this.markdown = false,
    this.color = NoteColor.none,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.remoteId,
    this.dirty = true,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  final String id;
  String title;
  String body;
  bool pinned;

  /// True when [body] is written in Markdown and should be rendered instead of
  /// shown as plain text. Old notes default to false, so nothing changes look.
  bool markdown;

  NoteColor color;

  final DateTime createdAt;

  /// Bumped on every edit; drives the sort order and the card subtitle, and is
  /// what the sync uses to settle conflicts.
  DateTime updatedAt;

  /// Parse's `objectId`, null until this note has been pushed once.
  String? remoteId;

  /// True while the local copy is ahead of the server.
  bool dirty;

  /// Marks the note as edited now, so the next sync pushes it.
  void touch() {
    updatedAt = DateTime.now();
    dirty = true;
  }

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

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'pinned': pinned,
        'markdown': markdown,
        'color': color.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'remoteId': remoteId,
        'dirty': dirty,
      };

  factory Note.fromJson(Map<String, dynamic> j) => Note(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        pinned: j['pinned'] as bool? ?? false,
        markdown: j['markdown'] as bool? ?? false,
        color: NoteColor.values.firstWhere(
          (c) => c.name == j['color'],
          orElse: () => NoteColor.none,
        ),
        createdAt: j['createdAt'] == null
            ? null
            : DateTime.tryParse(j['createdAt'] as String),
        updatedAt: j['updatedAt'] == null
            ? null
            : DateTime.tryParse(j['updatedAt'] as String),
        remoteId: j['remoteId'] as String?,
        // A file written before sync existed has no flag: treat those notes as
        // unpushed so the first sync uploads them.
        dirty: j['dirty'] as bool? ?? true,
      );

  /// The Back4App body. `space` is added by the sync service, and Parse owns
  /// the names `createdAt`/`updatedAt`, hence the `note` prefix here.
  Map<String, Object?> toParse() => {
        'localId': id,
        'title': title,
        'body': body,
        'pinned': pinned,
        'markdown': markdown,
        'color': color.name,
        'noteCreatedAt': createdAt.millisecondsSinceEpoch,
        'noteUpdatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory Note.fromParse(Map<String, Object?> json) {
    DateTime? at(String key) {
      final value = json[key];
      return value is num
          ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
          : null;
    }

    final now = DateTime.now();
    return Note(
      id: json['localId'] as String,
      title: (json['title'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      pinned: json['pinned'] as bool? ?? false,
      markdown: json['markdown'] as bool? ?? false,
      color: NoteColor.values.firstWhere(
        (c) => c.name == json['color'],
        orElse: () => NoteColor.none,
      ),
      createdAt: at('noteCreatedAt') ?? now,
      updatedAt: at('noteUpdatedAt') ?? now,
      remoteId: json['objectId'] as String?,
      dirty: false,
    );
  }
}
