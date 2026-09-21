import 'dart:convert';
import 'dart:io';

import 'package:event_notice/p2p/models/peer.dart';
import 'package:event_notice/p2p/services/discovery_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Gửi gói UDP thẳng vào cổng của dịch vụ (unicast loopback) thay vì broadcast
/// thật: máy chạy test có thể không có card mạng nào cho phép broadcast.
void main() {
  late DiscoveryService service;
  late List<Peer> seen;
  late RawDatagramSocket outsider;

  // Không dùng 45699: bản app thật trên máy có thể đang giữ cổng đó.
  const discoveryPort = 45699 + 111;

  setUp(() async {
    seen = [];
    service = DiscoveryService(
      deviceId: 'me',
      deviceName: 'Máy này',
      platform: 'windows',
      servicePort: 45700,
      discoveryPort: discoveryPort,
      // Máy chạy test có thể đang mở app thật; chỉ nhận gói của test này.
      onPeer: (peer) {
        if (peer.id == 'phone' || peer.id == 'me') seen.add(peer);
      },
    );
    await service.start();
    outsider = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    outsider.close();
    await service.stop();
  });

  void shout(Map<String, Object?> body) {
    outsider.send(
      utf8.encode(jsonEncode(body)),
      InternetAddress.loopbackIPv4,
      discoveryPort,
    );
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 200));

  Map<String, Object?> hello({
    String id = 'phone',
    String type = 'hello',
    int port = 45701,
  }) =>
      {
        'magic': 'event_notice_p2p/1',
        'type': type,
        'id': id,
        'name': 'Điện thoại của Felix',
        'platform': 'android',
        'port': port,
      };

  test('nghe được lời chào thì ghi thiết bị vào danh sách', () async {
    shout(hello());
    await settle();

    expect(seen, hasLength(1));
    expect(seen.single.id, 'phone');
    expect(seen.single.name, 'Điện thoại của Felix');
    expect(seen.single.port, 45701);
    expect(seen.single.isStale, isFalse);
  });

  test('chào lại đúng cổng nguồn để bên kia thấy mình ngay', () async {
    final replies = <Map<String, dynamic>>[];
    outsider.listen((event) {
      if (event != RawSocketEvent.read) return;
      final packet = outsider.receive();
      if (packet == null) return;
      replies.add(jsonDecode(utf8.decode(packet.data)) as Map<String, dynamic>);
    });

    shout(hello());
    await settle();

    expect(replies, hasLength(1));
    expect(replies.single['id'], 'me');
    expect(replies.single['name'], 'Máy này');
    // Kiểu 'hi' để hai bên không chào qua chào lại mãi.
    expect(replies.single['type'], 'hi');
  });

  test('gói "bye" đánh dấu thiết bị đã rời mạng', () async {
    shout(hello(type: 'bye'));
    await settle();

    expect(seen.single.isStale, isTrue);
  });

  test('bản thứ hai trên cùng máy vẫn thấy được (trùng id, khác cổng)',
      () async {
    shout(hello(id: 'me', port: 45701));
    await settle();

    expect(seen.single.id, 'me');
    expect(seen.single.port, 45701);
  });

  test('bỏ qua gói của chính mình và gói của app khác', () async {
    // Đúng cả id lẫn cổng dịch vụ mới là gói của chính mình dội lại.
    shout(hello(id: 'me', port: 45700));
    shout({'magic': 'thu-khac/9', 'id': 'x', 'type': 'hello'});
    outsider.send(utf8.encode('không phải JSON'), InternetAddress.loopbackIPv4,
        discoveryPort);
    await settle();

    expect(seen, isEmpty);
  });
}
