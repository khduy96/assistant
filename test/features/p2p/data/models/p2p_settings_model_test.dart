import 'package:event_notice/features/p2p/data/mappers/p2p_settings_mapper.dart';
import 'package:event_notice/features/p2p/data/models/p2p_settings_model.dart';
import 'package:event_notice/features/p2p/domain/entities/p2p_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  var ids = 0;
  var names = 0;

  P2pSettingsModel read(Map<String, dynamic> json) => P2pSettingsModel.fromJson(
    json,
    newId: () => 'new-${++ids}',
    defaultName: () {
      names++;
      return 'Máy thử';
    },
  );

  setUp(() {
    ids = 0;
    names = 0;
  });

  test('đọc đủ sáu khoá của p2p.json', () {
    final model = read({
      'deviceId': 'dev-1',
      'deviceName': 'Laptop',
      'autoAccept': true,
      'enabled': false,
      'saveDir': r'D:\Nhận',
      'manualPeers': ['172.28.0.50:45700'],
    });

    expect(model.deviceId, 'dev-1');
    expect(model.deviceName, 'Laptop');
    expect(model.autoAccept, isTrue);
    expect(model.enabled, isFalse);
    expect(model.saveDir, r'D:\Nhận');
    expect(model.manualPeers, ['172.28.0.50:45700']);
    // Id và tên có sẵn thì không sinh mới.
    expect(ids, 0);
    expect(names, 0);
  });

  test('khoá thiếu thì lấy mặc định', () {
    final model = read({});

    expect(model.deviceId, 'new-1');
    expect(model.deviceName, 'Máy thử');
    expect(model.autoAccept, isFalse);
    expect(model.enabled, isTrue);
    expect(model.saveDir, isNull);
    expect(model.manualPeers, isEmpty);
  });

  test('ghi đúng thứ tự khoá cũ, bỏ saveDir khi không có', () {
    final model = read({'deviceId': 'dev-1', 'deviceName': 'Laptop'});

    expect(model.toJson().keys, [
      'deviceId',
      'deviceName',
      'autoAccept',
      'enabled',
      'manualPeers',
    ]);
    expect(
      read({...model.toJson(), 'saveDir': '/x'}).toJson().keys.toList()[4],
      'saveDir',
    );
  });

  test('kiểu sai thì ném lỗi thay vì lặng lẽ đổi giá trị', () {
    expect(() => read({'deviceId': 42}), throwsA(isA<TypeError>()));
    expect(
      () => read({
        'manualPeers': [1],
      }),
      throwsA(isA<TypeError>()),
    );
  });

  test('mapper đổi qua lại không mất gì', () {
    final settings = P2pSettings(
      deviceId: 'dev-1',
      deviceName: 'Laptop',
      autoAccept: true,
      enabled: false,
      saveDir: '/tmp/in',
      manualPeers: const ['10.0.0.7:45700'],
    );

    final model = P2pSettingsMapper.toModel(settings);
    expect(P2pSettingsMapper.toEntity(model), settings);
    expect(P2pSettingsMapper.toEntity(read(model.toJson())), settings);
  });
}
