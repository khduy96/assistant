import 'dart:convert';
import 'dart:io';

import '../sync/domain/sync_collection.dart';
import 'app_paths.dart';

/// What a [JsonFileStore] holds: the raw item objects, and the tombstones of
/// items deleted here whose server object is still waiting to be removed.
typedef JsonFileContents = ({
  List<Map<String, dynamic>> items,
  List<SyncTombstone> deleted,
});

/// One JSON file of synced items plus their tombstones, such as `notes.json`.
///
/// The file holds the tombstones as well as the items: a deleted item has to
/// be remembered until its object on Back4App is gone, or the other devices
/// would simply hand it back on the next sync. This class only does the IO
/// and the envelope; turning each item map into a model is the caller's job.
///
/// Files that are not synced, such as `reminders.json`, are a bare list of
/// items with no envelope; [loadList] and [saveList] read and write those.
class JsonFileStore {
  /// A file called [fileName] in the application support directory, or the
  /// file at [path] when given (tests use that).
  JsonFileStore(this.fileName, {String? path, this.paths = const AppPaths()})
    : _file = path == null ? null : File(path);

  final String fileName;
  final AppPaths paths;
  File? _file;

  /// The last write in flight. Writes run one after the other, so two quick
  /// saves can never interleave and leave a half-written file behind.
  Future<void> _writing = Future<void>.value();

  Future<File> _target() async {
    final cached = _file;
    if (cached != null) return cached;
    return _file = File(await paths.supportFile(fileName));
  }

  /// Reads the file. A missing or corrupted file reads as empty, so a broken
  /// file never blocks the app.
  Future<JsonFileContents> load() async {
    final file = await _target();
    if (!await file.exists()) return _empty();
    try {
      final decoded = jsonDecode(await file.readAsString());
      // Files written before sync existed are a bare list of items.
      final rawItems = decoded is List ? decoded : (decoded as Map)['items'];
      final rawDeleted = decoded is Map ? decoded['deleted'] as List? : null;
      return (
        items: [for (final e in rawItems as List) e as Map<String, dynamic>],
        deleted: [
          for (final e in rawDeleted ?? const [])
            ?SyncTombstone.fromJson((e as Map).cast<String, Object?>()),
        ],
      );
    } catch (_) {
      // Corrupted file: start clean rather than blocking the app.
      return _empty();
    }
  }

  /// Writes [items] and [deleted] as `{items, deleted}`, indented by two
  /// spaces. The text is built right away, so later changes to the lists do
  /// not leak into this write.
  Future<void> save(
    List<Map<String, Object?>> items,
    List<SyncTombstone> deleted,
  ) {
    final text = const JsonEncoder.withIndent('  ').convert({
      'items': items,
      'deleted': deleted.map((t) => t.toJson()).toList(),
    });
    return _write(text);
  }

  /// Reads a file written by [saveList]. A missing or corrupted file, or one
  /// that is not a list of objects, reads as empty.
  Future<List<Map<String, dynamic>>> loadList() async {
    final file = await _target();
    if (!await file.exists()) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(await file.readAsString()) as List;
      return [for (final e in decoded) e as Map<String, dynamic>];
    } catch (_) {
      // Corrupted file: start clean rather than blocking the app.
      return <Map<String, dynamic>>[];
    }
  }

  /// Writes [items] as a bare list, indented by two spaces. Like [save], the
  /// text is built right away and waits for the write before it.
  Future<void> saveList(List<Map<String, Object?>> items) =>
      _write(const JsonEncoder.withIndent('  ').convert(items));

  Future<void> _write(String text) {
    final write = _writing.then((_) async {
      final file = await _target();
      await file.writeAsString(text);
    });
    // A failed write is reported to its caller; the next one still runs.
    _writing = write.then((_) {}, onError: (_) {});
    return write;
  }

  static JsonFileContents _empty() =>
      (items: <Map<String, dynamic>>[], deleted: <SyncTombstone>[]);
}
