import '../entities/clip_item.dart';

/// The search box and the type chip of the clipboard tab, applied to clips.
class ClipFilter {
  const ClipFilter({this.query = '', this.type});

  /// Lets every clip through.
  static const ClipFilter none = ClipFilter();

  /// Matched against the content and the note, ignoring case and the
  /// surrounding blanks. Blank matches everything.
  final String query;

  /// Only clips of this type pass; null lets every type through.
  final ClipType? type;

  bool matches(ClipItem clip) {
    if (type != null && clip.type != type) return false;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return clip.content.toLowerCase().contains(q) ||
        (clip.note?.toLowerCase().contains(q) ?? false);
  }

  /// The clips of [clips] that pass, in the same order.
  Iterable<ClipItem> apply(Iterable<ClipItem> clips) => clips.where(matches);

  @override
  bool operator ==(Object other) =>
      other is ClipFilter && other.query == query && other.type == type;

  @override
  int get hashCode => Object.hash(query, type);
}
