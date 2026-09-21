import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:event_notice/p2p/models/peer.dart';
import 'package:event_notice/p2p/models/transfer.dart';
import 'package:event_notice/p2p/services/file_sender.dart';
import 'package:event_notice/p2p/services/file_server.dart';
import 'package:event_notice/p2p/services/p2p_settings.dart';
import 'package:event_notice/p2p/services/public_files.dart';
import 'package:flutter_test/flutter_test.dart';

/// Chạy thử đúng con đường tệp đi trong thật: FileSender đẩy qua HTTP sang
/// FileServer đang nghe trên loopback.
void main() {
  late Directory inbox;
  late Directory outbox;
  late FileServer server;
  late List<TransferTask> offered;
  bool accept = true;

  setUp(() async {
    inbox = await Directory.systemTemp.createTemp('p2p-in');
    outbox = await Directory.systemTemp.createTemp('p2p-out');
    offered = [];
    accept = true;
    server = FileServer(
      settings: P2pSettings(
        deviceId: 'pc',
        deviceName: 'Máy tính',
        autoAccept: false,
        enabled: true,
        saveDir: inbox.path,
      ),
      onOffer: (task) async {
        offered.add(task);
        return accept;
      },
      onProgress: (_) {},
      onFinished: (_) {},
    );
    await server.start();
  });

  tearDown(() async {
    await server.stop();
    await inbox.delete(recursive: true);
    await outbox.delete(recursive: true);
  });

  Peer peerToServer() => Peer(
        id: 'pc',
        name: 'Máy tính',
        platform: 'windows',
        address: '127.0.0.1',
        port: server.port!,
        seenAt: DateTime.now(),
      );

  TransferTask outgoing(String name, int? size) => TransferTask(
        id: 't',
        direction: TransferDirection.send,
        fileName: name,
        peerName: 'Máy tính',
        size: size,
      );

  FileSender sender() =>
      FileSender(deviceId: 'phone', deviceName: 'Điện thoại của Felix');

  File makeFile(String name, int bytes) {
    final file = File('${outbox.path}${Platform.pathSeparator}$name');
    file.writeAsBytesSync(
        Uint8List.fromList(List.generate(bytes, (i) => i % 256)));
    return file;
  }

  test('gửi xong thì tệp nằm nguyên vẹn trong thư mục nhận', () async {
    final source = makeFile('ảnh nghỉ mát.jpg', 300000);
    final task = outgoing('ảnh nghỉ mát.jpg', source.lengthSync());

    await sender().send(
      peer: peerToServer(),
      file: OutgoingFile.fromFile(source),
      task: task,
      onProgress: (_) {},
    );

    final received = File('${inbox.path}${Platform.pathSeparator}ảnh nghỉ mát.jpg');
    expect(received.existsSync(), isTrue);
    expect(received.readAsBytesSync(), source.readAsBytesSync());
    expect(task.state, TransferState.done);
    expect(task.transferred, source.lengthSync());
    // Tên máy gửi có dấu vẫn đọc được ở đầu nhận.
    expect(offered.single.peerName, 'Điện thoại của Felix');
  });

  test('GET /info khai đúng danh tính, đủ cho việc thêm bằng IP', () async {
    final client = HttpClient();
    final request = await client
        .getUrl(Uri.parse('http://127.0.0.1:${server.port}/info'));
    final response = await request.close();
    final body = jsonDecode(await response.transform(utf8.decoder).join())
        as Map<String, dynamic>;
    client.close();

    expect(response.statusCode, 200);
    expect(body['id'], 'pc');
    expect(body['name'], 'Máy tính');
    expect(body['platform'], isNotEmpty);
  });

  test('từ chối thì báo lỗi và không để lại tệp nào', () async {
    accept = false;
    final source = makeFile('tai-lieu.pdf', 2048);

    await expectLater(
      sender().send(
        peer: peerToServer(),
        file: OutgoingFile.fromFile(source),
        task: outgoing('tai-lieu.pdf', 2048),
        onProgress: (_) {},
      ),
      throwsA(isA<P2pRejected>()),
    );
    expect(inbox.listSync(), isEmpty);
  });

  test('trùng tên thì thêm hậu tố, không đè tệp cũ', () async {
    final source = makeFile('ghi-chu.txt', 16);
    for (var i = 0; i < 2; i++) {
      await sender().send(
        peer: peerToServer(),
        file: OutgoingFile.fromFile(source),
        task: outgoing('ghi-chu.txt', 16),
        onProgress: (_) {},
      );
    }
    final names = inbox.listSync().map((e) => e.uri.pathSegments.last).toList()
      ..sort();
    expect(names, ['ghi-chu (1).txt', 'ghi-chu.txt']);
  });

  test('tên tệp độc hại không thoát ra khỏi thư mục nhận', () {
    expect(FileServer.sanitize('../../../etc/passwd'), isNot(contains('/')));
    expect(FileServer.sanitize(r'..\..\windows\system32'), isNot(contains(r'\')));
    expect(FileServer.sanitize('   '), 'tep-nhan-duoc');
  });

  test('bước chuyển tiếp (Android: ra Download) đổi chỗ lưu đã báo', () async {
    // Giả lập PublicFiles.publish: chép đi chỗ khác rồi xoá bản tạm.
    final published = <String>[];
    TransferTask? receivedTask;
    final server2 = FileServer(
      settings: P2pSettings(
        deviceId: 'phone',
        deviceName: 'Điện thoại',
        autoAccept: true,
        enabled: true,
        saveDir: inbox.path,
      ),
      onOffer: (_) async => true,
      onProgress: (_) {},
      onFinished: (t) => receivedTask = t,
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

    final source = makeFile('bao-cao.docx', 4096);
    final task = outgoing('bao-cao.docx', 4096);
    await sender().send(
      peer: Peer(
        id: 'phone',
        name: 'Điện thoại',
        platform: 'android',
        address: '127.0.0.1',
        port: server2.port!,
        seenAt: DateTime.now(),
      ),
      file: OutgoingFile.fromFile(source),
      task: task,
      onProgress: (_) {},
    );

    expect(published, hasLength(1));
    // Bản tạm đã dọn, và UI được chỉ sang chỗ mới chứ không phải chỗ ghi tạm.
    expect(inbox.listSync(), isEmpty);
    expect(task.state, TransferState.done);
    expect(receivedTask?.savedPath, 'Download/Trợ lý/bao-cao.docx');
    expect(receivedTask?.savedUri, 'content://downloads/42');
  });

  test('huỷ giữa chừng: bên nhận dọn sạch phần đã ghi', () async {
    final source = makeFile('phim.mp4', 4 * 1024 * 1024);
    final task = outgoing('phim.mp4', source.lengthSync());

    await expectLater(
      sender().send(
        peer: peerToServer(),
        file: OutgoingFile.fromFile(source),
        task: task,
        // Vừa chạy được một khối là bấm huỷ.
        onProgress: (t) => t.cancelRequested = true,
      ),
      throwsA(anything),
    );
    // Cho bên nhận kịp phát hiện kết nối đứt rồi xoá tệp .part.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(inbox.listSync(), isEmpty);
  });
}

