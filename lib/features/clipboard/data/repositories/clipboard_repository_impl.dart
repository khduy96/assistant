import 'dart:async';

import '../../../../core/domain/clock.dart';
import '../../../../core/domain/failure.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/sync/data/class_names.dart';
import '../../domain/entities/clip_group.dart';
import '../../domain/entities/clip_item.dart';
import '../../domain/repositories/clipboard_repository.dart';
import '../datasources/clip_local_data_source.dart';
import '../mappers/clip_group_mapper.dart';
import '../mappers/clip_mapper.dart';
import '../models/clip_group_model.dart';
import '../models/clip_model.dart';

/// Keeps the clips and groups in SQLite, along with their sync state and the
/// server deletes still waiting to go out.
///
/// The user's edits come in through [ClipboardRepository]; the sync engine's
/// come in through `ClipSyncCollection` and `ClipGroupSyncCollection`, which
/// use the members below the "Sync side" mark. Only the user's edits fire
/// [localClipChanges] and [localGroupChanges]; only the engine's fire
/// [remoteChanges]. So applying a pull never schedules a push of its own.
class ClipboardRepositoryImpl implements ClipboardRepository {
  /// The clock stamps queued server deletes.
  ClipboardRepositoryImpl(this._source, this._clock);

  final ClipLocalDataSource _source;
  final Clock _clock;

  /// Server ids of clips removed by [deleteClips], by clip id, so
  /// [restoreClip] can link the clip to its server object again.
  final Map<String, String> _deletedRemoteIds = {};

  final _remoteChanges = StreamController<void>.broadcast();
  final _localClipChanges = StreamController<void>.broadcast();
  final _localGroupChanges = StreamController<void>.broadcast();

  @override
  Stream<void> get remoteChanges => _remoteChanges.stream;

  /// Fires after a change made on this device that leaves a clip for the
  /// server to hear about. A new temp clip or a copy count does not.
  Stream<void> get localClipChanges => _localClipChanges.stream;

  /// Fires after a group was created, edited or deleted on this device.
  Stream<void> get localGroupChanges => _localGroupChanges.stream;

  Future<void> dispose() async {
    await _remoteChanges.close();
    await _localClipChanges.close();
    await _localGroupChanges.close();
  }

  // ---------------------------------------------------------------- clips

  @override
  Future<Result<List<ClipItem>>> getClips() => _guard(
    'read clips',
    () async => [for (final m in await _source.clips()) ClipMapper.toEntity(m)],
  );

  @override
  Future<Result<ClipItem?>> findClipByContent(String content) =>
      _guard('read clips', () async {
        final model = await _source.clipByContent(content);
        return model == null ? null : ClipMapper.toEntity(model);
      });

  @override
  Future<Result<void>> saveClip(ClipItem clip, {bool share = true}) =>
      _guard('save clip', () async {
        await _source.upsertClip(ClipMapper.toModel(clip), keepRemoteId: true);
        if (share) _changedLocally(clips: true);
      });

  @override
  Future<Result<void>> recordCopy(ClipItem clip) => _guard(
    'save clip',
    () => _source.updateCopy(
      clip.id,
      copiedAt: clip.copiedAt,
      copyCount: clip.copyCount,
    ),
  );

  @override
  Future<Result<void>> detachFromServer(String id) =>
      _guard('save clip', () async {
        final remoteId = (await _source.clipById(id))?.remoteId;
        if (remoteId == null) return;
        await _source.queueDelete(remoteId, SyncClassNames.clip, _clock.now());
        await _source.clearClipRemoteId(id);
      });

  @override
  Future<Result<void>> deleteClips(Iterable<String> ids, {bool share = true}) =>
      _guard('delete clips', () async {
        final wanted = ids.toList();
        final now = _clock.now();
        for (final doomed in await _source.clipsByIds(wanted)) {
          final remoteId = doomed.remoteId;
          if (remoteId == null) continue;
          await _source.queueDelete(remoteId, SyncClassNames.clip, now);
          _deletedRemoteIds[doomed.id] = remoteId;
        }
        await _source.deleteClips(wanted);
        if (share) _changedLocally(clips: true);
      });

  @override
  Future<Result<void>> restoreClip(ClipItem clip) =>
      _guard('restore clip', () async {
        final remoteId = _deletedRemoteIds.remove(clip.id);
        // Without a remembered server id, a row still stored keeps its own.
        await _source.upsertClip(
          ClipMapper.toModel(clip, remoteId: remoteId),
          keepRemoteId: remoteId == null,
        );
        // If the delete never went out, cancel it instead of racing it.
        if (remoteId != null) await _source.cancelDelete(remoteId);
        _changedLocally(clips: true);
      });

