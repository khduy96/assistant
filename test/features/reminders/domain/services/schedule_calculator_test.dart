import 'package:event_notice/core/domain/time_of_day.dart';
import 'package:event_notice/features/reminders/domain/entities/reminder.dart';
import 'package:event_notice/features/reminders/domain/services/schedule_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

final _created = DateTime(2026, 9, 1, 8);

Reminder build({
  RepeatRule repeat = RepeatRule.once,
  required DateTime date,
  required TimeOfDay time,
  Set<int> weekdays = const {},
  int leadMinutes = 0,
  int repeatEveryMinutes = 0,
  TimeOfDay? endTime,
}) => Reminder(
  id: 'r1',
  title: 'Họp online',
  repeat: repeat,
  date: date,
  time: time,
  weekdays: weekdays,
  leadMinutes: leadMinutes,
  repeatEveryMinutes: repeatEveryMinutes,
  endTime: endTime,
  createdAt: _created,
);

DateTime? nextAlertAfter(Reminder r, DateTime from) =>
    ScheduleCalculator.nextAlertAfter(r, from);

AlertTime? nextAlertInfoAfter(Reminder r, DateTime from) =>
    ScheduleCalculator.nextAlertInfoAfter(r, from);

void main() {
  // The 14 cases below are ported from test/reminder_test.dart with the same
  // expectations. The two "lưu và đọc lại" cases check that a copy keeps
  // every field; the JSON round trip itself is tested in the data layer.

  test('một lần: chỉ báo đúng ngày giờ đã đặt', () {
    final r = build(
      date: DateTime(2026, 9, 14),
      time: TimeOfDay(hour: 14, minute: 0),
    );
    final from = DateTime(2026, 9, 14, 9);

    expect(nextAlertAfter(r, from), DateTime(2026, 9, 14, 14, 0));
    expect(nextAlertAfter(r, DateTime(2026, 9, 14, 14, 1)), isNull);
  });

  test('nhắc trước N phút báo thêm một lần trước sự kiện', () {
    final r = build(
      date: DateTime(2026, 9, 14),
      time: TimeOfDay(hour: 14, minute: 0),
      leadMinutes: 10,
    );

    final lead = nextAlertInfoAfter(r, DateTime(2026, 9, 14, 9))!;
    expect(lead.at, DateTime(2026, 9, 14, 13, 50));
    expect(lead.eventAt, DateTime(2026, 9, 14, 14, 0));
    expect(lead.isLead, isTrue);

    final event = nextAlertInfoAfter(r, lead.at)!;
    expect(event.at, DateTime(2026, 9, 14, 14, 0));
    expect(event.isLead, isFalse);
  });

  test('hàng ngày: sau giờ báo thì chuyển sang ngày hôm sau', () {
    final r = build(
      repeat: RepeatRule.daily,
      date: DateTime(2026, 9, 11),
      time: TimeOfDay(hour: 9, minute: 30),
    );

    expect(
      nextAlertAfter(r, DateTime(2026, 9, 11, 8)),
      DateTime(2026, 9, 11, 9, 30),
    );
    expect(
      nextAlertAfter(r, DateTime(2026, 9, 11, 10)),
      DateTime(2026, 9, 12, 9, 30),
    );
  });

  test('hàng tuần: chỉ báo vào các thứ đã chọn', () {
    final r = build(
      repeat: RepeatRule.weekly,
      date: DateTime(2026, 9, 11),
      time: TimeOfDay(hour: 14, minute: 0),
      weekdays: {DateTime.monday, DateTime.thursday},
    );

    // 11/09/2026 là thứ sáu -> lần kế tiếp là thứ hai 14/09.
    expect(
      nextAlertAfter(r, DateTime(2026, 9, 11, 15)),
      DateTime(2026, 9, 14, 14, 0),
    );
    // Sau thứ hai -> thứ năm 17/09.
    expect(
      nextAlertAfter(r, DateTime(2026, 9, 14, 15)),
      DateTime(2026, 9, 17, 14, 0),
    );
  });

  test('đang tắt thì không báo', () {
    final r = build(
      date: DateTime(2026, 9, 14),
      time: TimeOfDay(hour: 14, minute: 0),
    ).copyWith(enabled: false);

    expect(nextAlertAfter(r, DateTime(2026, 9, 14, 9)), isNull);
  });

  test('báo lại (snooze) được ưu tiên trước lịch thường', () {
    final r = build(
      repeat: RepeatRule.daily,
      date: DateTime(2026, 9, 11),
      time: TimeOfDay(hour: 9, minute: 30),
    ).copyWith(snoozedUntil: DateTime(2026, 9, 11, 9, 35));

    expect(
      nextAlertAfter(r, DateTime(2026, 9, 11, 9, 31)),
      DateTime(2026, 9, 11, 9, 35),
    );
  });

  group('lặp trong ngày: 10:00, mỗi 2 giờ, dừng lúc 22:00', () {
    Reminder everyTwoHours({int leadMinutes = 0}) => build(
      repeat: RepeatRule.daily,
      date: DateTime(2026, 9, 11),
      time: TimeOfDay(hour: 10, minute: 0),
      leadMinutes: leadMinutes,
      repeatEveryMinutes: 120,
      endTime: TimeOfDay(hour: 22, minute: 0),
    );

    test('báo đủ các mốc trong ngày rồi dừng sau 22:00', () {
      final r = everyTwoHours();
      final hours = <int>[];
      var cursor = DateTime(2026, 9, 11, 0, 0);
      for (var i = 0; i < 10; i++) {
        final next = nextAlertAfter(r, cursor);
        if (next == null || next.day != 11) break;
        hours.add(next.hour);
        cursor = next;
      }

      expect(hours, [10, 12, 14, 16, 18, 20, 22]);
      // Sau 22:00 là sang 10:00 hôm sau, không có mốc nào lúc nửa đêm.
      expect(
        nextAlertAfter(r, DateTime(2026, 9, 11, 22, 1)),
        DateTime(2026, 9, 12, 10, 0),
      );
    });

    test('báo trước 5 phút cho từng mốc', () {
      final r = everyTwoHours(leadMinutes: 5);

      final lead = nextAlertInfoAfter(r, DateTime(2026, 9, 11, 11, 0))!;
      expect(lead.at, DateTime(2026, 9, 11, 11, 55));
      expect(lead.eventAt, DateTime(2026, 9, 11, 12, 0));
      expect(lead.isLead, isTrue);

      final event = nextAlertInfoAfter(r, lead.at)!;
      expect(event.at, DateTime(2026, 9, 11, 12, 0));
      expect(event.isLead, isFalse);
    });

    test('mốc cuối không vượt quá giờ dừng', () {
      final r = build(
        repeat: RepeatRule.daily,
        date: DateTime(2026, 9, 11),
        time: TimeOfDay(hour: 10, minute: 0),
        repeatEveryMinutes: 180,
        endTime: TimeOfDay(hour: 17, minute: 0),
      );

      // 10:00, 13:00, 16:00 rồi dừng (19:00 đã quá 17:00).
      expect(
        nextAlertAfter(r, DateTime(2026, 9, 11, 16, 1)),
        DateTime(2026, 9, 12, 10, 0),
      );
    });
  });

  _deadlineTests();

  test('lưu và đọc lại giữ nguyên dữ liệu', () {
    final r = build(
      repeat: RepeatRule.weekly,
      date: DateTime(2026, 9, 11),
      time: TimeOfDay(hour: 14, minute: 5),
      weekdays: {DateTime.monday, DateTime.thursday},
      leadMinutes: 15,
      repeatEveryMinutes: 120,
      endTime: TimeOfDay(hour: 22, minute: 0),
    );

    final back = r.copyWith();
    expect(back.repeat, RepeatRule.weekly);
    expect(back.weekdays, {DateTime.monday, DateTime.thursday});
    expect(back.time.hour, 14);
    expect(back.time.minute, 5);
    expect(back.leadMinutes, 15);
    expect(back.repeatEveryMinutes, 120);
    expect(back.endTime, TimeOfDay(hour: 22, minute: 0));
  });

  _nowDependentTests();
}

