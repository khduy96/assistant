import '../entities/clip_item.dart';

/// How each user action changes a clip, as of [now]. Pure: storing the result
/// is up to the use case.
abstract final class ClipEdits {
  /// Kept in the saved list. A non-null [groupId] also files it there;
  /// null leaves its group as it is.
  static ClipItem saved(ClipItem clip, DateTime now, {String? groupId}) =>
      clip.copyWith(
        isSaved: true,
        groupId: groupId ?? clip.groupId,
        updatedAt: now,
      );

  /// Back to a temp clip: unpinned, out of its group, and its one-day
  /// countdown restarts at [now].
  static ClipItem unsaved(ClipItem clip, DateTime now) => clip.copyWith(
    isSaved: false,
    isPinned: false,
    groupId: null,
    createdAt: now,
    updatedAt: now,
  );

  /// Pinned or unpinned. Pinning a temp clip also saves it, so it survives
  /// the purge; unpinning leaves it saved.
  static ClipItem pinned(ClipItem clip, bool pin, DateTime now) =>
      clip.copyWith(
        isPinned: pin,
        isSaved: pin ? true : clip.isSaved,
        updatedAt: now,
      );

  /// Filed into [groupId], or taken out of any group when it is null. Filing
  /// a temp clip also saves it; taking it out leaves it saved.
  static ClipItem grouped(ClipItem clip, String? groupId, DateTime now) =>
      clip.copyWith(
        groupId: groupId,
        isSaved: groupId != null ? true : clip.isSaved,
        updatedAt: now,
      );

  /// Content replaced by [content] (trimmed, type detected again); [note]
  /// replaces the note when given.
  static ClipItem edited(
    ClipItem clip,
    String content,
    DateTime now, {
    String? note,
  }) => clip.copyWith(
    content: content.trim(),
    type: ClipItem.detectType(content),
    note: note ?? clip.note,
    updatedAt: now,
  );

  /// Copied by the user once more.
  static ClipItem copied(ClipItem clip, DateTime now) =>
      clip.copyWith(copiedAt: now, copyCount: clip.copyCount + 1);

  /// Seen on the system clipboard again: moves to the top of its list. A temp
  /// clip's countdown restarts; a saved clip keeps its creation time.
  static ClipItem recaptured(ClipItem clip, DateTime now) => clip.copyWith(
    createdAt: clip.isTemp ? now : clip.createdAt,
    updatedAt: now,
    copiedAt: now,
  );
}
