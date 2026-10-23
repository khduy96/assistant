import 'package:event_notice/features/p2p/domain/services/manual_entry.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ô "Thêm thiết bị bằng IP" nhận chữ người dùng gõ tay, nên phải chịu được
/// mọi kiểu gõ thiếu/thừa trước khi đem đi nối. Cùng kỳ vọng với
/// test/p2p_manual_peer_test.dart.
void main() {
  group('normalizeEntry', () {
    test('thiếu cổng thì mặc định 45700', () {
      expect(normalizeEntry('172.28.0.50'), '172.28.0.50:45700');
      expect(normalizeEntry('  172.28.0.50  '), '172.28.0.50:45700');
    });

    test('gõ kèm cổng thì giữ nguyên cổng đó', () {
      expect(normalizeEntry('172.28.0.50:45701'), '172.28.0.50:45701');
      expect(normalizeEntry('may-tinh.local:1'), 'may-tinh.local:1');
      expect(normalizeEntry('10.0.0.2:65535'), '10.0.0.2:65535');
    });

    test('chữ vô nghĩa bị loại', () {
      expect(normalizeEntry(''), isNull);
      expect(normalizeEntry('   '), isNull);
      expect(normalizeEntry('172.28.0.50:cong'), isNull);
      expect(normalizeEntry('172.28.0.50:0'), isNull);
      expect(normalizeEntry('172.28.0.50:70000'), isNull);
      expect(normalizeEntry('may tinh cua toi'), isNull);
    });
  });

  group('splitEntry', () {
    test('tách lại host và cổng của một mục đã chuẩn hoá', () {
      final parts = splitEntry(normalizeEntry('172.28.0.50')!);
      expect(parts?.host, '172.28.0.50');
      expect(parts?.port, 45700);
    });

    test('mục không có cổng ở cuối thì không tách được', () {
      expect(splitEntry('172.28.0.50'), isNull);
      expect(splitEntry('172.28.0.50:abc'), isNull);
      expect(splitEntry(':45700'), isNull);
    });
  });
}