void _deadlineTests() {
  group('deadline', () {
    Reminder deadline({int leadMinutes = 60}) => Reminder(
      id: 'd1',
      title: 'Nộp báo cáo quý III',
      date: DateTime(2026, 9, 20),
      time: TimeOfDay(hour: 17, minute: 0),
      leadMinutes: leadMinutes,
      isDeadline: true,
      createdAt: DateTime(2026, 9, 15, 17, 0),
    );

    test('mốc hạn chót lấy đúng ngày giờ đã đặt', () {
      expect(deadline().deadlineAt, DateTime(2026, 9, 20, 17, 0));
    });

    test('vẫn báo trước hạn rồi báo đúng hạn', () {
      final d = deadline(leadMinutes: 60);

      final lead = nextAlertInfoAfter(d, DateTime(2026, 9, 20, 15))!;
      expect(lead.at, DateTime(2026, 9, 20, 16, 0));
      expect(lead.isLead, isTrue);

      final due = nextAlertInfoAfter(d, lead.at)!;
      expect(due.at, DateTime(2026, 9, 20, 17, 0));
      expect(due.isLead, isFalse);

      // Hết hạn thì không báo nữa.
      expect(nextAlertAfter(d, DateTime(2026, 9, 20, 17, 1)), isNull);
    });

    test('thanh tiến độ chạy từ lúc tạo tới hạn chót', () {
      final d = deadline();
      expect(
        ScheduleCalculator.elapsedFraction(d, DateTime(2026, 9, 18, 5)),
        inInclusiveRange(0.0, 1.0),
      );
    });

    test('lưu và đọc lại giữ nguyên deadline', () {
      final back = deadline().copyWith();
      expect(back.isDeadline, isTrue);
      expect(back.createdAt, DateTime(2026, 9, 15, 17, 0));
      expect(back.deadlineAt, DateTime(2026, 9, 20, 17, 0));
    });
  });
}

