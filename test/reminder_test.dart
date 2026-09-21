import 'package:event_notice/models/reminder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Reminder build({
  RepeatRule repeat = RepeatRule.once,
  required DateTime date,
  required TimeOfDay time,
  Set<int>? weekdays,
  int leadMinutes = 0,
  int repeatEveryMinutes = 0,
  TimeOfDay? endTime,
}) =>
    Reminder(
      id: 'r1',
      title: 'Họp online',
      repeat: repeat,
      date: date,
      time: time,
      weekdays: weekdays,
      leadMinutes: leadMinutes,
      repeatEveryMinutes: repeatEveryMinutes,
      endTime: endTime,
    );

void main() {
  test('một lần: chỉ báo đúng ngày giờ đã đặt', () {
    final r = build(
      date: DateTime(2026, 9, 14),
      time: const TimeOfDay(hour: 14, minute: 0),
    );
    final from = DateTime(2026, 9, 14, 9);

    expect(r.nextAlertAfter(from), DateTime(2026, 9, 14, 14, 0));
    expect(r.nextAlertAfter(DateTime(2026, 9, 14, 14, 1)), isNull);
  });

  test('nhắc trước N phút báo thêm một lần trước sự kiện', () {
    final r = build(
      date: DateTime(2026, 9, 14),
      time: const TimeOfDay(hour: 14, minute: 0),
      leadMinutes: 10,
    );

    final lead = r.nextAlertInfoAfter(DateTime(2026, 9, 14, 9))!;
    expect(lead.at, DateTime(2026, 9, 14, 13, 50));
    expect(lead.eventAt, DateTime(2026, 9, 14, 14, 0));
    expect(lead.isLead, isTrue);

    final event = r.nextAlertInfoAfter(lead.at)!;
    expect(event.at, DateTime(2026, 9, 14, 14, 0));
    expect(event.isLead, isFalse);
  });

  test('hàng ngày: sau giờ báo thì chuyển sang ngày hôm sau', () {
    final r = build(
      repeat: RepeatRule.daily,
      date: DateTime(2026, 9, 11),
      time: const TimeOfDay(hour: 9, minute: 30),
    );

    expect(r.nextAlertAfter(DateTime(2026, 9, 11, 8)), DateTime(2026, 9, 11, 9, 30));
    expect(r.nextAlertAfter(DateTime(2026, 9, 11, 10)), DateTime(2026, 9, 12, 9, 30));
  });

  test('hàng tuần: chỉ báo vào các thứ đã chọn', () {
    final r = build(
      repeat: RepeatRule.weekly,
      date: DateTime(2026, 9, 11),
      time: const TimeOfDay(hour: 14, minute: 0),
      weekdays: {DateTime.monday, DateTime.thursday},
    );

    // 11/09/2026 là thứ sáu -> lần kế tiếp là thứ hai 14/09.
    expect(r.nextAlertAfter(DateTime(2026, 9, 11, 15)), DateTime(2026, 9, 14, 14, 0));
    // Sau thứ hai -> thứ năm 17/09.
    expect(r.nextAlertAfter(DateTime(2026, 9, 14, 15)), DateTime(2026, 9, 17, 14, 0));
  });

  test('đang tắt thì không báo', () {
    final r = build(
      date: DateTime(2026, 9, 14),
      time: const TimeOfDay(hour: 14, minute: 0),
    )..enabled = false;

    expect(r.nextAlertAfter(DateTime(2026, 9, 14, 9)), isNull);
  });

  test('báo lại (snooze) được ưu tiên trước lịch thường', () {
    final r = build(
      repeat: RepeatRule.daily,
      date: DateTime(2026, 9, 11),
      time: const TimeOfDay(hour: 9, minute: 30),
    )..snoozedUntil = DateTime(2026, 9, 11, 9, 35);

    expect(r.nextAlertAfter(DateTime(2026, 9, 11, 9, 31)), DateTime(2026, 9, 11, 9, 35));
  });

  group('lặp trong ngày: 10:00, mỗi 2 giờ, dừng lúc 22:00', () {
    Reminder everyTwoHours({int leadMinutes = 0}) => build(
          repeat: RepeatRule.daily,
          date: DateTime(2026, 9, 11),
          time: const TimeOfDay(hour: 10, minute: 0),
          leadMinutes: leadMinutes,
          repeatEveryMinutes: 120,
          endTime: const TimeOfDay(hour: 22, minute: 0),
        );

    test('báo đủ các mốc trong ngày rồi dừng sau 22:00', () {
      final r = everyTwoHours();
      final hours = <int>[];
      var cursor = DateTime(2026, 9, 11, 0, 0);
      for (var i = 0; i < 10; i++) {
        final next = r.nextAlertAfter(cursor);
        if (next == null || next.day != 11) break;
        hours.add(next.hour);
        cursor = next;
      }

      expect(hours, [10, 12, 14, 16, 18, 20, 22]);
      // Sau 22:00 là sang 10:00 hôm sau, không có mốc nào lúc nửa đêm.
      expect(r.nextAlertAfter(DateTime(2026, 9, 11, 22, 1)),
          DateTime(2026, 9, 12, 10, 0));
    });

    test('báo trước 5 phút cho từng mốc', () {
      final r = everyTwoHours(leadMinutes: 5);

      final lead = r.nextAlertInfoAfter(DateTime(2026, 9, 11, 11, 0))!;
      expect(lead.at, DateTime(2026, 9, 11, 11, 55));
      expect(lead.eventAt, DateTime(2026, 9, 11, 12, 0));
      expect(lead.isLead, isTrue);

      final event = r.nextAlertInfoAfter(lead.at)!;
      expect(event.at, DateTime(2026, 9, 11, 12, 0));
      expect(event.isLead, isFalse);
    });

    test('mốc cuối không vượt quá giờ dừng', () {
      final r = build(
        repeat: RepeatRule.daily,
        date: DateTime(2026, 9, 11),
        time: const TimeOfDay(hour: 10, minute: 0),
        repeatEveryMinutes: 180,
        endTime: const TimeOfDay(hour: 17, minute: 0),
      );

      // 10:00, 13:00, 16:00 rồi dừng (19:00 đã quá 17:00).
      expect(r.nextAlertAfter(DateTime(2026, 9, 11, 16, 1)),
          DateTime(2026, 9, 12, 10, 0));
    });
  });

  _deadlineTests();

  test('lưu và đọc lại giữ nguyên dữ liệu', () {
    final r = build(
      repeat: RepeatRule.weekly,
      date: DateTime(2026, 9, 11),
      time: const TimeOfDay(hour: 14, minute: 5),
      weekdays: {DateTime.monday, DateTime.thursday},
      leadMinutes: 15,
      repeatEveryMinutes: 120,
      endTime: const TimeOfDay(hour: 22, minute: 0),
    );

    final back = Reminder.fromJson(r.toJson());
    expect(back.repeat, RepeatRule.weekly);
    expect(back.weekdays, {DateTime.monday, DateTime.thursday});
    expect(back.time.hour, 14);
    expect(back.time.minute, 5);
    expect(back.leadMinutes, 15);
    expect(back.repeatEveryMinutes, 120);
    expect(back.endTime, const TimeOfDay(hour: 22, minute: 0));
  });
}

