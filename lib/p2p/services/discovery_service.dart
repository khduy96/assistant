import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/peer.dart';

/// Tự tìm nhau trong LAN bằng UDP broadcast.
///
/// Không cần server, không cần nhập IP: mỗi máy cứ vài giây lại hét lên một gói
/// JSON nhỏ ra toàn mạng, máy nào nghe được thì ghi tên vào danh sách. Gói
/// nghe được cũng được trả lời riêng (unicast) để bên kia thấy mình ngay thay
/// vì phải đợi hết một nhịp quảng bá.
class DiscoveryService {
  DiscoveryService({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.servicePort,
    required this.onPeer,
    this.discoveryPort = defaultDiscoveryPort,
  });

  /// Cổng UDP nghe/quảng bá. Chọn số cao, ít đụng hàng.
  static const defaultDiscoveryPort = 45699;

  /// Cổng thật đang dùng; test đổi sang cổng khác để không giành cổng với bản
  /// app đang chạy trên cùng máy.
  final int discoveryPort;

  /// Nhãn trong gói tin để bỏ qua mọi thứ khác đang chạy trên cùng cổng.
  static const _magic = 'event_notice_p2p/1';

  static const _announceEvery = Duration(seconds: 3);

  final String deviceId;
  final String platform;
  final int servicePort;

  /// Tên hiển thị; đổi được trong lúc đang chạy.
  String deviceName;

  final void Function(Peer peer) onPeer;

  RawDatagramSocket? _socket;

  /// Socket gửi riêng cho từng địa chỉ IPv4 của máy, xem [_perInterfaceSenders].
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
      // Cổng bị app khác giữ: vẫn gửi quảng bá được từ một cổng ngẫu nhiên,
      // chỉ là phải đợi bên kia trả lời riêng mới thấy nhau.
      debugPrint('P2P: không giữ được cổng $discoveryPort ($e), dùng cổng tạm');
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    }
    final socket = _socket!;
    socket.broadcastEnabled = true;
    socket.listen((event) => _onEvent(socket, event));
    _timer = Timer.periodic(_announceEvery, (_) => announce());
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

  /// Gửi một nhịp quảng bá ngay, dùng khi vừa bật hoặc khi người dùng bấm
  /// "Tìm lại".
  Future<void> announce() async {
    final socket = _socket;
    if (socket == null) return;
    await _send(socket, {'type': 'hello'});
  }

  /// Chào riêng từng địa chỉ trong dải /24 quanh máy này, thay vì hét một lần
  /// ra broadcast.
  ///
  /// Mạng công ty và Wi-Fi khách thường chặn gói broadcast giữa các máy, nhưng
  /// vẫn cho gói unicast đi qua — 254 gói nhỏ là đủ tìm ra nhau. Chỉ chạy khi
  /// người dùng bấm "Tìm lại", không chạy theo nhịp, để không rải rác gói vô
  /// ích lên mạng.
  Future<void> sweep() async {
    final socket = _socket;
    if (socket == null) return;
    final data = utf8.encode(jsonEncode({
      'magic': _magic,
      'type': 'hello',
      'id': deviceId,
      'name': deviceName,
      'platform': platform,
      'port': servicePort,
    }));

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
          // Một địa chỉ không gửi được không chặn các địa chỉ còn lại.
        }
      }
    }
  }

  Future<void> _send(RawDatagramSocket socket, Map<String, Object?> extra) async {
    final data = utf8.encode(jsonEncode({
      'magic': _magic,
      'id': deviceId,
      'name': deviceName,
      'platform': platform,
      'port': servicePort,
      ...extra,
    }));

    // Gửi qua socket chính: đủ cho máy chỉ có một card mạng.
    _sendVia(socket, data);
    // Và qua một socket buộc vào IP của từng card: gói broadcast hạn cục bộ
    // sẽ đi ra đúng card đó, nên máy có nhiều card (Wi-Fi + dây + máy ảo +
    // VPN) không bị hệ điều hành chọn hộ một card rồi bỏ quên phần còn lại.
    for (final sender in await _perInterfaceSenders()) {
      _sendVia(sender, data);
    }
  }

  void _sendVia(RawDatagramSocket socket, List<int> data) {
    try {
      // 255.255.255.255 là broadcast "hạn cục bộ": router không bao giờ
      // chuyển nó đi xa, nhưng mọi máy trong cùng đoạn mạng đều nhận được —
      // và không phải đoán mặt nạ mạng là /24, /22 hay /16 như địa chỉ
      // broadcast có hướng (x.y.z.255), thứ mà Dart không cho biết.
      socket.send(data, _limitedBroadcast, discoveryPort);
    } catch (_) {
      // Một card mạng không gửi được (VPN vừa ngắt, máy ảo đang tắt) không
      // được làm hỏng các card còn lại.
    }
  }

  static final _limitedBroadcast = InternetAddress('255.255.255.255');

  /// Một socket gửi cho mỗi địa chỉ IPv4 của máy, dựng lại khi danh sách card
  /// mạng đổi (cắm dây, đổi Wi-Fi, bật VPN).
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
      // Không liệt kê được card mạng: đành trông vào socket chính.
      return const [];
    }

    for (final gone in _senders.keys.toList()) {
      if (!addresses.contains(gone)) _senders.remove(gone)?.close();
    }
    for (final address in addresses) {
      if (_senders.containsKey(address)) continue;
      try {
        final sender =
            await RawDatagramSocket.bind(InternetAddress(address), 0);
        sender.broadcastEnabled = true;
        // Câu trả lời riêng bên kia gửi về cổng này cũng phải được đọc.
        sender.listen((event) => _onEvent(sender, event));
        _senders[address] = sender;
      } catch (_) {
        // Card mạng vừa biến mất giữa chừng.
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
    if (body['magic'] != _magic) return;
    final id = body['id'] as String?;
    if (id == null) return;
    final peerPort = (body['port'] as num?)?.toInt() ?? 0;
    // Gói của chính mình dội lại từ broadcast. Phải so cả cổng, không chỉ id:
    // hai bản app mở trên cùng một máy dùng chung tệp cấu hình nên trùng id,
    // nhưng là hai đầu truyền khác nhau và vẫn phải thấy được nhau.
    if (id == deviceId && peerPort == servicePort) return;

    final type = body['type'] as String? ?? 'hello';
    if (type == 'bye') {
      onPeer(Peer(
        id: id,
        name: body['name'] as String? ?? '?',
        platform: body['platform'] as String? ?? 'other',
        address: packet.address.address,
        port: peerPort,
        // Đánh dấu đã cũ để store loại khỏi danh sách ngay.
        seenAt: DateTime.now().subtract(Peer.staleAfter * 2),
      ));
      return;
    }

    onPeer(Peer(
      id: id,
      name: body['name'] as String? ?? 'Không tên',
      platform: body['platform'] as String? ?? 'other',
      address: packet.address.address,
      port: peerPort,
      seenAt: DateTime.now(),
    ));

    // Chào lại đúng người vừa chào mình. Kiểu 'hi' không được chào lại nữa để
    // hai máy không ping-pong vô tận.
    if (type == 'hello') {
      try {
        socket.send(
          utf8.encode(jsonEncode({
            'magic': _magic,
            'type': 'hi',
            'id': deviceId,
            'name': deviceName,
            'platform': platform,
            'port': servicePort,
          })),
          packet.address,
          // Trả về đúng cổng nguồn: máy bên kia có thể đã phải dùng cổng tạm.
          packet.port,
        );
      } catch (_) {
        // Bên kia biến mất giữa chừng: nhịp quảng bá sau sẽ lo.
      }
    }
  }
}
