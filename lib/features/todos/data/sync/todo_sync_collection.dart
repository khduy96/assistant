import '../../../../core/domain/clock.dart';
import '../../../../core/sync/data/class_names.dart';
import '../../../../core/sync/domain/sync_collection.dart';
import '../models/todo_model.dart';
import '../repositories/todo_repository_impl.dart';

/// Mirrors the todo list to the `TodoItem` class on Back4App.
///
/// Every member waits for the repository to load `todos.json` first, so a
/// sync that starts early still sees the todos. Nothing done here fires the
/// repository's `localChanges`: a change a sync applied must not schedule
/// another push.
class TodoSyncCollection implements SyncCollection {
  /// The clock stands in for timestamps missing from a server object.
  TodoSyncCollection(this._repo, this._clock);

  final TodoRepositoryImpl _repo;
  final Clock _clock;

  @override
  String get className => SyncClassNames.todo;

  /// Fires after the user changes a todo on this device.
  @override
  Stream<void> get localChanges => _repo.localChanges;

  @override
  Future<List<SyncRecord>> dirtyRecords() async {
    await _repo.ensureLoaded();
    return [
      for (final todo in _repo.models)
        if (todo.dirty)
          SyncRecord(
            localId: todo.id,
            remoteId: todo.remoteId,
            fields: todo.toParse(),
          ),
    ];
  }

  @override
  Future<Set<String>> syncedIds() async {
    await _repo.ensureLoaded();
    return {
      for (final todo in _repo.models)
        if (todo.remoteId != null) todo.id,
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
    final todo = _find(localId);
    if (todo == null) return;
    await _repo.putFromSync(todo.copyWith(remoteId: remoteId, dirty: false));
  }

  @override
  Future<bool> applyRemote(Map<String, Object?> json) async {
    if (json['localId'] is! String) return false;
    await _repo.ensureLoaded();
    final incoming = TodoModel.fromParse(json, now: _clock.now());
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

  TodoModel? _find(String id) =>
      _repo.models.where((t) => t.id == id).firstOrNull;
}
