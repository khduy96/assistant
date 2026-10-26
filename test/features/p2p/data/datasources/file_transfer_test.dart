import 'dart:convert';
import 'dart:io';

import 'package:event_notice/features/p2p/data/datasources/file_sender.dart';
import 'package:event_notice/features/p2p/data/datasources/file_server.dart';
import 'package:event_notice/features/p2p/data/datasources/public_files.dart';
import 'package:event_notice/features/p2p/data/models/transfer_job.dart';
import 'package:event_notice/features/p2p/domain/entities/p2p_settings.dart';
import 'package:event_notice/features/p2p/domain/entities/peer.dart';
import 'package:event_notice/features/p2p/domain/entities/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

/// The real path a file takes: [FileSender] pushes over HTTP to a
/// [FileServer] listening on loopback, on any free port.
void main() {
  late Directory inbox;
  late Directory outbox;
  late FileServer server;
  late List<TransferJob> offered;
  late List<TransferJob> finished;
  late FakeClock clock;
  var accept = true;

  FileServer makeServer({
    String id = 'pc',
    String name = 'Máy tính',
    Future<PublishedFile?> Function(File saved)? publish,
  }) => FileServer(
    settings: () =>
        P2pSettings(deviceId: id, deviceName: name, saveDir: inbox.path),
    platform: 'windows',
    clock: clock,
    onOffer: (job) async {
      offered.add(job);
      return accept;
    },
    onProgress: (_) {},
    onFinished: finished.add,
    publish: publish,
    basePort: 0,
  );

  setUp(() async {
    inbox = await Directory.systemTemp.createTemp('p2p-in');
    outbox = await Directory.systemTemp.createTemp('p2p-out');
    offered = [];
    finished = [];
    clock = FakeClock();
    accept = true;
    server = makeServer();
    await server.start();
  });

  tearDown(() async {
    await server.stop();
    await inbox.delete(recursive: true);
    await outbox.delete(recursive: true);
  });

  Peer peerAt(FileServer target) => Peer(
    id: 'pc',
    name: 'Máy tính',
    platform: 'windows',
    address: '127.0.0.1',
    port: target.port!,
    seenAt: start,
  );

  TransferJob outgoing(String name, int? size) => TransferJob(
    id: 't',
    direction: TransferDirection.send,
    fileName: name,
    peerName: 'Máy tính',
    size: size,
    startedAt: start,
  );

  FileSender sender() =>
      FileSender(deviceId: 'phone', deviceName: 'Điện thoại của Felix');

  test('gửi xong thì tệp nằm nguyên vẹn trong thư mục nhận', () async {
    final source = makeFile(outbox, 'ảnh nghỉ mát.jpg', 300000);
    final job = outgoing('ảnh nghỉ mát.jpg', source.lengthSync());
    var progress = 0;

    await sender().send(
      peer: peerAt(server),
      file: outgoingFromFile(source),
      job: job,
      onProgress: (_) => progress++,
    );

    final received = File(
      '${inbox.path}${Platform.pathSeparator}ảnh nghỉ mát.jpg',
    );
    expect(received.readAsBytesSync(), source.readAsBytesSync());
    expect(job.state, TransferState.done);
    expect(job.transferred, source.lengthSync());
    expect(progress, greaterThan(0));

    final offer = offered.single;
    // Tên máy gửi có dấu vẫn đọc được ở đầu nhận.
    expect(offer.peerName, 'Điện thoại của Felix');
    expect(offer.peerId, 'phone');
    expect(offer.size, 300000);
    expect(offer.direction, TransferDirection.receive);
    // Id và giờ bắt đầu lấy từ Clock.
    expect(offer.id, 'in-${start.microsecondsSinceEpoch}-0');
    expect(offer.startedAt, start);

    final done = finished.single;
    expect(done.state, TransferState.done);
    expect(done.savedPath, received.path);
    expect(done.transferred, 300000);
  });

  test('id nhận về tăng dần theo bộ đếm', () async {
    final source = makeFile(outbox, 'a.txt', 4);
    for (var i = 0; i < 2; i++) {
      await sender().send(
        peer: peerAt(server),
        file: outgoingFromFile(source),
        job: outgoing('a.txt', 4),
        onProgress: (_) {},
      );
    }
    expect(offered.map((j) => j.id), [
      'in-${start.microsecondsSinceEpoch}-0',
      'in-${start.microsecondsSinceEpoch}-1',
    ]);
  });

  test('GET /info khai đúng danh tính, đủ cho việc thêm bằng IP', () async {
    final client = HttpClient();
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/info'),
    );
    final response = await request.close();
    final body = jsonDecode(await response.transform(utf8.decoder).join());
    client.close();

    expect(response.statusCode, 200);
    expect(body, {'id': 'pc', 'name': 'Máy tính', 'platform': 'windows'});
  });

  test('đường dẫn lạ trả 404', () async {
    final client = HttpClient();
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/khac'),
    );
    final response = await request.close();
    await response.drain<void>();
    client.close();

    expect(response.statusCode, 404);
  });

  test('từ chối thì báo P2pRejected và không để lại tệp nào', () async {
    accept = false;
    final source = makeFile(outbox, 'tai-lieu.pdf', 2048);

    await expectLater(
      sender().send(
        peer: peerAt(server),
        file: outgoingFromFile(source),
        job: outgoing('tai-lieu.pdf', 2048),
        onProgress: (_) {},
      ),
      throwsA(isA<P2pRejected>()),
    );
    expect(inbox.listSync(), isEmpty);
    expect(finished.single.state, TransferState.cancelled);
    expect(finished.single.problem, TransferProblem.declined);
  });

  test('lời mời đã hết giờ thì giữ lý do offerExpired', () async {
    final expiring = FileServer(
      settings: () => P2pSettings(deviceId: 'pc', deviceName: 'Máy tính'),
      platform: 'windows',
      clock: clock,
      onOffer: (job) async {
        job.problem = TransferProblem.offerExpired;
        return false;
      },
      onProgress: (_) {},
      onFinished: finished.add,
      basePort: 0,
    );
    await expiring.start();
    addTearDown(expiring.stop);

    await expectLater(
      sender().send(
        peer: peerAt(expiring),
        file: outgoingFromFile(makeFile(outbox, 'x.txt', 8)),
        job: outgoing('x.txt', 8),
        onProgress: (_) {},
      ),
      throwsA(isA<P2pRejected>()),
    );
    expect(finished.single.problem, TransferProblem.offerExpired);
  });

  test('trùng tên thì thêm hậu tố, không đè tệp cũ', () async {
    final source = makeFile(outbox, 'ghi-chu.txt', 16);
    for (var i = 0; i < 2; i++) {
      await sender().send(
        peer: peerAt(server),
        file: outgoingFromFile(source),
        job: outgoing('ghi-chu.txt', 16),
        onProgress: (_) {},
      );
    }
    expect(namesIn(inbox), ['ghi-chu (1).txt', 'ghi-chu.txt']);
  });

  test('tên tệp độc hại không thoát ra khỏi thư mục nhận', () {
    expect(FileServer.sanitize('../../../etc/passwd'), isNot(contains('/')));
    expect(
      FileServer.sanitize(r'..\..\windows\system32'),
      isNot(contains(r'\')),
    );
    expect(FileServer.sanitize('   '), 'tep-nhan-duoc');
    expect(FileServer.sanitize('a:b*c?.txt'), 'a_b_c_.txt');
    expect(FileServer.sanitize('${'x' * 200}.txt').length, 120);
  });

  test('bước chuyển tiếp (Android: ra Download) đổi chỗ lưu đã báo', () async {
    final published = <String>[];
    final server2 = makeServer(
      id: 'phone',
      name: 'Điện thoại',
      publish: (saved) async {
        published.add(saved.path);
        await saved.delete();
        return PublishedFile(
          uri: 'content://downloads/42',
          path: 'Download/Trợ lý/${saved.uri.pathSegments.last}',
        );
      },
    );
    await server2.start();
    addTearDown(server2.stop);

    final job = outgoing('bao-cao.docx', 4096);
    await sender().send(
      peer: peerAt(server2),
      file: outgoingFromFile(makeFile(outbox, 'bao-cao.docx', 4096)),
      job: job,
      onProgress: (_) {},
    );

    expect(published, hasLength(1));
    // Bản tạm đã dọn, và chỗ lưu chỉ sang chỗ mới chứ không phải chỗ ghi tạm.
    expect(inbox.listSync(), isEmpty);
    expect(job.state, TransferState.done);
    expect(finished.single.savedPath, 'Download/Trợ lý/bao-cao.docx');
    expect(finished.single.savedUri, 'content://downloads/42');
  });

  test('huỷ giữa chừng: bên gửi ném P2pCancelled, bên nhận dọn sạch', () async {
    final source = makeFile(outbox, 'phim.mp4', 4 * 1024 * 1024);
    final job = outgoing('phim.mp4', source.lengthSync());

    await expectLater(
      sender().send(
        peer: peerAt(server),
        file: outgoingFromFile(source),
        job: job,
        // Vừa chạy được một khối là bấm huỷ.
        onProgress: (j) => j.cancelRequested = true,
      ),
      throwsA(isA<P2pCancelled>()),
    );
    // Cho bên nhận kịp thấy kết nối đứt rồi xoá tệp .part.
    await eventually(() => finished.isNotEmpty);
    expect(inbox.listSync(), isEmpty);
    expect(finished.single.state, TransferState.failed);
    expect(finished.single.problem, TransferProblem.failed);
  });

  test(
    'bên nhận huỷ giữa chừng: kết thúc cancelled, xoá phần đã ghi',
    () async {
      final receiving = FileServer(
        settings: () =>
            P2pSettings(deviceId: 'pc', deviceName: 'Máy', saveDir: inbox.path),
        platform: 'windows',
        clock: clock,
        onOffer: (_) async => true,
        onProgress: (job) {
          if (job.transferred > 0) job.cancelRequested = true;
        },
        onFinished: finished.add,
        basePort: 0,
      );
      await receiving.start();
      addTearDown(receiving.stop);

      await expectLater(
        sender().send(
          peer: peerAt(receiving),
          file: outgoingFromFile(makeFile(outbox, 'lon.bin', 4 * 1024 * 1024)),
          job: outgoing('lon.bin', 4 * 1024 * 1024),
          onProgress: (_) {},
        ),
        throwsA(anything),
      );
      await eventually(() => finished.isNotEmpty);
      expect(finished.single.state, TransferState.cancelled);
      expect(finished.single.problem, TransferProblem.cancelled);
      expect(inbox.listSync(), isEmpty);
    },
  );

  test('cổng đầu bị chiếm thì thử cổng kế tiếp', () async {
    final taken = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    addTearDown(taken.close);
    final next = FileServer(
      settings: () => P2pSettings(deviceId: 'pc', deviceName: 'Máy'),
      platform: 'windows',
      clock: clock,
      onOffer: (_) async => true,
      onProgress: (_) {},
      onFinished: (_) {},
      basePort: taken.port,
      portAttempts: 5,
    );
    try {
      await next.start();
    } on SocketException {
      // Các cổng sau cũng bị chiếm: hiếm, bỏ qua lần này.
      return;
    }
    addTearDown(next.stop);
    expect(next.port, greaterThan(taken.port));
    expect(next.port, lessThan(taken.port + 5));
  });

  test('hết số lần thử thì ném SocketException', () async {
    final taken = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    addTearDown(taken.close);
    final blocked = FileServer(
      settings: () => P2pSettings(deviceId: 'pc', deviceName: 'Máy'),
      platform: 'windows',
      clock: clock,
      onOffer: (_) async => true,
      onProgress: (_) {},
      onFinished: (_) {},
      basePort: taken.port,
      portAttempts: 1,
    );
    await expectLater(blocked.start(), throwsA(isA<SocketException>()));
    expect(blocked.isRunning, isFalse);
  });
}
