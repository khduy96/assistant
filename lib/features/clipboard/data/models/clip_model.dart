import '../../domain/entities/clip_item.dart';

/// A clip as it is stored: the entity's fields plus the sync state.
///
/// The only place that knows the columns of the `clips` table and the `Clip`
/// body on Back4App. Neither format may change: databases written by older
/// builds and other devices running one still read and write them.
class ClipModel {
  const ClipModel({
    required this.id,
    required this.content,
    required this.type,
    required this.createdAt,
    required this.updatedAt,
    this.copiedAt,
    this.isSaved = false,
    this.isPinned = false,
    this.groupId,
    this.note,
    this.copyCount = 0,
    this.remoteId,
    this.dirty = true,
  });

  final String id;
  final String content;
  final ClipType type;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? copiedAt;
  final bool isSaved;
  final bool isPinned;
  final String? groupId;
  final String? note;
  final int copyCount;

  /// Parse's `objectId`, null until this clip has been pushed once.
  final String? remoteId;

  /// True while the local row holds changes the server has not seen.
  final bool dirty;

  /// Same rule as [ClipItem.isTemp]: temp clips never leave the device.
  bool get isTemp => !isSaved && !isPinned;

  /// The row of the `clips` table. Columns added for features that are gone
  /// (`deleted_at`, the `file_*` ones) are not written.
  Map<String, Object?> toMap() => {
    'id': id,
    'content': content,
    'type': type.name,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'copied_at': copiedAt?.millisecondsSinceEpoch,
    'is_saved': isSaved ? 1 : 0,
    'is_pinned': isPinned ? 1 : 0,
    'group_id': groupId,
    'note': note,
    'copy_count': copyCount,
    'remote_id': remoteId,
    'dirty': dirty ? 1 : 0,
  };

  /// Reads one row of the `clips` table. An unknown type reads as text.
  factory ClipModel.fromMap(Map<String, Object?> map) => ClipModel(
    id: map['id'] as String,
    content: map['content'] as String,
    type: _type(map['type']),
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    copiedAt: map['copied_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(map['copied_at'] as int),
    isSaved: (map['is_saved'] as int) == 1,
    isPinned: (map['is_pinned'] as int) == 1,
    groupId: map['group_id'] as String?,
    note: map['note'] as String?,
    copyCount: (map['copy_count'] as int?) ?? 0,
    remoteId: map['remote_id'] as String?,
    dirty: ((map['dirty'] as int?) ?? 0) == 1,
  );

  /// The Back4App body. `space` is added by the sync engine, and Parse owns
  /// the names `createdAt`/`updatedAt`, hence the `clip` prefix here.
  /// [copiedAt] never travels.
  Map<String, Object?> toParse() => {
    'localId': id,
    'content': content,
    'kind': type.name,
    'clipCreatedAt': createdAt.millisecondsSinceEpoch,
    'clipUpdatedAt': updatedAt.millisecondsSinceEpoch,
    'isSaved': isSaved,
    'isPinned': isPinned,
    'groupLocalId': groupId,
    'note': note,
    'copyCount': copyCount,
  };

  /// Reads one `Clip` object from the server. It is clean by definition: it
  /// is what the server already has. [copiedAt] is this device's own, kept
  /// from the stored row; [now] stands in for a missing time.
  factory ClipModel.fromParse(
    Map<String, Object?> json, {
    DateTime? copiedAt,
    required DateTime now,
  }) {
    DateTime at(String key) {
      final value = json[key];
      return value is num
          ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
          : now;
    }

    return ClipModel(
      id: json['localId'] as String,
      content: (json['content'] as String?) ?? '',
      type: _type(json['kind']),
      createdAt: at('clipCreatedAt'),
      updatedAt: at('clipUpdatedAt'),
      copiedAt: copiedAt,
      isSaved: json['isSaved'] == true,
      isPinned: json['isPinned'] == true,
      groupId: json['groupLocalId'] as String?,
      note: json['note'] as String?,
      copyCount: (json['copyCount'] as num?)?.toInt() ?? 0,
      remoteId: json['objectId'] as String?,
      dirty: false,
    );
  }

  /// Types are stored by name; an unknown name reads as text.
  static ClipType _type(Object? name) => ClipType.values.firstWhere(
    (t) => t.name == name,
    orElse: () => ClipType.text,
  );
}
