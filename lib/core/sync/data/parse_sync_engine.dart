import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/clock.dart';
import '../domain/entities/sync_budget.dart';
import '../domain/entities/sync_settings.dart';
import '../domain/entities/sync_status.dart';
import '../domain/sync_channel.dart';
import '../domain/sync_collection.dart';
import '../domain/sync_engine.dart';
import '../domain/sync_state_store.dart';
import 'class_names.dart';
import 'parse_client.dart';
import 'parse_config.dart';

/// Two-way sync between the app's [SyncCollection]s and Back4App.
///
/// Conflicts resolve last-write-wins on the app's own `updatedAt`, not on the
/// server's, so a device with a slow connection still wins if its edit is
/// newer. Each collection applies that rule itself in `applyRemote`.
///
/// Deleting removes the row here and the object there — there is no `deleted`
/// column on the server. Other devices notice through [_reconcile].
///
/// Requests are metered against this device's share of the user's monthly
/// request [budget]. Each push bumps a counter per class on one
/// [SyncClassNames.meta] object, and a pull reads that object first: a
/// channel whose counters have not moved is skipped, so an idle cycle costs
/// one request instead of a query and a reconcile per class.
///
/// The engine's own state lives in [SyncStateStore] under keys that devices
/// already in use have on disk; they must not change.
class ParseSyncEngine implements SyncEngine {
  ParseSyncEngine({
    required this.config,
    required this._state,
    required List<SyncChannel> channels,
    required this._clock,
    this.budget = SyncBudget.configured,
    this._httpClientFactory,
    this.onePassMaxRows = 500,
  }) : assert(channels.where((c) => c.shared).length <= 1),
       _channels = List.unmodifiable(channels);

  final ParseConfig config;
  final SyncStateStore _state;
  final List<SyncChannel> _channels;
  final Clock _clock;

  /// The monthly request budget. An automatic cycle stops once this device
  /// has spent its share, and the budget level sets how often a full pull is
  /// due (a safety net for a build that does not bump the counters, or a
  /// bump that never landed).
  final SyncBudget budget;

  /// Makes the HTTP client of each cycle; null uses a plain one.
  final http.Client Function()? _httpClientFactory;

  /// A collection with fewer synced rows than this is pulled in one pass:
  /// one query for the whole class, instead of a cursor query plus the list
  /// of ids that shows what was deleted. 0 always takes the two queries.
  final int onePassMaxRows;

  static const String metaClass = SyncClassNames.meta;

  /// Why an automatic cycle did not run, or stopped short.
  static const String budgetSpentMessage =
      'Máy này đã dùng hết ngân sách request tháng này; sync tự động tạm dừng '
      'tới tháng sau';

  bool _running = false;

  /// Requests sent by the running cycle, against what it may send.
  _CycleMeter _cycle = _CycleMeter();

  /// Settings as of the start of the running cycle, kept current by [_put].
  Map<String, String> _settings = const {};

  /// `className/localId` of records whose create may have reached the server
  /// without the answer reaching us (timeout, crash before the objectId was
  /// stored). Only these are looked up before creating; everything else is
  /// created straight away, which saves a query per new record.
  Set<String> _inflight = {};

  /// Every collection, in push order.
  Iterable<SyncCollection> get _collections =>
      _channels.expand((channel) => channel.collections);

  @override
  SyncSettings get settings => SyncSettings(
    isConfigured: config.isConfigured,
    autoSync: config.autoSync,
    space: config.space,
  );

  @override
  late final Stream<void> localChanges = _mergeLocalChanges();

  /// One stream over every collection's local changes, listening to them
  /// only while someone listens to it.
  Stream<void> _mergeLocalChanges() {
    final subscriptions = <StreamSubscription<void>>[];
    late final StreamController<void> merged;
    merged = StreamController<void>.broadcast(
      onListen: () {
        for (final collection in _collections) {
          subscriptions.add(collection.localChanges.listen(merged.add));
        }
      },
      onCancel: () async {
        final active = [...subscriptions];
        subscriptions.clear();
        for (final subscription in active) {
          await subscription.cancel();
        }
      },
    );
    return merged.stream;
  }

