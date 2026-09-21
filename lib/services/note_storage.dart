import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/note.dart';
import 'sync/sync_collection.dart';

/// Persists notes to their own JSON file next to the reminders.
///
/// The file holds the tombstones as well as the notes: a deleted note has to
/// be remembered until its object on Back4App is gone, or the other devices
/// would simply hand it back on the next sync.
class NoteStorage {
  NoteStorage({String? path}) : _file = path == null ? null : File(path);

  File? _file;

  Future<File> _target() async {
    final cached = _file;
    if (cached != null) return cached;
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return _file = File('${dir.path}${Platform.pathSeparator}notes.json');
  }

  Future<({List<Note> items, List<SyncTombstone> deleted})> load() async {
    final file = await _target();
    if (!await file.exists()) {
      return (items: <Note>[], deleted: <SyncTombstone>[]);
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      // Files written before sync existed are a bare list of notes.
      final rawItems = decoded is List ? decoded : (decoded as Map)['items'];
      final rawDeleted = decoded is Map ? decoded['deleted'] as List? : null;
      return (
        items: [
          for (final e in rawItems as List)
            Note.fromJson(e as Map<String, dynamic>),
        ],
        deleted: [
          for (final e in rawDeleted ?? const [])
            ?SyncTombstone.fromJson((e as Map).cast<String, Object?>()),
        ],
      );
    } catch (_) {
      // Corrupted file: start clean rather than blocking the app.
      return (items: <Note>[], deleted: <SyncTombstone>[]);
    }
  }

  Future<void> save(List<Note> notes, List<SyncTombstone> deleted) async {
    final file = await _target();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'items': notes.map((n) => n.toJson()).toList(),
        'deleted': deleted.map((t) => t.toJson()).toList(),
      }),
    );
  }
}
