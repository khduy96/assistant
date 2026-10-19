import 'dart:convert';
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
    this.monthRequests,
  });

  final SyncState state;
  final String? message;
  final DateTime? lastSyncAt;
  final int pushed;
  final int pulled;

  /// Back4App requests this device has made in the current calendar month.
  final int? monthRequests;

  bool get isRunning => state == SyncState.running;

  SyncStatus withMonthRequests(int? value) => SyncStatus(
        state: state,
        message: message,
        lastSyncAt: lastSyncAt,
        pushed: pushed,
        pulled: pulled,
        monthRequests: value,
      );
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
/// Only saved and pinned clips travel: temp clips expire after a day, and
/// pushing every copy only to delete it again was most of the request bill.
///
/// Requests are metered against the Back4App quota. Each push bumps a counter
/// per class on one [SyncClassNames.meta] object, and a pull reads that object
/// first: a class whose counter has not moved is skipped, so an idle cycle
/// costs one request instead of a query and a reconcile per class.
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
  static const String metaClass = SyncClassNames.meta;

  /// How often every class is pulled whatever the counters say. A safety net
  /// for a build that does not bump them yet, or a bump that never landed.
  static const Duration fullPullEvery = Duration(hours: 24);

  bool _running = false;

  /// Settings as of the start of the running cycle, kept current by [_put].
  Map<String, String> _settings = const {};

  /// `className/localId` of records whose create may have reached the server
  /// without the answer reaching us (timeout, crash before the objectId was
  /// stored). Only these are looked up before creating; everything else is
  /// created straight away, which saves a query per new record.
  Set<String> _inflight = {};

  /// Runs one full cycle: push local changes, then pull remote ones.
  ///
  /// [full] pulls every class even when its counter has not moved — what the
  /// "Đồng bộ ngay" button asks for.
  ///
  /// Returns the resulting status; never throws — failures come back as
  /// [SyncState.error] so the UI can show them without crashing a background
  /// timer.
  Future<SyncStatus> sync({bool full = false}) async {
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
    var requests = 0;
    final client = ParseClient(config, onRequest: () => requests++);
    SyncStatus status;
    try {
      _settings = {...await _repo.loadSettings()};
      _inflight = _decodeSet(_get(_inflightKey));

      final (pushed, touched) = await _push(client);
      await _bumpMeta(client, touched);
      final pulled = await _pull(client, full: full);
      final now = DateTime.now();
      await _put('sync_last_at', '${now.millisecondsSinceEpoch}');
      status = SyncStatus(
        state: SyncState.ok,
        lastSyncAt: now,
        pushed: pushed,
        pulled: pulled,
      );
    } on ParseException catch (error) {
      status = SyncStatus(state: SyncState.error, message: error.message);
    } on SocketException {
      status = const SyncStatus(
          state: SyncState.error, message: 'Không có kết nối mạng');
    } catch (error) {
      status = SyncStatus(state: SyncState.error, message: '$error');
    } finally {
      _running = false;
      client.close();
    }
    return status.withMonthRequests(await _meter(requests));
  }

  /// Whether anything here still waits to go out: edits, deletes, or a
  /// counter bump that did not land. Answered locally, without a request.
  Future<bool> hasLocalChanges() async {
    if ((await _repo.pendingDeletes()).isNotEmpty) return true;
    if ((await _repo.dirtyGroups()).isNotEmpty) return true;
    if ((await _repo.dirtyClips()).isNotEmpty) return true;
    for (final collection in collections) {
      if (collection.pendingDeletes().isNotEmpty) return true;
      if (collection.dirtyRecords().isNotEmpty) return true;
    }
    final settings = await _repo.loadSettings();
    return (settings[_bumpKey] ?? '').isNotEmpty;
  }

  // ---------------------------------------------------------------- meter

  static String monthKey(DateTime time) =>
      'sync_req_${time.year}-${time.month.toString().padLeft(2, '0')}';

  /// Requests counted so far this month on this device.
  Future<int> requestsThisMonth() async {
    final settings = await _repo.loadSettings();
    return int.tryParse(settings[monthKey(DateTime.now())] ?? '') ?? 0;
  }

  /// Adds [requests] to this month's tally and returns the new total.
  Future<int?> _meter(int requests) async {
    try {
      final key = monthKey(DateTime.now());
      final settings = await _repo.loadSettings();
      final total = (int.tryParse(settings[key] ?? '') ?? 0) + requests;
      if (requests > 0) await _repo.putSetting(key, '$total');
      return total;
    } catch (error) {
      debugPrint('Sync meter failed: $error');
      return null;
    }
  }

  // ------------------------------------------------------------------ push

  /// Returns how many changes went out and which classes they touched.
  Future<(int, Set<String>)> _push(ParseClient client) async {
    var count = 0;
    final touched = <String>{};

    // Deletions first: a row recreated below should not be wiped by a stale
    // delete queued for the same object.
    for (final (remoteId, className) in await _repo.pendingDeletes()) {
      await client.delete(className, remoteId);
      await _repo.clearPendingDelete(remoteId);
      touched.add(className);
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
      await _landed(groupClass, group.id);
      touched.add(groupClass);
      count++;
    }

    for (final item in await _repo.dirtyClips()) {
      final objectId = await _upsert(
        client,
        clipClass,
        localId: item.id,
        remoteId: item.remoteId,
        data: item.toParse(config.space),
      );
      await _repo.putClip(item.copyWith(remoteId: objectId, dirty: false));
      await _landed(clipClass, item.id);
      touched.add(clipClass);
      count++;
    }

    for (final collection in collections) {
      for (final tombstone in collection.pendingDeletes()) {
        await client.delete(collection.className, tombstone.remoteId);
        await collection.clearPendingDelete(tombstone.localId);
        touched.add(collection.className);
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
        await _landed(collection.className, record.localId);
        touched.add(collection.className);
        count++;
      }
    }

    return (count, touched);
  }

  /// Updates the object, or creates it.
  ///
  /// A record is looked up by `{space, localId}` before creating only when it
  /// may already be there: its stored object vanished, or an earlier create
  /// never confirmed (see [_inflight]). The caller clears the in-flight mark
  /// through [_landed] once the objectId is stored locally.
  Future<String> _upsert(
    ParseClient client,
    String className, {
    required String localId,
    required String? remoteId,
    required Map<String, Object?> data,
  }) async {
    var lookUp = _inflight.contains(_inflightId(className, localId));
    if (remoteId != null) {
      try {
        await client.update(className, remoteId, data);
        return remoteId;
      } on ParseException catch (error) {
        // 101 = object not found: it was deleted server-side, or this row was
        // pushed to a different space. Fall through and create it again.
        if (error.statusCode != 404 && error.code != 101) rethrow;
        lookUp = true;
      }
    }
    if (lookUp) {
      final existing = await client.findOne(className, where: {
        'space': config.space,
        'localId': localId,
      });
      final existingId = existing?['objectId'] as String?;
      if (existingId != null) {
        await client.update(className, existingId, data);
        return existingId;
      }
    }
    await _setInflight(className, localId, on: true);
    return client.create(className, data);
  }

  Future<void> _landed(String className, String localId) =>
      _setInflight(className, localId, on: false);

  static String _inflightId(String className, String localId) =>
      '$className/$localId';

  Future<void> _setInflight(String className, String localId,
      {required bool on}) async {
    final id = _inflightId(className, localId);
    final changed = on ? _inflight.add(id) : _inflight.remove(id);
    if (changed) await _put(_inflightKey, jsonEncode(_inflight.toList()));
  }

  // ------------------------------------------------------------------ meta

  String get _inflightKey => 'sync_inflight';
  String get _metaIdKey => 'sync_meta_id_${config.space}';
  String get _bumpKey => 'sync_meta_bump_${config.space}';
  String get _fullKey => 'sync_full_at_${config.space}';
  String _revKey(String className) => 'sync_rev_${config.space}_$className';
  static String _revField(String className) => 'rev_$className';

  List<String> get _classNames => [
        clipClass,
        groupClass,
        for (final collection in collections) collection.className,
      ];

  /// Tells the other devices which classes just changed.
  ///
  /// The set is saved before the request, so a bump that fails is retried on
  /// the next cycle instead of leaving the other devices unaware.
  Future<void> _bumpMeta(ParseClient client, Set<String> touched) async {
    final pending = {..._decodeSet(_get(_bumpKey)), ...touched};
    if (pending.isEmpty) return;
    await _put(_bumpKey, jsonEncode(pending.toList()));

    final metaId = _get(_metaIdKey) ??
        (await _findMeta(client))?['objectId'] as String?;
    if (metaId == null) {
      await _createMeta(client, bumped: pending);
    } else {
      Map<String, Object?> result;
      try {
        result = await client.update(metaClass, metaId, _increments(pending));
      } on ParseException catch (error) {
        if (error.statusCode != 404 && error.code != 101) rethrow;
        await _put(_metaIdKey, '');
        await _createMeta(client, bumped: pending);
        result = const {};
      }
      // Parse answers an Increment with the new value. One step past what this
      // device last saw means no one else wrote in between, so there is
      // nothing to pull back but our own push.
      for (final className in pending) {
        final seen = int.tryParse(_get(_revKey(className)) ?? '');
        final now = (result[_revField(className)] as num?)?.toInt();
        if (seen != null && now == seen + 1) {
          await _put(_revKey(className), '$now');
        }
      }
    }
    await _put(_bumpKey, '');
  }

  static Map<String, Object?> _increments(Set<String> classNames) => {
        for (final className in classNames)
          _revField(className): {'__op': 'Increment', 'amount': 1},
      };

  /// This space's counter object: the oldest one, should two devices have
  /// raced to create it.
  Future<Map<String, Object?>?> _findMeta(ParseClient client) async {
    final row = await client.findOne(
      metaClass,
      where: {'space': config.space},
      order: 'createdAt',
    );
    final id = row?['objectId'];
    if (id is String) await _put(_metaIdKey, id);
    return row;
  }

  Future<Map<String, Object?>> _createMeta(
    ParseClient client, {
    Set<String> bumped = const {},
  }) async {
    final createdId = await client.create(metaClass, {
      'space': config.space,
      for (final className in _classNames)
        _revField(className): bumped.contains(className) ? 1 : 0,
    });
    final row = await _findMeta(client);
    if (row == null) return {'objectId': createdId};
    // Lost the race: carry our bumps over to the object everyone reads.
    final winnerId = row['objectId'] as String;
    if (winnerId != createdId && bumped.isNotEmpty) {
      return {
        ...row,
        ...await client.update(metaClass, winnerId, _increments(bumped)),
      };
    }
    return row;
  }

  // ------------------------------------------------------------------ pull

  Future<int> _pull(ParseClient client, {required bool full}) async {
    final now = DateTime.now();
    final lastFull = int.tryParse(_get(_fullKey) ?? '');
    final fullDue = full ||
        lastFull == null ||
        now.difference(DateTime.fromMillisecondsSinceEpoch(lastFull)) >=
            fullPullEvery;

    final meta = await _findMeta(client) ?? await _createMeta(client);
    final revs = {
      for (final className in _classNames)
        className: (meta[_revField(className)] as num?)?.toInt() ?? 0,
    };
    // The counter is read before pulling, so a write landing mid-pull moves it
    // past what gets stored here and is picked up next cycle.
    bool stale(String className) =>
        fullDue || _get(_revKey(className)) != '${revs[className]}';

    var applied = 0;
    // Clips and groups share a cursor, so they are pulled as one.
    if (stale(clipClass) || stale(groupClass)) {
      applied += await _pullClipboard(client);
      await _put(_revKey(clipClass), '${revs[clipClass]}');
      await _put(_revKey(groupClass), '${revs[groupClass]}');
    }
    for (final collection in collections) {
      final className = collection.className;
      if (!stale(className)) continue;
      applied += await _pullCollection(client, collection);
      await _put(_revKey(className), '${revs[className]}');
    }

    if (fullDue) await _put(_fullKey, '${now.millisecondsSinceEpoch}');
    return applied;
  }

  Future<int> _pullClipboard(ParseClient client) async {
    final cursorKey = 'sync_cursor_${config.space}';
    final since = _get(cursorKey);
    final where = <String, Object?>{
      'space': config.space,
      if (since != null)
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

    if (newestIso != null) await _put(cursorKey, newestIso);
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
  ) async {
    final key = 'sync_cursor_${config.space}_${collection.className}';
    final since = _get(key);
    final rows = await client.queryAll(collection.className, where: {
      'space': config.space,
      if (since != null)
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
    if (newestIso != null) await _put(key, newestIso);
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
  /// query can never report it. So each pull also fetches the bare list of ids
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

  // -------------------------------------------------------------- settings

  /// A stored setting, with an empty value read as absent.
  String? _get(String key) {
    final value = _settings[key];
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> _put(String key, String value) async {
    _settings[key] = value;
    await _repo.putSetting(key, value);
  }

  static Set<String> _decodeSet(String? raw) {
    if (raw == null) return {};
    try {
      return {...(jsonDecode(raw) as List<dynamic>).cast<String>()};
    } on FormatException {
      return {};
    }
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
