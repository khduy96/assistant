import '../entities/clip_item.dart';
import 'clip_filter.dart';
import 'clip_ordering.dart';

/// The lists the clipboard tab shows, each cut from every clip through a
/// [ClipFilter] and returned as a new list in display order.
abstract final class ClipLists {
  /// Temp clips (neither saved nor pinned), newest first.
  static List<ClipItem> temp(
    Iterable<ClipItem> clips, [
    ClipFilter filter = ClipFilter.none,
  ]) => _sorted(clips, filter, (c) => c.isTemp, ClipOrdering.newestFirst);

  /// Saved clips, pinned first.
  static List<ClipItem> saved(
    Iterable<ClipItem> clips, [
    ClipFilter filter = ClipFilter.none,
  ]) => _sorted(clips, filter, (c) => c.isSaved, ClipOrdering.saved);

  /// Pinned clips.
  static List<ClipItem> pinned(
    Iterable<ClipItem> clips, [
    ClipFilter filter = ClipFilter.none,
  ]) => _sorted(clips, filter, (c) => c.isPinned, ClipOrdering.saved);

  /// Clips filed in [groupId], pinned first.
  static List<ClipItem> ofGroup(
    Iterable<ClipItem> clips,
    String groupId, [
    ClipFilter filter = ClipFilter.none,
  ]) => _sorted(clips, filter, (c) => c.groupId == groupId, ClipOrdering.saved);

  /// Saved clips in no group, pinned first.
  static List<ClipItem> ungroupedSaved(
    Iterable<ClipItem> clips, [
    ClipFilter filter = ClipFilter.none,
  ]) => _sorted(
    clips,
    filter,
    (c) => c.isSaved && c.groupId == null,
    ClipOrdering.saved,
  );

  static List<ClipItem> _sorted(
    Iterable<ClipItem> clips,
    ClipFilter filter,
    bool Function(ClipItem) section,
    int Function(ClipItem, ClipItem) order,
  ) => filter.apply(clips.where(section)).toList()..sort(order);
}
