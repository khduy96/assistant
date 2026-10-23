import '../../../../core/domain/clock.dart';
import '../../../../core/sync/data/class_names.dart';
import '../../../../core/sync/domain/sync_collection.dart';
import '../models/note_model.dart';
import '../repositories/note_repository_impl.dart';

/// Mirrors the notes to the `NoteItem` class on Back4App.
///
/// Every member waits for the repository to load `notes.json` first, so a
/// sync that starts early still sees the notes. Nothing done here fires the
/// repository's `localChanges`: a change a sync applied must not schedule
/// another push.
class NoteSyncCollection implements SyncCollection {
  /// The clock stands in for timestamps missing from a server object.
  NoteSyncCollection(this._repo, this._clock);

  final NoteRepositoryImpl _repo;
  final Clock _clock;

  @override
  String get className => SyncClassNames.note;

  /// Fires after the user changes a note on this device.
  @override
  Stream<void> get localChanges => _repo.localChanges;

  @override
  Future<List<SyncRecord>> dirtyRecords() async {
    await _repo.ensureLoaded();
    return [
      for (final note in _repo.models)
        if (note.dirty)
          SyncRecord(
            localId: note.id,
            remoteId: note.remoteId,
            fields: note.toParse(),
          ),
    ];
  }

  @override
  Future<Set<String>> syncedIds() async {
    await _repo.ensureLoaded();
    return {
      for (final note in _repo.models)
        if (note.remoteId != null) note.id,
    };
  }

  @override
  Future<List<String>> pendingDeletes() async {
    await _repo.ensureLoaded();
    return [for (final tombstone in _repo.tombstones) tombstone.remoteId];
  }

  @override
  Future<void> clearPendingDelete(String remoteId) async {
    await _repo.ensureLoaded();
    await _repo.clearTombstone(remoteId);
  }

  @override
  Future<void> markSynced(String localId, String remoteId) async {
    await _repo.ensureLoaded();
    final note = _find(localId);
    if (note == null) return;
    await _repo.putFromSync(note.copyWith(remoteId: remoteId, dirty: false));
  }

  @override
  Future<bool> applyRemote(Map<String, Object?> json) async {
    if (json['localId'] is! String) return false;
    await _repo.ensureLoaded();
    final incoming = NoteModel.fromParse(json, now: _clock.now());
    final existing = _find(incoming.id);

    // Local edits that have not been pushed yet, and newer local state, win.
    if (existing != null) {
      if (existing.dirty) return false;
      if (existing.updatedAt.isAfter(incoming.updatedAt)) return false;
    } else if (_repo.tombstones.any((t) => t.localId == incoming.id)) {
      // Deleted here, not yet on the server: the push will remove it.
      return false;
    }

    await _repo.putFromSync(incoming);
    return true;
  }

  @override
  Future<void> removeLocalOnly(String localId) async {
    await _repo.ensureLoaded();
    await _repo.removeFromSync(localId);
  }

  NoteModel? _find(String id) =>
      _repo.models.where((n) => n.id == id).firstOrNull;
}
