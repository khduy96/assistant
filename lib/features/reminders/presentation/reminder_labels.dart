import '../../../core/presentation/format.dart';
import '../domain/entities/reminder.dart';
import '../domain/services/schedule_calculator.dart';
import 'time_of_day_convert.dart';

extension RepeatRuleLabel on RepeatRule {
  String get label => switch (this) {
    RepeatRule.once => 'Một lần',
    RepeatRule.daily => 'Hàng ngày',
    RepeatRule.weekly => 'Hàng tuần',
  };
}

/// Short Vietnamese name of each weekday, keyed `DateTime.monday` ..
/// `DateTime.sunday`, in that order.
const weekdayShortNames = {
  DateTime.monday: 'T2',
  DateTime.tuesday: 'T3',
  DateTime.wednesday: 'T4',
  DateTime.thursday: 'T5',
  DateTime.friday: 'T6',
  DateTime.saturday: 'T7',
  DateTime.sunday: 'CN',
};

/// Human description of when a reminder fires, e.g.
/// "Hàng ngày lúc 10:00, lặp mỗi 2 giờ đến 22:00".
String describeSchedule(Reminder r) {
  final time = formatTime(r.time.toFlutter());
  final String base;
  switch (r.repeat) {
    case RepeatRule.once:
      base = '${formatDate(r.date)} lúc $time';
    case RepeatRule.daily:
      base = 'Hàng ngày lúc $time';
    case RepeatRule.weekly:
      if (r.weekdays.isEmpty) {
        base = 'Chưa chọn thứ — lúc $time';
      } else {
        final days = (r.weekdays.toList()..sort())
            .map((d) => weekdayShortNames[d]!)
            .join(', ');
        base = '$days lúc $time';
      }
  }
  if (!r.repeatsWithinDay) return base;
  return '$base, lặp mỗi ${formatEvery(r.repeatEveryMinutes)}'
      ' đến ${formatTime(r.endTime!.toFlutter())}';
}

/// One-line summary of what rings next, for the Android ongoing notification
/// and the tray tooltip; [next] is the soonest ring, null when none is left.
String describeNextAlert(DateTime? next) => next == null
    ? 'Chưa có nhắc nhở nào đang bật'
    : 'Lần báo kế tiếp: ${formatDateTime(next)}';

/// `<title>: còn <countdown>` for the nearest [deadline] still ahead at
/// [now]; null when there is none.
String? describeNearestDeadline(Reminder? deadline, DateTime now) {
  if (deadline == null) return null;
  final left = ScheduleCalculator.timeLeft(deadline, now);
  return '${deadline.title}: còn ${formatLongCountdown(left)}';
}

/// Status chip of a reminder card as of [now]: whether it is off or done,
/// how long until a snoozed alert rings again, or the countdown to the next
/// occurrence.
String reminderStatus(Reminder r, DateTime now) {
  if (!r.enabled) {
    return ScheduleCalculator.isExpired(r, now) && r.repeat == RepeatRule.once
        ? 'Đã xong'
        : 'Đang tắt';
  }
  final snoozed = r.snoozedUntil;
  if (snoozed != null && snoozed.isAfter(now)) {
    return 'Báo lại ${formatCountdown(snoozed.difference(now))}';
  }
  final next = ScheduleCalculator.nextOccurrence(r, now);
  if (next != null) return formatCountdown(next.difference(now));
  return 'Đã qua';
}

/// The big number of a deadline card: the countdown, prefixed "QUÁ HẠN" once
/// [left] is negative.
String deadlineHeadline(Duration left) => left.isNegative
    ? 'QUÁ HẠN ${formatLongCountdown(left)}'
    : formatLongCountdown(left);
