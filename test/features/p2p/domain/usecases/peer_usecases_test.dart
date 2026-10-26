import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/core/domain/usecase.dart';
import 'package:event_notice/features/p2p/domain/entities/peer.dart';
import 'package:event_notice/features/p2p/domain/usecases/add_manual_peer.dart';
import 'package:event_notice/features/p2p/domain/usecases/get_local_address.dart';
import 'package:event_notice/features/p2p/domain/usecases/probe_manual_peers.dart';
import 'package:event_notice/features/p2p/domain/usecases/refresh_peers.dart';
import 'package:event_notice/features/p2p/domain/usecases/remove_manual_peer.dart';
import 'package:event_notice/features/p2p/domain/usecases/start_p2p.dart';
import 'package:event_notice/features/p2p/domain/usecases/stop_p2p.dart';
import 'package:event_notice/features/p2p/domain/usecases/watch_peer_sightings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

const _socket = NetworkFailure('port taken');
const _disk = StorageFailure('disk');

void main() {
  late InMemoryP2pSettingsRepository settings;
  late FakeTransferRepository transfers;
  late FakePeerRepository peers;

  setUp(() {
    settings = InMemoryP2pSettingsRepository();
    transfers = FakeTransferRepository();
    peers = FakePeerRepository();
  });

  group('StartP2p', () {
    test('mở server trước, rồi dò tìm quảng bá đúng cổng server', () async {
      transfers.port = 45702;
      final result = await StartP2p(settings, transfers, peers)(
        const NoParams(),
      );
      expect(result.valueOrNull, 45702);
      expect(transfers.startedWith, settings.current);
      expect(peers.startedWith, settings.current);
      expect(peers.servicePort, 45702);
    });

    test('thứ tự: server trước, dò tìm sau', () async {
      final log = <String>[];
      await StartP2p(
        settings,
        FakeTransferRepository(log: log),
        FakePeerRepository(log: log),
      )(const NoParams());
      expect(log, ['transfers.start', 'peers.start']);
    });

    test('không mở được server thì không dò tìm', () async {
      transfers.failures['start'] = _socket;
      final result = await StartP2p(settings, transfers, peers)(
        const NoParams(),
      );
      expect(result.failureOrNull, _socket);
      expect(peers.calls, isEmpty);
    });

    test('dò tìm hỏng thì đóng server lại, không để dở dang', () async {
      peers.failures['start'] = _socket;
      final result = await StartP2p(settings, transfers, peers)(
        const NoParams(),
      );
      expect(result.failureOrNull, _socket);
      expect(transfers.calls, ['start', 'stop']);
    });
  });

  group('StopP2p', () {
    test('chào tạm biệt và tắt dò tìm rồi mới đóng server', () async {
      final log = <String>[];
      final result = await StopP2p(
        FakeTransferRepository(log: log),
        FakePeerRepository(log: log),
      )(const NoParams());
      expect(result.isOk, isTrue);
      expect(log, ['peers.stop', 'transfers.stop']);
    });

    test('một bên lỗi vẫn tắt bên còn lại, trả lỗi đầu tiên', () async {
      peers.failures['stop'] = _socket;
      final result = await StopP2p(transfers, peers)(const NoParams());
      expect(result.failureOrNull, _socket);
      expect(transfers.calls, ['stop']);
    });
  });

  group('AddManualPeer', () {
    test('chữ không phải địa chỉ thì không hỏi mạng', () async {
      final result = await AddManualPeer(settings, peers)('may tinh cua toi');
      expect(result.valueOrNull, isA<ManualPeerInvalid>());
      expect(peers.calls, isEmpty);
    });

    test('không ai trả lời thì báo lại mục đã chuẩn hoá, không lưu', () async {
      final result = await AddManualPeer(settings, peers)('172.28.0.50');
      final outcome = result.valueOrNull;
      expect(outcome, isA<ManualPeerUnreachable>());
      expect((outcome as ManualPeerUnreachable).entry, '172.28.0.50:45700');
      expect(peers.calls, ['probe 172.28.0.50:45700']);
      expect(settings.saves, 0);
    });

    test('trả lời thì lưu mục, chỉ một lần', () async {
      peers.answers['172.28.0.50:45701'] = peer('pc', address: '172.28.0.50');
      final add = AddManualPeer(settings, peers);

      final first = (await add(' 172.28.0.50:45701 ')).valueOrNull;
      expect(first, isA<ManualPeerAdded>());
      expect((first as ManualPeerAdded).entry, '172.28.0.50:45701');
      expect(first.peer.id, 'pc');
      expect(settings.current.manualPeers, ['172.28.0.50:45701']);

      await add('172.28.0.50:45701');
      expect(settings.current.manualPeers, ['172.28.0.50:45701']);
      expect(settings.saves, 1);
    });

    test('lưu lỗi thì trả lỗi', () async {
      peers.answers['172.28.0.50:45700'] = peer('pc');
      settings.saveFailure = _disk;
      final result = await AddManualPeer(settings, peers)('172.28.0.50');
      expect(result.failureOrNull, _disk);
    });
  });

  test('RemoveManualPeer bỏ đúng mục và lưu lại', () async {
    settings.current = settings.current.copyWith(
      manualPeers: const ['10.0.0.2:45700', '172.28.0.50:45700'],
    );
    final result = await RemoveManualPeer(settings)('10.0.0.2:45700');
    expect(result.valueOrNull?.manualPeers, ['172.28.0.50:45700']);
    expect(settings.current.manualPeers, ['172.28.0.50:45700']);
  });

  group('ProbeManualPeers', () {
    test('hỏi lần lượt từng mục, theo thứ tự đã lưu', () async {
      settings.current = settings.current.copyWith(
        manualPeers: const ['10.0.0.2:45700', '172.28.0.50:45700'],
      );
      final pc = peer('pc', address: '172.28.0.50');
      peers.answers['172.28.0.50:45700'] = pc;
      peers.failures['probe 10.0.0.2:45700'] = _socket;

      final result = await ProbeManualPeers(settings, peers)(const NoParams());
      expect(result.valueOrNull, <String, Peer?>{
        '10.0.0.2:45700': null,
        '172.28.0.50:45700': pc,
      });
      expect(result.valueOrNull!.keys, ['10.0.0.2:45700', '172.28.0.50:45700']);
    });

    test('không có mục nào thì không hỏi ai', () async {
      final result = await ProbeManualPeers(settings, peers)(const NoParams());
      expect(result.valueOrNull, isEmpty);
      expect(peers.calls, isEmpty);
    });
  });

  group('RefreshPeers', () {
    test('quảng bá, hỏi lại máy thêm tay, rồi mới quét cả dải', () async {
      settings.current = settings.current.copyWith(
        manualPeers: const ['172.28.0.50:45700'],
      );
      final refresh = RefreshPeers(peers, ProbeManualPeers(settings, peers));
      final result = await refresh(const NoParams());
      expect(result.valueOrNull, {'172.28.0.50:45700': null});
      expect(peers.calls, ['announce', 'probe 172.28.0.50:45700', 'sweep']);
    });

    test('quảng bá lỗi vẫn hỏi và quét tiếp', () async {
      peers.failures['announce'] = _socket;
      final refresh = RefreshPeers(peers, ProbeManualPeers(settings, peers));
      expect((await refresh(const NoParams())).isOk, isTrue);
      expect(peers.calls, ['announce', 'sweep']);
    });
  });

  test('WatchPeerSightings chuyển nguyên những gì dò tìm nghe được', () async {
    final stream = (await WatchPeerSightings(peers)(
      const NoParams(),
    )).valueOrNull!;
    final heard = <PeerSighting>[];
    final sub = stream.listen(heard.add);
    peers.hear(PeerSighting(peer: peer('phone')));
    peers.hear(PeerSighting(peer: peer('phone'), left: true));
    await sub.cancel();
    expect(heard.map((s) => s.left), [false, true]);
  });

  test('GetLocalAddress hỏi repository', () async {
    final result = await GetLocalAddress(peers)(const NoParams());
    expect(result, const Ok('192.168.1.10'));
  });
}
