import '../../../../core/data/app_paths.dart';
import '../../../../core/data/json_file_store.dart';
import '../../../../core/domain/clock.dart';
import '../../../../core/sync/domain/sync_collection.dart';
import '../models/todo_model.dart';

/// Reads and writes `todos.json` in the application support directory.
///
/// IO only: which items to keep and when to queue a tombstone is the
/// repository's business.
class TodoLocalDataSource {
  /// The clock stands in for timestamps missing from old files. [path]
  /// replaces the default location; tests pass their own file.
  TodoLocalDataSource(
    this._clock, {
    String? path,
    AppPaths paths = const AppPaths(),
  }) : _file = JsonFileStore(fileName, path: path, paths: paths);

  static const String fileName = 'todos.json';

  final Clock _clock;
  final JsonFileStore _file;

  /// The saved items and tombstones. A missing or corrupted file, including
  /// one with an entry that cannot be read as a todo, reads as empty.
  Future<({List<TodoModel> items, List<SyncTombstone> deleted})> load() async {
    final saved = await _file.load();
    try {
      final now = _clock.now();
      return (
        items: [for (final e in saved.items) TodoModel.fromJson(e, now: now)],
        deleted: saved.deleted,
      );
    } catch (_) {
      return (items: <TodoModel>[], deleted: <SyncTombstone>[]);
    }
  }

  Future<void> save(List<TodoModel> todos, List<SyncTombstone> deleted) =>
      _file.save([for (final t in todos) t.toJson()], [...deleted]);
}
