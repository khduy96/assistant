import 'dart:convert';
import 'dart:io';

import 'package:event_notice/features/p2p/data/datasources/p2p_settings_local_data_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

const _fixtures = 'test/features/p2p/data/fixtures';

void main() {
  late Directory dir;
  late String path;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('p2p_settings_source_test');
    path = '${dir.path}/p2p.json';
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('tên file là p2p.json trong thư mục dữ liệu của app', () async {
    final source = P2pSettingsLocalDataSource(paths: TempPaths(dir.path));
    await source.save({'deviceId': 'a'});
    expect(await File('${dir.path}/p2p.json').exists(), isTrue);
  });

  test('chưa có file thì đọc ra rỗng', () async {
    expect(await P2pSettingsLocalDataSource(path: path).load(), isEmpty);
  });

  test('file hỏng hoặc không phải object thì đọc ra rỗng', () async {
    await File('$_fixtures/p2p_corrupt.json').copy(path);
    expect(await P2pSettingsLocalDataSource(path: path).load(), isEmpty);

    await File(path).writeAsString('["a"]');
    expect(await P2pSettingsLocalDataSource(path: path).load(), isEmpty);
  });

  test('đọc nguyên văn file có sẵn', () async {
    await File('$_fixtures/p2p_full.json').copy(path);

    final raw = await P2pSettingsLocalDataSource(path: path).load();

    expect(raw['deviceId'], '5b0c1e7a-3f2d-4c55-9a51-0f7d2a6c9e11');
    expect(raw['manualPeers'], ['172.28.0.50:45700', '192.168.1.9:45701']);
    expect(raw['saveDir'], r'D:\Nhận');
  });

  test('ghi JSON một dòng như bản cũ', () async {
    final source = P2pSettingsLocalDataSource(path: path);
    await source.save({
      'deviceId': 'a',
      'deviceName': 'Máy',
      'manualPeers': <String>[],
    });

    final text = await File(path).readAsString();
    expect(text, '{"deviceId":"a","deviceName":"Máy","manualPeers":[]}');
    expect(jsonDecode(text), isA<Map<String, dynamic>>());
  });

  test('hai lần ghi liền nhau không chen vào nhau, lần sau thắng', () async {
    final source = P2pSettingsLocalDataSource(path: path);
    await Future.wait([
      source.save({'deviceName': 'một'}),
      source.save({'deviceName': 'hai'}),
    ]);
    expect((await source.load())['deviceName'], 'hai');
  });
}