  /// Runs one full cycle: push local changes, then pull remote ones.
  ///
  /// [full] pulls every class even when its counter has not moved — what the
  /// "Đồng bộ ngay" button asks for.
  ///
  /// [auto] keeps the cycle within this device's share of the [budget]: with
  /// the share spent it sends nothing, and otherwise it stops right before
  /// the request that would go past it. Either way it answers
  /// [SyncState.paused]; whatever did not go out stays queued for the next
  /// cycle. A manual cycle ([auto] false) always runs, and is counted too.
  ///
  /// [checkRemote] false only pushes and bumps the counters, without asking
  /// the server what changed ([full] is then ignored).
  ///
  /// Returns the resulting status; never throws — failures come back as
  /// [SyncState.error] so the UI can show them without crashing a background
  /// timer.
  @override
  Future<SyncStatus> sync({
    bool full = false,
    bool auto = false,
    bool checkRemote = true,
  }) async {
    if (!config.isConfigured) {
      return const SyncStatus(
        state: SyncState.notConfigured,
        message: 'Chưa nhập App ID và Client Key của Back4App',
      );
    }
    if (_running) {
      return const SyncStatus(
        state: SyncState.running,
        message: 'Đang đồng bộ…',
      );
    }

    _running = true;
    _cycle = _CycleMeter();
    ParseClient? client;
    SyncStatus status;
    try {
      _settings = {...await _state.readAll()};
      final used = int.tryParse(_get(monthKey(_clock.now())) ?? '') ?? 0;
      final level = budget.levelFor(used);
      if (auto && level == SyncBudgetLevel.exhausted) {
        throw const _BudgetSpent();
      }
      _cycle = _CycleMeter(auto ? budget.stopAt - used : null);
      client = ParseClient(
        config,
        httpClient: _httpClientFactory?.call(),
        onRequest: _cycle.take,
      );
      _inflight = _decodeSet(_get(_inflightKey));

      final (pushed, touched) = await _push(client);
      await _bumpMeta(client, touched);
      final pulled = checkRemote
          ? await _pull(client, full: full, level: level)
          : 0;
      final now = _clock.now();
      await _put('sync_last_at', '${now.millisecondsSinceEpoch}');
      status = SyncStatus(
        state: SyncState.ok,
        lastSyncAt: now,
        pushed: pushed,
        pulled: pulled,
      );
    } on _BudgetSpent {
      status = const SyncStatus(
        state: SyncState.paused,
        message: budgetSpentMessage,
      );
    } on ParseException catch (error) {
      status = SyncStatus(state: SyncState.error, message: error.message);
    } on SocketException {
      status = const SyncStatus(
        state: SyncState.error,
        message: 'Không có kết nối mạng',
      );
    } catch (error) {
      status = SyncStatus(state: SyncState.error, message: '$error');
    } finally {
      _running = false;
      client?.close();
    }
    return status.withMonthRequests(await _meter(_cycle.sent));
  }

  /// Whether anything here still waits to go out: edits, deletes, or a
  /// counter bump that did not land. Answered locally, without a request.
  @override
  Future<bool> hasLocalChanges() async {
    for (final collection in _collections) {
      if ((await collection.pendingDeletes()).isNotEmpty) return true;
      if ((await collection.dirtyRecords()).isNotEmpty) return true;
    }
    return ((await _state.read(_bumpKey)) ?? '').isNotEmpty;
  }

  // ---------------------------------------------------------------- meter

  static String monthKey(DateTime time) =>
      'sync_req_${time.year}-${time.month.toString().padLeft(2, '0')}';

  /// Requests counted so far this month on this device: every request sent,
  /// failed or not, automatic or manual.
  @override
  Future<int> requestsThisMonth() async =>
      int.tryParse(await _state.read(monthKey(_clock.now())) ?? '') ?? 0;

  /// Adds [requests] to this month's tally and returns the new total.
  Future<int?> _meter(int requests) async {
    try {
      final key = monthKey(_clock.now());
      final total =
          (int.tryParse(await _state.read(key) ?? '') ?? 0) + requests;
      if (requests > 0) await _state.write(key, '$total');
      return total;
    } catch (error) {
      debugPrint('Sync meter failed: $error');
      return null;
    }
  }