void _deadlineTests() {
  group('deadline', () {
    Reminder deadline({int leadMinutes = 60}) => Reminder(
          id: 'd1',
          title: 'Nộp báo cáo quý III',
          date: DateTime(2026, 9, 20),
          time: const TimeOfDay(hour: 17, minute: 0),
          leadMinutes: leadMinutes,
          isDeadline: true,
          createdAt: DateTime(2026, 9, 15, 17, 0),
        );

    test('mốc hạn chót lấy đúng ngày giờ đã đặt', () {
      expect(deadline().deadlineAt, DateTime(2026, 9, 20, 17, 0));
    });

    test('vẫn báo trước hạn rồi báo đúng hạn', () {
      final d = deadline(leadMinutes: 60);

      final lead = d.nextAlertInfoAfter(DateTime(2026, 9, 20, 15))!;
      expect(lead.at, DateTime(2026, 9, 20, 16, 0));
      expect(lead.isLead, isTrue);

      final due = d.nextAlertInfoAfter(lead.at)!;
      expect(due.at, DateTime(2026, 9, 20, 17, 0));
      expect(due.isLead, isFalse);

      // Hết hạn thì không báo nữa.
      expect(d.nextAlertAfter(DateTime(2026, 9, 20, 17, 1)), isNull);
    });

    test('thanh tiến độ chạy từ lúc tạo tới hạn chót', () {
      final d = deadline();
      expect(d.elapsedFraction, inInclusiveRange(0.0, 1.0));
    });

    test('lưu và đọc lại giữ nguyên deadline', () {
      final back = Reminder.fromJson(deadline().toJson());
      expect(back.isDeadline, isTrue);
      expect(back.createdAt, DateTime(2026, 9, 15, 17, 0));
      expect(back.deadlineAt, DateTime(2026, 9, 20, 17, 0));
    });
  });
}
