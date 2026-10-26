import '../p2p_protocol.dart';

/// Another device running the app on the same LAN.
///
/// Immutable. Whether it is still around depends on the time, which is passed
/// in: see [isStale].
class Peer {
  const Peer({
    required this.id,
    required this.name,
    required this.platform,
    required this.address,
    required this.port,
    required this.seenAt,
  });

  /// Fixed id of the device, made once and kept on that device.
  final String id;
  final String name;

  /// 'windows', 'android', ... — only used to pick an icon.
  final String platform;

  /// IPv4 the device was heard from, and the HTTP port it receives files on.
  final String address;
  final int port;

  /// When the device was last heard from.
  final DateTime seenAt;

  /// Quiet for longer than this and the device counts as gone.
  static const staleAfter = P2pProtocol.staleAfter;

  /// True when the device has not been heard from for longer than
  /// [staleAfter] at [now].
  bool isStale(DateTime now) => now.difference(seenAt) > staleAfter;

  /// Tells devices apart by id and port: two copies of the app on one machine
  /// share an id but are two separate ends, and must not replace each other.
  String get key => '$id@$port';

  /// Address of [path] on the device's HTTP server.
  Uri uri(String path) => Uri.parse('http://$address:$port$path');

  /// A copy with the given fields replaced. The id never changes.
  Peer copyWith({
    String? name,
    String? platform,
    String? address,
    int? port,
    DateTime? seenAt,
  }) => Peer(
    id: id,
    name: name ?? this.name,
    platform: platform ?? this.platform,
    address: address ?? this.address,
    port: port ?? this.port,
    seenAt: seenAt ?? this.seenAt,
  );

  @override
  bool operator ==(Object other) =>
      other is Peer &&
      other.id == id &&
      other.name == name &&
      other.platform == platform &&
      other.address == address &&
      other.port == port &&
      other.seenAt == seenAt;

  @override
  int get hashCode => Object.hash(id, name, platform, address, port, seenAt);

  @override
  String toString() => 'Peer($key, $name, $address)';
}

/// One thing discovery heard about a device: it is here, or it just said
/// goodbye ([left]) because it turned file transfer off.
class PeerSighting {
  const PeerSighting({required this.peer, this.left = false});

  final Peer peer;
  final bool left;

  @override
  bool operator ==(Object other) =>
      other is PeerSighting && other.peer == peer && other.left == left;

  @override
  int get hashCode => Object.hash(peer, left);

  @override
  String toString() => 'PeerSighting(${peer.key}, left: $left)';
}
