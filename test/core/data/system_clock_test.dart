import 'package:event_notice/core/data/system_clock.dart';
import 'package:event_notice/core/domain/clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SystemClock trả về giờ máy hiện tại', () {
    const Clock clock = SystemClock();
    final before = DateTime.now();
    final now = clock.now();
    final after = DateTime.now();
    expect(now.isBefore(before), isFalse);
    expect(now.isAfter(after), isFalse);
    expect(now.isUtc, isFalse);
  });
}
