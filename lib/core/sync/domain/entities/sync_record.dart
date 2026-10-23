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

  /// The object body, without `space` — the sync engine adds that.
  final Map<String, Object?> fields;
}
