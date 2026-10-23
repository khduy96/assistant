import 'entities/sync_record.dart';

export 'entities/sync_record.dart';
export 'entities/sync_tombstone.dart';

/// A local list the sync engine mirrors to one Back4App class.
///
/// Every feature that syncs hands the engine one of these per class: the
/// clipboard keeps its rows in SQLite, todos and notes keep theirs in JSON
/// files, and the engine sees none of that. Every member that reads or writes
/// is async, so an implementation can wait for its storage to load first.
///
/// Deletes still to be sent are keyed by the server's `objectId`: the
/// clipboard's `pending_deletes` table holds nothing else.
abstract interface class SyncCollection {
  /// Back4App class name, e.g. `TodoItem`.
  String get className;

  /// Records changed since the last successful push.
  Future<List<SyncRecord>> dirtyRecords();

  /// Local ids of rows already on the server, used to notice rows another
  /// device has deleted. Each collection decides whether rows with unpushed
  /// edits count.
  Future<Set<String>> syncedIds();

  /// `objectId`s of rows deleted here whose server object is still waiting to
  /// be removed, in the order they should go.
  Future<List<String>> pendingDeletes();

  /// Forgets a pending delete once its object is gone from the server.
  Future<void> clearPendingDelete(String remoteId);

  /// Records the `objectId` a push returned and clears the dirty flag.
  Future<void> markSynced(String localId, String remoteId);

  /// Applies one object from the server. False when the local copy wins
  /// (unpushed local edits, or a newer local timestamp).
  Future<bool> applyRemote(Map<String, Object?> json);

  /// Drops a row that no longer exists on the server, without queueing a
  /// delete back to it.
  Future<void> removeLocalOnly(String localId);

  /// Fires after a change made on this device that leaves something for the
  /// server to hear about. Never fires for a change the engine applied.
  Stream<void> get localChanges;
}