/// The getters that used to read `DateTime.now()`, checked at fixed moments.
void _nowDependentTests() {
  group('phụ thuộc giờ hiện tại, với thời điểm cố định', () {
    final deadline = Reminder(
      id: 'd1',
      title: 'Nộp báo cáo',
      date: DateTime(2026, 9, 20),
      time: TimeOfDay(hour: 17, minute: 0),
      isDeadline: true,
      createdAt: DateTime(2026, 9, 15, 17, 0),
    );

    test('timeLeft dương trước hạn, âm sau hạn', () {
      expect(
        ScheduleCalculator.timeLeft(deadline, DateTime(2026, 9, 20, 15, 30)),
        const Duration(hours: 1, minutes: 30),
      );
      expect(
        ScheduleCalculator.timeLeft(deadline, DateTime(2026, 9, 20, 17, 1)),
        const Duration(minutes: -1),
      );
    });

    test('elapsedFraction: 0 lúc tạo, 0.6 sau 3/5 thời gian, 1 sau hạn', () {
      double at(DateTime now) =>
          ScheduleCalculator.elapsedFraction(deadline, now);
      expect(at(DateTime(2026, 9, 15, 17)), 0.0);
      expect(at(DateTime(2026, 9, 18, 17)), closeTo(0.6, 1e-9));
      expect(at(DateTime(2026, 9, 21)), 1.0);
      // Trước lúc tạo vẫn kẹp về 0.
      expect(at(DateTime(2026, 9, 1)), 0.0);
    });

    test('elapsedFraction là 1 khi hạn không sau lúc tạo', () {
      final odd = deadline.copyWith(createdAt: DateTime(2026, 9, 21));
      expect(
        ScheduleCalculator.elapsedFraction(odd, DateTime(2026, 9, 1)),
        1.0,
      );
    });

    test('nextOccurrence bỏ qua lần báo trước, chỉ tính sự kiện', () {
      final r = build(
        repeat: RepeatRule.daily,
        date: DateTime(2026, 9, 11),
        time: TimeOfDay(hour: 9, minute: 30),
        leadMinutes: 10,
      );
      expect(
        ScheduleCalculator.nextOccurrence(r, DateTime(2026, 9, 11, 9, 25)),
        DateTime(2026, 9, 11, 9, 30),
      );
      expect(
        ScheduleCalculator.nextOccurrence(r, DateTime(2026, 9, 11, 9, 30)),
        DateTime(2026, 9, 12, 9, 30),
      );
    });

    test('isExpired chỉ đúng với nhắc một lần đã qua hết', () {
      final once = build(
        date: DateTime(2026, 9, 14),
        time: TimeOfDay(hour: 14, minute: 0),
      );
      expect(
        ScheduleCalculator.isExpired(once, DateTime(2026, 9, 14, 13)),
        isFalse,
      );
      expect(
        ScheduleCalculator.isExpired(once, DateTime(2026, 9, 14, 14)),
        isTrue,
      );

      final daily = build(
        repeat: RepeatRule.daily,
        date: DateTime(2026, 9, 14),
        time: TimeOfDay(hour: 14, minute: 0),
      );
      expect(
        ScheduleCalculator.isExpired(daily, DateTime(2026, 9, 30)),
        isFalse,
      );
    });

    test('nextAlert theo mốc firedUpTo, có thể nằm trong quá khứ', () {
      final r = build(
        repeat: RepeatRule.daily,
        date: DateTime(2026, 9, 11),
        time: TimeOfDay(hour: 9, minute: 30),
      );
      final now = DateTime(2026, 9, 11, 9, 40);

      // Chưa có mốc: tính từ một giây trước bây giờ.
      expect(
        ScheduleCalculator.nextAlert(r, now),
        DateTime(2026, 9, 12, 9, 30),
      );

      // Mốc dừng ở hôm qua: lần 09:30 hôm nay vẫn đang chờ.
      final missed = r.copyWith(firedUpTo: DateTime(2026, 9, 10, 9, 30));
      expect(
        ScheduleCalculator.nextAlert(missed, now),
        DateTime(2026, 9, 11, 9, 30),
      );
    });

    test('lần báo lại lấy sự kiện kế tiếp tính từ now', () {
      final r = build(
        repeat: RepeatRule.daily,
        date: DateTime(2026, 9, 11),
        time: TimeOfDay(hour: 9, minute: 30),
      ).copyWith(snoozedUntil: DateTime(2026, 9, 11, 9, 35));

      final info = ScheduleCalculator.nextAlertInfoAfter(
        r,
        DateTime(2026, 9, 11, 9, 31),
        now: DateTime(2026, 9, 11, 9, 20),
      )!;
      expect(info.at, DateTime(2026, 9, 11, 9, 35));
      expect(info.eventAt, DateTime(2026, 9, 11, 9, 30));
      expect(info.isLead, isFalse);
    });

    test('upcomingAlerts liệt kê lần lượt, gồm cả lần báo trước', () {
      final r = build(
        repeat: RepeatRule.daily,
        date: DateTime(2026, 9, 11),
        time: TimeOfDay(hour: 9, minute: 0),
        leadMinutes: 15,
      );
      final alerts = ScheduleCalculator.upcomingAlerts(
        r,
        3,
        from: DateTime(2026, 9, 11, 8),
      );
      expect(
        [for (final a in alerts) (a.at, a.isLead)],
        [
          (DateTime(2026, 9, 11, 8, 45), true),
          (DateTime(2026, 9, 11, 9, 0), false),
          (DateTime(2026, 9, 12, 8, 45), true),
        ],
      );

      final done = build(
        date: DateTime(2026, 9, 11),
        time: TimeOfDay(hour: 9, minute: 0),
      );
      expect(
        ScheduleCalculator.upcomingAlerts(
          done,
          8,
          from: DateTime(2026, 9, 11, 10),
        ),
        isEmpty,
      );
    });
  });
}
