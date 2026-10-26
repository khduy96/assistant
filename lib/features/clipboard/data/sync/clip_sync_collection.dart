import '../../../../core/domain/clock.dart';
import '../../../../core/sync/data/class_names.dart';
import '../../../../core/sync/domain/sync_collection.dart';
import '../models/clip_model.dart';
import '../repositories/clipboard_repository_impl.dart';

/// Mirrors the saved and pinned clips to the `Clip` class on Back4App.
///
/// Only saved and pinned clips travel: temp clips expire after a day, and
/// pushing every copy only to delete it again was most of the request bill.
/// Pulled clips keep this device's `copiedAt`.
///
/// Registered after `ClipGroupSyncCollection` in one shared channel, so a
/// pulled clip finds its group already there.
class ClipSyncCollection implements SyncCollection {
  /// The clock stands in for timestamps missing from a server object.
  ClipSyncCollection(this._repo, this._clock);

  final ClipboardRepositoryImpl _repo;
  final Clock _clock;

  @override
  String get className => SyncClassNames.clip;

  @override
  Stream<void> get localChanges => _repo.localClipChanges;

  @override
  Future<List<SyncRecord>> dirtyRecords() async => [
    for (final clip in await _repo.dirtyClips())
      if (!clip.isTemp)
        SyncRecord(
          localId: clip.id,
          remoteId: clip.remoteId,
          fields: clip.toParse(),
        ),
  ];

  /// Clips with unpushed edits do not count: a pull must not drop them.
  @override
  Future<Set<String>> syncedIds() => _repo.syncedClipIds();

  @override
  Future<List<String>> pendingDeletes() => _repo.pendingDeletes(className);

  @override
  Future<void> clearPendingDelete(String remoteId) =>
      _repo.clearPendingDelete(remoteId);

  @override
  Future<void> markSynced(String localId, String remoteId) =>
      _repo.markClipSynced(localId, remoteId);

  @override
  Future<bool> applyRemote(Map<String, Object?> json) async {
    final localId = json['localId'];
    if (localId is! String) return false;

    final existing = await _repo.clipModel(localId);
    final incoming = ClipModel.fromParse(
      json,
      copiedAt: existing?.copiedAt,
      now: _clock.now(),
    );

    // Local edits that have not been pushed yet, and newer local state, win.
    if (existing != null) {
      if (existing.dirty) return false;
      if (existing.updatedAt.isAfter(incoming.updatedAt)) return false;
    }

    await _repo.putClipFromSync(incoming);
    return true;
  }

  @override
  Future<void> removeLocalOnly(String localId) =>
      _repo.removeClipFromSync(localId);
}
