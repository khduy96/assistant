import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../../core/domain/clock.dart';
import '../../domain/entities/peer.dart';
import '../../domain/p2p_protocol.dart';

/// Finds other devices on the LAN by UDP broadcast.
///
/// No server and no IP to type: every few seconds each device shouts a small
/// JSON packet to the whole network, and whoever hears it writes the sender
/// down. A packet heard is also answered directly (unicast), so the other
/// side sees this device at once instead of waiting a full round.
///
/// Packets are `{magic, type, id, name, platform, port}` with `type` one of
/// `hello` (announcement), `hi` (direct answer, never answered again) and
/// `bye` (leaving). Older builds of the app read exactly this.
class DiscoveryService {
  DiscoveryService({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.servicePort,
    required this.onSighting,
    required this.clock,
    this.discoveryPort = P2pProtocol.discoveryPort,
  });

  /// UDP port listened and announced on; tests use another one so they do
  /// not fight a running copy of the app for it.
  final int discoveryPort;

  final String deviceId;
  final String platform;
  final int servicePort;

  /// Name announced; may change while running.
  String deviceName;

  /// Called for every device heard, and for every goodbye.
  final void Function(PeerSighting sighting) onSighting;

  final Clock clock;

  RawDatagramSocket? _socket;

  /// One sending socket per IPv4 address of this machine, see
  /// [_perInterfaceSenders].
  final Map<String, RawDatagramSocket> _senders = {};
  Timer? _timer;

  bool get isRunning => _socket != null;

