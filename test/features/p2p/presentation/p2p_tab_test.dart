import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/features/p2p/domain/entities/p2p_settings.dart';
import 'package:event_notice/features/p2p/domain/entities/peer.dart';
import 'package:event_notice/features/p2p/domain/entities/transfer.dart';
import 'package:event_notice/features/p2p/presentation/p2p_actions.dart';
import 'package:event_notice/features/p2p/presentation/p2p_controller.dart';
import 'package:event_notice/features/p2p/presentation/pages/p2p_tab.dart';
import 'package:event_notice/features/p2p/presentation/widgets/peer_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../domain/fakes.dart';
import 'fixture.dart';

void main() {
  late P2pFakes fakes;
  late FakeP2pFiles files;
  late P2pController controller;

  setUp(() {
    fakes = P2pFakes();
    files = FakeP2pFiles();
    controller = controllerFor(fakes);
  });

  /// Shows the tab, after [init] when set; transfer is on unless [enabled]
  /// is false.
  Future<void> pumpTab(
    WidgetTester tester, {
    bool init = true,
    bool enabled = true,
    List<String> manualPeers = const [],
  }) async {
    fakes.settings.current = P2pSettings(
      deviceId: 'dev-1',
      deviceName: 'Máy này',
      enabled: enabled,
      manualPeers: manualPeers,
    );
    if (init) await controller.init();
    await tester.pumpWidget(
      ChangeNotifierProvider<P2pController>.value(
        value: controller,
        child: MaterialApp(
          home: Scaffold(body: P2pTab(files: files)),
        ),
      ),
    );
    // The spinner of a tab still loading never settles.
    init ? await tester.pumpAndSettle() : await tester.pump();
  }

  /// Stops the controller's timers before the test ends.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Tuỳ chọn truyền tệp'));
    await tester.pumpAndSettle();
  }

  Transfer received({String? savedPath, String? savedUri}) => Transfer(
    id: 'in-1',
    direction: TransferDirection.receive,
    fileName: 'a.pdf',
    peerName: 'Máy kia',
    startedAt: seen,
    state: TransferState.done,
    savedPath: savedPath,
    savedUri: savedUri,
  );

  testWidgets('waits for the settings', (tester) async {
    await pumpTab(tester, init: false);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await finish(tester);
  });

  testWidgets('switched off', (tester) async {
    await pumpTab(tester, enabled: false);

    expect(find.text('Máy này'), findsOneWidget);
    expect(find.text('Đang tắt'), findsOneWidget);
    expect(
      find.text(
        'Đang tắt. Bật công tắc ở trên để thiết bị khác nhìn thấy máy này.',
      ),
      findsOneWidget,
    );
    expect(find.text('Tệp nhận được lưu ở: Downloads/Trợ lý'), findsOneWidget);
    expect(find.text('Chưa có tệp nào được gửi hay nhận.'), findsOneWidget);
    final add = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.add_link),
    );
    expect(add.onPressed, isNull);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('192.168.1.10:45701'), findsOneWidget);
    expect(fakes.settings.current.enabled, isTrue);
    await finish(tester);
  });

  testWidgets('a failed start shows why', (tester) async {
    fakes.peers.failures['start'] = const NetworkFailure('cổng bận');
    await pumpTab(tester);

    expect(find.text('Không bật được: cổng bận'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('devices on the network can be sent files', (tester) async {
    await pumpTab(tester);
    expect(find.textContaining('Chưa tự tìm thấy thiết bị nào.'), findsOne);

    fakes.peers.hear(PeerSighting(peer: peer('k', name: 'Bếp')));
    await tester.pump();
    expect(find.text('Bếp'), findsOneWidget);
    expect(find.text('192.168.1.20:45700'), findsOneWidget);

    files.picked = [outgoing('a.txt'), outgoing('b.txt')];
    await tester.tap(find.text('Gửi tệp'));
    await tester.pumpAndSettle();

    expect(files.calls, ['pickFiles Chọn tệp gửi sang Bếp']);
    expect(
      fakes.transfers.calls,
      containsAllInOrder(['send a.txt to k', 'send b.txt to k']),
    );
    await finish(tester);
  });

  testWidgets('an offer can be accepted or declined', (tester) async {
    await pumpTab(tester);

    fakes.transfers.emit(
      transfer(
        'in-1',
        direction: TransferDirection.receive,
        state: TransferState.pending,
        size: 1536,
      ),
    );
    await tester.pump();
    expect(find.text('Máy kia muốn gửi cho bạn'), findsOneWidget);
    expect(find.text('in-1.txt'), findsOneWidget);
    expect(find.text('1,5 KB'), findsOneWidget);
    // Offers are not in the transfer list.
    expect(find.text('Chưa có tệp nào được gửi hay nhận.'), findsOneWidget);

    await tester.tap(find.text('Nhận'));
    await tester.pump();
    await tester.tap(find.text('Từ chối'));
    await tester.pump();

    expect(
      fakes.transfers.calls,
      containsAllInOrder(['respond in-1 true', 'respond in-1 false']),
    );
    await finish(tester);
  });

  testWidgets('the transfer list', (tester) async {
    await pumpTab(tester);

    fakes.transfers.emit(
      transfer('out-1').copyWith(
        state: TransferState.failed,
        problem: TransferProblem.unreachable,
      ),
    );
    fakes.transfers.emit(transfer('out-2', size: 2048, transferred: 1024));
    await tester.pump();

    expect(
      find.text('Không nối được tới thiết bị kia (cùng Wi-Fi? tường lửa?)'),
      findsOneWidget,
    );
    expect(find.text('Đang gửi tới Máy kia — 1,0 KB / 2,0 KB'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.tap(find.byTooltip('Huỷ'));
    await tester.pump();
    expect(fakes.transfers.calls, contains('cancel out-2'));

    await tester.tap(find.text('Xoá lịch sử'));
    await tester.pump();
    expect(find.text('out-1.txt'), findsNothing);
    expect(find.text('out-2.txt'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('add a device by IP', (tester) async {
    await pumpTab(tester);

    Future<void> addByIp(String text) async {
      await tester.tap(find.byTooltip('Thêm thiết bị bằng IP'));
      await tester.pumpAndSettle();
      expect(find.text('Thêm thiết bị bằng IP'), findsWidgets);
      await tester.enterText(find.byType(TextField), text);
      await tester.tap(find.text('Nối thử'));
      await tester.pumpAndSettle();
    }

    await addByIp('10.0.0.9');
    expect(
      find.text(
        'Không nối được tới 10.0.0.9:45700. Máy kia đã mở app và bật truyền '
        'tệp chưa? Tường lửa của máy đó có cho phép không?',
      ),
      findsOneWidget,
    );

    fakes.peers.answers['10.0.0.9:45700'] = peer('k', name: 'Bếp');
    await addByIp('10.0.0.9');
    expect(
      find.text('Đã nối được, thiết bị nằm trong danh sách.'),
      findsOneWidget,
    );
    expect(find.text('Bếp'), findsOneWidget);
    expect(find.text('10.0.0.9:45700 — thêm bằng IP'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a device added by IP that does not answer', (tester) async {
    await pumpTab(tester, manualPeers: ['10.0.0.9:45700']);

    expect(find.text('10.0.0.9:45700'), findsOneWidget);
    expect(find.text('Không nối được — thêm bằng IP'), findsOneWidget);

    await tester.tap(find.byTooltip('Bỏ khỏi danh sách'));
    await tester.pumpAndSettle();
    expect(find.text('10.0.0.9:45700'), findsNothing);
    expect(fakes.settings.current.manualPeers, isEmpty);
    await finish(tester);
  });

  testWidgets('rename and auto-accept from the menu', (tester) async {
    await pumpTab(tester);

    await openMenu(tester);
    // Android (the test platform) cannot open folders.
    expect(find.text('Chọn thư mục lưu…'), findsNothing);
    await tester.tap(find.text('Đổi tên máy này'));
    await tester.pumpAndSettle();
    expect(find.text('Tên hiển thị của máy này'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Máy này'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Máy bàn');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(find.text('Máy bàn'), findsOneWidget);

    await openMenu(tester);
    await tester.tap(find.text('Tự nhận, không hỏi'));
    await tester.pumpAndSettle();
    expect(fakes.settings.current.autoAccept, isTrue);
    await finish(tester);
  });

  group('Android', () {
    testWidgets('opens the Downloads screen', (tester) async {
      await pumpTab(tester);

      await tester.tap(find.byTooltip('Mở màn hình Tải xuống'));
      await tester.pumpAndSettle();
      expect(fakes.transfers.calls, contains('openDownloads'));
      expect(find.byType(SnackBar), findsNothing);

      fakes.transfers.failures['openDownloads'] = const UnexpectedFailure('x');
      await tester.tap(find.byTooltip('Mở màn hình Tải xuống'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Máy không mở được màn hình Tải xuống. Tìm trong app Files, '
          'thư mục Downloads/Trợ lý.',
        ),
        findsOneWidget,
      );
      await finish(tester);
    });

    testWidgets('opens a received file', (tester) async {
      await pumpTab(tester);
      fakes.transfers.emit(received(savedUri: 'content://downloads/1'));
      await tester.pump();

      await tester.tap(find.byTooltip('Mở tệp'));
      await tester.pumpAndSettle();
      expect(fakes.transfers.calls, contains('openReceived in-1'));
      expect(find.byType(SnackBar), findsNothing);

      fakes.transfers.failures['openReceived in-1'] = const UnexpectedFailure(
        'x',
      );
      await tester.tap(find.byTooltip('Mở tệp'));
      await tester.pumpAndSettle();
      expect(
        find.text('Máy chưa có app nào mở được loại tệp này.'),
        findsOneWidget,
      );
      await finish(tester);
    });
  });

  group('desktop', () {
    final windows = TargetPlatformVariant.only(TargetPlatform.windows);

    testWidgets('chooses and opens the save folder', (tester) async {
      await pumpTab(tester);

      await openMenu(tester);
      expect(find.text('Dùng thư mục mặc định'), findsNothing);
      files.folder = 'D:/Nhận';
      await tester.tap(find.text('Chọn thư mục lưu…'));
      await tester.pumpAndSettle();
      expect(files.calls, ['pickDirectory Chọn thư mục lưu tệp nhận được']);
      expect(find.text('Tệp nhận được lưu ở: D:/Nhận'), findsOneWidget);

      await tester.tap(find.byTooltip('Mở thư mục này'));
      await tester.pumpAndSettle();
      expect(files.calls.last, 'open D:/Nhận select: false');

      files.openError = 'không có explorer';
      await tester.tap(find.byTooltip('Mở thư mục này'));
      await tester.pumpAndSettle();
      expect(
        find.text('Không mở được thư mục: không có explorer'),
        findsOneWidget,
      );

      await openMenu(tester);
      await tester.tap(find.text('Dùng thư mục mặc định'));
      await tester.pumpAndSettle();
      expect(controller.saveDir, isNull);
      expect(
        find.text('Tệp nhận được lưu ở: Downloads/Trợ lý'),
        findsOneWidget,
      );
      await finish(tester);
    }, variant: windows);

    testWidgets('points at a received file', (tester) async {
      await pumpTab(tester);
      fakes.transfers.emit(received(savedPath: 'C:/Tải về/a.pdf'));
      await tester.pump();

      await tester.tap(find.byTooltip('Mở thư mục chứa tệp'));
      await tester.pumpAndSettle();
      expect(files.calls.last, 'open C:/Tải về/a.pdf select: true');
      await finish(tester);
    }, variant: windows);

    testWidgets('files dropped on a device are sent, folders skipped', (
      tester,
    ) async {
      await pumpTab(tester);
      fakes.peers.hear(PeerSighting(peer: peer('k', name: 'Bếp')));
      await tester.pump();
      expect(find.byType(PeerDropZone), findsOneWidget);
      expect(
        find.byTooltip('Chọn tệp, hoặc kéo thả tệp vào thẻ này'),
        findsOneWidget,
      );
      final context = tester.element(find.byType(PeerTile));
      final bep = controller.peers.single;

      files.dropped = (files: [outgoing('a.txt')], skipped: 1);
      await sendDropped(context, bep, ['C:/a.txt', 'C:/thư mục']);
      await tester.pumpAndSettle();
      expect(files.calls.last, 'filesAt C:/a.txt,C:/thư mục');
      expect(find.text('Đã bỏ qua 1 thư mục, chỉ gửi các tệp.'), findsOne);
      expect(fakes.transfers.calls, contains('send a.txt to k'));

      files.dropped = (files: const [], skipped: 2);
      await sendDropped(context, bep, ['C:/x', 'C:/y']);
      await tester.pumpAndSettle();
      expect(
        find.text('Chưa gửi được thư mục — kéo từng tệp bên trong vào.'),
        findsOne,
      );
      await finish(tester);
    }, variant: windows);
  });
}
