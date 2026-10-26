import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/usecase.dart';
import 'package:event_notice/features/p2p/domain/entities/save_location.dart';
import 'package:event_notice/features/p2p/domain/usecases/get_save_location.dart';
import 'package:event_notice/features/p2p/domain/usecases/load_p2p_settings.dart';
import 'package:event_notice/features/p2p/domain/usecases/rename_device.dart';
import 'package:event_notice/features/p2p/domain/usecases/set_auto_accept.dart';
import 'package:event_notice/features/p2p/domain/usecases/set_p2p_enabled.dart';
import 'package:event_notice/features/p2p/domain/usecases/set_save_dir.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

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

  test('LoadP2pSettings đọc từ repository', () async {
    final result = await LoadP2pSettings(settings)(const NoParams());
    expect(result.valueOrNull, settings.current);

    settings.loadFailure = _disk;
    final failed = await LoadP2pSettings(settings)(const NoParams());
    expect(failed.failureOrNull, _disk);
  });

  group('SetP2pEnabled', () {
    test('chỉ lưu lựa chọn, không tự bật hay tắt dịch vụ', () async {
      final result = await SetP2pEnabled(settings)(false);
      expect(result.valueOrNull?.enabled, isFalse);
      expect(settings.current.enabled, isFalse);
      expect(transfers.calls, isEmpty);
      expect(peers.calls, isEmpty);
    });

    test('lưu lỗi thì trả lỗi, cài đặt giữ như cũ', () async {
      settings.saveFailure = _disk;
      expect((await SetP2pEnabled(settings)(false)).failureOrNull, _disk);
      expect(settings.current.enabled, isTrue);
    });
  });

  group('SetAutoAccept', () {
    test('lưu rồi báo cho phía nhận tệp', () async {
      final result = await SetAutoAccept(settings, transfers)(true);
      expect(result.valueOrNull?.autoAccept, isTrue);
      expect(settings.current.autoAccept, isTrue);
      expect(transfers.updatedWith?.autoAccept, isTrue);
    });

    test('lưu lỗi thì không báo cho phía nhận', () async {
      settings.saveFailure = _disk;
      expect((await SetAutoAccept(settings, transfers)(true)).isErr, isTrue);
      expect(transfers.calls, isEmpty);
    });
  });

  group('SetSaveDir', () {
    test('đổi thư mục nhận cho các tệp tới sau', () async {
      final result = await SetSaveDir(settings, transfers)('D:/Nhận');
      expect(result.valueOrNull?.saveDir, 'D:/Nhận');
      expect(transfers.updatedWith?.saveDir, 'D:/Nhận');
    });

    test('null thì quay về thư mục mặc định', () async {
      settings.current = settings.current.copyWith(saveDir: 'D:/Nhận');
      final result = await SetSaveDir(settings, transfers)(null);
      expect(result.valueOrNull?.saveDir, isNull);
      expect(settings.current.saveDir, isNull);
    });
  });

  group('RenameDevice', () {
    test('cắt khoảng trắng, lưu, báo cả hai phía rồi quảng bá ngay', () async {
      final result = await RenameDevice(settings, transfers, peers)(
        '  Laptop của Felix ',
      );
      expect(result.valueOrNull?.deviceName, 'Laptop của Felix');
      expect(settings.current.deviceName, 'Laptop của Felix');
      expect(transfers.updatedWith?.deviceName, 'Laptop của Felix');
      expect(peers.updatedWith?.deviceName, 'Laptop của Felix');
      expect(peers.calls, ['updateSettings', 'announce']);
    });

    test('tên trống hoặc trùng tên cũ thì không đổi gì', () async {
      final rename = RenameDevice(settings, transfers, peers);
      expect((await rename('   ')).valueOrNull, settings.current);
      expect((await rename('Máy này')).valueOrNull, settings.current);
      expect(settings.saves, 0);
      expect(transfers.calls, isEmpty);
      expect(peers.calls, isEmpty);
    });

    test('lưu lỗi thì không quảng bá tên mới', () async {
      settings.saveFailure = _disk;
      final result = await RenameDevice(settings, transfers, peers)('Mới');
      expect(result.failureOrNull, _disk);
      expect(peers.calls, isEmpty);
    });
  });

  test('GetSaveLocation hỏi theo thư mục đang chọn', () async {
    settings.current = settings.current.copyWith(saveDir: 'D:/Nhận');
    final result = await GetSaveLocation(settings, transfers)(const NoParams());
    expect(result.valueOrNull, const SaveLocation(directory: 'D:/Nhận'));
    expect(transfers.calls, ['saveLocation D:/Nhận']);
  });
}