  Future<void> start() async {
    if (_socket != null) return;
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
      );
      _socket = socket;
    } on SocketException catch (e) {
      // Another app holds the port: broadcasts still go out from a random
      // port, the other side just has to answer directly before both see
      // each other.
      debugPrint('P2P: không giữ được cổng $discoveryPort ($e), dùng cổng tạm');
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    }
    final socket = _socket!;
    socket.broadcastEnabled = true;
    socket.listen((event) => _onEvent(socket, event));
    _timer = Timer.periodic(P2pProtocol.announceEvery, (_) => announce());
    await announce();
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final socket = _socket;
    if (socket == null) return;
    await _send(socket, {'type': 'bye'});
    for (final sender in _senders.values) {
      sender.close();
    }
    _senders.clear();
    socket.close();
    _socket = null;
  }

  /// Sends one announcement now: when just started, or when the user asks
  /// to search again.
  Future<void> announce() async {
    final socket = _socket;
    if (socket == null) return;
    await _send(socket, {'type': 'hello'});
  }

  /// Greets each address of the /24 range around this machine one by one,
  /// instead of one broadcast.
  ///
  /// Office networks and guest Wi-Fi often drop broadcasts between devices
  /// but let unicast through, and 254 small packets are enough to find each
  /// other. Only on demand, never on a timer, so the network is not littered
  /// with useless packets.
  Future<void> sweep() async {
    final socket = _socket;
    if (socket == null) return;
    final data = utf8.encode(
      jsonEncode({
        'magic': P2pProtocol.magic,
        'type': 'hello',
        'id': deviceId,
        'name': deviceName,
        'platform': platform,
        'port': servicePort,
      }),
    );

    for (final sender in await _perInterfaceSenders()) {
      final own = sender.address.address;
      final parts = own.split('.');
      if (parts.length != 4) continue;
      for (var last = 1; last < 255; last++) {
        final target = '${parts[0]}.${parts[1]}.${parts[2]}.$last';
        if (target == own) continue;
        try {
          socket.send(data, InternetAddress(target), discoveryPort);
        } catch (_) {
          // One address that cannot be reached does not stop the others.
        }
      }
    }
  }

  Future<void> _send(
    RawDatagramSocket socket,
    Map<String, Object?> extra,
  ) async {
    final data = utf8.encode(
      jsonEncode({
        'magic': P2pProtocol.magic,
        'id': deviceId,
        'name': deviceName,
        'platform': platform,
        'port': servicePort,
        ...extra,
      }),
    );

    // Through the main socket: enough for a machine with one network card.
    _sendVia(socket, data);
    // And through a socket bound to each card's IP: a limited broadcast
    // leaves through that very card, so a machine with several cards (Wi-Fi
    // + cable + VMs + VPN) does not have the OS pick one and forget the rest.
    for (final sender in await _perInterfaceSenders()) {
      _sendVia(sender, data);
    }
  }

  void _sendVia(RawDatagramSocket socket, List<int> data) {
    try {
      // 255.255.255.255 is the "limited" broadcast: routers never forward
      // it, but every device on the same segment gets it, without guessing
      // whether the mask is /24, /22 or /16 as a directed broadcast
      // (x.y.z.255) would need, which Dart does not tell.
      socket.send(data, _limitedBroadcast, discoveryPort);
    } catch (_) {
      // One card that cannot send (VPN just dropped, VM switched off) must
      // not spoil the others.
    }
  }

  static final _limitedBroadcast = InternetAddress('255.255.255.255');

  /// One sending socket per IPv4 address of the machine, rebuilt when the
  /// list of cards changes (cable plugged in, Wi-Fi switched, VPN on).
  Future<List<RawDatagramSocket>> _perInterfaceSenders() async {
    final addresses = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          addresses.add(addr.address);
        }
      }
    } catch (_) {
      // Cards cannot be listed: rely on the main socket alone.
      return const [];
    }

    for (final gone in _senders.keys.toList()) {
      if (!addresses.contains(gone)) _senders.remove(gone)?.close();
    }
    for (final address in addresses) {
      if (_senders.containsKey(address)) continue;
      try {
        final sender = await RawDatagramSocket.bind(
          InternetAddress(address),
          0,
        );
        sender.broadcastEnabled = true;
        // Direct answers the other side sends to this port must be read too.
        sender.listen((event) => _onEvent(sender, event));
        _senders[address] = sender;
      } catch (_) {
        // The card went away in the meantime.
      }
    }
    return _senders.values.toList();
  }

  void _onEvent(RawDatagramSocket socket, RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final packet = socket.receive();
    if (packet == null) return;

    Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(packet.data)) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (body['magic'] != P2pProtocol.magic) return;
    final id = body['id'] as String?;
    if (id == null) return;
    final peerPort = (body['port'] as num?)?.toInt() ?? 0;
    // Our own packet echoed by the broadcast. The port must match too, not
    // only the id: two copies of the app on one machine share the settings
    // file and so the id, but are two separate ends that must see each other.
    if (id == deviceId && peerPort == servicePort) return;

    final type = body['type'] as String? ?? 'hello';
    final now = clock.now();
    if (type == 'bye') {
      onSighting(
        PeerSighting(
          peer: Peer(
            id: id,
            name: body['name'] as String? ?? '?',
            platform: body['platform'] as String? ?? 'other',
            address: packet.address.address,
            port: peerPort,
            // Already stale as well, for whoever only looks at the time.
            seenAt: now.subtract(Peer.staleAfter * 2),
          ),
          left: true,
        ),
      );
      return;
    }

    onSighting(
      PeerSighting(
        peer: Peer(
          id: id,
          name: body['name'] as String? ?? 'Không tên',
          platform: body['platform'] as String? ?? 'other',
          address: packet.address.address,
          port: peerPort,
          seenAt: now,
        ),
      ),
    );

    // Answer whoever just greeted us. A 'hi' is never answered, so two
    // devices do not ping-pong forever.
    if (type == 'hello') {
      try {
        socket.send(
          utf8.encode(
            jsonEncode({
              'magic': P2pProtocol.magic,
              'type': 'hi',
              'id': deviceId,
              'name': deviceName,
              'platform': platform,
              'port': servicePort,
            }),
          ),
          packet.address,
          // Back to the source port: the other side may be on a temporary one.
          packet.port,
        );
      } catch (_) {
        // The other side vanished meanwhile: the next announcement will do.
      }
    }
  }
}
