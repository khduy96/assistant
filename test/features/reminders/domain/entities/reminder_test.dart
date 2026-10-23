import 'package:event_notice/core/domain/time_of_day.dart';
import 'package:event_notice/features/reminders/domain/entities/pending_alert.dart';
import 'package:event_notice/features/reminders/domain/entities/reminder.dart';
import 'package:event_notice/features/reminders/domain/entities/scheduled_alarm.dart';
import 'package:flutter_test/flutter_test.dart';

Reminder _reminder({Set<int> weekdays = const {}}) => Reminder(
  id: 'r1',
  title: 'Họp',
  date: DateTime(2026, 9, 14),
  time: TimeOfDay(hour: 14, minute: 0),
  weekdays: weekdays,
  endTime: TimeOfDay(hour: 22, minute: 0),
  snoozedUntil: DateTime(2026, 9, 14, 14, 5),
  firedUpTo: DateTime(2026, 9, 14, 14),
  createdAt: DateTime(2026, 9, 1),
);

void main() {
  group('Reminder', () {
    test('giá trị mặc định giống bản cũ', () {
      final r = Reminder(
        id: 'r',
        title: 't',
        date: DateTime(2026, 9, 14),
        time: TimeOfDay(hour: 8, minute: 0),
        createdAt: DateTime(2026, 9, 1),
      );
      expect(r.note, '');
      expect(r.enabled, isTrue);
      expect(r.repeat, RepeatRule.once);
      expect(r.weekdays, isEmpty);
      expect(r.repeatEveryMinutes, 0);
      expect(r.endTime, isNull);
      expect(r.leadMinutes, 0);
      expect(r.snoozeMinutes, 5);
      expect(r.snoozedUntil, isNull);
      expect(r.firedUpTo, isNull);
      expect(r.isDeadline, isFalse);
    });

    test('weekdays không sửa được, kể cả qua set đã truyền vào', () {
      final days = {DateTime.monday};
      final r = _reminder(weekdays: days);
      days.add(DateTime.friday);

      expect(r.weekdays, {DateTime.monday});
      expect(() => r.weekdays.add(DateTime.sunday), throwsUnsupportedError);
    });

    test('copyWith giữ nguyên id và các field không truyền', () {
      final r = _reminder();
      final edited = r.copyWith(title: 'Họp khách', leadMinutes: 10);

      expect(edited.id, 'r1');
      expect(edited.title, 'Họp khách');
      expect(edited.leadMinutes, 10);
      expect(edited.endTime, r.endTime);
      expect(edited.snoozedUntil, r.snoozedUntil);
      expect(edited.firedUpTo, r.firedUpTo);
      expect(r.title, 'Họp', reason: 'bản gốc không đổi');
    });

    test('copyWith với null tường minh thì xoá endTime, snooze, mốc', () {
      final cleared = _reminder().copyWith(
        endTime: null,
        snoozedUntil: null,
        firedUpTo: null,
      );
      expect(cleared.endTime, isNull);
      expect(cleared.snoozedUntil, isNull);
      expect(cleared.firedUpTo, isNull);
    });

    test('so sánh bằng theo giá trị, weekdays không kể thứ tự', () {
      final a = _reminder(weekdays: {DateTime.monday, DateTime.thursday});
      final b = _reminder(weekdays: {DateTime.thursday, DateTime.monday});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == a.copyWith(weekdays: {DateTime.monday}), isFalse);
      expect(a == a.copyWith(enabled: false), isFalse);
    });

    test('deadlineAt ghép ngày với giờ, repeatsWithinDay cần cả giờ dừng', () {
      final r = _reminder();
      expect(r.deadlineAt, DateTime(2026, 9, 14, 14, 0));
      expect(r.repeatsWithinDay, isFalse);
      expect(r.copyWith(repeatEveryMinutes: 120).repeatsWithinDay, isTrue);
      expect(
        r.copyWith(repeatEveryMinutes: 120, endTime: null).repeatsWithinDay,
        isFalse,
      );
    });
  });

  test('PendingAlert và ScheduledAlarm so sánh theo giá trị', () {
    PendingAlert alert() => PendingAlert(
      reminder: _reminder(),
      at: DateTime(2026, 9, 14, 13, 50),
      eventAt: DateTime(2026, 9, 14, 14),
      isLead: true,
    );
    expect(alert(), alert());
    expect(alert().hashCode, alert().hashCode);

    ScheduledAlarm alarm(int id) => ScheduledAlarm(
      id: id,
      at: DateTime(2026, 9, 14, 14),
      title: 'Họp',
      body: 'b',
      payload: 'p',
    );
    expect(alarm(1), alarm(1));
    expect(alarm(1) == alarm(2), isFalse);
  });
}
