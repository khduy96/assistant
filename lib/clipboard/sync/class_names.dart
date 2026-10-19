/// Names of the Back4App classes this app owns.
///
/// Lives on its own so the repository can queue deletes by class without
/// importing the sync service (which imports the repository).
class SyncClassNames {
  const SyncClassNames._();

  static const String clip = 'Clip';
  static const String group = 'ClipGroup';

  /// The reminder side's lists, synced through `SyncCollection`.
  static const String todo = 'TodoItem';
  static const String note = 'NoteItem';

  /// One object per space holding a change counter per class, so an idle
  /// sync costs a single read instead of a query per class.
  static const String meta = 'SyncMeta';
}
