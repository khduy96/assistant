import 'dart:async';

import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/features/p2p/domain/entities/p2p_settings.dart';
import 'package:event_notice/features/p2p/domain/entities/peer.dart';
import 'package:event_notice/features/p2p/domain/entities/transfer.dart';
import 'package:event_notice/features/p2p/presentation/p2p_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/fakes.dart';
import 'fixture.dart';

void main() {
  late P2pFakes fakes;
  late P2pController controller;
  late int notified;

  P2pController make({P2pSettings? settings}) {
    if (settings != null) fakes.settings.current = settings;
    controller = controllerFor(fakes)..addListener(() => notified++);
    return controller;
  }

  setUp(() {
    fakes = P2pFakes();
    notified = 0;
  });

  tearDown(() => controller.dispose());

  P2pSettings settingsWith({
    bool enabled = true,
    List<String> manualPeers = const [],
  }) => P2pSettings(
    deviceId: 'dev-1',
    deviceName: 'Máy này',
    enabled: enabled,
    manualPeers: manualPeers,
  );

  group('init', () {
    test('loads the settings and starts when transfer was left on', () async {
      await make(
        settings: settingsWith(manualPeers: ['10.0.0.9:45700']),
      ).init();

      expect(controller.isReady, isTrue);
      expect(controller.deviceName, 'Máy này');
      expect(controller.deviceId, 'dev-1');
      expect(controller.isRunning, isTrue);
      expect(controller.isStarting, isFalse);
      expect(controller.port, 45701);
      expect(controller.localAddress, '192.168.1.10');
      expect(controller.error, isNull);
      await pumpEventQueue();
      expect(fakes.transfers.calls, contains('start'));
      expect(fakes.peers.calls, containsAll(['start', 'localAddress']));
      // The devices added by IP are asked right after starting.
      expect(fakes.peers.calls, contains('probe 10.0.0.9:45700'));
      expect(controller.saveLocationLabel, 'Downloads/Trợ lý');
    });

    test('stays off when transfer was left off', () async {
      await make(settings: settingsWith(enabled: false)).init();

      expect(controller.isReady, isTrue);
      expect(controller.isRunning, isFalse);
      expect(controller.port, isNull);
      expect(fakes.transfers.calls, isNot(contains('start')));
    });

    test('a second call does nothing', () async {
      make();
      await controller.init();
      await controller.init();

      expect(fakes.transfers.calls.where((c) => c == 'start'), hasLength(1));
    });

    test('a failed start is shown with its reason', () async {
      fakes.peers.failures['start'] = const NetworkFailure('cổng bận');
      await make().init();

      expect(controller.isRunning, isFalse);
      expect(controller.error, 'Không bật được: cổng bận');
      // StartP2p closes the server again.
      expect(fakes.transfers.calls, contains('stop'));
    });

    test('settings that cannot be read leave the tab not ready', () async {
      fakes.settings.loadFailure = const StorageFailure('đọc lỗi');
      await make().init();

      expect(controller.isReady, isFalse);
      expect(controller.failure, const StorageFailure('đọc lỗi'));
    });
  });

  group('switch', () {
    test('turning off says goodbye and forgets the devices', () async {
      await make().init();
      fakes.peers.hear(PeerSighting(peer: peer('a')));
      expect(controller.peers, hasLength(1));

      await controller.setEnabled(false);

      expect(controller.enabled, isFalse);
      expect(fakes.settings.current.enabled, isFalse);
      expect(controller.isRunning, isFalse);
      expect(controller.peers, isEmpty);
      expect(fakes.peers.calls, contains('stop'));
      expect(fakes.transfers.calls, contains('stop'));
    });

    test('turning on saves the choice and starts', () async {
      await make(settings: settingsWith(enabled: false)).init();

      await controller.setEnabled(true);

      expect(controller.enabled, isTrue);
      expect(controller.isRunning, isTrue);
    });

    test('a choice that cannot be saved changes nothing', () async {
      await make().init();
      fakes.settings.saveFailure = const StorageFailure('ghi lỗi');

      await controller.setEnabled(false);

      expect(controller.enabled, isTrue);
      expect(controller.isRunning, isTrue);
      expect(controller.failure, const StorageFailure('ghi lỗi'));
    });
  });

  group('settings', () {
    test('rename, auto-accept and save folder are kept', () async {
      await make().init();

      await controller.rename('  Máy bàn  ');
      await controller.setAutoAccept(true);
      await controller.setSaveDir('D:/Nhận');
      await pumpEventQueue();

      expect(controller.deviceName, 'Máy bàn');
      expect(controller.autoAccept, isTrue);
      expect(controller.saveDir, 'D:/Nhận');
      expect(controller.saveLocationLabel, 'D:/Nhận');
      expect(fakes.peers.calls, contains('announce'));

      await controller.setSaveDir(null);
      await pumpEventQueue();
      expect(controller.saveDir, isNull);
      expect(controller.saveLocationLabel, 'Downloads/Trợ lý');
    });

    test('currentSaveDir yields the folder in use', () async {
      await make(settings: settingsWith(enabled: false)).init();

      expect(await controller.currentSaveDir(), 'Downloads/Trợ lý');
    });
  });

  group('devices', () {
    test('sightings come and go, sorted by name', () async {
      await make().init();

      fakes.peers.hear(PeerSighting(peer: peer('b', name: 'bếp')));
      fakes.peers.hear(PeerSighting(peer: peer('a', name: 'Anh')));
      expect(controller.peers.map((p) => p.name), ['Anh', 'bếp']);

      fakes.peers.hear(PeerSighting(peer: peer('a', name: 'Anh'), left: true));
      expect(controller.peers.map((p) => p.name), ['bếp']);
    });

    test('nothing heard while off is kept', () async {
      await make(settings: settingsWith(enabled: false)).init();

      fakes.peers.hear(PeerSighting(peer: peer('a')));

      expect(controller.peers, isEmpty);
    });

    test('silent devices are swept every 5 seconds', () {
      fakeAsync((async) {
        unawaited(make().init());
        async.flushMicrotasks();
        fakes.peers.hear(PeerSighting(peer: peer('a')));
        final before = notified;

        fakes.clock.advance(const Duration(seconds: 16));
        async.elapse(const Duration(seconds: 5));

        expect(controller.peers, isEmpty);
        expect(notified, greaterThan(before));
      });
    });

    test('devices added by IP are asked again every 15 seconds', () {
      fakeAsync((async) {
        unawaited(
          make(settings: settingsWith(manualPeers: ['10.0.0.9:45700'])).init(),
        );
        async.flushMicrotasks();
        int probes() =>
            fakes.peers.calls.where((c) => c == 'probe 10.0.0.9:45700').length;
        expect(probes(), 1);

        async.elapse(const Duration(seconds: 14));
        expect(probes(), 1);
        async.elapse(const Duration(seconds: 1));
        expect(probes(), 2);
        async.elapse(const Duration(seconds: 15));
        expect(probes(), 3);

        controller.setEnabled(false);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 30));
        expect(probes(), 3);
      });
    });

    test('a device added by IP shows whether it answers', () async {
      final kitchen = peer('k', name: 'Bếp', address: '10.0.0.9');
      fakes.peers.answers['10.0.0.9:45700'] = kitchen;
      await make(
        settings: settingsWith(manualPeers: ['10.0.0.9:45700']),
      ).init();
      await pumpEventQueue();

      expect(controller.manualEntries, ['10.0.0.9:45700']);
      expect(controller.manualPeer('10.0.0.9:45700'), kitchen);

      fakes.peers.answers.clear();
      await controller.pingManual();
      expect(controller.manualPeer('10.0.0.9:45700'), isNull);
    });

    test(
      'refresh announces, asks the devices added by IP and sweeps',
      () async {
        await make().init();
        fakes.peers.calls.clear();

        await controller.refresh();

        expect(fakes.peers.calls, ['announce', 'sweep']);
      },
    );
  });

  group('add by IP', () {
    test('a bad address says how it should look', () async {
      await make().init();

      expect(
        await controller.addManualPeer('10.0.0.9:99999'),
        'Địa chỉ không hợp lệ. Ví dụ: 172.28.0.50',
      );
    });

    test('nobody answering says what to check', () async {
      await make().init();

      expect(
        await controller.addManualPeer('10.0.0.9'),
        'Không nối được tới 10.0.0.9:45700. Máy kia đã mở app và bật truyền '
        'tệp chưa? Tường lửa của máy đó có cho phép không?',
      );
      expect(controller.manualEntries, isEmpty);
    });

    test('a device that answers is listed and saved', () async {
      final kitchen = peer('k', name: 'Bếp', address: '10.0.0.9');
      fakes.peers.answers['10.0.0.9:45700'] = kitchen;
      await make().init();

      expect(await controller.addManualPeer(' 10.0.0.9 '), isNull);

      expect(controller.manualEntries, ['10.0.0.9:45700']);
      expect(controller.manualPeer('10.0.0.9:45700'), kitchen);
      expect(fakes.settings.current.manualPeers, ['10.0.0.9:45700']);
    });

    test('removing forgets the entry', () async {
      fakes.peers.answers['10.0.0.9:45700'] = peer('k');
      await make(
        settings: settingsWith(manualPeers: ['10.0.0.9:45700']),
      ).init();
      await pumpEventQueue();

      await controller.removeManualPeer('10.0.0.9:45700');

      expect(controller.manualEntries, isEmpty);
      expect(controller.manualPeer('10.0.0.9:45700'), isNull);
      expect(fakes.settings.current.manualPeers, isEmpty);
    });
  });

  group('transfers', () {
    test('snapshots build the list; offers are kept apart', () async {
      await make().init();

      fakes.transfers.emit(transfer('out-1'));
      fakes.transfers.emit(
        transfer(
          'in-1',
          direction: TransferDirection.receive,
          state: TransferState.pending,
        ),
      );

      expect(controller.transfers.map((t) => t.id), ['in-1', 'out-1']);
      expect(controller.pendingOffers.map((t) => t.id), ['in-1']);
      expect(controller.history.map((t) => t.id), ['out-1']);
      expect(controller.activeCount, 2);
    });

    test(
      'progress redraws at most every 120 ms; the end always does',
      () async {
        await make().init();
        fakes.transfers.emit(transfer('out-1'));
        var before = notified;

        fakes.clock.advance(const Duration(seconds: 1));
        fakes.transfers.emit(transfer('out-1', transferred: 10));
        fakes.clock.advance(const Duration(milliseconds: 50));
        fakes.transfers.emit(transfer('out-1', transferred: 20));
        expect(notified - before, 1);
        expect(controller.transfers.single.transferred, 20);

        fakes.clock.advance(const Duration(milliseconds: 70));
        fakes.transfers.emit(transfer('out-1', transferred: 30));
        expect(notified - before, 2);

        before = notified;
        fakes.transfers.emit(
          transfer('out-1', transferred: 100, state: TransferState.done),
        );
        expect(notified - before, 1);
        expect(controller.transfers.single.state, TransferState.done);
      },
    );

    test('clearing the history keeps what is still going', () async {
      await make().init();
      fakes.transfers.emit(transfer('done', state: TransferState.done));
      fakes.transfers.emit(transfer('running'));

      controller.clearHistory();

      expect(controller.transfers.map((t) => t.id), ['running']);
    });

    test('answers, cancels and sends go to the repository', () async {
      await make().init();
      final offer = transfer('in-1', state: TransferState.pending);

      await controller.respond(offer, accept: true);
      await controller.cancel(transfer('out-1'));
      await controller.sendFiles(peer('a'), [outgoing('x.txt')]);

      expect(
        fakes.transfers.calls,
        containsAllInOrder([
          'respond in-1 true',
          'cancel out-1',
          'send x.txt to a',
        ]),
      );
      expect(controller.error, isNull);
    });

    test('sending while off says so', () async {
      await make(settings: settingsWith(enabled: false)).init();
      fakes.transfers.failures['send x.txt to a'] = const UnexpectedFailure(
        'not started',
      );

      await controller.sendFiles(peer('a'), [outgoing('x.txt')]);

      expect(controller.error, 'Chưa bật truyền tệp');
    });

    test('opening received files goes through the repository', () async {
      await make().init();
      final received = Transfer(
        id: 'in-1',
        direction: TransferDirection.receive,
        fileName: 'a.pdf',
        peerName: 'Máy kia',
        startedAt: seen,
        state: TransferState.done,
        savedUri: 'content://downloads/1',
      );

      expect(await controller.openReceived(received), isTrue);
      expect(await controller.openReceived(transfer('in-2')), isFalse);
      expect(await controller.openDownloads(), isTrue);
    });
  });

  test('disposing while on says goodbye', () async {
    await make().init();
    fakes.peers.calls.clear();

    controller.dispose();
    await pumpEventQueue();

    expect(fakes.peers.calls, contains('stop'));
    // tearDown disposes again; a fresh controller keeps that harmless.
    controller = controllerFor(fakes);
  });
}
