import 'package:event_notice/core/domain/time_of_day.dart';
import 'package:event_notice/features/reminders/data/mappers/reminder_mapper.dart';
import 'package:event_notice/features/reminders/domain/entities/reminder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('entity qua model rồi về lại không mất trường nào', () {
    final reminders = [
      Reminder(
        id: 'r1',
        title: 'Nộp hồ sơ',
        note: 'bản cứng',
        date: DateTime(2026, 10, 30),
        time: TimeOfDay(hour: 17, minute: 0),
        leadMinutes: 60,
        firedUpTo: DateTime(2026, 10, 22, 8, 15, 30, 500),
        isDeadline: true,
        createdAt: DateTime(2026, 10, 20, 9),
      ),
      Reminder(
        id: 'r2',
        title: 'Uống nước',
        enabled: false,
        repeat: RepeatRule.weekly,
        date: DateTime(2026, 10, 1),
        time: TimeOfDay(hour: 10, minute: 0),
        weekdays: const {1, 3, 5},
        repeatEveryMinutes: 120,
        endTime: TimeOfDay(hour: 22, minute: 30),
        leadMinutes: 10,
        snoozeMinutes: 15,
        snoozedUntil: DateTime(2026, 10, 22, 10, 15),
        createdAt: DateTime(2026, 10, 1, 7, 45),
      ),
    ];
    for (final r in reminders) {
      expect(ReminderMapper.toEntity(ReminderMapper.toModel(r)), r);
    }
  });
}
