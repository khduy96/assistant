/// Detected content kind of a clipboard entry. Drives the icon and the filter
/// chips; the data layer stores it by name.
enum ClipType { text, link, email, phone, number, color, code }

/// Marks a [ClipItem.copyWith] argument that was not passed, so an explicit
/// null can clear a field.
const Object _unset = Object();

/// One clipboard entry: captured automatically as a temp clip, or kept by the
/// user as a saved (and maybe pinned) one.
///
/// Immutable: edits go through [copyWith]. Sync state (the server id, whether
/// the local copy is ahead) lives in the data layer, not here.
class ClipItem {
  const ClipItem({
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
  });

  final String id;
  final String content;
  final ClipType type;

  /// When the clip was captured or created. A temp clip's one-day countdown
  /// runs from here, so capturing it again or unsaving it moves it.
  final DateTime createdAt;

  /// Bumped on every edit; what the sync uses to settle conflicts.
  final DateTime updatedAt;

  /// When the clip was last put back on the clipboard. Never leaves the
  /// device.
  final DateTime? copiedAt;

  final bool isSaved;
  final bool isPinned;
  final String? groupId;
  final String? note;
  final int copyCount;

  /// A temp clip lives for [ClipItem.tempTtl] then gets purged automatically.
  static const Duration tempTtl = Duration(days: 1);

  bool get isTemp => !isSaved && !isPinned;

  DateTime get expiresAt => createdAt.add(tempTtl);

  /// Time left at [now] before a temp clip is purged; zero once it is due.
  Duration remaining(DateTime now) {
    final left = expiresAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  String get preview {
    final flat = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.isEmpty ? '(trống)' : flat;
  }

  /// A copy with the given fields replaced. The id never changes.
  ///
  /// [copiedAt], [groupId] and [note] can be cleared by passing an explicit
  /// null; leaving them out keeps the current value.
  ClipItem copyWith({
    String? content,
    ClipType? type,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? copiedAt = _unset,
    bool? isSaved,
    bool? isPinned,
    Object? groupId = _unset,
    Object? note = _unset,
    int? copyCount,
  }) => ClipItem(
    id: id,
    content: content ?? this.content,
    type: type ?? this.type,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    copiedAt: identical(copiedAt, _unset)
        ? this.copiedAt
        : copiedAt as DateTime?,
    isSaved: isSaved ?? this.isSaved,
    isPinned: isPinned ?? this.isPinned,
    groupId: identical(groupId, _unset) ? this.groupId : groupId as String?,
    note: identical(note, _unset) ? this.note : note as String?,
    copyCount: copyCount ?? this.copyCount,
  );

  /// Best-effort classification so the list can show meaningful icons.
  static ClipType detectType(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return ClipType.text;
    if (RegExp(
      r'^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$',
    ).hasMatch(value)) {
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
      '{',
      '}',
      ';',
      '=>',
      '()',
      '</',
      'function ',
      'const ',
      'class ',
      'import ',
      'def ',
      'SELECT ',
      'return ',
    ];
    final hits = markers.where(value.contains).length;
    return hits >= 2 || (value.contains('\n') && hits >= 1);
  }

  @override
  bool operator ==(Object other) =>
      other is ClipItem &&
      other.id == id &&
      other.content == content &&
      other.type == type &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.copiedAt == copiedAt &&
      other.isSaved == isSaved &&
      other.isPinned == isPinned &&
      other.groupId == groupId &&
      other.note == note &&
      other.copyCount == copyCount;

  @override
  int get hashCode => Object.hash(
    id,
    content,
    type,
    createdAt,
    updatedAt,
    copiedAt,
    isSaved,
    isPinned,
    groupId,
    note,
    copyCount,
  );

  @override
  String toString() =>
      'ClipItem($id, ${type.name}, saved: $isSaved, pinned: $isPinned, '
      'group: $groupId)';
}
