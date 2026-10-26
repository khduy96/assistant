import '../../../../core/data/app_paths.dart';
import '../../../../core/data/json_file_store.dart';
import '../../../../core/domain/clock.dart';
import '../../../../core/sync/domain/sync_collection.dart';
import '../models/note_model.dart';

/// Reads and writes `notes.json` in the application support directory.
///
/// IO only: which notes to keep and when to queue a tombstone is the
/// repository's business.
class NoteLocalDataSource {
  /// The clock stands in for timestamps missing from old files. [path]
  /// replaces the default location; tests pass their own file.
  NoteLocalDataSource(
    this._clock, {
    String? path,
    AppPaths paths = const AppPaths(),
  }) : _file = JsonFileStore(fileName, path: path, paths: paths);

  static const String fileName = 'notes.json';

  final Clock _clock;
  final JsonFileStore _file;

  /// The saved notes and tombstones. A missing or corrupted file, including
  /// one with an entry that cannot be read as a note, reads as empty.
  Future<({List<NoteModel> items, List<SyncTombstone> deleted})> load() async {
    final saved = await _file.load();
    try {
      final now = _clock.now();
      return (
        items: [for (final e in saved.items) NoteModel.fromJson(e, now: now)],
        deleted: saved.deleted,
      );
    } catch (_) {
      return (items: <NoteModel>[], deleted: <SyncTombstone>[]);
    }
  }

  Future<void> save(List<NoteModel> notes, List<SyncTombstone> deleted) =>
      _file.save([for (final n in notes) n.toJson()], [...deleted]);
}
