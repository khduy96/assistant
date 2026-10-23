import '../entities/transfer.dart';
import '../p2p_protocol.dart';

/// The list of transfers shown to the user, newest first. Every method
/// returns a new list and leaves its input alone.
abstract final class TransferHistory {
  /// Takes the snapshot [transfer] into account: a transfer already listed is
  /// replaced where it stands, a new one goes on top and the list is
  /// [trim]med.
  static List<Transfer> record(List<Transfer> list, Transfer transfer) {
    final index = list.indexWhere((t) => t.id == transfer.id);
    if (index >= 0) return List.of(list)..[index] = transfer;
    return trim([transfer, ...list]);
  }

  /// Drops the oldest finished transfers until at most [limit] are left.
  /// Active ones are never dropped, so the list may stay longer than [limit].
  static List<Transfer> trim(
    List<Transfer> list, {
    int limit = P2pProtocol.historyLimit,
  }) {
    final next = List.of(list);
    for (var i = next.length - 1; i >= 0 && next.length > limit; i--) {
      if (!next[i].isActive) next.removeAt(i);
    }
    return next;
  }

  /// The list without finished transfers.
  static List<Transfer> clearFinished(List<Transfer> list) =>
      list.where((t) => t.isActive).toList();

  /// Incoming files waiting for the user to accept or decline them.
  static List<Transfer> pendingOffers(List<Transfer> list) =>
      list.where((t) => t.state == TransferState.pending).toList();

  /// Everything but the waiting offers: what the transfer list shows.
  static List<Transfer> withoutOffers(List<Transfer> list) =>
      list.where((t) => t.state != TransferState.pending).toList();

  /// How many transfers are waiting or running.
  static int activeCount(List<Transfer> list) =>
      list.where((t) => t.isActive).length;
}