  // --------------------------------------------------------------- groups

  @override
  Future<Result<List<ClipGroup>>> getGroups() => _guard(
    'read groups',
    () async => [
      for (final m in await _source.groups()) ClipGroupMapper.toEntity(m),
    ],
  );

  @override
  Future<Result<void>> saveGroup(ClipGroup group) =>
      _guard('save group', () async {
        await _source.upsertGroup(
          ClipGroupMapper.toModel(group),
          keepRemoteId: true,
        );
        _changedLocally(groups: true);
      });

  @override
  Future<Result<void>> deleteGroup(String id) => _guard(
    'delete group',
    () async {
      final stored = await _source.groupById(id);
      if (stored == null) return;
      await _source.deleteGroup(id);
      final remoteId = stored.remoteId;
      if (remoteId != null) {
        await _source.queueDelete(remoteId, SyncClassNames.group, _clock.now());
      }
      _changedLocally(groups: true);
    },
  );

  // Sync side. These throw on IO errors: the sync engine reports them.

  /// Clips holding changes the server has not seen, temp ones included.
  Future<List<ClipModel>> dirtyClips() => _source.dirtyClips();

  Future<List<ClipGroupModel>> dirtyGroups() => _source.dirtyGroups();

  Future<ClipModel?> clipModel(String id) => _source.clipById(id);

  Future<ClipGroupModel?> groupModel(String id) => _source.groupById(id);

  /// Ids of clips on the server that hold no unpushed change.
  Future<Set<String>> syncedClipIds() =>
      _source.syncedIds(ClipLocalDataSource.clipsTable);

  /// Ids of groups on the server that hold no unpushed change.
  Future<Set<String>> syncedGroupIds() =>
      _source.syncedIds(ClipLocalDataSource.groupsTable);

  /// Server ids of [className] waiting for a DELETE, oldest first.
  Future<List<String>> pendingDeletes(String className) =>
      _source.pendingDeletes(className);

  /// Forgets the queued delete of [remoteId] once the object is gone.
  Future<void> clearPendingDelete(String remoteId) =>
      _source.cancelDelete(remoteId);

  /// Records a successful push of the clip [id]: stores its `objectId` and
  /// clears the dirty flag, leaving every other column as it is now.
  Future<void> markClipSynced(String id, String remoteId) async {
    await _source.markSynced(ClipLocalDataSource.clipsTable, id, remoteId);
    _changedBySync();
  }

  /// Same as [markClipSynced], for the group [id].
  Future<void> markGroupSynced(String id, String remoteId) async {
    await _source.markSynced(ClipLocalDataSource.groupsTable, id, remoteId);
    _changedBySync();
  }

  /// Writes a pulled clip exactly as given.
  Future<void> putClipFromSync(ClipModel model) async {
    await _source.upsertClip(model);
    _changedBySync();
  }

  /// Writes a pulled group exactly as given, in place, so its clips stay in
  /// it.
  Future<void> putGroupFromSync(ClipGroupModel model) async {
    await _source.upsertGroup(model);
    _changedBySync();
  }

  /// Drops the clip [id] because the server no longer has it. No delete is
  /// queued: the object is already gone.
  Future<void> removeClipFromSync(String id) async {
    await _source.deleteClips([id]);
    _changedBySync();
  }

  /// Same as [removeClipFromSync], for the group [id].
  Future<void> removeGroupFromSync(String id) async {
    await _source.deleteGroup(id);
    _changedBySync();
  }

  /// Reports a change made on this device; [clips] and [groups] say which
  /// class now has something to push.
  void _changedLocally({bool clips = false, bool groups = false}) {
    if (clips && !_localClipChanges.isClosed) _localClipChanges.add(null);
    if (groups && !_localGroupChanges.isClosed) _localGroupChanges.add(null);
  }

  /// Reports a change the sync engine made. Never schedules a push.
  void _changedBySync() {
    if (!_remoteChanges.isClosed) _remoteChanges.add(null);
  }

  Future<Result<T>> _guard<T>(String action, Future<T> Function() body) async {
    try {
      return Ok(await body());
    } catch (e) {
      return Err(StorageFailure('Could not $action', cause: e));
    }
  }
}
