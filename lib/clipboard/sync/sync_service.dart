import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../services/sync/sync_collection.dart';
import '../data/clip_repository.dart';
import '../models/clip_group.dart';
import '../models/clip_item.dart';
import 'class_names.dart';
import 'parse_client.dart';
import 'parse_config.dart';

enum SyncState { idle, running, ok, error, notConfigured }

class SyncStatus {
  const SyncStatus({
    this.state = SyncState.notConfigured,
    this.message,
    this.lastSyncAt,
    this.pushed = 0,
    this.pulled = 0,
  });

  final SyncState state;
  final String? message;
  final DateTime? lastSyncAt;
  final int pushed;
  final int pulled;

  bool get isRunning => state == SyncState.running;
}

/// Two-way sync between the local SQLite tables and two Back4App classes,
/// `Clip` and `ClipGroup`.
///
/// Conflicts resolve last-write-wins on the app's own `updatedAt`, not on the
/// server's, so a device with a slow connection still wins if its edit is newer.
///
/// Deleting removes the row here and the object there — there is no `deleted`
/// column on the server. Other devices notice through [_reconcileDeletes].
///
/// Attachments are deliberately NOT synced: Back4App blocks file uploads from
/// clients that are not signed in, and this app has no sign-in. A clip holding
/// a file stays on the device that created it.
class SyncService {
  SyncService({
    required ClipRepository repository,
    required this.config,
    this.collections = const [],
  }) : _repo = repository;

  final ClipRepository _repo;
  ParseConfig config;

  /// Lists outside the clipboard database that ride along on the same cycle:
  /// the todo list and the notes. They keep one status, one timer and one
  /// "Đồng bộ ngay" for the whole app.
  final List<SyncCollection> collections;

  static const String clipClass = SyncClassNames.clip;
  static const String groupClass = SyncClassNames.group;

  bool _running = false;

  /// Runs one full cycle: push local changes, then pull remote ones.
  ///
  /// Returns the resulting status; never throws — failures come back as
  /// [SyncState.error] so the UI can show them without crashing a background
  /// timer.
  Future<SyncStatus> sync() async {
    if (!config.isConfigured) {
      return const SyncStatus(
        state: SyncState.notConfigured,
        message: 'Chưa nhập App ID và Client Key của Back4App',
      );
    }
    if (_running) {
      return const SyncStatus(
          state: SyncState.running, message: 'Đang đồng bộ…');
    }

    _running = true;
    final client = ParseClient(config);
    try {
      final pushed = await _push(client);
      final pulled = await _pull(client);
      final now = DateTime.now();
      await _repo.putSetting('sync_last_at', '${now.millisecondsSinceEpoch}');
      return SyncStatus(
        state: SyncState.ok,
        lastSyncAt: now,
        pushed: pushed,
        pulled: pulled,
      );
    } on ParseException catch (error) {
      return SyncStatus(state: SyncState.error, message: error.message);
    } on SocketException {
      return const SyncStatus(
          state: SyncState.error, message: 'Không có kết nối mạng');
    } catch (error) {
      return SyncStatus(state: SyncState.error, message: '$error');
    } finally {
      _running = false;
      client.close();
    }
  }

  // ------------------------------------------------------------------ push

  Future<int> _push(ParseClient client) async {
    var count = 0;

    // Deletions first: a row recreated below should not be wiped by a stale
    // delete queued for the same object.
    for (final (remoteId, className) in await _repo.pendingDeletes()) {
      await client.delete(className, remoteId);
      await _repo.clearPendingDelete(remoteId);
      count++;
    }

    for (final group in await _repo.dirtyGroups()) {
      final objectId = await _upsert(
        client,
        groupClass,
        localId: group.id,
        remoteId: group.remoteId,
        data: group.toParse(config.space),
      );
      await _repo.putGroup(group.copyWith(remoteId: objectId, dirty: false));
      count++;
    }

    // Attachments stay on the device that made them (see class docs), so only
    // text clips are pushed.
    for (final item in await _repo.dirtyClips()) {
      final objectId = await _upsert(
        client,
        clipClass,
        localId: item.id,
        remoteId: item.remoteId,
        data: item.toParse(config.space),
      );
      await _repo.putClip(item.copyWith(remoteId: objectId, dirty: false));
      count++;
    }

    for (final collection in collections) {
      for (final tombstone in collection.pendingDeletes()) {
        await client.delete(collection.className, tombstone.remoteId);
        await collection.clearPendingDelete(tombstone.localId);
        count++;
      }
      for (final record in collection.dirtyRecords()) {
        final objectId = await _upsert(
          client,
          collection.className,
          localId: record.localId,
          remoteId: record.remoteId,
          data: {...record.fields, 'space': config.space},
        );
        await collection.markSynced(record.localId, objectId);
        count++;
      }
    }

    return count;
  }

  /// Creates the object, or updates it when this space already has that
  /// `localId` — which is also how a second device adopts an existing row.
  Future<String> _upsert(
    ParseClient client,
    String className, {
    required String localId,
    required String? remoteId,
    required Map<String, Object?> data,
  }) async {
    if (remoteId != null) {
      try {
        await client.update(className, remoteId, data);
        return remoteId;
      } on ParseException catch (error) {
        // 101 = object not found: it was deleted server-side, or this row was
        // pushed to a different space. Fall through and create it again.
        if (error.statusCode != 404 && error.code != 101) rethrow;
      }
    }
    final existing = await client.findOne(className, where: {
      'space': config.space,
      'localId': localId,
    });
    final existingId = existing?['objectId'] as String?;
    if (existingId != null) {
      await client.update(className, existingId, data);
      return existingId;
    }
    return client.create(className, data);
  }