  // ------------------------------------------------------------------ push

  /// Returns how many changes went out and which classes they touched.
  ///
  /// Collections go in the order they were registered. Within one, deletions
  /// go first: a row recreated below should not be wiped by a stale delete
  /// queued for the same object.
  Future<(int, Set<String>)> _push(ParseClient client) async {
    var count = 0;
    final touched = <String>{};

    try {
      for (final collection in _collections) {
        final className = collection.className;
        for (final remoteId in await collection.pendingDeletes()) {
          await client.delete(className, remoteId);
          await collection.clearPendingDelete(remoteId);
          touched.add(className);
          count++;
        }
        for (final record in await collection.dirtyRecords()) {
          final objectId = await _upsert(
            client,
            className,
            localId: record.localId,
            remoteId: record.remoteId,
            data: {...record.fields, 'space': config.space},
          );
          await collection.markSynced(record.localId, objectId);
          await _landed(className, record.localId);
          touched.add(className);
          count++;
        }
      }
    } on _BudgetSpent {
      // What did go out still has to reach the other devices: the next
      // cycle's bump announces it.
      await _queueBump(touched);
      rethrow;
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
      final existing = await client.findOne(
        className,
        where: {'space': config.space, 'localId': localId},
      );
      final existingId = existing?['objectId'] as String?;
      if (existingId != null) {
        await client.update(className, existingId, data);
        return existingId;
      }
    }
    // A create the budget stops is never sent, so it must not be marked.
    _cycle.check();
    await _setInflight(className, localId, on: true);
    return client.create(className, data);
  }

  Future<void> _landed(String className, String localId) =>
      _setInflight(className, localId, on: false);

  static String _inflightId(String className, String localId) =>
      '$className/$localId';

