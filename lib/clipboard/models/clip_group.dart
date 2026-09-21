import 'package:flutter/material.dart';

class ClipGroup {
  ClipGroup({
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
  final int color;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int sortOrder;
  final String? remoteId;
  final bool dirty;

  Color get materialColor => Color(color);

  /// Palette offered when creating a group.
  static const List<int> palette = [
    0xFF5B8DEF,
    0xFF00B894,
    0xFFE17055,
    0xFFA55EEA,
    0xFFF9A825,
    0xFFEF5DA8,
    0xFF20BFA9,
    0xFF6C7A89,
  ];

  ClipGroup copyWith({
    String? name,
    int? color,
    int? sortOrder,
    DateTime? updatedAt,
    String? remoteId,
    bool? dirty,
  }) =>
      ClipGroup(
        id: id,
        name: name ?? this.name,
        color: color ?? this.color,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        sortOrder: sortOrder ?? this.sortOrder,
        remoteId: remoteId ?? this.remoteId,
        dirty: dirty ?? this.dirty,
      );

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

  factory ClipGroup.fromMap(Map<String, Object?> map) {
    final created = map['created_at'] as int;
    return ClipGroup(
      id: map['id'] as String,
      name: map['name'] as String,
      color: map['color'] as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(created),
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch((map['updated_at'] as int?) ?? created),
      sortOrder: (map['sort_order'] as int?) ?? 0,
      remoteId: map['remote_id'] as String?,
      dirty: ((map['dirty'] as int?) ?? 0) == 1,
    );
  }

  Map<String, Object?> toParse(String space) => {
        'space': space,
        'localId': id,
        'name': name,
        'color': color,
        'groupCreatedAt': createdAt.millisecondsSinceEpoch,
        'groupUpdatedAt': updatedAt.millisecondsSinceEpoch,
        'sortOrder': sortOrder,
      };

  factory ClipGroup.fromParse(Map<String, Object?> json) {
    final now = DateTime.now().millisecondsSinceEpoch;
    int ms(String key) {
      final value = json[key];
      return value is num ? value.toInt() : now;
    }

    return ClipGroup(
      id: json['localId'] as String,
      name: (json['name'] as String?) ?? 'Nhóm',
      color: (json['color'] as num?)?.toInt() ?? palette.first,
      createdAt: DateTime.fromMillisecondsSinceEpoch(ms('groupCreatedAt')),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(ms('groupUpdatedAt')),
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      remoteId: json['objectId'] as String?,
      dirty: false,
    );
  }
}
