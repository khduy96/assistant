import 'dart:convert';
import 'dart:io';

import 'package:event_notice/app/di/bridges/p2p_files_bridge.dart';
import 'package:event_notice/app/di/injection.dart';
import 'package:event_notice/core/domain/clock.dart';
import 'package:event_notice/core/domain/id_generator.dart';
import 'package:event_notice/features/p2p/data/datasources/p2p_settings_local_data_source.dart';
import 'package:event_notice/features/p2p/data/datasources/public_files.dart';
import 'package:event_notice/features/p2p/data/repositories/p2p_settings_repository_impl.dart';
import 'package:event_notice/features/p2p/data/repositories/peer_repository_impl.dart';
import 'package:event_notice/features/p2p/data/repositories/transfer_repository_impl.dart';
import 'package:event_notice/features/p2p/domain/repositories/p2p_settings_repository.dart';
import 'package:event_notice/features/p2p/domain/repositories/peer_repository.dart';
import 'package:event_notice/features/p2p/domain/repositories/transfer_repository.dart';
import 'package:event_notice/features/p2p/domain/usecases/send_files.dart';
import 'package:event_notice/features/p2p/domain/usecases/start_p2p.dart';
import 'package:event_notice/features/p2p/p2p_injection.dart';
import 'package:event_notice/features/p2p/presentation/p2p_controller.dart';
import 'package:event_notice/features/p2p/presentation/p2p_files.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'data/fakes.dart';

void main() {
  late GetIt sl;

  setUp(() => sl = GetIt.asNewInstance());
  tearDown(() => sl.reset());

  group('configureDependencies', () {
    test(
      'đăng ký đủ P2P; một controller, repository mạng thấy dưới hai kiểu',
      () {
        configureDependencies(sl);

        expect(sl<P2pController>(), same(sl<P2pController>()));
        expect(sl<P2pSettingsRepository>(), isA<P2pSettingsRepositoryImpl>());
        expect(sl<PeerRepository>(), same(sl<PeerRepositoryImpl>()));
        expect(sl<TransferRepository>(), same(sl<TransferRepositoryImpl>()));
        expect(sl<P2pFiles>(), isA<P2pFilesBridge>());
      },
    );
  });

  group('registerP2p', () {
    late Directory dir;
    late String path;
    late SequentialIdGenerator ids;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('p2p_injection');
      addTearDown(() => dir.delete(recursive: true));
      path = '${dir.path}${Platform.pathSeparator}p2p.json';
      final inbox = Directory('${dir.path}${Platform.pathSeparator}inbox');

      sl
        ..registerSingleton<Clock>(FakeClock())
        ..registerSingleton<IdGenerator>(ids = SequentialIdGenerator());
      registerP2p(sl);
      // File trong thư mục tạm, cổng riêng cho test; phần còn lại giữ như
      // đăng ký.
      sl
        ..unregister<P2pSettingsLocalDataSource>()
        ..registerLazySingleton(() => P2pSettingsLocalDataSource(path: path))
        ..unregister<PeerRepositoryImpl>()
        ..registerLazySingleton(
          () => PeerRepositoryImpl(
            sl(),
            device: const FakeLocalDevice(),
            // Không trùng cổng thật và cổng của các test P2P khác.
            discoveryPort: 45699 + 444,
          ),
        )
        ..unregister<TransferRepositoryImpl>()
        ..registerLazySingleton(
          () => TransferRepositoryImpl(
            sl(),
            device: const FakeLocalDevice(),
            saveFolder: FixedSaveFolder(inbox),
            publicFiles: PublicFiles(isAndroid: false),
            basePort: 0,
          ),
        );
    });

    /// The registered controller, started; it and the network repositories
    /// are closed after the test, as the app shell does.
    Future<P2pController> started() async {
      final controller = sl<P2pController>();
      addTearDown(() async {
        controller.dispose();
        await sl<PeerRepositoryImpl>().dispose();
        await sl<TransferRepositoryImpl>().dispose();
      });
      await controller.init();
      return controller;
    }

    Map<String, dynamic> saved() =>
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

    test('use case dùng chung một repository mỗi loại', () {
      expect(sl<StartP2p>(), same(sl<StartP2p>()));
      expect(sl<SendFiles>(), same(sl<SendFiles>()));
      expect(sl<PeerRepository>(), same(sl<PeerRepositoryImpl>()));
      expect(sl<TransferRepository>(), same(sl<TransferRepositoryImpl>()));
    });

    test('p2p.json có sẵn: giữ deviceId và máy thêm tay; đổi tuỳ chọn thì '
        'ghi lại file', () async {
      File(path).writeAsStringSync(
        jsonEncode({
          'deviceId': 'may-cu',
          'deviceName': 'Laptop của Felix',
          'autoAccept': false,
          'enabled': false,
          'manualPeers': ['172.28.0.50:45700'],
        }),
      );

      final controller = await started();

      expect(controller.isReady, isTrue);
      expect(controller.deviceId, 'may-cu');
      expect(controller.deviceName, 'Laptop của Felix');
      expect(controller.manualEntries, ['172.28.0.50:45700']);
      // Đã tắt từ lần trước: không mở cổng nào.
      expect(controller.isRunning, isFalse);
      expect(ids.calls, 0);

      await controller.setAutoAccept(true);

      expect(controller.autoAccept, isTrue);
      expect(saved()['deviceId'], 'may-cu');
      expect(saved()['autoAccept'], isTrue);
      expect(saved()['manualPeers'], ['172.28.0.50:45700']);
    });

    test('chưa có p2p.json: id lấy từ IdGenerator; bật sẵn nên mở cổng, tắt '
        'thì đóng', () async {
      final controller = await started();

      expect(controller.deviceId, 'id-1');
      expect(saved()['deviceId'], 'id-1');
      expect(controller.isRunning, isTrue);
      expect(controller.port, isNotNull);
      expect(controller.localAddress, '192.168.1.5');

      await controller.setEnabled(false);

      expect(controller.isRunning, isFalse);
      expect(controller.port, isNull);
      expect(saved()['enabled'], isFalse);
    });
  });

  group('P2pFilesBridge', () {
    test('tệp kéo thả: thư mục và đường dẫn không tồn tại bị bỏ qua', () async {
      final dir = await Directory.systemTemp.createTemp('p2p_files');
      addTearDown(() => dir.delete(recursive: true));
      final file = makeFile(dir, 'ảnh.jpg', 300);
      final folder = Directory('${dir.path}${Platform.pathSeparator}thu-muc')
        ..createSync();

      final dropped = await const P2pFilesBridge().filesAt([
        folder.path,
        file.path,
        '${dir.path}${Platform.pathSeparator}khong-co.txt',
      ]);

      expect(dropped.skipped, 2);
      expect(dropped.files, hasLength(1));
      expect(dropped.files.single.name, 'ảnh.jpg');
      expect(dropped.files.single.size, 300);
      final bytes = await dropped.files.single.open().fold<List<int>>(
        [],
        (all, chunk) => all..addAll(chunk),
      );
      expect(bytes, file.readAsBytesSync());
    });
  });
}
