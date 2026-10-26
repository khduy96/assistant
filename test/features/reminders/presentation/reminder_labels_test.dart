import 'package:event_notice/core/domain/time_of_day.dart' as core;
import 'package:event_notice/features/reminders/domain/entities/reminder.dart';
import 'package:event_notice/features/reminders/presentation/reminder_alarm_body_formatter.dart';
import 'package:event_notice/features/reminders/presentation/reminder_labels.dart';
import 'package:event_notice/features/reminders/presentation/time_of_day_convert.dart';
import 'package:flutter/material.dart' as material show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';

import 'fixture.dart';

void main() {
  group('RepeatRule.label và weekdayShortNames', () {
    test('nhãn tiếng Việt của kiểu lặp', () {
      expect(RepeatRule.values.map((r) => r.label), [
        'Một lần',
        'Hàng ngày',
        'Hàng tuần',
      ]);
    });

    test('thứ hai tới chủ nhật, đúng thứ tự', () {
      expect(weekdayShortNames.keys, [
        DateTime.monday,
        DateTime.tuesday,
        DateTime.wednesday,
        DateTime.thursday,
        DateTime.friday,
        DateTime.saturday,
        DateTime.sunday,
      ]);
      expect(weekdayShortNames.values, [
        'T2',
        'T3',
        'T4',
        'T5',
        'T6',
        'T7',
        'CN',
      ]);
    });
  });

  group('describeSchedule', () {
    test('một lần: ngày và giờ', () {
      expect(
        describeSchedule(reminder('a', hour: 9, minute: 5)),
        '22/10/2026 lúc 09:05',
      );
    });

    test('hàng ngày, lặp trong ngày', () {
      expect(
        describeSchedule(
          reminder(
            'a',
            repeat: RepeatRule.daily,
            every: 120,
            end: core.TimeOfDay(hour: 22, minute: 0),
          ),
        ),
        'Hàng ngày lúc 10:00, lặp mỗi 2 giờ đến 22:00',
      );
      expect(
        describeSchedule(
          reminder(
            'a',
            repeat: RepeatRule.daily,
            every: 90,
            end: core.TimeOfDay(hour: 18, minute: 30),
          ),
        ),
        'Hàng ngày lúc 10:00, lặp mỗi 1 giờ 30 phút đến 18:30',
      );
    });

    test('không có giờ dừng thì không lặp trong ngày', () {
      expect(
        describeSchedule(reminder('a', repeat: RepeatRule.daily, every: 60)),
        'Hàng ngày lúc 10:00',
      );
    });

    test('hàng tuần: các thứ đã chọn theo thứ tự, hoặc chưa chọn', () {
      expect(
        describeSchedule(
          reminder(
            'a',
            repeat: RepeatRule.weekly,
            hour: 14,
            weekdays: {DateTime.sunday, DateTime.friday, DateTime.monday},
          ),
        ),
        'T2, T6, CN lúc 14:00',
      );
      expect(
        describeSchedule(reminder('a', repeat: RepeatRule.weekly, hour: 14)),
        'Chưa chọn thứ — lúc 14:00',
      );
    });
  });

  group('trạng thái thẻ nhắc nhở', () {
    test('đếm ngược tới lần kế tiếp', () {
      expect(reminderStatus(reminder('a'), t0), 'còn 30 phút');
    });

    test('đang hoãn thì đếm tới lúc báo lại', () {
      expect(
        reminderStatus(
          reminder('a', snoozedUntil: t0.add(const Duration(minutes: 5))),
          t0,
        ),
        'Báo lại còn 5 phút',
      );
    });

    test('tắt: nhắc một lần đã qua là xong, còn lại là đang tắt', () {
      expect(
        reminderStatus(reminder('a', enabled: false, hour: 8), t0),
        'Đã xong',
      );
      expect(reminderStatus(reminder('a', enabled: false), t0), 'Đang tắt');
      expect(
        reminderStatus(
          reminder('a', enabled: false, hour: 8, repeat: RepeatRule.daily),
          t0,
        ),
        'Đang tắt',
      );
    });

    test('bật mà không còn lần nào thì đã qua', () {
      expect(reminderStatus(reminder('a', hour: 8), t0), 'Đã qua');
    });
  });

  group('deadline', () {
    test('đếm ngược dài, quá hạn thì ghi QUÁ HẠN', () {
      expect(
        deadlineHeadline(
          const Duration(days: 2, hours: 5, minutes: 12, seconds: 33),
        ),
        '2 ngày 05:12:33',
      );
      expect(
        deadlineHeadline(const Duration(minutes: 4, seconds: 9)),
        '00:04:09',
      );
      expect(deadlineHeadline(const Duration(hours: -1)), 'QUÁ HẠN 01:00:00');
    });
  });

  group('câu tóm tắt cho thông báo thường trực và khay', () {
    test('lần báo kế tiếp', () {
      expect(describeNextAlert(null), 'Chưa có nhắc nhở nào đang bật');
      expect(
        describeNextAlert(DateTime(2026, 10, 22, 14, 5)),
        'Lần báo kế tiếp: 22/10/2026 14:05',
      );
    });

    test('deadline gần nhất', () {
      expect(describeNearestDeadline(null, t0), isNull);
      expect(
        describeNearestDeadline(
          reminder(
            'd',
            title: 'Nộp báo cáo',
            isDeadline: true,
            hour: 10,
            minute: 15,
          ),
          t0,
        ),
        'Nộp báo cáo: còn 00:45:00',
      );
    });
  });

  group('ReminderAlarmBodyFormatter', () {
    const formatter = ReminderAlarmBodyFormatter();
    final event = DateTime(2026, 10, 22, 9, 5);

    test('trước giờ: còn N phút nữa', () {
      expect(
        formatter.body(reminder('a', lead: 10), event, isLead: true),
        'Còn 10 phút nữa — bắt đầu lúc 09:05',
      );
    });

    test('đúng giờ: kèm ghi chú đã cắt khoảng trắng nếu có', () {
      expect(
        formatter.body(reminder('a'), event, isLead: false),
        'Đến giờ rồi — 09:05',
      );
      expect(
        formatter.body(reminder('a', note: '   '), event, isLead: false),
        'Đến giờ rồi — 09:05',
      );
      expect(
        formatter.body(reminder('a', note: ' phòng 3 '), event, isLead: false),
        'Đến giờ rồi — 09:05 · phòng 3',
      );
    });
  });

  group('đổi TimeOfDay core ↔ Flutter', () {
    test('giữ nguyên giờ và phút cả hai chiều', () {
      final c = core.TimeOfDay(hour: 7, minute: 5);
      expect(c.toFlutter(), const material.TimeOfDay(hour: 7, minute: 5));
      expect(
        const material.TimeOfDay(hour: 23, minute: 59).toCore(),
        core.TimeOfDay(hour: 23, minute: 59),
      );
      expect(c.toFlutter().toCore(), c);
    });
  });
}
