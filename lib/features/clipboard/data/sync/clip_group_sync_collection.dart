import '../../../../core/domain/clock.dart';
import '../../../../core/sync/data/class_names.dart';
import '../../../../core/sync/domain/sync_collection.dart';
import '../models/clip_group_model.dart';
import '../repositories/clipboard_repository_impl.dart';

/// Mirrors the clip groups to the `ClipGroup` class on Back4App.
///
/// Registered before `ClipSyncCollection` in one shared channel:
/// `clips.group_id` is a foreign key to `groups`, so a group has to land
/// before the clips that point at it.
class ClipGroupSyncCollection implements SyncCollection {
  /// The clock stands in for timestamps missing from a server object.
  ClipGroupSyncCollection(this._repo, this._clock);

  final ClipboardRepositoryImpl _repo;
  final Clock _clock;

  @override
  String get className => SyncClassNames.group;

  @override
  Stream<void> get localChanges => _repo.localGroupChanges;

  @override
  Future<List<SyncRecord>> dirtyRecords() async => [
    for (final group in await _repo.dirtyGroups())
      SyncRecord(
        localId: group.id,
        remoteId: group.remoteId,
        fields: group.toParse(),
      ),
  ];

  /// Groups with unpushed edits do not count: a pull must not drop them.
  @override
  Future<Set<String>> syncedIds() => _repo.syncedGroupIds();

  @override
  Future<List<String>> pendingDeletes() => _repo.pendingDeletes(className);

  @override
  Future<void> clearPendingDelete(String remoteId) =>
      _repo.clearPendingDelete(remoteId);

  @override
  Future<void> markSynced(String localId, String remoteId) =>
      _repo.markGroupSynced(localId, remoteId);

  @override
  Future<bool> applyRemote(Map<String, Object?> json) async {
    final localId = json['localId'];
    if (localId is! String) return false;

    final existing = await _repo.groupModel(localId);
    final incoming = ClipGroupModel.fromParse(json, now: _clock.now());

    // Local edits that have not been pushed yet, and newer local state, win.
    if (existing != null) {
      if (existing.dirty) return false;
      if (existing.updatedAt.isAfter(incoming.updatedAt)) return false;
    }

    await _repo.putGroupFromSync(incoming);
    return true;
  }

  @override
  Future<void> removeLocalOnly(String localId) =>
      _repo.removeGroupFromSync(localId);
}
