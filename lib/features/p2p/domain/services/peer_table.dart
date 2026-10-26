import '../entities/peer.dart';

/// The devices heard on the LAN, as a map from [Peer.key] to the latest
/// sighting. Every method returns a new map and leaves its input alone.
abstract final class PeerTable {
  /// Takes [sighting] into account: a device saying goodbye leaves the table,
  /// any other sighting adds the device or refreshes it.
  static Map<String, Peer> record(
    Map<String, Peer> table,
    PeerSighting sighting,
  ) {
    final next = Map<String, Peer>.of(table);
    final key = sighting.peer.key;
    if (sighting.left) {
      next.remove(key);
    } else {
      next[key] = sighting.peer;
    }
    return next;
  }

  /// Drops devices gone quiet at [now] (see [Peer.isStale]); a machine
  /// switched off never says goodbye.
  static Map<String, Peer> prune(Map<String, Peer> table, DateTime now) =>
      Map<String, Peer>.of(table)..removeWhere((_, peer) => peer.isStale(now));

  /// Devices still heard from at [now], sorted by name, case aside.
  static List<Peer> visible(Iterable<Peer> peers, DateTime now) =>
      peers.where((peer) => !peer.isStale(now)).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}
