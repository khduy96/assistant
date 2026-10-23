import '../entities/clip_group.dart';
import '../entities/clip_item.dart';

/// The orders clips and groups are listed in.
abstract final class ClipOrdering {
  /// Most recently captured or created first: the temp list, and the order
  /// the clipboard keeps its clips in.
  static int newestFirst(ClipItem a, ClipItem b) =>
      b.createdAt.compareTo(a.createdAt);

  /// Oldest first: the order a multi-copy joins its clips in.
  static int oldestFirst(ClipItem a, ClipItem b) =>
      a.createdAt.compareTo(b.createdAt);

  /// Saved, pinned and group lists: pinned clips first, then the most
  /// recently edited.
  static int saved(ClipItem a, ClipItem b) {
    if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
    return b.updatedAt.compareTo(a.updatedAt);
  }

  /// Groups by their position, then by name.
  static int groups(ClipGroup a, ClipGroup b) {
    final byOrder = a.sortOrder.compareTo(b.sortOrder);
    return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
  }
}
