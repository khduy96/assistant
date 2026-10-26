import 'package:event_notice/features/p2p/domain/services/manual_entry.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ô "Thêm thiết bị bằng IP" nhận chữ người dùng gõ tay, nên phải chịu được
/// mọi kiểu gõ thiếu/thừa trước khi đem đi nối.
void main() {
  test('thiếu cổng thì mặc định 45700', () {
    expect(normalizeEntry('172.28.0.50'), '172.28.0.50:45700');
    expect(normalizeEntry('  172.28.0.50  '), '172.28.0.50:45700');
  });

  test('gõ kèm cổng thì giữ nguyên cổng đó', () {
    expect(normalizeEntry('172.28.0.50:45701'), '172.28.0.50:45701');
  });

  test('chữ vô nghĩa bị loại', () {
    expect(normalizeEntry(''), isNull);
    expect(normalizeEntry('   '), isNull);
    expect(normalizeEntry('172.28.0.50:cong'), isNull);
    expect(normalizeEntry('172.28.0.50:0'), isNull);
    expect(normalizeEntry('172.28.0.50:70000'), isNull);
    expect(normalizeEntry('may tinh cua toi'), isNull);
  });
}
