/// Where received files end up.
class SaveLocation {
  const SaveLocation({required this.directory, this.publicFolder});

  /// Folder received files are written to. On Android this is only a staging
  /// folder when [publicFolder] is set.
  final String directory;

  /// Shared folder the files are moved on to after writing, shown as e.g.
  /// `Download/Trợ lý` (Android 10 and later); null where files stay in
  /// [directory].
  final String? publicFolder;

  /// What to tell the user: the folder they will find the files in.
  String get label => publicFolder ?? directory;

  @override
  bool operator ==(Object other) =>
      other is SaveLocation &&
      other.directory == directory &&
      other.publicFolder == publicFolder;

  @override
  int get hashCode => Object.hash(directory, publicFolder);

  @override
  String toString() => 'SaveLocation($directory, public: $publicFolder)';
}
