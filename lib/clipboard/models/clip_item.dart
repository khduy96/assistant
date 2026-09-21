import 'package:flutter/material.dart';

/// Detected content kind of a clipboard entry. Used for icon + filter chips.
enum ClipType { text, link, email, phone, number, color, code }

extension ClipTypeX on ClipType {
  String get label {
    switch (this) {
      case ClipType.text:
        return 'Văn bản';
      case ClipType.link:
        return 'Liên kết';
      case ClipType.email:
        return 'Email';
      case ClipType.phone:
        return 'Số điện thoại';
      case ClipType.number:
        return 'Số';
      case ClipType.color:
        return 'Màu';
      case ClipType.code:
        return 'Mã / Code';
    }
  }

  IconData get icon {
    switch (this) {
      case ClipType.text:
        return Icons.notes_rounded;
      case ClipType.link:
        return Icons.link_rounded;
      case ClipType.email:
        return Icons.alternate_email_rounded;
      case ClipType.phone:
        return Icons.phone_rounded;
      case ClipType.number:
        return Icons.tag_rounded;
      case ClipType.color:
        return Icons.palette_rounded;
      case ClipType.code:
        return Icons.code_rounded;
    }
  }
}

class ClipItem {
  ClipItem({
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

  /// Parse `objectId` once this clip has been pushed at least one time.
  final String? remoteId;

  /// True while the local row holds changes the server has not seen.
  final bool dirty;

  /// A temp clip lives for [ClipItem.tempTtl] then gets purged automatically.
  static const Duration tempTtl = Duration(days: 1);

  bool get isTemp => !isSaved && !isPinned;

  DateTime get expiresAt => createdAt.add(tempTtl);

  Duration get remaining {
    final left = expiresAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  String get preview {
    final flat = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.isEmpty ? '(trống)' : flat;
  }

  ClipItem copyWith({
    String? content,
    ClipType? type,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? copiedAt,
    bool? isSaved,
    bool? isPinned,
    String? groupId,
    bool clearGroup = false,
    String? note,
    int? copyCount,
    String? remoteId,
    bool? dirty,
  }) {
    return ClipItem(
      id: id,
      content: content ?? this.content,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      copiedAt: copiedAt ?? this.copiedAt,
      isSaved: isSaved ?? this.isSaved,
      isPinned: isPinned ?? this.isPinned,
      groupId: clearGroup ? null : (groupId ?? this.groupId),
      note: note ?? this.note,
      copyCount: copyCount ?? this.copyCount,
      remoteId: remoteId ?? this.remoteId,
      dirty: dirty ?? this.dirty,
    );
  }

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

  factory ClipItem.fromMap(Map<String, Object?> map) => ClipItem(
        id: map['id'] as String,
        content: map['content'] as String,
        type: ClipType.values.firstWhere(
          (t) => t.name == map['type'],
          orElse: () => ClipType.text,
        ),
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
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

  /// Best-effort classification so the list can show meaningful icons.
  static ClipType detectType(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return ClipType.text;
    if (RegExp(r'^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$')
        .hasMatch(value)) {
      return ClipType.color;
    }
    if (RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$').hasMatch(value)) {
      return ClipType.email;
    }
    if (RegExp(r'^(https?://|www\.)\S+$').hasMatch(value)) {
      return ClipType.link;
    }
    if (RegExp(r'^\+?[\d\s().-]{8,20}$').hasMatch(value) &&
        RegExp(r'\d').allMatches(value).length >= 8) {
      return ClipType.phone;
    }
    if (RegExp(r'^-?[\d.,]+$').hasMatch(value)) return ClipType.number;
    if (_looksLikeCode(value)) return ClipType.code;
    return ClipType.text;
  }

  static bool _looksLikeCode(String value) {
    const markers = [
      '{', '}', ';', '=>', '()', '</', 'function ', 'const ', 'class ',
      'import ', 'def ', 'SELECT ', 'return ',
    ];
    final hits = markers.where(value.contains).length;
    return hits >= 2 || (value.contains('\n') && hits >= 1);
  }

  /// Shape sent to Back4App. Parse owns `createdAt`/`updatedAt`, so the app's
  /// own timestamps travel under distinct names.
  Map<String, Object?> toParse(String space) => {
        'space': space,
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

  /// Rebuilds a clip from a Back4App row, keeping device-local fields from
  /// [existing] when there is one.
  factory ClipItem.fromParse(Map<String, Object?> json, {ClipItem? existing}) {
    int ms(String key, int fallback) {
      final value = json[key];
      return value is num ? value.toInt() : fallback;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    return ClipItem(
      id: json['localId'] as String,
      content: (json['content'] as String?) ?? '',
      type: ClipType.values.firstWhere(
        (t) => t.name == json['kind'],
        orElse: () => ClipType.text,
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(ms('clipCreatedAt', now)),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(ms('clipUpdatedAt', now)),
      copiedAt: existing?.copiedAt,
      isSaved: json['isSaved'] == true,
      isPinned: json['isPinned'] == true,
      groupId: json['groupLocalId'] as String?,
      note: json['note'] as String?,
      copyCount: (json['copyCount'] as num?)?.toInt() ?? 0,
      remoteId: json['objectId'] as String?,
      dirty: false,
    );
  }
}
