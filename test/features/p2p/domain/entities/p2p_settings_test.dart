import 'package:event_notice/features/p2p/domain/entities/p2p_settings.dart';
import 'package:event_notice/features/p2p/domain/entities/save_location.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  P2pSettings settings() => P2pSettings(
    deviceId: 'dev-1',
    deviceName: 'Máy này',
    saveDir: 'D:/Nhận',
    manualPeers: const ['172.28.0.50:45700'],
  );

  test('mặc định: hỏi trước khi nhận, truyền tệp bật, thư mục mặc định', () {
    final s = P2pSettings(deviceId: 'dev-1', deviceName: 'Máy này');
    expect(s.autoAccept, isFalse);
    expect(s.enabled, isTrue);
    expect(s.saveDir, isNull);
    expect(s.manualPeers, isEmpty);
  });

  test('danh sách máy thêm tay không sửa được từ ngoài', () {
    final source = ['172.28.0.50:45700'];
    final s = P2pSettings(
      deviceId: 'dev-1',
      deviceName: 'x',
      manualPeers: source,
    );
    source.add('10.0.0.2:45700');
    expect(s.manualPeers, ['172.28.0.50:45700']);
    expect(() => s.manualPeers.add('y'), throwsUnsupportedError);
  });

  test('copyWith giữ deviceId và các trường không truyền', () {
    final s = settings().copyWith(deviceName: 'Tên mới', autoAccept: true);
    expect(s.deviceId, 'dev-1');
    expect(s.deviceName, 'Tên mới');
    expect(s.autoAccept, isTrue);
    expect(s.enabled, isTrue);
    expect(s.saveDir, 'D:/Nhận');
    expect(s.manualPeers, ['172.28.0.50:45700']);
  });

  test('copyWith(saveDir: null) quay về thư mục mặc định', () {
    expect(settings().copyWith(saveDir: null).saveDir, isNull);
    expect(settings().copyWith().saveDir, 'D:/Nhận');
  });

  test('so sánh bằng theo giá trị, kể cả danh sách máy thêm tay', () {
    expect(settings(), settings());
    expect(settings().hashCode, settings().hashCode);
    expect(
      settings(),
      isNot(settings().copyWith(manualPeers: const ['10.0.0.2:45700'])),
    );
  });

  test('SaveLocation hiện thư mục công cộng nếu có, không thì thư mục ghi', () {
    expect(
      const SaveLocation(
        directory: '/data/app/files/Trợ lý',
        publicFolder: 'Download/Trợ lý',
      ).label,
      'Download/Trợ lý',
    );
    expect(
      const SaveLocation(directory: r'C:\Users\a\Downloads\Trợ lý').label,
      r'C:\Users\a\Downloads\Trợ lý',
    );
  });
}
