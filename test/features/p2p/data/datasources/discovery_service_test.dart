import 'dart:convert';
import 'dart:io';

import 'package:event_notice/features/p2p/data/datasources/discovery_service.dart';
import 'package:event_notice/features/p2p/domain/entities/peer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

/// Packets go straight to the service's port (unicast on loopback) instead of
/// a real broadcast: the test machine may have no card that allows one.
void main() {
  late DiscoveryService service;
  late List<PeerSighting> seen;
  late RawDatagramSocket outsider;
  late FakeClock clock;

  // Not 45699, which a running copy of the app may hold, and not the port of
  // test/p2p_discovery_test.dart, which may run at the same time.
  const discoveryPort = 45699 + 222;

  setUp(() async {
    seen = [];
    clock = FakeClock();
    service = DiscoveryService(
      deviceId: 'me',
      deviceName: 'Máy này',
      platform: 'windows',
      servicePort: 45700,
      discoveryPort: discoveryPort,
      clock: clock,
      // A real copy of the app may be running: only keep this test's packets.
      onSighting: (s) {
        if (s.peer.id == 'phone' || s.peer.id == 'me') seen.add(s);
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
  }) => {
    'magic': 'event_notice_p2p/1',
    'type': type,
    'id': id,
    'name': 'Điện thoại của Felix',
    'platform': 'android',
    'port': port,
  };

  test('nghe được lời chào thì báo thiết bị, giờ thấy lấy từ Clock', () async {
    shout(hello());
    await settle();

    expect(seen, hasLength(1));
    final peer = seen.single.peer;
    expect(seen.single.left, isFalse);
    expect(peer.id, 'phone');
    expect(peer.name, 'Điện thoại của Felix');
    expect(peer.platform, 'android');
    expect(peer.address, '127.0.0.1');
    expect(peer.port, 45701);
    expect(peer.seenAt, start);
    expect(peer.isStale(clock.now()), isFalse);
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
    expect(replies.single, {
      'magic': 'event_notice_p2p/1',
      'type': 'hi',
      'id': 'me',
      'name': 'Máy này',
      'platform': 'windows',
      'port': 45700,
    });
  });

  test('gói "hi" không được chào lại', () async {
    final replies = <Object>[];
    outsider.listen((event) {
      if (event == RawSocketEvent.read && outsider.receive() != null) {
        replies.add(event);
      }
    });

    shout(hello(type: 'hi'));
    await settle();

    expect(seen, hasLength(1));
    expect(replies, isEmpty);
  });

  test('gói "bye" báo thiết bị đã rời mạng', () async {
    shout(hello(type: 'bye'));
    await settle();

    expect(seen.single.left, isTrue);
    expect(seen.single.peer.isStale(clock.now()), isTrue);
  });

  test(
    'bản thứ hai trên cùng máy vẫn thấy được (trùng id, khác cổng)',
    () async {
      shout(hello(id: 'me', port: 45701));
      await settle();

      expect(seen.single.peer.id, 'me');
      expect(seen.single.peer.port, 45701);
    },
  );

  test('bỏ qua gói của chính mình và gói của app khác', () async {
    shout(hello(id: 'me', port: 45700));
    shout({'magic': 'thu-khac/9', 'id': 'x', 'type': 'hello'});
    outsider.send(
      utf8.encode('không phải JSON'),
      InternetAddress.loopbackIPv4,
      discoveryPort,
    );
    await settle();

    expect(seen, isEmpty);
  });

  test('đổi tên khi đang chạy thì lời chào sau mang tên mới', () async {
    final replies = <Map<String, dynamic>>[];
    outsider.listen((event) {
      if (event != RawSocketEvent.read) return;
      final packet = outsider.receive();
      if (packet == null) return;
      replies.add(jsonDecode(utf8.decode(packet.data)) as Map<String, dynamic>);
    });

    service.deviceName = 'Tên mới';
    shout(hello());
    await settle();

    expect(replies.single['name'], 'Tên mới');
  });
}
