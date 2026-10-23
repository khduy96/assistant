/// A file to send, as a source of bytes. Kept apart from where the file comes
/// from, so a file on disk (desktop) and a content-URI stream (Android) are
/// sent the same way.
class OutgoingFile {
  const OutgoingFile({
    required this.name,
    required this.size,
    required this.open,
  });

  final String name;

  /// Size in bytes; null when the file picker could not tell.
  final int? size;

  /// Opens a fresh stream of the file's bytes.
  final Stream<List<int>> Function() open;

  @override
  String toString() => 'OutgoingFile($name, ${size ?? '?'} B)';
}
