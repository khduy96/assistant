import '../../domain/entities/clip_group.dart';

/// A group as it is stored: the entity's fields plus the sync state.
///
/// The only place that knows the columns of the `groups` table and the
/// `ClipGroup` body on Back4App. Neither format may change.
class ClipGroupModel {
  const ClipGroupModel({
    required this.id,
    required this.name,
    required this.color,
    required this.createdAt,
    required this.updatedAt,
    this.sortOrder = 0,
    this.remoteId,
    this.dirty = true,
  });

  final String id;
  final String name;

  /// ARGB, e.g. `0xFF5B8DEF`.
  final int color;

  final DateTime createdAt;
  final DateTime updatedAt;
  final int sortOrder;

  /// Parse's `objectId`, null until this group has been pushed once.
  final String? remoteId;

  /// True while the local row holds changes the server has not seen.
  final bool dirty;

  /// The row of the `groups` table. `deleted_at`, left from the tombstone
  /// era, is not written.
  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'color': color,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'sort_order': sortOrder,
    'remote_id': remoteId,
    'dirty': dirty ? 1 : 0,
  };

  /// Reads one row of the `groups` table. Rows from before v2 may lack
  /// `updated_at`; it falls back to `created_at`.
  factory ClipGroupModel.fromMap(Map<String, Object?> map) {
    final created = map['created_at'] as int;
    return ClipGroupModel(
      id: map['id'] as String,
      name: map['name'] as String,
      color: map['color'] as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(created),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['updated_at'] as int?) ?? created,
      ),
      sortOrder: (map['sort_order'] as int?) ?? 0,
      remoteId: map['remote_id'] as String?,
      dirty: ((map['dirty'] as int?) ?? 0) == 1,
    );
  }

  /// The Back4App body. `space` is added by the sync engine, and Parse owns
  /// the names `createdAt`/`updatedAt`, hence the `group` prefix here.
  Map<String, Object?> toParse() => {
    'localId': id,
    'name': name,
    'color': color,
    'groupCreatedAt': createdAt.millisecondsSinceEpoch,
    'groupUpdatedAt': updatedAt.millisecondsSinceEpoch,
    'sortOrder': sortOrder,
  };

  /// Reads one `ClipGroup` object from the server. It is clean by
  /// definition. [now] stands in for a missing time; a missing name reads as
  /// 'Nhóm' and a missing colour as the first of [ClipGroup.palette].
  factory ClipGroupModel.fromParse(
    Map<String, Object?> json, {
    required DateTime now,
  }) {
    DateTime at(String key) {
      final value = json[key];
      return value is num
          ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
          : now;
    }

    return ClipGroupModel(
      id: json['localId'] as String,
      name: (json['name'] as String?) ?? 'Nhóm',
      color: (json['color'] as num?)?.toInt() ?? ClipGroup.palette.first,
      createdAt: at('groupCreatedAt'),
      updatedAt: at('groupUpdatedAt'),
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      remoteId: json['objectId'] as String?,
      dirty: false,
    );
  }
}
