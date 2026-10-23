/// A named, coloured folder the user files saved clips into.
///
/// Immutable: edits go through [copyWith]. The colour is an ARGB value; the
/// presentation layer turns it into a Flutter colour. Sync state lives in the
/// data layer, not here.
class ClipGroup {
  const ClipGroup({
    required this.id,
    required this.name,
    required this.color,
    required this.createdAt,
    required this.updatedAt,
    this.sortOrder = 0,
  });

  final String id;
  final String name;

  /// ARGB, e.g. `0xFF5B8DEF`.
  final int color;

  final DateTime createdAt;

  /// Bumped on every edit; what the sync uses to settle conflicts.
  final DateTime updatedAt;

  /// Position in the group list; groups are created at the end.
  final int sortOrder;

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

  /// A copy with the given fields replaced. The id and creation time never
  /// change.
  ClipGroup copyWith({
    String? name,
    int? color,
    int? sortOrder,
    DateTime? updatedAt,
  }) => ClipGroup(
    id: id,
    name: name ?? this.name,
    color: color ?? this.color,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    sortOrder: sortOrder ?? this.sortOrder,
  );

  @override
  bool operator ==(Object other) =>
      other is ClipGroup &&
      other.id == id &&
      other.name == name &&
      other.color == color &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.sortOrder == sortOrder;

  @override
  int get hashCode =>
      Object.hash(id, name, color, createdAt, updatedAt, sortOrder);

  @override
  String toString() => 'ClipGroup($id, $name, order: $sortOrder)';
}