  // ------------------------------------------------------------------ pull

  Future<int> _pull(ParseClient client) async {
    final settings = await _repo.loadSettings();
    final since = settings['sync_cursor_${config.space}'];
    final where = <String, Object?>{
      'space': config.space,
      if (since != null && since.isNotEmpty)
        'updatedAt': {
          r'$gt': {'__type': 'Date', 'iso': since},
        },
    };

    final groups = await client.queryAll(groupClass, where: where);
    final clips = await client.queryAll(clipClass, where: where);

    var applied = await _reconcileDeletes(client);
    String? newestIso = since;

    for (final json in groups) {
      if (await _applyGroup(json)) applied++;
      newestIso = _newer(newestIso, json['updatedAt'] as String?);
    }
    for (final json in clips) {
      if (await _applyClip(json)) applied++;
      newestIso = _newer(newestIso, json['updatedAt'] as String?);
    }

    if (newestIso != null) {
      await _repo.putSetting('sync_cursor_${config.space}', newestIso);
    }

    for (final collection in collections) {
      applied += await _pullCollection(client, collection, settings);
    }
    return applied;
  }

  /// Same cycle as the clipboard classes, for one outside list.
  ///
  /// Each collection keeps its own cursor: they were added after the clipboard
  /// one had already moved on, and a shared cursor would have hidden every
  /// todo and note written before that.
  Future<int> _pullCollection(
    ParseClient client,
    SyncCollection collection,
    Map<String, String> settings,
  ) async {
    final key = 'sync_cursor_${config.space}_${collection.className}';
    final since = settings[key];
    final rows = await client.queryAll(collection.className, where: {
      'space': config.space,
      if (since != null && since.isNotEmpty)
        'updatedAt': {
          r'$gt': {'__type': 'Date', 'iso': since},
        },
    });

    var applied = await _reconcileCollection(client, collection);
    String? newestIso = since;
    for (final json in rows) {
      if (await collection.applyRemote(json)) applied++;
      newestIso = _newer(newestIso, json['updatedAt'] as String?);
    }
    if (newestIso != null) await _repo.putSetting(key, newestIso);
    return applied;
  }

  /// Mirrors deletions made on other devices, the same way [_reconcileDeletes]
  /// does for clips: anything pushed from here but gone there is dropped.
  Future<int> _reconcileCollection(
    ParseClient client,
    SyncCollection collection,
  ) async {
    final remote = await client.queryAll(
      collection.className,
      where: {'space': config.space},
      keys: const ['localId'],
    );
    final liveIds = {
      for (final row in remote)
        if (row['localId'] is String) row['localId'] as String,
    };
    var removed = 0;
    for (final localId in collection.syncedIds()) {
      if (liveIds.contains(localId)) continue;
      await collection.removeLocalOnly(localId);
      removed++;
    }
    return removed;
  }

  /// Mirrors deletions made on other devices.
  ///
  /// Without tombstones a deleted object simply stops existing, and a cursor
  /// query can never report it. So each sync also fetches the bare list of ids
  /// in this space (`keys=localId`, no content) and drops any local row that
  /// had been synced but is no longer there.
  Future<int> _reconcileDeletes(ParseClient client) async {
    var removed = 0;
    for (final (className, table) in [
      (clipClass, 'clips'),
      (groupClass, 'groups'),
    ]) {
      final remote = await client.queryAll(
        className,
        where: {'space': config.space},
        keys: const ['localId'],
      );
      final liveIds = {
        for (final row in remote)
          if (row['localId'] is String) row['localId'] as String,
      };
      for (final localId in await _repo.syncedLocalIds(table)) {
        if (liveIds.contains(localId)) continue;
        await _repo.deleteLocalOnly(table, localId);
        removed++;
      }
    }
    return removed;
  }

  Future<bool> _applyClip(Map<String, Object?> json) async {
    final localId = json['localId'];
    if (localId is! String) return false;

    final existing = await _repo.clipById(localId);
    final incoming = ClipItem.fromParse(json, existing: existing);

    // Local edits that have not been pushed yet, and newer local state, win.
    if (existing != null) {
      if (existing.dirty) return false;
      if (existing.updatedAt.isAfter(incoming.updatedAt)) return false;
    }

    await _repo.putClip(incoming);
    return true;
  }

  Future<bool> _applyGroup(Map<String, Object?> json) async {
    final localId = json['localId'];
    if (localId is! String) return false;

    final existing = await _repo.groupById(localId);
    final incoming = ClipGroup.fromParse(json);
    if (existing != null) {
      if (existing.dirty) return false;
      if (existing.updatedAt.isAfter(incoming.updatedAt)) return false;
    }
    await _repo.putGroup(incoming);
    return true;
  }

  static String? _newer(String? current, String? candidate) {
    if (candidate == null) return current;
    if (current == null) return candidate;
    return candidate.compareTo(current) > 0 ? candidate : current;
  }


  @visibleForTesting
  static Map<String, Object?> debugWhereForSpace(String space) =>
      {'space': space};
}
