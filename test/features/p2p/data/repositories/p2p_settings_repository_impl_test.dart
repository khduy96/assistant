import 'dart:convert';
import 'dart:io';

import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/features/p2p/data/datasources/p2p_settings_local_data_source.dart';
import 'package:event_notice/features/p2p/data/repositories/p2p_settings_repository_impl.dart';
import 'package:event_notice/features/p2p/domain/entities/p2p_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

const _fixtures = 'test/features/p2p/data/fixtures';

void main() {
  late Directory dir;
  late String path;
  late SequentialIdGenerator ids;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('p2p_settings_repo_test');
    path = '${dir.path}/p2p.json';
    ids = SequentialIdGenerator();
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  P2pSettingsRepositoryImpl repo({String? at}) => P2pSettingsRepositoryImpl(
    P2pSettingsLocalDataSource(path: at ?? path),
    ids,
    device: const FakeLocalDevice(name: 'Máy thử'),
  );

  Future<Map<String, dynamic>> saved() async =>
      jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;

  test('p2p.json có sẵn: giữ deviceId và danh sách máy thêm tay', () async {
    await File('$_fixtures/p2p_full.json').copy(path);
    final before = await File(path).readAsString();

    final settings = (await repo().load()).valueOrNull!;

    expect(settings.deviceId, '5b0c1e7a-3f2d-4c55-9a51-0f7d2a6c9e11');
    expect(settings.manualPeers, ['172.28.0.50:45700', '192.168.1.9:45701']);
    expect(settings.deviceName, 'Laptop của Felix');
    expect(settings.autoAccept, isTrue);
    expect(settings.enabled, isFalse);
    expect(settings.saveDir, r'D:\Nhận');
    // Không sinh id mới, không ghi đè file.
    expect(ids.calls, 0);
    expect(await File(path).readAsString(), before);
  });

  test('ghi lại file có sẵn ra đúng nội dung cũ', () async {
    await File('$_fixtures/p2p_full.json').copy(path);
    final before = jsonDecode(await File(path).readAsString());
    final repository = repo();

    final settings = (await repository.load()).valueOrNull!;
    await repository.save(settings);

    expect(await saved(), before);
  });

  test('file cũ thiếu khoá: điền mặc định, giữ id và máy thêm tay', () async {
    await File('$_fixtures/p2p_old.json').copy(path);

    final settings = (await repo().load()).valueOrNull!;

    expect(settings.deviceId, 'c0ffee00-1111-4222-8333-444455556666');
    expect(settings.manualPeers, ['10.0.0.7:45700']);
    expect(settings.deviceName, 'Máy thử');
    expect(settings.autoAccept, isFalse);
    expect(settings.enabled, isTrue);
    expect(settings.saveDir, isNull);
  });

  test(
    'lần đầu chạy: id lấy từ IdGenerator, tên máy mặc định, lưu ngay',
    () async {
      final settings = (await repo().load()).valueOrNull!;

      expect(settings, P2pSettings(deviceId: 'id-1', deviceName: 'Máy thử'));
      expect(await saved(), {
        'deviceId': 'id-1',
        'deviceName': 'Máy thử',
        'autoAccept': false,
        'enabled': true,
        'manualPeers': <String>[],
      });
      // Mở lại app thì vẫn là thiết bị ấy.
      expect((await repo().load()).valueOrNull!.deviceId, 'id-1');
      expect(ids.calls, 1);
    },
  );

  test('file hỏng thì bắt đầu lại từ mặc định và ghi đè', () async {
    await File('$_fixtures/p2p_corrupt.json').copy(path);

    final settings = (await repo().load()).valueOrNull!;

    expect(settings.deviceId, 'id-1');
    expect((await saved())['deviceId'], 'id-1');
  });

  test('chỉ đọc đĩa một lần, kể cả khi gọi song song', () async {
    final repository = repo();
    final results = await Future.wait([repository.load(), repository.load()]);

    expect(results[0].valueOrNull, results[1].valueOrNull);
    expect(ids.calls, 1);
    await File(path).writeAsString('{"deviceId":"khac"}');
    expect((await repository.load()).valueOrNull!.deviceId, 'id-1');
  });

  test('save ghi file và load sau đó trả bản mới', () async {
    final repository = repo();
    final first = (await repository.load()).valueOrNull!;
    final next = first.copyWith(
      deviceName: 'Tên mới',
      saveDir: '/tmp/nhan',
      manualPeers: ['10.0.0.9:45700'],
    );

    expect(await repository.save(next), const Ok<void>(null));
    expect((await repository.load()).valueOrNull, next);
    expect(await saved(), {
      'deviceId': 'id-1',
      'deviceName': 'Tên mới',
      'autoAccept': false,
      'enabled': true,
      'saveDir': '/tmp/nhan',
      'manualPeers': ['10.0.0.9:45700'],
    });
  });

  test('ghi lỗi thì trả Err và giữ cài đặt cũ', () async {
    // Đường dẫn là một thư mục: đọc ra rỗng, ghi thì hỏng.
    final blocked = Directory('${dir.path}/blocked.json')..createSync();
    final repository = repo(at: blocked.path);

    final first = (await repository.load()).valueOrNull!;
    // Lần đầu lưu lỗi vẫn dùng cài đặt mới cho phiên này.
    expect(first.deviceId, 'id-1');

    final result = await repository.save(first.copyWith(deviceName: 'X'));
    expect(result.failureOrNull, isA<StorageFailure>());
    expect((await repository.load()).valueOrNull, first);
  });

  test('kiểu dữ liệu sai trong file thì trả Err, lần sau đọc lại', () async {
    await File(path).writeAsString('{"deviceId":42}');
    final repository = repo();

    expect((await repository.load()).failureOrNull, isA<StorageFailure>());

    await File(path).writeAsString('{"deviceId":"sua-roi"}');
    expect((await repository.load()).valueOrNull!.deviceId, 'sua-roi');
  });
}
