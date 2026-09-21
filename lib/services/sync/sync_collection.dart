/// One local record on its way to (or back from) Back4App.
class SyncRecord {
  const SyncRecord({
    required this.localId,
    required this.remoteId,
    required this.fields,
  });

  /// The app's own id, stored on the server as `localId`.
  final String localId;

  /// Parse's `objectId`, null until the record has been pushed once.
  final String? remoteId;

  /// The object body, without `space` — the sync service adds that.
  final Map<String, Object?> fields;
}

/// A row deleted locally whose server object still has to go.
///
/// Kept because deleting the row would otherwise lose the only pointer to the
/// object on Back4App, and the other devices would keep pulling it back.
class SyncTombstone {
  const SyncTombstone({required this.localId, required this.remoteId});

  final String localId;
  final String remoteId;

  Map<String, Object?> toJson() => {'id': localId, 'remoteId': remoteId};

  static SyncTombstone? fromJson(Map<String, Object?> json) {
    final localId = json['id'];
    final remoteId = json['remoteId'];
    if (localId is! String || remoteId is! String) return null;
    return SyncTombstone(localId: localId, remoteId: remoteId);
  }
}

/// A local list the sync engine can mirror to one Back4App class.
///
/// The clipboard keeps its rows in SQLite and syncs them through
/// `SyncService` directly; todos and notes live in JSON files instead, so they
/// hand the engine this small interface rather than a database.
abstract interface class SyncCollection {
  /// Back4App class name, e.g. `Todo`.
  String get className;

  /// Records changed since the last successful push.
  List<SyncRecord> dirtyRecords();

  /// Local ids already pushed at some point, used to notice rows another
  /// device has deleted.
  Set<String> syncedIds();

  /// Rows deleted here whose server object is still waiting to be removed.
  List<({String localId, String remoteId})> pendingDeletes();

  /// Forgets a tombstone once its object is gone from the server.
  Future<void> clearPendingDelete(String localId);

  /// Records the `objectId` a push returned and clears the dirty flag.
  Future<void> markSynced(String localId, String remoteId);

  /// Applies one object from the server. False when the local copy wins
  /// (unpushed local edits, or a newer local timestamp).
  Future<bool> applyRemote(Map<String, Object?> json);

  /// Drops a row that no longer exists on the server, without queueing a
  /// delete back to it.
  Future<void> removeLocalOnly(String localId);
}
