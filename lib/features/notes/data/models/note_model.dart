import '../../domain/entities/note.dart';

/// A note as it is stored: the entity's fields plus the sync state.
///
/// The only place that knows the `notes.json` layout and the `NoteItem`
/// body on Back4App. Neither format may change: old files and other devices
/// running an older build still read and write them.
class NoteModel {
  const NoteModel({
    required this.id,
    this.title = '',
    this.body = '',
    this.pinned = false,
    this.markdown = false,
    this.color = NoteColor.none,
    required this.createdAt,
    required this.updatedAt,
    this.remoteId,
    this.dirty = true,
  });

  final String id;
  final String title;
  final String body;
  final bool pinned;
  final bool markdown;
  final NoteColor color;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Parse's `objectId`, null until this note has been pushed once.
  final String? remoteId;

  /// True while the local copy is ahead of the server.
  final bool dirty;

  /// A copy with the given fields replaced. Only the sync state ever changes
  /// on a stored model; edits come in as a new model from the mapper.
  NoteModel copyWith({String? remoteId, bool? dirty}) => NoteModel(
    id: id,
    title: title,
    body: body,
    pinned: pinned,
    markdown: markdown,
    color: color,
    createdAt: createdAt,
    updatedAt: updatedAt,
    remoteId: remoteId ?? this.remoteId,
    dirty: dirty ?? this.dirty,
  );

  Map<String, Object?> toJson() => {
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

  /// Reads one entry of `notes.json`. [now] stands in for a missing or
  /// unreadable `createdAt`; a missing `updatedAt` falls back to `createdAt`.
  factory NoteModel.fromJson(Map<String, dynamic> j, {required DateTime now}) {
    final createdAt = j['createdAt'] == null
        ? null
        : DateTime.tryParse(j['createdAt'] as String);
    final updatedAt = j['updatedAt'] == null
        ? null
        : DateTime.tryParse(j['updatedAt'] as String);
    return NoteModel(
      id: j['id'] as String,
      title: j['title'] as String? ?? '',
      body: j['body'] as String? ?? '',
      pinned: j['pinned'] as bool? ?? false,
      // Notes written before Markdown existed are plain text.
      markdown: j['markdown'] as bool? ?? false,
      color: _color(j['color']),
      createdAt: createdAt ?? now,
      updatedAt: updatedAt ?? createdAt ?? now,
      remoteId: j['remoteId'] as String?,
      // A file written before sync existed has no flag: treat those notes as
      // unpushed so the first sync uploads them.
      dirty: j['dirty'] as bool? ?? true,
    );
  }

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

  /// Reads one `NoteItem` object from the server. It is clean by definition:
  /// it is what the server already has. [now] stands in for a missing time.
  factory NoteModel.fromParse(
    Map<String, Object?> json, {
    required DateTime now,
  }) {
    DateTime? at(String key) {
      final value = json[key];
      return value is num
          ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
          : null;
    }

    return NoteModel(
      id: json['localId'] as String,
      title: (json['title'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      pinned: json['pinned'] as bool? ?? false,
      markdown: json['markdown'] as bool? ?? false,
      color: _color(json['color']),
      createdAt: at('noteCreatedAt') ?? now,
      updatedAt: at('noteUpdatedAt') ?? now,
      remoteId: json['objectId'] as String?,
      dirty: false,
    );
  }

  /// Colours are stored by name; an unknown name reads as no colour.
  static NoteColor _color(Object? name) => NoteColor.values.firstWhere(
    (c) => c.name == name,
    orElse: () => NoteColor.none,
  );
}
