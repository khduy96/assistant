import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../clipboard/sync/class_names.dart';
import '../models/note.dart';
import 'note_storage.dart';
import 'sync/sync_collection.dart';

/// Holds the notes and keeps them on disk.
///
/// Unlike [ReminderStore] there is no ticker here: a note has no schedule, so
/// the list only changes when the user changes it.
class NoteStore extends ChangeNotifier {
  NoteStore({NoteStorage? storage}) : _storage = storage ?? NoteStorage();

  final NoteStorage _storage;
  final _uuid = const Uuid();
  final List<Note> _notes = [];

  /// Notes deleted here whose Back4App object is still waiting to be removed.
  final List<SyncTombstone> _deleted = [];

  List<Note> get notes => List.unmodifiable(_notes);

  int get count => _notes.length;

  /// The note list as the sync engine sees it.
  late final SyncCollection syncCollection = _NoteSyncCollection(this);

  Future<void> init() async {
    final saved = await _storage.load();
    _notes.addAll(saved.items);
    _deleted.addAll(saved.deleted);
    _sort();
    notifyListeners();
  }

  String newId() => _uuid.v4();

  /// Notes matching [query], pinned ones first. An empty query returns all.
  List<Note> search(String query) =>
      _notes.where((n) => n.matches(query)).toList();

  /// Adds a note, or replaces the one with the same id. Empty notes are
  /// dropped so backing out of the editor leaves nothing behind.
  Future<void> upsert(Note note) async {
    if (note.isEmpty) {
      await remove(note.id);
      return;
    }
    note.touch();
    final i = _notes.indexWhere((n) => n.id == note.id);
    if (i == -1) {
      _notes.add(note);
    } else {
      _notes[i] = note;
    }
    _sort();
    await _persist();
  }

  Future<void> setPinned(Note note, bool pinned) async {
    note.pinned = pinned;
    note.touch();
    _sort();
    await _persist();
  }

  Future<void> remove(String id) async {
    final gone = _notes.where((n) => n.id == id).firstOrNull;
    if (gone == null) return;
    // Never pushed: there is nothing on the server to delete.
    final remoteId = gone.remoteId;
    if (remoteId != null) {
      _deleted.add(SyncTombstone(localId: gone.id, remoteId: remoteId));
    }
    _notes.remove(gone);
    await _persist();
  }

  /// Pinned first, then most recently edited.
  void _sort() {
    _notes.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
  }

  Future<void> _persist() async {
    await _storage.save(_notes, _deleted);
    notifyListeners();
  }
}

/// Mirrors the notes to the `NoteItem` class on Back4App.
class _NoteSyncCollection implements SyncCollection {
  _NoteSyncCollection(this._store);

  final NoteStore _store;

  @override
  String get className => SyncClassNames.note;

  @override
  List<SyncRecord> dirtyRecords() => [
        for (final note in _store._notes)
          if (note.dirty)
            SyncRecord(
              localId: note.id,
              remoteId: note.remoteId,
              fields: note.toParse(),
            ),
      ];

  @override
  Set<String> syncedIds() => {
        for (final note in _store._notes)
          if (note.remoteId != null) note.id,
      };

  @override
  List<({String localId, String remoteId})> pendingDeletes() => [
        for (final tombstone in _store._deleted)
          (localId: tombstone.localId, remoteId: tombstone.remoteId),
      ];

  @override
  Future<void> clearPendingDelete(String localId) async {
    _store._deleted.removeWhere((t) => t.localId == localId);
    await _store._persist();
  }

  @override
  Future<void> markSynced(String localId, String remoteId) async {
    final note = _store._notes.where((n) => n.id == localId).firstOrNull;
    if (note == null) return;
    note.remoteId = remoteId;
    note.dirty = false;
    await _store._persist();
  }

  @override
  Future<bool> applyRemote(Map<String, Object?> json) async {
    if (json['localId'] is! String) return false;
    final incoming = Note.fromParse(json);
    final existing =
        _store._notes.where((n) => n.id == incoming.id).firstOrNull;

    // Local edits that have not been pushed yet, and newer local state, win.
    if (existing != null) {
      if (existing.dirty) return false;
      if (existing.updatedAt.isAfter(incoming.updatedAt)) return false;
      _store._notes.remove(existing);
    } else if (_store._deleted.any((t) => t.localId == incoming.id)) {
      // Deleted here, not yet on the server: the push will remove it.
      return false;
    }

    _store._notes.add(incoming);
    _store._sort();
    await _store._persist();
    return true;
  }

  @override
  Future<void> removeLocalOnly(String localId) async {
    _store._notes.removeWhere((n) => n.id == localId);
    await _store._persist();
  }
}
