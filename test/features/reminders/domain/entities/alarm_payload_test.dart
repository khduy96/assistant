import 'package:event_notice/features/reminders/domain/entities/alarm_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final at = DateTime(2026, 9, 14, 13, 50);
  final millis = at.millisecondsSinceEpoch;

  test('encode ra dạng reminderId|epochMillis|0 hoặc 1', () {
    expect(
      AlarmPayload(reminderId: 'r1', at: at, isLead: false).encode(),
      'r1|$millis|0',
    );
    expect(
      AlarmPayload(reminderId: 'r1', at: at, isLead: true).encode(),
      'r1|$millis|1',
    );
  });

  group('parseAlarmPayload', () {
    test('đọc payload hợp lệ', () {
      expect(
        parseAlarmPayload('r1|$millis|1'),
        AlarmPayload(reminderId: 'r1', at: at, isLead: true),
      );
      expect(parseAlarmPayload('r1|$millis|0')!.isLead, isFalse);
    });

    test('đọc lại đúng thứ đã encode', () {
      final p = AlarmPayload(
        reminderId: '3f2b-uuid',
        at: DateTime(2026, 12, 31, 23, 59),
        isLead: true,
      );
      expect(parseAlarmPayload(p.encode()), p);
    });

    test('phần thứ ba khác 1 thì không phải báo trước', () {
      expect(parseAlarmPayload('r1|$millis|x')!.isLead, isFalse);
      expect(parseAlarmPayload('r1|$millis|')!.isLead, isFalse);
    });

    test('payload không hợp lệ thì trả null', () {
      expect(parseAlarmPayload(''), isNull);
      expect(parseAlarmPayload('r1'), isNull);
      expect(parseAlarmPayload('r1|$millis'), isNull);
      expect(parseAlarmPayload('r1|$millis|1|extra'), isNull);
      expect(parseAlarmPayload('r1|abc|1'), isNull);
      expect(parseAlarmPayload('r1||1'), isNull);
    });
  });
}