  Future<void> _setInflight(
    String className,
    String localId, {
    required bool on,
  }) async {
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

  /// The space-wide cursor, shared by the classes of the shared channel
  /// (the clipboard's, which had it first).
  String get _sharedCursorKey => 'sync_cursor_${config.space}';
  String _cursorKey(String className) =>
      'sync_cursor_${config.space}_$className';

  List<String> get _classNames => [
    for (final collection in _collections) collection.className,
  ];

  /// Tells the other devices which classes just changed.
  ///
  /// The set is saved before the request, so a bump that fails is retried on
  /// the next cycle instead of leaving the other devices unaware.
  Future<void> _bumpMeta(ParseClient client, Set<String> touched) async {
    final pending = await _queueBump(touched);
    if (pending.isEmpty) return;

    final metaId =
        _get(_metaIdKey) ?? (await _findMeta(client))?['objectId'] as String?;
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

  /// Adds [touched] to the classes still waiting for a bump, and returns
  /// them all.
  Future<Set<String>> _queueBump(Set<String> touched) async {
    final pending = {..._decodeSet(_get(_bumpKey)), ...touched};
    if (pending.isNotEmpty) await _put(_bumpKey, jsonEncode(pending.toList()));
    return pending;
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

  /// [level] is where this device stood against the budget when the cycle
  /// started; it sets how old the last full pull may get.
  Future<int> _pull(
    ParseClient client, {
    required bool full,
    required SyncBudgetLevel level,
  }) async {
    final now = _clock.now();
    final lastFull = int.tryParse(_get(_fullKey) ?? '');
    final fullDue =
        full ||
        lastFull == null ||
        now.difference(DateTime.fromMillisecondsSinceEpoch(lastFull)) >=
            budget.fullPullEvery(level);

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
    for (final channel in _channels) {
      final classNames = [
        for (final collection in channel.collections) collection.className,
      ];
      // A channel is pulled as one: any of its classes moving pulls them all.
      if (!classNames.any(stale)) continue;
      applied += await _pullChannel(client, channel);
      for (final className in classNames) {
        await _put(_revKey(className), '${revs[className]}');
      }
    }

    if (fullDue) await _put(_fullKey, '${now.millisecondsSinceEpoch}');
    return applied;
  }

  /// Fetches what changed since the channel's cursor, mirrors deletions, then
  /// applies the changes, collection by collection in the channel's order.
  ///
  /// Every collection outside the shared channel keeps its own cursor: they
  /// were added after the clipboard one had already moved on, and a shared
  /// cursor would have hidden everything written before that.
  ///
  /// A collection with fewer than [onePassMaxRows] synced rows is fetched
  /// whole instead, in one query: the rows past the cursor are the changes,
  /// and the ids of all of them show what was deleted. That saves the
  /// reconcile request, at the cost of downloading rows already here.
  Future<int> _pullChannel(ParseClient client, SyncChannel channel) async {
    final cursorKey = channel.shared
        ? _sharedCursorKey
        : _cursorKey(channel.collections.single.className);
    final since = _get(cursorKey);
    final where = <String, Object?>{
      'space': config.space,
      if (since != null)
        'updatedAt': {
          r'$gt': {'__type': 'Date', 'iso': since},
        },
    };

    final whole = <bool>[];
    final rows = <List<Map<String, Object?>>>[];
    for (final collection in channel.collections) {
      final onePass = (await collection.syncedIds()).length < onePassMaxRows;
      whole.add(onePass);
      rows.add(
        await client.queryAll(
          collection.className,
          where: onePass ? {'space': config.space} : where,
        ),
      );
    }

    var applied = 0;
    for (var i = 0; i < channel.collections.length; i++) {
      applied += await _reconcile(
        client,
        channel.collections[i],
        live: whole[i] ? rows[i] : null,
      );
    }

    String? newestIso = since;
    for (var i = 0; i < channel.collections.length; i++) {
      final collection = channel.collections[i];
      for (final json in rows[i]) {
        final updatedAt = json['updatedAt'] as String?;
        // A whole class holds rows the cursor already covers.
        if (whole[i] && !_isPast(updatedAt, since)) continue;
        if (await collection.applyRemote(json)) applied++;
        newestIso = _newer(newestIso, updatedAt);
      }
    }

    if (newestIso != null) await _put(cursorKey, newestIso);
    return applied;
  }

  /// Mirrors deletions made on other devices.
  ///
  /// Without tombstones a deleted object simply stops existing, and a cursor
  /// query can never report it. So each pull also looks at the list of ids in
  /// this space and drops any local row that had been synced but is no longer
  /// there. [live] is that list when the whole class was just fetched;
  /// otherwise the bare ids are fetched here (`keys=localId`, no content).
  Future<int> _reconcile(
    ParseClient client,
    SyncCollection collection, {
    List<Map<String, Object?>>? live,
  }) async {
    final remote =
        live ??
        await client.queryAll(
          collection.className,
          where: {'space': config.space},
          keys: const ['localId'],
        );
    final liveIds = {
      for (final row in remote)
        if (row['localId'] is String) row['localId'] as String,
    };
    var removed = 0;
    for (final localId in await collection.syncedIds()) {
      if (liveIds.contains(localId)) continue;
      await collection.removeLocalOnly(localId);
      removed++;
    }
    return removed;
  }

  // -------------------------------------------------------------- settings

  /// A stored setting, with an empty value read as absent.
  String? _get(String key) {
    final value = _settings[key];
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> _put(String key, String value) async {
    _settings[key] = value;
    await _state.write(key, value);
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

  /// Whether a row stamped [updatedAt] is one a cursor query from [since]
  /// would have returned.
  static bool _isPast(String? updatedAt, String? since) {
    if (since == null) return true;
    return updatedAt != null && updatedAt.compareTo(since) > 0;
  }
}

/// Thrown right before a request an automatic cycle may no longer send.
class _BudgetSpent implements Exception {
  const _BudgetSpent();
}

/// Requests one cycle has sent, against the most it may send.
class _CycleMeter {
  _CycleMeter([this.cap]);

  /// Null for a cycle without a limit.
  final int? cap;
  int sent = 0;

  /// Throws [_BudgetSpent] once the cycle has no request left.
  void check() {
    final limit = cap;
    if (limit != null && sent >= limit) throw const _BudgetSpent();
  }

  /// Counts a request about to go out, or stops it with [_BudgetSpent].
  void take() {
    check();
    sent++;
  }
}
