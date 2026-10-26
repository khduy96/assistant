import 'package:event_notice/core/domain/time_of_day.dart';
import 'package:event_notice/features/reminders/domain/entities/reminder.dart';
import 'package:event_notice/features/reminders/domain/services/reminder_ordering.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 9, 14, 12);

Reminder _r(
  String id, {
  String? title,
  bool enabled = true,
  RepeatRule repeat = RepeatRule.once,
  DateTime? date,
  int hour = 14,
  bool isDeadline = false,
  DateTime? snoozedUntil,
}) => Reminder(
  id: id,
  title: title ?? id,
  enabled: enabled,
  repeat: repeat,
  date: date ?? DateTime(2026, 9, 14),
  time: TimeOfDay(hour: hour, minute: 0),
  isDeadline: isDeadline,
  snoozedUntil: snoozedUntil,
  createdAt: DateTime(2026, 9, 1),
);

List<String> _ids(Iterable<Reminder> list) => [for (final r in list) r.id];

void main() {
  group('ReminderOrdering.sorted', () {
    test('đang bật trước, rồi theo lần kế tiếp, hết lịch xuống cuối', () {
      final sorted = ReminderOrdering.sorted([
        _r('off', enabled: false, hour: 13),
        _r('past', hour: 9), // một lần, đã qua
        _r('later', hour: 18),
        _r('soon', hour: 13),
        _r('daily', repeat: RepeatRule.daily, hour: 9), // mai 09:00
      ], _now);

      expect(_ids(sorted), ['soon', 'later', 'daily', 'past', 'off']);
    });

    test('cùng không còn lịch thì theo tên', () {
      final sorted = ReminderOrdering.sorted([
        _r('b', title: 'Bơi', hour: 9),
        _r('a', title: 'An', hour: 8),
      ], _now);
      expect(_ids(sorted), ['a', 'b']);
    });

    test('trả list mới, không đụng list vào', () {
      final input = [_r('later', hour: 18), _r('soon', hour: 13)];
      ReminderOrdering.sorted(input, _now);
      expect(_ids(input), ['later', 'soon']);
    });
  });

  test('deadlines: gần nhất trước, đã quá hạn xuống cuối', () {
    final list = ReminderOrdering.deadlines([
      _r('plain', hour: 13),
      _r('overdue', isDeadline: true, hour: 10),
      _r('far', isDeadline: true, date: DateTime(2026, 9, 20)),
      _r('near', isDeadline: true, hour: 15),
      _r('overdueOld', isDeadline: true, date: DateTime(2026, 9, 1)),
    ], _now);

    expect(_ids(list), ['near', 'far', 'overdueOld', 'overdue']);
  });

  group('nextAlertAt', () {
    test('lấy lần báo sớm nhất của các nhắc đang bật', () {
      expect(
        ReminderOrdering.nextAlertAt([
          _r('later', hour: 18),
          _r('off', enabled: false, hour: 13),
          _r('soon', hour: 15),
        ], _now),
        DateTime(2026, 9, 14, 15),
      );
    });

    test('tính cả lần báo lại', () {
      expect(
        ReminderOrdering.nextAlertAt([
          _r('later', hour: 18),
          _r('snoozed', hour: 9, snoozedUntil: DateTime(2026, 9, 14, 12, 5)),
        ], _now),
        DateTime(2026, 9, 14, 12, 5),
      );
    });

    test('không còn gì thì null', () {
      expect(
        ReminderOrdering.nextAlertAt([
          _r('past', hour: 9),
          _r('off', enabled: false, hour: 18),
        ], _now),
        isNull,
      );
    });
  });

  group('nearestDeadline', () {
    test('deadline chưa qua gần nhất, bật hay tắt đều tính', () {
      final r = ReminderOrdering.nearestDeadline([
        _r('plain', hour: 13),
        _r('overdue', isDeadline: true, hour: 10),
        _r('far', isDeadline: true, date: DateTime(2026, 9, 20)),
        _r('nearOff', isDeadline: true, enabled: false, hour: 16),
      ], _now);
      expect(r?.id, 'nearOff');
    });

    test('không có deadline nào còn hạn thì null', () {
      expect(
        ReminderOrdering.nearestDeadline([
          _r('plain', hour: 13),
          _r('overdue', isDeadline: true, hour: 10),
        ], _now),
        isNull,
      );
    });
  });
}
