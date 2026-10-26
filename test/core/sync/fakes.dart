import 'dart:async';

import 'package:event_notice/core/domain/clock.dart';
import 'package:event_notice/core/sync/domain/entities/sync_settings.dart';
import 'package:event_notice/core/sync/domain/entities/sync_status.dart';
import 'package:event_notice/core/sync/domain/sync_collection.dart';
import 'package:event_notice/core/sync/domain/sync_engine.dart';
import 'package:event_notice/core/sync/domain/sync_state_store.dart';

/// A clock that stays at [current] until a test moves it.
class FixedClock implements Clock {
  FixedClock(this.current);

  DateTime current;

  @override
  DateTime now() => current;
}

/// One row of a [MemorySyncCollection].
class MemoryRow {
  MemoryRow({required this.fields, this.remoteId, this.dirty = true});

  Map<String, Object?> fields;
  String? remoteId;
  bool dirty;
}

/// A [SyncCollection] kept in maps, standing in for the todos or the notes.
///
/// Applies whatever the server sends (no conflict rule), and records it.
class MemorySyncCollection implements SyncCollection {
  MemorySyncCollection(this.className);

  @override
  final String className;

  final Map<String, MemoryRow> rows = {};

  /// `objectId`s waiting for a DELETE.
  final List<String> tombstones = [];

  /// Server objects handed to [applyRemote], in order.
  final List<Map<String, Object?>> applied = [];

  final _localChanges = StreamController<void>.broadcast();

  /// Adds or edits a row as the user would.
  void edit(String localId, Map<String, Object?> fields) {
    final row = rows[localId];
    if (row == null) {
      rows[localId] = MemoryRow(fields: {'localId': localId, ...fields});
    } else {
      row
        ..fields = {...row.fields, ...fields}
        ..dirty = true;
    }
    _localChanges.add(null);
  }

  /// Deletes a row as the user would: a row already on the server leaves its
  /// `objectId` in [tombstones].
  void delete(String localId) {
    final row = rows.remove(localId);
    if (row == null) return;
    final remoteId = row.remoteId;
    if (remoteId != null) tombstones.add(remoteId);
    _localChanges.add(null);
  }

  Future<void> close() => _localChanges.close();

  @override
  Stream<void> get localChanges => _localChanges.stream;

  @override
  Future<List<SyncRecord>> dirtyRecords() async => [
    for (final MapEntry(:key, :value) in rows.entries)
      if (value.dirty)
        SyncRecord(
          localId: key,
          remoteId: value.remoteId,
          fields: value.fields,
        ),
  ];

  @override
  Future<Set<String>> syncedIds() async => {
    for (final MapEntry(:key, :value) in rows.entries)
      if (value.remoteId != null && !value.dirty) key,
  };

  @override
  Future<List<String>> pendingDeletes() async => [...tombstones];

  @override
  Future<void> clearPendingDelete(String remoteId) async =>
      tombstones.remove(remoteId);

  @override
  Future<void> markSynced(String localId, String remoteId) async {
    rows[localId]
      ?..remoteId = remoteId
      ..dirty = false;
  }

  @override
  Future<bool> applyRemote(Map<String, Object?> json) async {
    final localId = json['localId'];
    if (localId is! String) return false;
    applied.add(json);
    rows[localId] = MemoryRow(
      fields: {...json},
      remoteId: json['objectId'] as String?,
      dirty: false,
    );
    return true;
  }

  @override
  Future<void> removeLocalOnly(String localId) async => rows.remove(localId);
}

/// A [SyncStateStore] kept in a map.
class MemorySyncStateStore implements SyncStateStore {
  final Map<String, String> values = {};

  @override
  Future<Map<String, String>> readAll() async => {...values};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

/// A [SyncEngine] whose answers the test sets.
class FakeSyncEngine implements SyncEngine {
  SyncStatus status = const SyncStatus(state: SyncState.ok);
  bool pending = false;
  int monthRequests = 0;
  Object? error;
  final List<bool> fullRequests = [];

  /// The arguments of every [sync] call, in order.
  final List<({bool full, bool auto, bool checkRemote})> syncCalls = [];
  final StreamController<void> changes = StreamController<void>.broadcast();

  @override
  SyncSettings settings = const SyncSettings(
    isConfigured: true,
    autoSync: true,
    space: 'nha',
  );

  void _maybeThrow() {
    final e = error;
    if (e != null) throw e;
  }

  @override
  Future<SyncStatus> sync({
    bool full = false,
    bool auto = false,
    bool checkRemote = true,
  }) async {
    _maybeThrow();
    fullRequests.add(full);
    syncCalls.add((full: full, auto: auto, checkRemote: checkRemote));
    return status;
  }

  @override
  Future<bool> hasLocalChanges() async {
    _maybeThrow();
    return pending;
  }

  @override
  Future<int> requestsThisMonth() async {
    _maybeThrow();
    return monthRequests;
  }

  @override
  Stream<void> get localChanges => changes.stream;
}
