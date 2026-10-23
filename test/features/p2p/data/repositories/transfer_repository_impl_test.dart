import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/features/p2p/data/datasources/file_sender.dart';
import 'package:event_notice/features/p2p/data/datasources/public_files.dart';
import 'package:event_notice/features/p2p/data/repositories/transfer_repository_impl.dart';
import 'package:event_notice/features/p2p/domain/entities/outgoing_file.dart';
import 'package:event_notice/features/p2p/domain/entities/p2p_settings.dart';
import 'package:event_notice/features/p2p/domain/entities/peer.dart';
import 'package:event_notice/features/p2p/domain/entities/save_location.dart';
import 'package:event_notice/features/p2p/domain/entities/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

/// Bigger than the HTTP client's output buffer, so each chunk goes out at
/// once instead of waiting for more.
const _chunk = 64 * 1024;

/// Two repositories on loopback, each on any free port: [phone] sends,
/// [pc] receives.
void main() {
  late Directory inbox;
  late Directory outbox;
  late FakeClock clock;
  late TransferRepositoryImpl pc;
  late TransferRepositoryImpl phone;
  late List<Transfer> received;
  late List<Transfer> sent;

  final pcSettings = P2pSettings(deviceId: 'pc', deviceName: 'Máy tính');
  final phoneSettings = P2pSettings(
    deviceId: 'phone',
    deviceName: 'Điện thoại của Felix',
  );

  TransferRepositoryImpl repo({
    PublicFiles? publicFiles,
    Duration offerTimeout = const Duration(seconds: 90),
  }) => TransferRepositoryImpl(
    clock,
    device: const FakeLocalDevice(),
    saveFolder: FixedSaveFolder(inbox),
    publicFiles: publicFiles ?? PublicFiles(isAndroid: false),
    basePort: 0,
    offerTimeout: offerTimeout,
  );

  setUp(() async {
    inbox = await Directory.systemTemp.createTemp('p2p-repo-in');
    outbox = await Directory.systemTemp.createTemp('p2p-repo-out');
    clock = FakeClock();
    pc = repo();
    phone = repo();
    received = [];
    sent = [];
    pc.updates.listen(received.add);
    phone.updates.listen(sent.add);
  });

  tearDown(() async {
    await pc.dispose();
    await phone.dispose();
    await inbox.delete(recursive: true);
    await outbox.delete(recursive: true);
  });

  /// Starts [pc] with [settings] and yields it as a peer of [phone].
  Future<Peer> startPc([P2pSettings? settings]) async {
    final port = (await pc.start(settings ?? pcSettings)).valueOrNull!;
    await phone.start(phoneSettings);
    return Peer(
      id: 'pc',
      name: 'Máy tính',
      platform: 'windows',
      address: '127.0.0.1',
      port: port,
      seenAt: start,
    );
  }

  /// The id of the first offer waiting on [pc].
  Future<String> waitingOffer() async {
    await eventually(
      () => received.any((t) => t.state == TransferState.pending),
    );
    return received.firstWhere((t) => t.state == TransferState.pending).id;
  }

  /// A file whose bytes the test hands out one [StreamController.add] at a
  /// time.
  (OutgoingFile, StreamController<List<int>>) controlled(String name) {
    final bytes = StreamController<List<int>>();
    return (
      OutgoingFile(name: name, size: 1 << 20, open: () => bytes.stream),
      bytes,
    );
  }

  test('chưa start thì send trả Err', () async {
    final result = await phone.send(
      peer: Peer(
        id: 'x',
        name: 'x',
        platform: 'windows',
        address: '127.0.0.1',
        port: 1,
        seenAt: start,
      ),
      file: outgoingFromFile(makeFile(outbox, 'a.txt', 4)),
    );
    expect(result.isErr, isTrue);
    expect(sent, isEmpty);
  });

  test('start lần hai trả lại đúng cổng đang mở', () async {
    final first = (await pc.start(pcSettings)).valueOrNull!;
    expect(await pc.start(pcSettings), Ok(first));
  });

  test('tự nhận: gửi xong tệp nằm nguyên vẹn, hai bên báo đủ', () async {
    final peer = await startPc(pcSettings.copyWith(autoAccept: true));
    final source = makeFile(outbox, 'ảnh.jpg', 300000);

    final result = (await phone.send(
      peer: peer,
      file: outgoingFromFile(source),
    )).valueOrNull!;

    expect(result.state, TransferState.done);
    expect(result.transferred, 300000);
    expect(
      result.id,
      'out-${start.microsecondsSinceEpoch}-${'ảnh.jpg'.hashCode}',
    );
    expect(result.startedAt, start);
    expect(result.peerName, 'Máy tính');
    expect(result.peerId, 'pc');
    expect(result.direction, TransferDirection.send);
    expect(sent.first.state, TransferState.running);
    expect(sent.first.transferred, 0);
    // The final snapshot reaches listeners right after send returns.
    await eventually(() => sent.last == result);

    await eventually(() => received.isNotEmpty && !received.last.isActive);
    // Tự nhận thì không bao giờ hiện ở dạng lời mời.
    expect(
      received.map((t) => t.state),
      isNot(contains(TransferState.pending)),
    );
    final done = received.last;
    expect(done.state, TransferState.done);
    expect(done.peerName, 'Điện thoại của Felix');
    expect(done.id, 'in-${start.microsecondsSinceEpoch}-0');
    final path = '${inbox.path}${Platform.pathSeparator}ảnh.jpg';
    expect(done.savedPath, path);
    expect(File(path).readAsBytesSync(), source.readAsBytesSync());
  });

  test('lời mời chờ trả lời, nhận thì tệp về', () async {
    final peer = await startPc();
    final sending = phone.send(
      peer: peer,
      file: outgoingFromFile(makeFile(outbox, 'a.txt', 64)),
    );

    final id = await waitingOffer();
    expect(received.first.state, TransferState.pending);
    expect(await pc.respond(id, accept: true), const Ok<void>(null));

    expect((await sending).valueOrNull!.state, TransferState.done);
    await eventually(() => !received.last.isActive);
    expect(received.last.state, TransferState.done);
    expect(namesIn(inbox), ['a.txt']);
  });

  test(
    'từ chối: máy gửi thấy rejectedByPeer, máy nhận thấy declined',
    () async {
      final peer = await startPc();
      final sending = phone.send(
        peer: peer,
        file: outgoingFromFile(makeFile(outbox, 'a.txt', 64)),
      );

      await pc.respond(await waitingOffer(), accept: false);

      final result = (await sending).valueOrNull!;
      expect(result.state, TransferState.failed);
      expect(result.problem, TransferProblem.rejectedByPeer);
      await eventually(() => !received.last.isActive);
      expect(received.last.state, TransferState.cancelled);
      expect(received.last.problem, TransferProblem.declined);
      expect(inbox.listSync(), isEmpty);
    },
  );

  test('trả lời id không phải lời mời thì bỏ qua', () async {
    expect(await pc.respond('khong-co', accept: true), const Ok<void>(null));
    expect(await pc.cancel('khong-co'), const Ok<void>(null));
  });

  test('không ai trả lời trong offerTimeout thì offerExpired', () async {
    await pc.dispose();
    pc = repo(offerTimeout: const Duration(milliseconds: 100));
    received.clear();
    pc.updates.listen(received.add);
    final peer = await startPc();

    final result = (await phone.send(
      peer: peer,
      file: outgoingFromFile(makeFile(outbox, 'a.txt', 64)),
    )).valueOrNull!;

    expect(result.problem, TransferProblem.rejectedByPeer);
    await eventually(() => !received.last.isActive);
    expect(received.last.state, TransferState.cancelled);
    expect(received.last.problem, TransferProblem.offerExpired);
  });

  test('huỷ lời mời đang chờ thì declined', () async {
    final peer = await startPc();
    final sending = phone.send(
      peer: peer,
      file: outgoingFromFile(makeFile(outbox, 'a.txt', 64)),
    );

    await pc.cancel(await waitingOffer());

    expect(
      (await sending).valueOrNull!.problem,
      TransferProblem.rejectedByPeer,
    );
    await eventually(() => !received.last.isActive);
    expect(received.last.problem, TransferProblem.declined);
  });

  test('stop khi có lời mời đang chờ thì declined', () async {
    final peer = await startPc();
    final sending = phone.send(
      peer: peer,
      file: outgoingFromFile(makeFile(outbox, 'a.txt', 64)),
    );
    await waitingOffer();

    expect(await pc.stop(), const Ok<void>(null));

    await eventually(() => !received.last.isActive);
    expect(received.last.state, TransferState.cancelled);
    expect(received.last.problem, TransferProblem.declined);
    expect((await sending).valueOrNull!.state, TransferState.failed);
  });

  test('máy gửi huỷ khi đang chạy: cancelled, bên nhận dọn sạch', () async {
    final peer = await startPc(pcSettings.copyWith(autoAccept: true));
    final (file, bytes) = controlled('dai.bin');
    final sending = phone.send(peer: peer, file: file);

    bytes.add(List.filled(_chunk, 1));
    await eventually(() => received.any((t) => t.transferred > 0));
    await phone.cancel(sent.last.id);
    bytes.add(List.filled(_chunk, 2));

    final result = (await sending).valueOrNull!;
    expect(result.state, TransferState.cancelled);
    expect(result.problem, TransferProblem.cancelled);
    expect(result.problemDetail, isNull);
    await eventually(() => !received.last.isActive);
    expect(inbox.listSync(), isEmpty);
    await bytes.close();
  });

  test('stop khi đang nhận: cancelled, không để lại .part', () async {
    final peer = await startPc(pcSettings.copyWith(autoAccept: true));
    final (file, bytes) = controlled('dai.bin');
    final sending = phone.send(peer: peer, file: file);

    bytes.add(List.filled(_chunk, 1));
    await eventually(() => received.any((t) => t.transferred > 0));
    await pc.stop();

    await eventually(() => !received.last.isActive);
    expect(received.last.state, TransferState.cancelled);
    expect(received.last.problem, TransferProblem.cancelled);
    expect(inbox.listSync(), isEmpty);
    unawaited(bytes.close());
    expect((await sending).valueOrNull!.state, TransferState.failed);
  });

  test('stop khi đang gửi: lượt gửi kết thúc cancelled', () async {
    final peer = await startPc(pcSettings.copyWith(autoAccept: true));
    final (file, bytes) = controlled('dai.bin');
    final sending = phone.send(peer: peer, file: file);

    bytes.add(List.filled(_chunk, 1));
    await eventually(() => sent.any((t) => t.transferred > 0));
    await phone.stop();
    bytes.add(List.filled(_chunk, 2));

    expect((await sending).valueOrNull!.problem, TransferProblem.cancelled);
    await bytes.close();
    // Đã tắt thì không gửi được nữa.
    expect(
      (await phone.send(
        peer: peer,
        file: outgoingFromFile(makeFile(outbox, 'b', 1)),
      )).isErr,
      isTrue,
    );
  });

  test('máy kia không mở cổng thì unreachable', () async {
    await phone.start(phoneSettings);
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close();

    final result = (await phone.send(
      peer: Peer(
        id: 'x',
        name: 'x',
        platform: 'windows',
        address: '127.0.0.1',
        port: port,
        seenAt: start,
      ),
      file: outgoingFromFile(makeFile(outbox, 'a.txt', 4)),
    )).valueOrNull!;

    expect(result.state, TransferState.failed);
    expect(result.problem, TransferProblem.unreachable);
  });

  test(
    'updateSettings: tên mới ở /info và trong lượt gửi, tự nhận bật ngay',
    () async {
      final peer = await startPc();
      await pc.updateSettings(
        pcSettings.copyWith(deviceName: 'Tên mới', autoAccept: true),
      );
      await phone.updateSettings(phoneSettings.copyWith(deviceName: 'ĐT mới'));

      final client = HttpClient();
      final request = await client.getUrl(peer.uri('/info'));
      final response = await request.close();
      final body = jsonDecode(await response.transform(utf8.decoder).join());
      client.close();
      expect(body, {'id': 'pc', 'name': 'Tên mới', 'platform': 'windows'});

      final result = await phone.send(
        peer: peer,
        file: outgoingFromFile(makeFile(outbox, 'a.txt', 8)),
      );
      expect(result.valueOrNull!.state, TransferState.done);
      expect(received.first.peerName, 'ĐT mới');
    },
  );

  test('updates sống qua stop rồi start lại', () async {
    var peer = await startPc(pcSettings.copyWith(autoAccept: true));
    await pc.stop();
    peer = peer.copyWith(
      port: (await pc.start(pcSettings.copyWith(autoAccept: true))).valueOrNull,
    );

    await phone.send(
      peer: peer,
      file: outgoingFromFile(makeFile(outbox, 'a.txt', 8)),
    );

    await eventually(() => received.isNotEmpty && !received.last.isActive);
    expect(received.last.state, TransferState.done);
  });

  test('Android: tệp nhận được chuyển ra Download', () async {
    final download = await Directory.systemTemp.createTemp('p2p-download');
    addTearDown(() => download.delete(recursive: true));
    await pc.dispose();
    pc = repo(publicFiles: FakePublicFiles(download: download));
    received.clear();
    pc.updates.listen(received.add);
    final peer = await startPc(pcSettings.copyWith(autoAccept: true));

    await phone.send(
      peer: peer,
      file: outgoingFromFile(makeFile(outbox, 'bao-cao.docx', 32)),
    );

    await eventually(() => received.isNotEmpty && !received.last.isActive);
    expect(received.last.savedPath, 'Download/Trợ lý/bao-cao.docx');
    expect(received.last.savedUri, 'content://downloads/bao-cao.docx');
    expect(inbox.listSync(), isEmpty);
    expect(namesIn(download), ['bao-cao.docx']);
  });

  test(
    'saveLocation: thư mục riêng, mặc định, và Download trên Android',
    () async {
      final custom = '${inbox.path}${Platform.pathSeparator}rieng';
      expect(
        await pc.saveLocation(custom),
        Ok(SaveLocation(directory: custom)),
      );
      expect(Directory(custom).existsSync(), isTrue);
      expect(
        await pc.saveLocation(null),
        Ok(SaveLocation(directory: inbox.path)),
      );
      expect(
        await pc.saveLocation('  '),
        Ok(SaveLocation(directory: inbox.path)),
      );

      final android = repo(publicFiles: FakePublicFiles());
      addTearDown(android.dispose);
      final location = (await android.saveLocation(null)).valueOrNull!;
      expect(location.publicFolder, 'Download/Trợ lý');
      expect(location.label, 'Download/Trợ lý');
    },
  );

  test('mở tệp đã nhận và màn hình Tải xuống qua PublicFiles', () async {
    final files = FakePublicFiles();
    final android = repo(publicFiles: files);
    addTearDown(android.dispose);
    final transfer = Transfer(
      id: 'in-1',
      direction: TransferDirection.receive,
      fileName: 'a.jpg',
      peerName: 'Máy',
      startedAt: start,
      state: TransferState.done,
    );

    expect(await android.openReceived(transfer), const Ok(false));
    expect(
      await android.openReceived(
        transfer.copyWith(savedUri: 'content://downloads/1'),
      ),
      const Ok(true),
    );
    expect(files.opened, ['content://downloads/1']);
    expect(await android.openDownloads(), const Ok(true));

    // Ngoài Android thì không có gì để mở.
    expect(await pc.openDownloads(), const Ok(false));
    expect(
      await pc.openReceived(transfer.copyWith(savedUri: 'content://x')),
      const Ok(false),
    );
  });
}
