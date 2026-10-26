import '../../../../core/data/app_paths.dart';
import '../../../../core/data/json_file_store.dart';
import '../../../../core/domain/clock.dart';
import '../models/reminder_model.dart';

/// Reads and writes `reminders.json` in the application support directory:
/// a bare list of reminders, with no tombstones since reminders are not
/// synced.
class ReminderLocalDataSource {
  /// The clock stands in for a `createdAt` missing from old files. [path]
  /// replaces the default location; tests pass their own file.
  ReminderLocalDataSource(
    this._clock, {
    String? path,
    AppPaths paths = const AppPaths(),
  }) : _file = JsonFileStore(fileName, path: path, paths: paths);

  static const String fileName = 'reminders.json';

  final Clock _clock;
  final JsonFileStore _file;

  /// The saved reminders. A missing or corrupted file, including one with an
  /// entry that cannot be read as a reminder, reads as empty.
  Future<List<ReminderModel>> load() async {
    final saved = await _file.loadList();
    try {
      final now = _clock.now();
      return [for (final e in saved) ReminderModel.fromJson(e, now: now)];
    } catch (_) {
      return <ReminderModel>[];
    }
  }

  Future<void> save(List<ReminderModel> reminders) =>
      _file.saveList([for (final r in reminders) r.toJson()]);
}
