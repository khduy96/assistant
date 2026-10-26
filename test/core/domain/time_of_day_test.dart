import 'package:event_notice/core/domain/time_of_day.dart';
import 'package:flutter_test/flutter_test.dart';

// Plain test(): no widget binding, the value object is pure Dart.
void main() {
  test('so sánh bằng theo giá trị', () {
    expect(TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 8, minute: 0));
    expect(TimeOfDay(hour: 8, minute: 0).hashCode,
        TimeOfDay(hour: 8, minute: 0).hashCode);
    expect(TimeOfDay(hour: 8, minute: 0),
        isNot(TimeOfDay(hour: 8, minute: 1)));
    expect(TimeOfDay(hour: 8, minute: 0),
        isNot(TimeOfDay(hour: 9, minute: 0)));
  });

  test('nhận đủ biên 00:00 và 23:59', () {
    final start = TimeOfDay(hour: 0, minute: 0);
    final end = TimeOfDay(hour: 23, minute: 59);
    expect(start.hour, 0);
    expect(start.minute, 0);
    expect(end.hour, 23);
    expect(end.minute, 59);
  });

  test('từ chối giờ ngoài 0–23', () {
    expect(() => TimeOfDay(hour: -1, minute: 0), throwsRangeError);
    expect(() => TimeOfDay(hour: 24, minute: 0), throwsRangeError);
  });

  test('từ chối phút ngoài 0–59', () {
    expect(() => TimeOfDay(hour: 8, minute: -1), throwsRangeError);
    expect(() => TimeOfDay(hour: 8, minute: 60), throwsRangeError);
  });

  test('toString dạng HH:mm', () {
    expect(TimeOfDay(hour: 8, minute: 5).toString(), '08:05');
    expect(TimeOfDay(hour: 23, minute: 59).toString(), '23:59');
  });
}
