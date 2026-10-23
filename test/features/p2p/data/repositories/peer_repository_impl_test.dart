import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/features/p2p/data/repositories/peer_repository_impl.dart';
import 'package:event_notice/features/p2p/domain/entities/p2p_settings.dart';
import 'package:event_notice/features/p2p/domain/entities/peer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

void main() {
  // Not 45699 (a running copy of the app) and not the ports of the other
  // discovery tests, which may run at the same time.
  const discoveryPort = 45699 + 333;

  late FakeClock clock;
  late PeerRepositoryImpl repo;
  late List<PeerSighting> seen;
  late StreamSubscription<PeerSighting> sub;

  final settings = P2pSettings(deviceId: 'me', deviceName: 'Máy này');

  setUp(() {
    clock = FakeClock();
    repo = PeerRepositoryImpl(
      clock,
      device: const FakeLocalDevice(platform: 'android', address: '10.1.2.3'),
      discoveryPort: discoveryPort,
    );
    seen = [];
    sub = repo.sightings.listen((s) {
      if (s.peer.id == 'phone') seen.add(s);
    });
  });

  tearDown(() async {
    await sub.cancel();
    await repo.dispose();
  });

  Future<RawDatagramSocket> outsider() async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(socket.close);
    return socket;
  }

  void shout(RawDatagramSocket from, String type) => from.send(
    utf8.encode(
      jsonEncode({
        'magic': 'event_notice_p2p/1',
        'type': type,
        'id': 'phone',
        'name': 'Điện thoại',
        'platform': 'android',
        'port': 45701,
      }),
    ),
    InternetAddress.loopbackIPv4,
    discoveryPort,
  );

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 200));

  /// A one-route HTTP server answering `GET /info` with [body].
  Future<HttpServer> infoServer(Object body, {int status = 200}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response
        ..statusCode = status
        ..write(jsonEncode(body));
      await request.response.close();
    });
    return server;
  }

  test('chưa start thì không nghe gì, các lệnh không làm gì', () async {
    expect(await repo.announce(), const Ok<void>(null));
    expect(await repo.sweep(), const Ok<void>(null));
    expect(await repo.stop(), const Ok<void>(null));
    expect(await repo.updateSettings(settings), const Ok<void>(null));

    shout(await outsider(), 'hello');
    await settle();
    expect(seen, isEmpty);
  });

  test(
    'start thì báo thiết bị nghe thấy, lời chào lại mang nền tảng máy',
    () async {
      expect(
        await repo.start(settings, servicePort: 45711),
        const Ok<void>(null),
      );
      final socket = await outsider();
      final replies = <Map<String, dynamic>>[];
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final packet = socket.receive();
        if (packet == null) return;
        replies.add(
          jsonDecode(utf8.decode(packet.data)) as Map<String, dynamic>,
        );
      });

      shout(socket, 'hello');
      await settle();

      expect(seen.single.left, isFalse);
      expect(seen.single.peer.seenAt, start);
      expect(replies.single['platform'], 'android');
      expect(replies.single['port'], 45711);
    },
  );

  test('gói "bye" thành PeerSighting(left: true)', () async {
    await repo.start(settings, servicePort: 45711);
    shout(await outsider(), 'bye');
    await settle();

    expect(seen.single.left, isTrue);
  });

  test('updateSettings đổi tên được chào từ đó về sau', () async {
    await repo.start(settings, servicePort: 45711);
    await repo.updateSettings(settings.copyWith(deviceName: 'Tên mới'));
    final socket = await outsider();
    final names = <Object?>[];
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final packet = socket.receive();
      if (packet == null) return;
      names.add((jsonDecode(utf8.decode(packet.data)) as Map)['name']);
    });

    shout(socket, 'hello');
    await settle();

    expect(names, ['Tên mới']);
  });

  test('stream sống qua stop rồi start lại', () async {
    await repo.start(settings, servicePort: 45711);
    expect(await repo.stop(), const Ok<void>(null));
    await repo.start(settings, servicePort: 45711);

    shout(await outsider(), 'hello');
    await settle();

    expect(seen, hasLength(1));
  });

  test('probe hỏi GET /info, giờ thấy lấy từ Clock', () async {
    final server = await infoServer({
      'id': 'pc',
      'name': 'Máy tính',
      'platform': 'windows',
    });

    final peer = (await repo.probe('127.0.0.1:${server.port}')).valueOrNull;

    expect(
      peer,
      Peer(
        id: 'pc',
        name: 'Máy tính',
        platform: 'windows',
        address: '127.0.0.1',
        port: server.port,
        seenAt: start,
      ),
    );
  });

  test('probe: thiếu trường thì lấy mục và host thay', () async {
    final server = await infoServer(<String, Object?>{});
    final entry = '127.0.0.1:${server.port}';

    final peer = (await repo.probe(entry)).valueOrNull!;

    expect(peer.id, entry);
    expect(peer.name, '127.0.0.1');
    expect(peer.platform, 'other');
  });

  test(
    'probe không có ai trả lời, trả lỗi, hay mục hỏng thì Ok(null)',
    () async {
      // Một cổng vừa đóng: không ai nghe.
      final closed = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close(force: true);
      expect(await repo.probe('127.0.0.1:$port'), const Ok<Peer?>(null));

      final failing = await infoServer({'id': 'x'}, status: 500);
      expect(
        await repo.probe('127.0.0.1:${failing.port}'),
        const Ok<Peer?>(null),
      );

      final notJson = await infoServer('chuỗi');
      expect(
        await repo.probe('127.0.0.1:${notJson.port}'),
        const Ok<Peer?>(null),
      );

      expect(await repo.probe('khong-co-cong'), const Ok<Peer?>(null));
    },
  );

  test('localAddress lấy từ máy', () async {
    expect(await repo.localAddress(), const Ok('10.1.2.3'));
  });
}
