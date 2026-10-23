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
